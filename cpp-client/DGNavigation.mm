#import "DGAnimation.h"
#import "DGCommon.h"
#import "DGDiagnostics.h"
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
static const void *DGWorkKey=&DGWorkKey;
void DGConfigureWorkTransition(UIViewController *player,UIView *(^source)(void)){objc_setAssociatedObject(player,DGWorkKey,source,OBJC_ASSOCIATION_COPY_NONATOMIC);}
@interface DGWorkAnimator:NSObject<UIViewControllerAnimatedTransitioning>
@property(nonatomic) BOOL opening;
@property(nonatomic,copy) UIView *(^source)(void);
@end
@implementation DGWorkAnimator
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context{return MIN(.30,MAX(.16,DGDuration(.20)));}
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context{
 CFTimeInterval started=CACurrentMediaTime();DGDiagnostic(@"transition.work_begin",self.opening?@"direction=open":@"direction=close");
 UIView *container=context.containerView,*from=[context viewForKey:UITransitionContextFromViewKey],*to=[context viewForKey:UITransitionContextToViewKey];
 UIViewController *destination=[context viewControllerForKey:UITransitionContextToViewControllerKey];if(!to)to=destination.view;to.frame=[context finalFrameForViewController:destination];
 if(self.opening)[container addSubview:to];else [container insertSubview:to belowSubview:from];
 UIView *source=self.source?self.source():nil;CGRect anchor=source.window?[source convertRect:source.bounds toView:container]:CGRectInset(container.bounds,container.bounds.size.width*.3,container.bounds.size.height*.35);
 UIView *cover=[source snapshotViewAfterScreenUpdates:NO];cover.userInteractionEnabled=NO;cover.layer.cornerRadius=8;cover.clipsToBounds=YES;
 if(cover){cover.frame=self.opening?anchor:container.bounds;[container addSubview:cover];}
 to.alpha=self.opening?0:1;to.transform=self.opening?CGAffineTransformMakeScale(.96,.96):CGAffineTransformIdentity;
 [UIView animateWithDuration:[self transitionDuration:context] delay:0 options:UIViewAnimationOptionCurveEaseOut|UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionBeginFromCurrentState animations:^{
  to.alpha=1;to.transform=CGAffineTransformIdentity;if(!self.opening){from.alpha=0;from.transform=CGAffineTransformMakeScale(.96,.96);}if(cover){cover.frame=self.opening?container.bounds:anchor;cover.alpha=0;}
 } completion:^(BOOL finished){BOOL complete=!context.transitionWasCancelled;from.alpha=1;from.transform=CGAffineTransformIdentity;to.alpha=1;to.transform=CGAffineTransformIdentity;[cover removeFromSuperview];[context completeTransition:complete];DGDiagnostic(@"transition.work_end",[NSString stringWithFormat:@"direction=%@ ms=%.0f complete=%d",self.opening?@"open":@"close",(CACurrentMediaTime()-started)*1000,complete]);}];
}
@end
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
@interface DGNavigationController()<UIGestureRecognizerDelegate,UINavigationControllerDelegate>
@end
@implementation DGNavigationController{
 UIVisualEffectView *_topBlur;DGNavigationFade *_fade;UIScreenEdgePanGestureRecognizer *_rootBack;
}
- (void)viewDidLoad{
 [super viewDidLoad];self.delegate=self;self.view.backgroundColor=UIColor.systemBackgroundColor;self.navigationBar.tintColor=UIColor.labelColor;self.interactivePopGestureRecognizer.enabled=YES;self.interactivePopGestureRecognizer.delegate=self;
 _rootBack=[[UIScreenEdgePanGestureRecognizer alloc]initWithTarget:self action:@selector(rootBack:)];_rootBack.edges=UIRectEdgeLeft;_rootBack.delegate=self;[self.view addGestureRecognizer:_rootBack];
 UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];[appearance configureWithTransparentBackground];appearance.backgroundEffect=nil;appearance.backgroundColor=UIColor.clearColor;appearance.shadowColor=UIColor.clearColor;appearance.titleTextAttributes=@{NSForegroundColorAttributeName:UIColor.labelColor};appearance.largeTitleTextAttributes=@{NSForegroundColorAttributeName:UIColor.labelColor};
 self.navigationBar.standardAppearance=appearance;self.navigationBar.scrollEdgeAppearance=appearance;self.navigationBar.compactAppearance=appearance;self.navigationBar.compactScrollEdgeAppearance=appearance;self.navigationBar.translucent=YES;
 _topBlur=[[UIVisualEffectView alloc]initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];_topBlur.userInteractionEnabled=NO;_fade=[[DGNavigationFade alloc]initWithFrame:CGRectZero];_topBlur.maskView=_fade;[self.view insertSubview:_topBlur belowSubview:self.navigationBar];
}
- (UIViewController *)childViewControllerForStatusBarStyle{return self.topViewController;}
- (UIViewController *)childViewControllerForStatusBarHidden{return self.topViewController;}
- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigation animationControllerForOperation:(UINavigationControllerOperation)operation fromViewController:(UIViewController *)from toViewController:(UIViewController *)to{
 UIViewController *player=operation==UINavigationControllerOperationPush?to:from;id source=objc_getAssociatedObject(player,DGWorkKey);if(!source||UIAccessibilityIsReduceMotionEnabled())return nil;
 DGWorkAnimator *animation=[DGWorkAnimator new];animation.opening=operation==UINavigationControllerOperationPush;animation.source=source;return animation;
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous{[super traitCollectionDidChange:previous];if([previous hasDifferentColorAppearanceComparedToTraitCollection:self.traitCollection])[self setNeedsStatusBarAppearanceUpdate];}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture{
 if(gesture!=self.interactivePopGestureRecognizer&&gesture!=_rootBack)return YES;
 if(self.transitionCoordinator||self.presentedViewController)return NO;
 UIViewController *top=self.topViewController;
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

