#import "DGCommon.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
@interface DGBackGesture:NSObject<UIGestureRecognizerDelegate>
@property(nonatomic,weak) UIViewController *controller;
@end
@implementation DGBackGesture
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture{UIViewController *host=self.controller;if([host isKindOfClass:UINavigationController.class])return host.presentingViewController&&((UINavigationController *)host).viewControllers.count<=1;return host.presentingViewController!=nil;}
- (void)swipe:(UIScreenEdgePanGestureRecognizer *)gesture{UIViewController *host=self.controller;CGFloat x=MAX(0,[gesture translationInView:host.view].x);if(gesture.state==UIGestureRecognizerStateChanged)host.view.transform=CGAffineTransformMakeTranslation(x*.85,0);if(gesture.state==UIGestureRecognizerStateEnded){if(x>80||[gesture velocityInView:host.view].x>650){[host dismissViewControllerAnimated:YES completion:^{host.view.transform=CGAffineTransformIdentity;[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];}else[UIView animateWithDuration:.2 animations:^{host.view.transform=CGAffineTransformIdentity;}];}if(gesture.state==UIGestureRecognizerStateCancelled||gesture.state==UIGestureRecognizerStateFailed)[UIView animateWithDuration:.2 animations:^{host.view.transform=CGAffineTransformIdentity;}];}
@end
void DGInstallBackGesture(UIViewController *controller){if(objc_getAssociatedObject(controller,@selector(DGInstallBackGestureMarker)))return;DGBackGesture *target=[DGBackGesture new];target.controller=controller;UIScreenEdgePanGestureRecognizer *pan=[[UIScreenEdgePanGestureRecognizer alloc]initWithTarget:target action:@selector(swipe:)];pan.edges=UIRectEdgeLeft;pan.delegate=target;[controller.view addGestureRecognizer:pan];objc_setAssociatedObject(controller,@selector(DGInstallBackGestureMarker),target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
// Mask the effect view itself so UIKit can keep sampling the live backdrop.
@interface DGNavigationFade:UIView
@end
@implementation DGNavigationFade
+ (Class)layerClass{return CAGradientLayer.class;}
- (instancetype)initWithFrame:(CGRect)frame{
 if((self=[super initWithFrame:frame])){CAGradientLayer *gradient=(CAGradientLayer *)self.layer;gradient.colors=@[(id)UIColor.blackColor.CGColor,(id)UIColor.blackColor.CGColor,(id)[UIColor colorWithWhite:0 alpha:.72].CGColor,(id)[UIColor colorWithWhite:0 alpha:.28].CGColor,(id)UIColor.clearColor.CGColor];gradient.locations=@[@0,@.42,@.64,@.82,@1];gradient.startPoint=CGPointMake(.5,0);gradient.endPoint=CGPointMake(.5,1);}return self;
}
@end
@implementation DGNavigationController{
 UIVisualEffectView *_topBlur;DGNavigationFade *_fade;
}
- (void)viewDidLoad{
 [super viewDidLoad];self.interactivePopGestureRecognizer.enabled=YES;DGInstallBackGesture(self);
 UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];[appearance configureWithTransparentBackground];appearance.backgroundEffect=nil;appearance.backgroundColor=UIColor.clearColor;appearance.shadowColor=UIColor.clearColor;
 self.navigationBar.standardAppearance=appearance;self.navigationBar.scrollEdgeAppearance=appearance;self.navigationBar.compactAppearance=appearance;self.navigationBar.compactScrollEdgeAppearance=appearance;self.navigationBar.translucent=YES;
 _topBlur=[[UIVisualEffectView alloc]initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];_topBlur.userInteractionEnabled=NO;_fade=[[DGNavigationFade alloc]initWithFrame:CGRectZero];_topBlur.maskView=_fade;[self.view insertSubview:_topBlur belowSubview:self.navigationBar];
}
- (void)viewDidLayoutSubviews{
 [super viewDidLayoutSubviews];CGRect bar=[self.navigationBar convertRect:self.navigationBar.bounds toView:self.view];CGFloat height=MAX(1,CGRectGetMaxY(bar)+64);_topBlur.hidden=self.navigationBarHidden;CGRect frame=CGRectMake(0,0,self.view.bounds.size.width,height);
 if(!CGRectEqualToRect(_topBlur.frame,frame)){_topBlur.maskView=nil;_topBlur.frame=frame;_fade.frame=_topBlur.bounds;CGFloat edge=MAX(0,CGRectGetMaxY(bar)/height);((CAGradientLayer *)_fade.layer).locations=@[@0,@(edge),@(edge+(1-edge)*.34),@(edge+(1-edge)*.68),@1];_topBlur.maskView=_fade;}
}
@end

