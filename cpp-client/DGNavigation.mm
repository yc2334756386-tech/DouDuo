#import "DGAnimation.h"
#import "DGCommon.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
@interface DGPagePresentation:UIPresentationController
@end
@implementation DGPagePresentation
- (BOOL)shouldRemovePresentersView{return NO;}
- (BOOL)shouldPresentInFullscreen{return YES;}
- (CGRect)frameOfPresentedViewInContainerView{return self.containerView.bounds;}
@end
@interface DGPageAnimator:NSObject<UIViewControllerAnimatedTransitioning>
@property(nonatomic) BOOL presenting;
@end
@implementation DGPageAnimator
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context{return DGDuration(.32);}
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context{
 UIView *container=context.containerView,*from=[context viewForKey:UITransitionContextFromViewKey],*to=[context viewForKey:UITransitionContextToViewKey];
 UIViewController *destination=[context viewControllerForKey:UITransitionContextToViewControllerKey];if(!to)to=destination.view;CGRect frame=[context finalFrameForViewController:destination];if(CGRectIsEmpty(frame))frame=container.bounds;to.frame=frame;CGFloat width=container.bounds.size.width;
 if(self.presenting){[container addSubview:to];to.transform=CGAffineTransformMakeTranslation(width,0);}else{to.hidden=NO;to.alpha=1;if(!to.superview)[container insertSubview:to belowSubview:from];if(to.superview==container)to.transform=CGAffineTransformMakeTranslation(-width*.24,0);}
 DGAnimate(.32,^{to.transform=CGAffineTransformIdentity;from.transform=CGAffineTransformMakeTranslation(self.presenting?-width*.24:width,0);},^(BOOL done){BOOL completed=!context.transitionWasCancelled;from.transform=CGAffineTransformIdentity;to.transform=CGAffineTransformIdentity;[context completeTransition:completed];if(completed&&!self.presenting)[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];});
}
@end
@interface DGPageTransition:NSObject<UIViewControllerTransitioningDelegate>
@property(nonatomic,strong) UIPercentDrivenInteractiveTransition *interaction;
@end
@implementation DGPageTransition
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source{DGPageAnimator *animation=[DGPageAnimator new];animation.presenting=YES;return animation;}
- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed{DGPageAnimator *animation=[DGPageAnimator new];return animation;}
- (id<UIViewControllerInteractiveTransitioning>)interactionControllerForDismissal:(id<UIViewControllerAnimatedTransitioning>)animator{return self.interaction;}
- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented presentingViewController:(UIViewController *)presenting sourceViewController:(UIViewController *)source{return [[DGPagePresentation alloc]initWithPresentedViewController:presented presentingViewController:presenting];}
@end
static const void *DGPageKey=&DGPageKey;
void DGConfigurePageTransition(UIViewController *controller){DGPageTransition *transition=[DGPageTransition new];objc_setAssociatedObject(controller,DGPageKey,transition,OBJC_ASSOCIATION_RETAIN_NONATOMIC);controller.transitioningDelegate=transition;controller.modalPresentationStyle=UIModalPresentationCustom;}
void DGInstallBackGesture(UIViewController *controller){}
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
 [super viewDidLoad];self.interactivePopGestureRecognizer.enabled=NO;DGInstallBackGesture(self);
 UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];[appearance configureWithTransparentBackground];appearance.backgroundEffect=nil;appearance.backgroundColor=UIColor.clearColor;appearance.shadowColor=UIColor.clearColor;
 self.navigationBar.standardAppearance=appearance;self.navigationBar.scrollEdgeAppearance=appearance;self.navigationBar.compactAppearance=appearance;self.navigationBar.compactScrollEdgeAppearance=appearance;self.navigationBar.translucent=YES;
 _topBlur=[[UIVisualEffectView alloc]initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];_topBlur.userInteractionEnabled=NO;_fade=[[DGNavigationFade alloc]initWithFrame:CGRectZero];_topBlur.maskView=_fade;[self.view insertSubview:_topBlur belowSubview:self.navigationBar];
}
- (void)viewDidLayoutSubviews{
 [super viewDidLayoutSubviews];CGRect bar=[self.navigationBar convertRect:self.navigationBar.bounds toView:self.view];CGFloat height=MAX(1,CGRectGetMaxY(bar)+64);_topBlur.hidden=self.navigationBarHidden;CGRect frame=CGRectMake(0,0,self.view.bounds.size.width,height);
 if(!CGRectEqualToRect(_topBlur.frame,frame)){_topBlur.maskView=nil;_topBlur.frame=frame;_fade.frame=_topBlur.bounds;CGFloat edge=MAX(0,CGRectGetMaxY(bar)/height);((CAGradientLayer *)_fade.layer).locations=@[@0,@(edge),@(edge+(1-edge)*.34),@(edge+(1-edge)*.68),@1];_topBlur.maskView=_fade;}
}
@end

