#import "DGNavigationResume.h"
#import "DGCommon.h"
#import "DGFeedCache.h"
#import "DGDiagnostics.h"

namespace {
constexpr NSUInteger Limit=2*1024*1024;
BOOL Consumed=NO,Restoring=NO;
NSUInteger SaveGeneration=0;
dispatch_queue_t SaveQueue(){static dispatch_queue_t queue;static dispatch_once_t once;dispatch_once(&once,^{queue=dispatch_queue_create("com.douglass.navigation-save",DISPATCH_QUEUE_SERIAL);});return queue;}
NSURL *File(){return [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"NavigationResume.json"];}
void Present(UIViewController *host,NSArray *groups,NSUInteger index,DGBridge *bridge){
 if(index>=groups.count){Restoring=NO;return;}
 NSMutableArray<UIViewController *> *pages=[NSMutableArray array];
 for(id item in Array(groups[index])){
  if(![item isKindOfClass:NSDictionary.class])continue;
  NSDictionary *state=item;UIViewController *page=nil;
  if([state[@"kind"]isEqual:@"explore"])page=DGMakeResumedExplore(bridge,state);
  else if([state[@"kind"]isEqual:@"player"])page=DGMakeResumedWorkPlayer(bridge,state);
  if(page)[pages addObject:page];if(pages.count==6)break;
 }
 if(!pages.count){Present(host,groups,index+1,bridge);return;}
 DGNavigationController *nav=[[DGNavigationController alloc]initWithRootViewController:pages.firstObject];
 [nav setViewControllers:pages animated:NO];DGConfigurePageTransition(nav);
 [host presentViewController:nav animated:NO completion:^{Present(nav,groups,index+1,bridge);}];
}
}
void DGSaveNavigationResume(UIWindow *window){
 if(!window||Restoring||!Consumed)return;
 NSMutableArray *groups=[NSMutableArray array];UIViewController *page=window.rootViewController.presentedViewController;
 while(page&&groups.count<3){
  NSArray *controllers=[page isKindOfClass:UINavigationController.class]?((UINavigationController *)page).viewControllers:@[page];
  NSMutableArray *states=[NSMutableArray array];
  for(UIViewController *controller in controllers){
   if(![controller conformsToProtocol:@protocol(DGPageResume)])continue;
   NSDictionary *state=[(id<DGPageResume>)controller dgResumeState];if(state)[states addObject:state];if(states.count==6)break;
  }
  if(states.count)[groups addObject:states];page=page.presentedViewController;
 }
 if(!groups.count){DGClearNavigationResume();return;}
 NSDictionary *save=@{@"schema":@1,@"scope":DGCurrentFeedScope(),@"time":@(NSDate.date.timeIntervalSince1970),@"groups":groups};
 NSURL *file=File();NSUInteger generation=++SaveGeneration;
 dispatch_async(SaveQueue(),^{@autoreleasepool{
  NSData *data=[NSJSONSerialization dataWithJSONObject:save options:0 error:nil];
  if(!data.length||data.length>Limit){DGDiagnostic(@"navigation.checkpoint.failed",@"reason=size");return;}
  NSFileManager *files=NSFileManager.defaultManager;[files createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
  BOOL ok=[data writeToURL:file options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];
  if(ok)[file setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
  DGDiagnostic(ok?@"navigation.checkpoint.saved":@"navigation.checkpoint.failed",[NSString stringWithFormat:@"groups=%lu bytes=%lu generation=%lu async=1",(unsigned long)groups.count,(unsigned long)data.length,(unsigned long)generation]);
 }});
}
BOOL DGRestoreNavigationResume(UIViewController *root,DGBridge *bridge){
 if(Consumed||root.presentedViewController)return NO;Consumed=YES;
 NSNumber *bytes=nil;[File()getResourceValue:&bytes forKey:NSURLFileSizeKey error:nil];
 if(!bytes||bytes.unsignedIntegerValue>Limit)return NO;
 NSData *data=[NSData dataWithContentsOfURL:File()];
 id saved=data.length?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
 if(![saved isKindOfClass:NSDictionary.class]||![saved[@"time"]isKindOfClass:NSNumber.class]||![saved[@"schema"]isEqual:@1]||![saved[@"scope"]isEqual:DGCurrentFeedScope()]){DGClearNavigationResume();return NO;}
 double age=NSDate.date.timeIntervalSince1970-[saved[@"time"]doubleValue];NSArray *groups=Array(saved[@"groups"]);
 if(age<0||age>300||!groups.count||groups.count>3){DGClearNavigationResume();return NO;}
 Restoring=YES;DGDiagnostic(@"navigation.checkpoint.restore",[NSString stringWithFormat:@"groups=%lu age_seconds=%.1f",(unsigned long)groups.count,age]);
 Present(root,groups,0,bridge);return YES;
}
void DGClearNavigationResume(void){NSURL *file=File();++SaveGeneration;dispatch_async(SaveQueue(),^{[NSFileManager.defaultManager removeItemAtURL:file error:nil];});}
