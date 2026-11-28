#import "DGRefreshPiP.h"
#import "DGDiagnostics.h"
#import <AVKit/AVKit.h>
#import <QuartzCore/QuartzCore.h>
NSNotificationName const DGRefreshPiPStatusChanged=@"DGRefreshPiPStatusChanged";

// Objective-C++ adaptation of the public VideoCall content-source approach
// described by CaiWanFeng/PiP and Yoroin/GlobalRefresh-PiP. No audio player,
// camera, runtime hooks, or private coexistence/control APIs are introduced.
@interface DGRefreshSurface:UIView
@property(nonatomic) CFTimeInterval timestamp;
@end
@implementation DGRefreshSurface
- (void)drawRect:(CGRect)rect{CGContextRef context=UIGraphicsGetCurrentContext();CGFloat ink=((NSInteger)(_timestamp*30)&1)?.01:.005;CGContextSetGrayFillColor(context,1,ink);CGContextFillRect(context,self.bounds);}
@end
@interface DGRefreshPiP:NSObject<AVPictureInPictureControllerDelegate>
@property(nonatomic,strong) UIView *source;
@property(nonatomic,strong) DGRefreshSurface *surface;
@property(nonatomic,strong) AVPictureInPictureVideoCallViewController *content;
@property(nonatomic,strong) AVPictureInPictureController *pip;
@property(nonatomic,strong) CADisplayLink *link;
@property(nonatomic,copy) NSString *status;
@property(nonatomic) BOOL starting,issued,stopping,blocked,video;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger startAttempt;
- (void)apply;
- (NSString *)currentStatus;
@end
@interface DGRefreshPiPClock:NSObject
@property(nonatomic,weak) DGRefreshPiP *owner;
- (void)tick:(CADisplayLink *)link;
@end
@implementation DGRefreshPiPClock
- (void)tick:(CADisplayLink *)link{DGRefreshPiP *owner=_owner;if(!owner){[link invalidate];return;}if(owner.stopping||(!owner.starting&&!owner.pip.pictureInPictureActive&&!owner.pip.pictureInPictureSuspended)){[link invalidate];if(owner.link==link)owner.link=nil;return;}if(owner.pip.pictureInPictureSuspended)return;owner.surface.timestamp=link.timestamp;[owner.surface setNeedsDisplay];}
@end
@implementation DGRefreshPiP
- (NSString *)startMetrics{return [NSString stringWithFormat:@"attempt=%lu possible=%d active=%d suspended=%d source_window=%d source_hidden=%d source_alpha=%.2f source_w=%.1f source_h=%.1f content_w=%.1f content_h=%.1f app_state=%ld",(unsigned long)_startAttempt,_pip.pictureInPicturePossible,_pip.pictureInPictureActive,_pip.pictureInPictureSuspended,_source.window!=nil,_source.hidden,_source.alpha,_source.bounds.size.width,_source.bounds.size.height,_content.view.bounds.size.width,_content.view.bounds.size.height,(long)UIApplication.sharedApplication.applicationState];}
- (void)startContentClock{
 if(_link)return;DGRefreshPiPClock *clock=[DGRefreshPiPClock new];clock.owner=self;_link=[CADisplayLink displayLinkWithTarget:clock selector:@selector(tick:)];_link.preferredFramesPerSecond=30;[_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
 _surface.timestamp=CACurrentMediaTime();[_surface setNeedsDisplay];[_surface.layer displayIfNeeded];
}
- (void)checkStart:(NSUInteger)check generation:(NSUInteger)generation{
 if(generation!=_generation||!_starting||_stopping)return;
 if(_pip.pictureInPictureActive){[self pictureInPictureControllerDidStartPictureInPicture:_pip];return;}
 if(_pip.pictureInPictureSuspended){_starting=NO;[self publishStatus];return;}
 if(check==0||check==5||check==10)DGDiagnostic(@"refresh.pip_start_wait",[self startMetrics]);
 if(check>=10){
  DGDiagnostic(@"refresh.pip_start_timeout",[self startMetrics]);_pip.delegate=nil;[_pip stopPictureInPicture];[self cleanup];
  if(_startAttempt==0&&[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.force120"]&&!_video){++_startAttempt;DGDiagnostic(@"refresh.pip_compatibility_retry",@"content_height=180");[self apply];return;}
  _blocked=YES;_status=@"PiP 未启动，保留前台高刷请求";[self publishStatus];return;
 }
 __weak DGRefreshPiP *weak=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weak checkStart:check+1 generation:generation];});
}
- (void)publishStatus{[NSNotificationCenter.defaultCenter postNotificationName:DGRefreshPiPStatusChanged object:self];}
- (NSString *)currentStatus{
 if(![NSUserDefaults.standardUserDefaults boolForKey:@"douglass.force120"])return @"已关闭";
 if(_video)return @"作品画中画优先，保留前台高刷请求";
 if(_stopping)return @"微型 PiP 正在停止，完成后重新开启";
 if(_pip.pictureInPictureSuspended)return @"微型 PiP 已挂起，等待系统恢复";
 if(_pip.pictureInPictureActive)return @"微型 PiP 已开启";
 if(_starting)return _issued?@"微型 PiP 正在启动":@"正在准备微型 PiP";
 if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return @"回到前台后准备微型 PiP";
 return _status?:@"微型 PiP 待启动";
}
- (void)cleanup{
 [_link invalidate];_link=nil;_pip.delegate=nil;_pip=nil;[_source removeFromSuperview];_source=nil;_surface=nil;_content=nil;_starting=NO;_issued=NO;_stopping=NO;_status=nil;++_generation;
}
- (void)checkStop:(NSUInteger)attempt generation:(NSUInteger)generation{
 if(generation!=_generation||!_stopping)return;
 // Stopping a still-pending start need not produce a didStop callback. Give its
 // delegate a bounded grace period, then reconcile an actually inactive session.
 if(!_pip.pictureInPictureActive&&(!_issued||attempt>=12)){
  [self cleanup];[self apply];DGDiagnostic(@"refresh.pip_stop_reconciled",nil);return;
 }
 if(attempt>=12){[self publishStatus];DGDiagnostic(@"refresh.pip_stop_waiting",nil);return;}
 if(attempt==6&&_pip.pictureInPictureActive)[_pip stopPictureInPicture];
 __weak DGRefreshPiP *weak=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weak checkStop:attempt+1 generation:generation];});
}
- (void)stop{
 if(_stopping){[self publishStatus];return;}
 ++_generation;[_link invalidate];_link=nil;_starting=NO;
 if(_pip.pictureInPictureActive||_issued){_stopping=YES;NSUInteger generation=_generation;[_pip stopPictureInPicture];[self checkStop:0 generation:generation];}else [self cleanup];
 [self publishStatus];
}
- (void)tryStart:(NSUInteger)attempt generation:(NSUInteger)generation{
 if(generation!=_generation||_stopping||_video||_blocked||![NSUserDefaults.standardUserDefaults boolForKey:@"douglass.force120"])return;
 if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){_starting=NO;[self publishStatus];return;}
 BOOL sourceReady=_source.window&&!CGRectIsEmpty(_source.bounds)&&!_source.hidden&&_source.alpha>.01&&!CGRectIsEmpty(_content.view.bounds);
 if(_pip.pictureInPicturePossible&&sourceReady){
  _issued=YES;[self startContentClock];[self publishStatus];DGDiagnostic(@"refresh.pip_start_requested",[self startMetrics]);
  @try{[_pip startPictureInPicture];}@catch(NSException *exception){[self cleanup];_blocked=YES;_status=@"系统未接受微型 PiP，保留前台高刷请求";[self publishStatus];DGDiagnostic(@"refresh.pip_rejected",exception.name);return;}
  [self checkStart:0 generation:generation];return;
 }
 if(attempt>=8){_starting=NO;_status=@"系统尚未允许 PiP，保留前台高刷请求";[self publishStatus];DGDiagnostic(@"refresh.pip_unavailable",[self startMetrics]);return;}
 __weak DGRefreshPiP *weak=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weak tryStart:attempt+1 generation:generation];});
}
- (void)apply{
 BOOL enabled=[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.force120"];
 if(!enabled){_blocked=NO;_startAttempt=0;[self stop];return;}
 if(_video){[self stop];return;}
 if(_blocked||_starting||_stopping||_pip.pictureInPictureActive||_pip.pictureInPictureSuspended||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){[self publishStatus];return;}
 if(![AVPictureInPictureController isPictureInPictureSupported]){_status=@"设备不支持 PiP，保留前台高刷请求";[self publishStatus];return;}
 UIWindow *window=nil;for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class]&&scene.activationState==UISceneActivationStateForegroundActive)for(UIWindow *candidate in ((UIWindowScene *)scene).windows)if(candidate.isKeyWindow){window=candidate;break;}
 if(!window||window.windowScene.screen.maximumFramesPerSecond<120){_status=@"等待支持高刷的前台窗口";[self publishStatus];return;}
 @try{if(!_pip){
  CGFloat startHeight=_startAttempt?180:44;
  _source=[[UIView alloc]initWithFrame:CGRectMake(MAX(0,(window.bounds.size.width-320)/2),window.safeAreaInsets.top+2,320,startHeight)];_source.backgroundColor=UIColor.clearColor;_source.alpha=1;_source.userInteractionEnabled=NO;_source.accessibilityElementsHidden=YES;[window addSubview:_source];
  _content=[AVPictureInPictureVideoCallViewController new];_content.preferredContentSize=CGSizeMake(320,startHeight);_content.view.frame=CGRectMake(0,0,320,startHeight);_content.view.backgroundColor=UIColor.clearColor;_content.view.opaque=NO;_content.view.userInteractionEnabled=NO;_content.view.clipsToBounds=YES;
  _surface=[[DGRefreshSurface alloc]initWithFrame:_content.view.bounds];_surface.backgroundColor=UIColor.clearColor;_surface.opaque=NO;_surface.userInteractionEnabled=NO;_surface.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[_content.view addSubview:_surface];
  AVPictureInPictureControllerContentSource *source=[[AVPictureInPictureControllerContentSource alloc]initWithActiveVideoCallSourceView:_source contentViewController:_content];_pip=[[AVPictureInPictureController alloc]initWithContentSource:source];_pip.delegate=self;
 }}@catch(NSException *exception){[self cleanup];_blocked=YES;_status=@"系统未接受微型 PiP，保留前台高刷请求";[self publishStatus];DGDiagnostic(@"refresh.pip_rejected",exception.name);return;}
 _starting=YES;_status=nil;[self publishStatus];NSUInteger generation=++_generation;__weak DGRefreshPiP *weak=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weak tryStart:0 generation:generation];});
}
- (void)pictureInPictureControllerWillStartPictureInPicture:(AVPictureInPictureController *)controller{if(controller==_pip)DGDiagnostic(@"refresh.pip_will_start",[self startMetrics]);}
- (void)pictureInPictureControllerWillStopPictureInPicture:(AVPictureInPictureController *)controller{if(controller==_pip)DGDiagnostic(@"refresh.pip_will_stop",[self startMetrics]);}
- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)controller{
 if(controller!=_pip)return;if(_stopping||_video||![NSUserDefaults.standardUserDefaults boolForKey:@"douglass.force120"]){[self stop];[controller stopPictureInPicture];return;}_starting=NO;_issued=YES;_status=nil;_content.preferredContentSize=CGSizeMake(320,.1);
 [self startContentClock];
 DGDiagnostic(@"refresh.pip_started",@"route=VideoCall content_fps=30 preferred_height=0.1");
 [self publishStatus];
}
- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)controller{
 if(controller!=_pip)return;BOOL requested=_stopping||_video||![NSUserDefaults.standardUserDefaults boolForKey:@"douglass.force120"];[self cleanup];if(!requested){_blocked=YES;_status=@"PiP 已被系统停止，关闭开关后可重试";[self publishStatus];}else [self apply];DGDiagnostic(@"refresh.pip_stopped",[NSString stringWithFormat:@"requested=%d",requested]);
}
- (void)pictureInPictureController:(AVPictureInPictureController *)controller failedToStartPictureInPictureWithError:(NSError *)error{
 if(controller!=_pip)return;DGDiagnostic(@"refresh.pip_failed_state",[self startMetrics]);BOOL cancelled=_stopping||_video||![NSUserDefaults.standardUserDefaults boolForKey:@"douglass.force120"];[self cleanup];if(cancelled)[self apply];else{_blocked=YES;_status=@"PiP 启动失败，保留前台高刷请求";[self publishStatus];}DGDiagnostic(@"refresh.pip_failed",[NSString stringWithFormat:@"domain=%@ code=%ld cancelled=%d",error.domain,(long)error.code,cancelled]);
}
- (void)pictureInPictureController:(AVPictureInPictureController *)controller restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL))completionHandler{completionHandler(YES);}
@end
static DGRefreshPiP *DGRefreshSession(){static DGRefreshPiP *session;static dispatch_once_t once;dispatch_once(&once,^{session=[DGRefreshPiP new];});return session;}
void DGRefreshPiPApply(void){[DGRefreshSession() apply];}
void DGRefreshPiPPreferVideo(BOOL video){DGRefreshPiP *session=DGRefreshSession();session.video=video;[session apply];}
NSString *DGRefreshPiPStatus(void){return [DGRefreshSession() currentStatus];}
