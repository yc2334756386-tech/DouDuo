#import "DGCommon.h"
#import "DGVerification.h"
#import <QuartzCore/QuartzCore.h>
static BOOL DGVerificationShowing=NO;
static CFTimeInterval DGVerificationCancelledAt=0;
static UIViewController *DGForegroundController(void){for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){if(scene.activationState!=UISceneActivationStateForegroundActive||![scene isKindOfClass:UIWindowScene.class])continue;for(UIWindow *window in ((UIWindowScene *)scene).windows)if(window.isKeyWindow){UIViewController *controller=window.rootViewController;while(controller.presentedViewController)controller=controller.presentedViewController;if([controller isKindOfClass:UINavigationController.class])controller=((UINavigationController *)controller).topViewController;return controller;}}return nil;}
@interface DGVerification:UIViewController
@property(nonatomic,strong) DGBridge *bridge;
@property(nonatomic,copy) NSString *operation;
@property(nonatomic,strong) NSDictionary *parameters;
@property(nonatomic,weak) UIViewController *origin;
@end
@implementation DGVerification{
 WKWebView *_web;UIView *_previousContainer;CGRect _previousFrame;UIViewAutoresizing _previousAutoresizing;BOOL _previousInteraction,_busy,_closing,_sawChallenge,_manual;NSTimer *_timer;NSDate *_started;UILabel *_status;
}
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"完成抖音安全验证";self.view.backgroundColor=UIColor.systemBackgroundColor;self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"已完成" style:UIBarButtonItemStyleDone target:self action:@selector(manual)];
 _status=Label(12,UIFontWeightRegular);_status.textColor=UIColor.secondaryLabelColor;_status.text=@"请在官方页面完成验证，通过后自动返回";_status.textAlignment=NSTextAlignmentCenter;_status.numberOfLines=2;[self.view addSubview:_status];_web=self.bridge.web;_previousContainer=_web.superview;_previousFrame=_web.frame;_previousAutoresizing=_web.autoresizingMask;_previousInteraction=_web.userInteractionEnabled;[_web removeFromSuperview];_web.userInteractionEnabled=YES;_web.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[self.view addSubview:_web];_started=NSDate.date;__weak DGVerification *weak=self;_timer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){[weak inspect];}];
}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];UIEdgeInsets safe=self.view.safeAreaInsets;_status.frame=CGRectMake(12,safe.top,self.view.bounds.size.width-24,40);_web.frame=CGRectMake(0,safe.top+40,self.view.bounds.size.width,self.view.bounds.size.height-safe.top-40-safe.bottom);}
- (void)manual{_manual=YES;[self inspect];}
- (void)inspect{
 if(_busy||_closing)return;_busy=YES;
 NSString *inspect=@"(()=>{const visible=e=>{const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>20&&r.height>20&&s.display!=='none'&&s.visibility!=='hidden'};return {challenge:[...document.querySelectorAll('iframe[src*=verify],iframe[src*=captcha],[id*=captcha_container],[class*=captcha_verify],[class*=captcha-verify],[class*=VerifyCenter]')].some(visible),ready:!!window.DouGlass}})()";
 [_web evaluateJavaScript:inspect completionHandler:^(id value,NSError *error){if(self->_closing)return;NSDictionary *state=[value isKindOfClass:NSDictionary.class]?value:@{};if([state[@"challenge"]boolValue]){self->_sawChallenge=YES;self->_busy=NO;return;}if(![state[@"ready"]boolValue]){self->_busy=NO;return;}if(!self->_sawChallenge&&!self->_manual&&[NSDate.date timeIntervalSinceDate:self->_started]<5){self->_busy=NO;return;}
  NSArray *reads=@[@"feed",@"comments",@"replies",@"profile",@"userProfile",@"works",@"likes",@"collections",@"following",@"search",@"musicList"];
  NSString *operation=[reads containsObject:self.operation]?self.operation:@"profile";NSDictionary *params=[reads containsObject:self.operation]?self.parameters:@{};
  [self->_web callAsyncJavaScript:@"return await window.DouGlass.request(operation,params);" arguments:@{@"operation":operation,@"params":params?:@{}} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id result,NSError *failure){self->_busy=NO;if(self->_closing)return;NSDictionary *response=[result isKindOfClass:NSDictionary.class]?result:nil;if(!failure&&response&&!response[@"error"]&&(![operation isEqualToString:@"profile"]||[response[@"loggedIn"]boolValue]))[self finish:YES];else if(self->_manual){self->_manual=NO;self->_status.text=@"接口尚未恢复，请完成页面中的验证后稍候";}}];
 }];
}
- (void)restore{if(!_web)return;[_web removeFromSuperview];[_previousContainer addSubview:_web];_web.frame=_previousFrame;_web.autoresizingMask=_previousAutoresizing;_web.userInteractionEnabled=_previousInteraction;_web=nil;}
- (void)cancel{DGVerificationCancelledAt=CACurrentMediaTime();[self finish:NO];}
- (void)finish:(BOOL)passed{
 if(_closing)return;_closing=YES;[_timer invalidate];[self restore];DGVerificationShowing=NO;UIViewController *origin=self.origin;NSString *operation=self.operation;DGSessionCapture(nil);
 [self dismissViewControllerAnimated:YES completion:^{if(passed){[NSNotificationCenter.defaultCenter postNotificationName:@"DGVerificationCompleted" object:nil userInfo:@{@"operation":operation?:@""}];if([origin respondsToSelector:@selector(refresh)])[origin performSelector:@selector(refresh)];}else [NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];
}
- (void)dealloc{[_timer invalidate];[self restore];DGVerificationShowing=NO;}
@end
void DGOpenVerification(DGBridge *bridge,NSString *operation,NSDictionary *parameters){
 if(DGVerificationShowing||CACurrentMediaTime()-DGVerificationCancelledAt<12)return;
 UIViewController *host=DGForegroundController();if(!host||[host isKindOfClass:UIAlertController.class])return;DGVerificationShowing=YES;DGVerification *verification=[DGVerification new];verification.bridge=bridge;verification.operation=operation;verification.parameters=parameters;verification.origin=host;UINavigationController *nav=[[UINavigationController alloc]initWithRootViewController:verification];nav.modalPresentationStyle=UIModalPresentationFullScreen;[host presentViewController:nav animated:YES completion:nil];
}

