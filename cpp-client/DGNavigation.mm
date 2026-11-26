#import "DGCommon.h"
#import <objc/runtime.h>
@interface DGBackGesture:NSObject<UIGestureRecognizerDelegate>
@property(nonatomic,weak) UIViewController *controller;
@end
@implementation DGBackGesture
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture{UIViewController *host=self.controller;if([host isKindOfClass:UINavigationController.class])return host.presentingViewController&&((UINavigationController *)host).viewControllers.count<=1;return host.presentingViewController!=nil;}
- (void)swipe:(UIScreenEdgePanGestureRecognizer *)gesture{UIViewController *host=self.controller;CGFloat x=MAX(0,[gesture translationInView:host.view].x);if(gesture.state==UIGestureRecognizerStateChanged)host.view.transform=CGAffineTransformMakeTranslation(x*.85,0);if(gesture.state==UIGestureRecognizerStateEnded){if(x>80||[gesture velocityInView:host.view].x>650){[host dismissViewControllerAnimated:YES completion:^{host.view.transform=CGAffineTransformIdentity;[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];}else[UIView animateWithDuration:.2 animations:^{host.view.transform=CGAffineTransformIdentity;}];}if(gesture.state==UIGestureRecognizerStateCancelled||gesture.state==UIGestureRecognizerStateFailed)[UIView animateWithDuration:.2 animations:^{host.view.transform=CGAffineTransformIdentity;}];}
@end
void DGInstallBackGesture(UIViewController *controller){if(objc_getAssociatedObject(controller,@selector(DGInstallBackGestureMarker)))return;DGBackGesture *target=[DGBackGesture new];target.controller=controller;UIScreenEdgePanGestureRecognizer *pan=[[UIScreenEdgePanGestureRecognizer alloc]initWithTarget:target action:@selector(swipe:)];pan.edges=UIRectEdgeLeft;pan.delegate=target;[controller.view addGestureRecognizer:pan];objc_setAssociatedObject(controller,@selector(DGInstallBackGestureMarker),target,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
@implementation DGNavigationController
- (void)viewDidLoad{[super viewDidLoad];self.interactivePopGestureRecognizer.enabled=YES;DGInstallBackGesture(self);}
@end

