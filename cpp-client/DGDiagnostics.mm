#import "DGDiagnostics.h"
#import "DGCommon.h"
#import <mach/mach.h>
#include <atomic>
#include <fcntl.h>
#include <unistd.h>
#include <cstdio>
#include <ctime>

namespace {
std::atomic_bool Enabled{false};
int ExceptionFile=-1;
NSUncaughtExceptionHandler *PreviousExceptionHandler=nullptr;
dispatch_queue_t LogQueue() {
    static dispatch_queue_t queue;static dispatch_once_t once;
    dispatch_once(&once,^{queue=dispatch_queue_create("com.douglass.diagnostics",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0));});
    return queue;
}
NSURL *LogFolder() {
    return [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"Diagnostics" isDirectory:YES];
}
NSURL *File(NSUInteger number) {return [LogFolder() URLByAppendingPathComponent:[NSString stringWithFormat:@"runtime-%lu.log",(unsigned long)number]];}
void RecordUncaughtException(NSException *exception){
    // Best-effort final breadcrumb only. Preserve normal process termination.
    if(Enabled.load(std::memory_order_relaxed)&&ExceptionFile>=0){
        char bytes[2048]={};int length=snprintf(bytes,sizeof(bytes),"exception.uncaught epoch=%lld pid=%d name=%.120s frames=",(long long)time(nullptr),getpid(),exception.name.UTF8String?:"unknown");
        for(NSNumber *address in exception.callStackReturnAddresses){if(length<0||length>=(int)sizeof(bytes)-40)break;length+=snprintf(bytes+length,sizeof(bytes)-length,"0x%llx,",address.unsignedLongLongValue);}
        if(length>0){length=MIN(length,(int)sizeof(bytes)-2);bytes[length++]='\n';pwrite(ExceptionFile,bytes,length,0);ftruncate(ExceptionFile,length);fsync(ExceptionFile);}
    }
    if(PreviousExceptionHandler)PreviousExceptionHandler(exception);
}
void PrepareExceptionRecord(){
    if(ExceptionFile>=0){close(ExceptionFile);ExceptionFile=-1;}
    [NSFileManager.defaultManager createDirectoryAtURL:LogFolder() withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *file=[LogFolder() URLByAppendingPathComponent:@"last-exception.txt"];NSNumber *size=nil;[file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    if(size.unsignedIntegerValue>0&&size.unsignedIntegerValue<=2048){NSString *previous=[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil];if(previous.length)DGDiagnostic(@"previous_run",previous);}
    ExceptionFile=open(file.fileSystemRepresentation,O_CREAT|O_WRONLY|O_TRUNC,0600);
    static dispatch_once_t once;dispatch_once(&once,^{PreviousExceptionHandler=NSGetUncaughtExceptionHandler();NSSetUncaughtExceptionHandler(RecordUncaughtException);});
}
void Append(NSString *message,NSDate *when) {
    static NSISO8601DateFormatter *clock;static dispatch_once_t once;
    dispatch_once(&once,^{clock=[NSISO8601DateFormatter new];clock.formatOptions=NSISO8601DateFormatWithInternetDateTime|NSISO8601DateFormatWithFractionalSeconds;});
    NSFileManager *manager=NSFileManager.defaultManager;
    NSURL *folder=LogFolder();
    if(![manager fileExistsAtPath:folder.path]){
        if(![manager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil])return;
        [folder setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
    }
    NSURL *current=File(0);
    unsigned long long size=[[manager attributesOfItemAtPath:current.path error:nil] fileSize];
    if(size>=512*1024){
        [manager removeItemAtURL:File(5) error:nil];
        for(NSInteger i=4;i>=0;--i)if([manager fileExistsAtPath:File(i).path])[manager moveItemAtURL:File(i) toURL:File(i+1) error:nil];
    }
    NSData *line=[[NSString stringWithFormat:@"%@ pid=%d %@\n",[clock stringFromDate:when],NSProcessInfo.processInfo.processIdentifier,message] dataUsingEncoding:NSUTF8StringEncoding];
    if(![manager fileExistsAtPath:current.path]){[line writeToURL:current options:NSDataWritingAtomic error:nil];return;}
    NSFileHandle *handle=[NSFileHandle fileHandleForWritingToURL:current error:nil];
    if(!handle)return;
    if([handle seekToEndReturningOffset:nullptr error:nil])[handle writeData:line error:nil];
    [handle closeAndReturnError:nil];
}
}
void DGDiagnosticStart(void) {
    Enabled.store([NSUserDefaults.standardUserDefaults boolForKey:@"douglass.diagnostics"],std::memory_order_relaxed);
    if(!Enabled.load(std::memory_order_relaxed))return;
    PrepareExceptionRecord();
    NSDictionary *info=NSBundle.mainBundle.infoDictionary;
    DGDiagnostic(@"app.launch",[NSString stringWithFormat:@"version=%@ build=%@ os=%@",info[@"CFBundleShortVersionString"],info[@"CFBundleVersion"],UIDevice.currentDevice.systemVersion]);
    DGDiagnosticMemory(@"memory.launch");
}
void DGDiagnosticEnable(BOOL enabled) {
    bool previous=Enabled.exchange(enabled,std::memory_order_relaxed);
    if(previous==enabled)return;
    if(enabled)PrepareExceptionRecord();else if(ExceptionFile>=0){close(ExceptionFile);ExceptionFile=-1;}
    NSString *event=enabled?[NSString stringWithFormat:@"logging.enabled version=%@ build=%@",NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"],NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]]:@"logging.disabled";
    NSDate *when=NSDate.date;dispatch_async(LogQueue(),^{Append(event,when);});
}
BOOL DGDiagnosticEnabled(void){return Enabled.load(std::memory_order_relaxed);}
void DGDiagnostic(NSString *event,NSString *metrics) {
    if(!Enabled.load(std::memory_order_relaxed))return;
    NSString *message=metrics.length?[NSString stringWithFormat:@"%@ %@",event,metrics]:event;
    NSDate *when=NSDate.date;dispatch_async(LogQueue(),^{@autoreleasepool{Append(message,when);}});
}
void DGDiagnosticMemory(NSString *event) {
    if(!Enabled.load(std::memory_order_relaxed))return;
    task_vm_info_data_t info={};mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    kern_return_t result=task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&count);
    if(result==KERN_SUCCESS)DGDiagnostic(event,[NSString stringWithFormat:@"footprint_MiB=%llu thermal=%ld",(unsigned long long)(info.phys_footprint/(1024*1024)),(long)NSProcessInfo.processInfo.thermalState]);
}
void DGDiagnosticExport(UIViewController *host) {
    __weak UIViewController *weak=host;
    dispatch_async(LogQueue(),^{
        NSMutableData *all=[NSMutableData data];
        for(NSInteger i=5;i>=0;--i){NSData *part=[NSData dataWithContentsOfURL:File(i)];if(part.length)[all appendData:part];}
        NSURL *file=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"DouGlass-%@.log",NSUUID.UUID.UUIDString]]];
        BOOL saved=all.length&&[all writeToURL:file options:NSDataWritingAtomic error:nil];
        dispatch_async(dispatch_get_main_queue(),^{
            UIViewController *host=weak;
            if(!host.viewIfLoaded.window||host.presentedViewController){if(saved)[NSFileManager.defaultManager removeItemAtURL:file error:nil];return;}
            if(!saved){DGToast(host,all.length?@"无法生成日志文件":@"暂无已记录的日志");return;}
            UIActivityViewController *share=[[UIActivityViewController alloc]initWithActivityItems:@[file] applicationActivities:nil];
            share.popoverPresentationController.sourceView=host.view;share.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(host.view.bounds),CGRectGetMidY(host.view.bounds),1,1);
            share.completionWithItemsHandler=^(UIActivityType activity,BOOL completed,NSArray *items,NSError *error){[NSFileManager.defaultManager removeItemAtURL:file error:nil];};
            [host presentViewController:share animated:YES completion:nil];
        });
    });
}
void DGDiagnosticClear(UIViewController *host) {
    if(!host||host.presentedViewController)return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"清空日志目录？" message:@"日志记录开关保持当前状态。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIViewController *weak=host;
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){dispatch_async(LogQueue(),^{
        NSURL *folder=LogFolder();NSFileManager *files=NSFileManager.defaultManager;
        BOOL removed=![files fileExistsAtPath:folder.path]||[files removeItemAtURL:folder error:nil];
        dispatch_async(dispatch_get_main_queue(),^{if(removed&&DGDiagnosticEnabled())PrepareExceptionRecord();DGToast(weak,removed?@"日志目录已清空":@"清空日志失败");});
    });}]];
    [host presentViewController:alert animated:YES completion:nil];
}

namespace {
NSString *ReadRecentLog() {
    constexpr NSUInteger limit=96*1024;
    NSMutableArray<NSString *> *chunks=[NSMutableArray array];NSUInteger remaining=limit;
    for(NSUInteger i=0;i<6&&remaining;i++){
        NSURL *file=File(i);NSFileHandle *handle=[NSFileHandle fileHandleForReadingFromURL:file error:nil];if(!handle)continue;
        unsigned long long size=0;
        if(![handle seekToEndReturningOffset:&size error:nil]){[handle closeAndReturnError:nil];continue;}
        NSUInteger length=MIN((unsigned long long)remaining,size);
        if(!length||![handle seekToOffset:size-length error:nil]){[handle closeAndReturnError:nil];continue;}
        NSData *data=[handle readDataUpToLength:length error:nil];[handle closeAndReturnError:nil];
        remaining-=data.length;
        if(length<size&&data.length){
            const unsigned char *bytes=(const unsigned char *)data.bytes;NSUInteger line=0;
            while(line<data.length&&bytes[line]!='\n')++line;
            if(line==data.length)continue;data=[data subdataWithRange:NSMakeRange(line+1,data.length-line-1)];
        }
        NSString *text=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];if(text.length)[chunks insertObject:text atIndex:0];
    }
    return [chunks componentsJoinedByString:@""];
}
}
@interface DGLogViewer:UIViewController
@end
@implementation DGLogViewer {
    UITextView *_contents;UILabel *_summary;NSTimer *_timer;
    NSString *_lastText;BOOL _reading;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"诊断日志";self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    UIBarButtonItem *refresh=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refreshNow)];
    UIBarButtonItem *save=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(exportLog)];
    refresh.accessibilityLabel=@"刷新日志";save.accessibilityLabel=@"导出完整日志";self.navigationItem.rightBarButtonItems=@[save,refresh];
    _summary=Label(12,UIFontWeightMedium);_summary.textColor=UIColor.secondaryLabelColor;_summary.numberOfLines=2;
    _contents=[UITextView new];_contents.backgroundColor=UIColor.secondarySystemBackgroundColor;_contents.textColor=UIColor.labelColor;
    _contents.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];_contents.editable=NO;_contents.selectable=YES;
    _contents.textContainerInset=UIEdgeInsetsMake(12,12,16,12);_contents.alwaysBounceVertical=YES;
    [self.view addSubview:_summary];[self.view addSubview:_contents];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];CGRect safe=self.view.safeAreaLayoutGuide.layoutFrame;
    _summary.frame=CGRectMake(safe.origin.x+16,safe.origin.y+6,MAX(0,safe.size.width-32),40);
    _contents.frame=CGRectMake(safe.origin.x+8,safe.origin.y+50,MAX(0,safe.size.width-16),MAX(0,safe.size.height-52));
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];[self refreshNow];
    __weak DGLogViewer *weak=self;_timer=[NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *timer){[weak refreshIfFollowing];}];
}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[_timer invalidate];_timer=nil;}
- (void)dealloc{[_timer invalidate];}
- (void)refreshIfFollowing {
    if(!DGDiagnosticEnabled()||_contents.dragging||_contents.decelerating||_contents.selectedRange.length||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    if(_contents.contentOffset.y+_contents.bounds.size.height>=_contents.contentSize.height-36)[self refreshNow];
}
- (void)refreshNow {
    _summary.text=DGDiagnosticEnabled()?@"记录中 · 显示最近日志 · 导出可查看完整记录":@"记录已关闭 · 仍可查看和导出已保存日志";
    if(_reading)return;_reading=YES;
    __weak DGLogViewer *weak=self;
    dispatch_async(LogQueue(),^{
        NSString *tail=ReadRecentLog();
        dispatch_async(dispatch_get_main_queue(),^{
            DGLogViewer *self=weak;if(!self)return;self->_reading=NO;
            if(![self->_lastText isEqualToString:tail]){self->_lastText=tail;self->_contents.text=tail.length?tail:@"暂无日志。可在更多设置启用日志。";}
            if(tail.length&&!self->_contents.dragging&&!self->_contents.selectedRange.length)[self->_contents scrollRangeToVisible:NSMakeRange(tail.length-1,1)];
        });
    });
}
- (void)exportLog{DGDiagnosticExport(self);}
- (void)close{[self dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];}
@end
void DGDiagnosticShow(UIViewController *host) {
    if(!host||host.presentedViewController)return;
    DGNavigationController *nav=[[DGNavigationController alloc]initWithRootViewController:[DGLogViewer new]];
    DGConfigurePageTransition(nav);[host presentViewController:nav animated:YES completion:nil];
}
