#import "DGRefreshPiP.h"
#import "DGDiagnostics.h"
#import <AVKit/AVKit.h>
#import <QuartzCore/QuartzCore.h>

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
- (void)apply;
@end
@interface DGRefreshPiPClock:NSObject
@property(nonatomic,weak) DGRefreshPiP *owner;
- (void)tick:(CADisplayLink *)link;
@end
@implementation DGRefreshPiPClock
- (void)tick:(CADisplayLink *)link{DGRefreshPiP *owner=_owner;if(!owner||!owner.pip.pictureInPictureActive){[link invalidate];return;}owner.surface.timestamp=link.timestamp;[owner.surface setNeedsDisplay];[owner.surface.layer setNeedsDisplay];}
@end
@implementation DGRefreshPiP
- (void)cleanup{
 [_link invalidate];_link=nil;_pip.delegate=nil;_pip=nil;[_source removeFromSuperview];_source=nil;_surface=nil;_content=nil;_starting=NO;_issued=NO;_stopping=NO;++_generation;
}
- (void)stop{
 ++_generation;[_link invalidate];_link=nil;_starting=NO;
 if(_pip.pictureInPictureActive||_issued){_stopping=YES;[_pip stopPictureInPicture];}else [self cleanup];
}
- (void)tryStart:(NSUInteger)attempt generation:(NSUInteger)generation{
 if(generation!=_generation||_stopping||_video||_blocked||![NSUserDefaults.standardUserDefaults boolForKey:@"douglass.force120"])return;
 if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive){_starting=NO;return;}
 if(_pip.pictureInPicturePossible){_issued=YES;_status=@"微型 PiP 正在启动";@try{[_pip startPictureInPicture];}@catch(NSException *exception){[self cleanup];_blocked=YES;_status=@"系统未接受微型 PiP，保留前台高刷请求";DGDiagnostic(@"refresh.pip_rejected",exception.name);}return;}
 if(attempt>=6){_starting=NO;_status=@"系统尚未允许 PiP，保留前台高刷请求";DGDiagnostic(@"refresh.pip_unavailable",nil);return;}
 __weak DGRefreshPiP *weak=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weak tryStart:attempt+1 generation:generation];});
}
- (void)apply{
 BOOL enabled=[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.force120"];
 if(!enabled){_blocked=NO;_status=@"已关闭";[self stop];return;}
 if(_video){_status=@"作品画中画优先，保留前台高刷请求";[self stop];return;}
 if(_blocked||_starting||_stopping||_pip.pictureInPictureActive||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
 if(![AVPictureInPictureController isPictureInPictureSupported]){_status=@"设备不支持 PiP，保留前台高刷请求";return;}
 UIWindow *window=nil;for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class]&&scene.activationState==UISceneActivationStateForegroundActive)for(UIWindow *candidate in ((UIWindowScene *)scene).windows)if(candidate.isKeyWindow){window=candidate;break;}
 if(!window||window.windowScene.screen.maximumFramesPerSecond<120)return;
 @try{if(!_pip){
  _source=[[UIView alloc]initWithFrame:CGRectMake(MAX(0,(window.bounds.size.width-320)/2),window.safeAreaInsets.top+2,320,.1)];_source.backgroundColor=UIColor.clearColor;_source.alpha=.01;_source.userInteractionEnabled=NO;_source.accessibilityElementsHidden=YES;[window addSubview:_source];
  _content=[AVPictureInPictureVideoCallViewController new];_content.preferredContentSize=CGSizeMake(320,.1);_content.view.backgroundColor=UIColor.clearColor;_content.view.opaque=NO;_content.view.userInteractionEnabled=NO;_content.view.clipsToBounds=YES;
  _surface=[[DGRefreshSurface alloc]initWithFrame:_content.view.bounds];_surface.backgroundColor=UIColor.clearColor;_surface.opaque=NO;_surface.userInteractionEnabled=NO;_surface.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[_content.view addSubview:_surface];
  AVPictureInPictureControllerContentSource *source=[[AVPictureInPictureControllerContentSource alloc]initWithActiveVideoCallSourceView:_source contentViewController:_content];_pip=[[AVPictureInPictureController alloc]initWithContentSource:source];_pip.delegate=self;
 }}@catch(NSException *exception){[self cleanup];_blocked=YES;_status=@"系统未接受微型 PiP，保留前台高刷请求";DGDiagnostic(@"refresh.pip_rejected",exception.name);return;}
 _starting=YES;_status=@"准备微型 VideoCall PiP";[self tryStart:0 generation:++_generation];
}
- (void)pictureInPictureControllerDidStartPictureInPicture:(AVPictureInPictureController *)controller{
 if(controller!=_pip)return;if(_stopping){[controller stopPictureInPicture];return;}_starting=NO;_status=@"微型 PiP 内容更新中";_content.preferredContentSize=CGSizeMake(320,.1);
 DGRefreshPiPClock *clock=[DGRefreshPiPClock new];clock.owner=self;_link=[CADisplayLink displayLinkWithTarget:clock selector:@selector(tick:)];_link.preferredFrameRateRange=CAFrameRateRangeDefault;_link.preferredFramesPerSecond=30;[_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
 DGDiagnostic(@"refresh.pip_started",@"route=VideoCall content_fps=30 preferred_height=0.1");
}
- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)controller{
 if(controller!=_pip)return;BOOL requested=_stopping;[self cleanup];if(!requested){_blocked=YES;_status=@"PiP 已被系统停止，关闭开关后可重试";}else if(!_video&&[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.force120"])[self apply];DGDiagnostic(@"refresh.pip_stopped",[NSString stringWithFormat:@"requested=%d",requested]);
}
- (void)pictureInPictureController:(AVPictureInPictureController *)controller failedToStartPictureInPictureWithError:(NSError *)error{
 if(controller!=_pip)return;[self cleanup];_blocked=YES;_status=@"PiP 启动失败，保留前台高刷请求";DGDiagnostic(@"refresh.pip_failed",[NSString stringWithFormat:@"code=%ld",(long)error.code]);
}
- (void)pictureInPictureController:(AVPictureInPictureController *)controller restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL))completionHandler{completionHandler(YES);}
@end
static DGRefreshPiP *DGRefreshSession(){static DGRefreshPiP *session;static dispatch_once_t once;dispatch_once(&once,^{session=[DGRefreshPiP new];});return session;}
void DGRefreshPiPApply(void){[DGRefreshSession() apply];}
void DGRefreshPiPPreferVideo(BOOL video){DGRefreshPiP *session=DGRefreshSession();session.video=video;[session apply];}
NSString *DGRefreshPiPStatus(void){return DGRefreshSession().status?:@"微型 PiP 待启动";}
