#import "DGAnimation.h"
#import "DGCommon.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "DGDiagnostics.h"
@interface DGTransitionClock:NSObject
@property(nonatomic,strong) CADisplayLink *link;
@property(nonatomic) CFTimeInterval last,maxGap;
@property(nonatomic) NSUInteger frames,longFrames;
- (void)tick:(CADisplayLink *)link;
@end
@implementation DGTransitionClock
- (void)tick:(CADisplayLink *)link{if(_last){CFTimeInterval gap=link.timestamp-_last,nominal=link.targetTimestamp-link.timestamp;_maxGap=MAX(_maxGap,gap);if(nominal>0&&gap>nominal*1.65)++_longFrames;}++_frames;_last=link.timestamp;}
@end
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
void DGConfigurePageTransition(UIViewController *controller){DGPageTransition *transition=[DGPageTransition new];objc_setAssociatedObject(controller,DGPageKey,transition,OBJC_ASSOCIATION_RETAIN_NONATOMIC);controller.transitioningDelegate=transition;controller.modalPresentationStyle=UIModalPresentationCustom;controller.modalPresentationCapturesStatusBarAppearance=YES;}
// Mask the effect view itself so UIKit can keep sampling the live backdrop.
@interface DGNavigationFade:UIView
@end
@implementation DGNavigationFade
+ (Class)layerClass{return CAGradientLayer.class;}
- (instancetype)initWithFrame:(CGRect)frame{
 if((self=[super initWithFrame:frame])){CAGradientLayer *gradient=(CAGradientLayer *)self.layer;gradient.colors=@[(id)UIColor.blackColor.CGColor,(id)UIColor.blackColor.CGColor,(id)[UIColor colorWithWhite:0 alpha:.72].CGColor,(id)[UIColor colorWithWhite:0 alpha:.28].CGColor,(id)UIColor.clearColor.CGColor];gradient.locations=@[@0,@.42,@.64,@.82,@1];gradient.startPoint=CGPointMake(.5,0);gradient.endPoint=CGPointMake(.5,1);}return self;
}
@end
@interface DGNavigationController()<UIGestureRecognizerDelegate>
@end
@implementation DGNavigationController{
 UIVisualEffectView *_topBlur;DGNavigationFade *_fade;UIScreenEdgePanGestureRecognizer *_rootBack;
}
- (void)trackTransition:(uint64_t)priority started:(CFTimeInterval)started operation:(NSString *)operation{
 id<UIViewControllerTransitionCoordinator> transition=self.transitionCoordinator;if(!transition){DGEndAnimationPriority(priority);return;}
 DGTransitionClock *probe=nil;if(DGDiagnosticEnabled()){probe=[DGTransitionClock new];probe.link=[CADisplayLink displayLinkWithTarget:probe selector:@selector(tick:)];DGApplyDisplayLinkRate(probe.link,self.view);[probe.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];DGDiagnostic(@"transition.prepared",[NSString stringWithFormat:@"operation=%@ preparation_ms=%.1f",operation,(CACurrentMediaTime()-started)*1000]);}
 BOOL registered=[transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context){DGEndAnimationPriority(priority);[probe.link invalidate];probe.link=nil;if(probe)DGDiagnostic(@"transition.finished",[NSString stringWithFormat:@"operation=%@ elapsed_ms=%.1f frames=%lu max_gap_ms=%.1f long_frames=%lu cancelled=%d",operation,(CACurrentMediaTime()-started)*1000,(unsigned long)probe.frames,probe.maxGap*1000,(unsigned long)probe.longFrames,context.isCancelled]);}];
 if(!registered){DGEndAnimationPriority(priority);[probe.link invalidate];probe.link=nil;}else if(probe){__weak DGTransitionClock *weak=probe;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{DGTransitionClock *clock=weak;[clock.link invalidate];clock.link=nil;});}
}
- (void)pushViewController:(UIViewController *)controller animated:(BOOL)animated{CFTimeInterval start=CACurrentMediaTime();uint64_t priority=animated?DGBeginAnimationPriority(3):0;[super pushViewController:controller animated:animated];if(priority)[self trackTransition:priority started:start operation:@"push"];}
- (UIViewController *)popViewControllerAnimated:(BOOL)animated{CFTimeInterval start=CACurrentMediaTime();uint64_t priority=animated?DGBeginAnimationPriority(3):0;UIViewController *page=[super popViewControllerAnimated:animated];if(priority)[self trackTransition:priority started:start operation:@"pop"];return page;}
- (NSArray<UIViewController *> *)popToViewController:(UIViewController *)controller animated:(BOOL)animated{CFTimeInterval start=CACurrentMediaTime();uint64_t priority=animated?DGBeginAnimationPriority(3):0;NSArray *pages=[super popToViewController:controller animated:animated];if(priority)[self trackTransition:priority started:start operation:@"pop_to"];return pages;}
- (void)viewDidLoad{
 [super viewDidLoad];self.view.backgroundColor=UIColor.systemBackgroundColor;self.navigationBar.tintColor=UIColor.labelColor;self.interactivePopGestureRecognizer.enabled=YES;self.interactivePopGestureRecognizer.delegate=self;
 _rootBack=[[UIScreenEdgePanGestureRecognizer alloc]initWithTarget:self action:@selector(rootBack:)];_rootBack.edges=UIRectEdgeLeft;_rootBack.delegate=self;[self.view addGestureRecognizer:_rootBack];
 UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];[appearance configureWithTransparentBackground];appearance.backgroundEffect=nil;appearance.backgroundColor=UIColor.clearColor;appearance.shadowColor=UIColor.clearColor;appearance.titleTextAttributes=@{NSForegroundColorAttributeName:UIColor.labelColor};appearance.largeTitleTextAttributes=@{NSForegroundColorAttributeName:UIColor.labelColor};
 self.navigationBar.standardAppearance=appearance;self.navigationBar.scrollEdgeAppearance=appearance;self.navigationBar.compactAppearance=appearance;self.navigationBar.compactScrollEdgeAppearance=appearance;self.navigationBar.translucent=YES;
 _topBlur=[[UIVisualEffectView alloc]initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];_topBlur.userInteractionEnabled=NO;_fade=[[DGNavigationFade alloc]initWithFrame:CGRectZero];_topBlur.maskView=_fade;[self.view insertSubview:_topBlur belowSubview:self.navigationBar];
}
- (UIViewController *)childViewControllerForStatusBarStyle{return self.topViewController;}
- (UIViewController *)childViewControllerForStatusBarHidden{return self.topViewController;}
- (void)traitCollectionDidChange:(UITraitCollection *)previous{[super traitCollectionDidChange:previous];if([previous hasDifferentColorAppearanceComparedToTraitCollection:self.traitCollection])[self setNeedsStatusBarAppearanceUpdate];}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture{
 if(gesture!=self.interactivePopGestureRecognizer&&gesture!=_rootBack)return YES;
 UIViewController *top=self.topViewController;
 if(self.presentedViewController)return NO;
 if(self.transitionCoordinator&&!(gesture==self.interactivePopGestureRecognizer&&top.preferredTransition))return NO;
 if(self.modalInPresentation||top.modalInPresentation)return NO;
 if([top conformsToProtocol:@protocol(DGInPageBack)]&&[(id<DGInPageBack>)top dgHasPreviousPage])return NO;
 if(gesture==self.interactivePopGestureRecognizer)return self.viewControllers.count>1;
 return self.viewControllers.count==1&&self.presentingViewController&&[objc_getAssociatedObject(self,DGPageKey)isKindOfClass:DGPageTransition.class];
}
- (void)rootBack:(UIScreenEdgePanGestureRecognizer *)gesture{
 DGPageTransition *transition=objc_getAssociatedObject(self,DGPageKey);if(!transition)return;
 CGFloat fraction=MIN(1,MAX(0,[gesture translationInView:self.view].x/MAX(1,self.view.bounds.size.width)));
 switch(gesture.state){
  case UIGestureRecognizerStateBegan:
   transition.interaction=[UIPercentDrivenInteractiveTransition new];transition.interaction.completionCurve=UIViewAnimationCurveEaseOut;
   {UIViewController *page=self.topViewController;[self dismissViewControllerAnimated:YES completion:^{if(!self.presentingViewController&&[page respondsToSelector:@selector(dgDidReturnToPreviousPage)])[(id<DGInPageBack>)page dgDidReturnToPreviousPage];}];}break;
  case UIGestureRecognizerStateChanged:[transition.interaction updateInteractiveTransition:fraction];break;
  case UIGestureRecognizerStateEnded:
   if(fraction>.35||[gesture velocityInView:self.view].x>650)[transition.interaction finishInteractiveTransition];else[transition.interaction cancelInteractiveTransition];transition.interaction=nil;break;
  case UIGestureRecognizerStateCancelled:case UIGestureRecognizerStateFailed:[transition.interaction cancelInteractiveTransition];transition.interaction=nil;break;
  default:break;
 }
}
- (void)viewDidLayoutSubviews{
 [super viewDidLayoutSubviews];CGRect bar=[self.navigationBar convertRect:self.navigationBar.bounds toView:self.view];CGFloat height=MAX(1,CGRectGetMaxY(bar)+64);_topBlur.hidden=self.navigationBarHidden;CGRect frame=CGRectMake(0,0,self.view.bounds.size.width,height);
 if(!CGRectEqualToRect(_topBlur.frame,frame)){_topBlur.maskView=nil;_topBlur.frame=frame;_fade.frame=_topBlur.bounds;CGFloat edge=MAX(0,CGRectGetMaxY(bar)/height);((CAGradientLayer *)_fade.layer).locations=@[@0,@(edge),@(edge+(1-edge)*.34),@(edge+(1-edge)*.68),@1];_topBlur.maskView=_fade;}
}
@end

