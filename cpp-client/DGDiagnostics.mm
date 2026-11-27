#import "DGDiagnostics.h"
#import "DGCommon.h"
#import <mach/mach.h>
#include <atomic>

namespace {
std::atomic_bool Enabled{false};
dispatch_queue_t LogQueue() {
    static dispatch_queue_t queue;static dispatch_once_t once;
    dispatch_once(&once,^{queue=dispatch_queue_create("com.douglass.diagnostics",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0));});
    return queue;
}
NSURL *LogFolder() {
    return [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"Diagnostics" isDirectory:YES];
}
NSURL *File(NSUInteger number) {return [LogFolder() URLByAppendingPathComponent:[NSString stringWithFormat:@"runtime-%lu.log",(unsigned long)number]];}
void Append(NSString *message) {
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
    NSData *line=[[NSString stringWithFormat:@"%@ pid=%d %@\n",[clock stringFromDate:NSDate.date],NSProcessInfo.processInfo.processIdentifier,message] dataUsingEncoding:NSUTF8StringEncoding];
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
    NSDictionary *info=NSBundle.mainBundle.infoDictionary;
    DGDiagnostic(@"app.launch",[NSString stringWithFormat:@"version=%@ build=%@ os=%@",info[@"CFBundleShortVersionString"],info[@"CFBundleVersion"],UIDevice.currentDevice.systemVersion]);
    DGDiagnosticMemory(@"memory.launch");
}
void DGDiagnosticEnable(BOOL enabled) {
    bool previous=Enabled.exchange(enabled,std::memory_order_relaxed);
    if(previous==enabled)return;
    dispatch_async(LogQueue(),^{Append(enabled?@"logging.enabled":@"logging.disabled");});
}
void DGDiagnostic(NSString *event,NSString *metrics) {
    if(!Enabled.load(std::memory_order_relaxed))return;
    NSString *message=metrics.length?[NSString stringWithFormat:@"%@ %@",event,metrics]:event;
    dispatch_async(LogQueue(),^{@autoreleasepool{Append(message);}});
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
        dispatch_async(dispatch_get_main_queue(),^{DGToast(weak,removed?@"日志目录已清空":@"清空日志失败");});
    });}]];
    [host presentViewController:alert animated:YES completion:nil];
}
