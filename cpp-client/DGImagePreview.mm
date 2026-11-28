#import "DGCommon.h"
#import "DGAnimation.h"
#import "DGDiagnostics.h"
#import <objc/runtime.h>
#include "InteractionState.hpp"
#include "ContrastMap.hpp"

@interface DGImagePreview:UIViewController<UIScrollViewDelegate,UIGestureRecognizerDelegate,UIAdaptivePresentationControllerDelegate>
@property(nonatomic,copy) NSString *url;
@property(nonatomic,strong) UIImage *initialImage;
@property(nonatomic,strong) UIView *backgroundSnapshot;
@property(nonatomic,weak) UIImageView *source;
@property(nonatomic,weak) UIImageView *originalSource;
@property(nonatomic,strong) UIImageView *transitionSource;
@property(nonatomic) CGFloat sourceOriginalAlpha;
@property(nonatomic,strong) CALayer *sourceOriginalMask;
@property(nonatomic) BOOL inlinePreview;
@property(nonatomic,copy) dispatch_block_t finished;
@property(nonatomic,weak) UIViewController *reader;
@end
@implementation DGImagePreview{
 UIScrollView *_scroll;DGImage *_image;UIVisualEffectView *_closeGlass,*_saveGlass,*_backdropBlur;UIButton *_close,*_save;UIView *_backdrop;
 BOOL _closing,_completed;CGSize _layoutSize;
}
static const void *DGInlinePreviewKey=&DGInlinePreviewKey;
- (void)viewDidLoad{
 [super viewDidLoad];self.view.backgroundColor=UIColor.blackColor;
 // Freeze the reader only for the backdrop; never transform or relayout its
 // live table. Native source-to-image Zoom still owns the image transition.
 _backdrop=[UIView new];_backdrop.clipsToBounds=YES;_backdrop.userInteractionEnabled=NO;[self.view addSubview:_backdrop];
 if(self.backgroundSnapshot)[_backdrop addSubview:self.backgroundSnapshot];
 _backdropBlur=[[UIVisualEffectView alloc]initWithEffect:nil];_backdropBlur.userInteractionEnabled=NO;[_backdrop addSubview:_backdropBlur];
 _scroll=[[UIScrollView alloc]initWithFrame:self.view.bounds];_scroll.delegate=self;_scroll.minimumZoomScale=1;_scroll.maximumZoomScale=4;_scroll.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;_scroll.showsHorizontalScrollIndicator=NO;_scroll.showsVerticalScrollIndicator=NO;_scroll.alwaysBounceVertical=NO;_scroll.alwaysBounceHorizontal=NO;[self.view addSubview:_scroll];
 _image=[DGImage new];_image.maximumPixelSize=2048;_image.contentMode=UIViewContentModeScaleAspectFit;_image.showsLoadingIndicator=YES;_image.placeholderImage=self.initialImage;_image.image=self.initialImage;_image.accessibilityLabel=@"图片或表情包预览";_image.userInteractionEnabled=YES;[_scroll addSubview:_image];
 UITapGestureRecognizer *doubleTap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(doubleTap:)];doubleTap.numberOfTapsRequired=2;[_image addGestureRecognizer:doubleTap];
 UITapGestureRecognizer *background=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(close)];background.delegate=self;[_scroll addGestureRecognizer:background];
 UISwipeGestureRecognizer *swipe=[[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(close)];swipe.direction=UISwipeGestureRecognizerDirectionDown;swipe.delegate=self;[self.view addGestureRecognizer:swipe];
 _closeGlass=Glass(23);_close=Symbol(@"xmark",self,@selector(close));_close.accessibilityLabel=@"返回评论原位置";[_closeGlass.contentView addSubview:_close];[self.view addSubview:_closeGlass];
 _saveGlass=Glass(23);_save=Symbol(@"square.and.arrow.down",self,@selector(save));_save.accessibilityLabel=@"保存图片或表情包";[_saveGlass.contentView addSubview:_save];[self.view addSubview:_saveGlass];
 if(!self.initialImage.images.count)[_image remote:self.url];
 DGDiagnostic(@"image.preview.open",[NSString stringWithFormat:@"initial=%d animated=%d",self.initialImage!=nil,self.initialImage.images.count>1]);
}
- (void)viewDidLayoutSubviews{
 [super viewDidLayoutSubviews];CGSize size=self.view.bounds.size;
 _scroll.bounds=(CGRect){_scroll.bounds.origin,size};
 _scroll.center=CGPointMake(size.width/2,size.height/2);
 _backdrop.frame=self.view.bounds;self.backgroundSnapshot.bounds=_backdrop.bounds;self.backgroundSnapshot.center=CGPointMake(CGRectGetMidX(_backdrop.bounds),CGRectGetMidY(_backdrop.bounds));_backdropBlur.frame=_backdrop.bounds;
 if(!CGSizeEqualToSize(size,_layoutSize)){_layoutSize=size;[_scroll setZoomScale:1 animated:NO];_image.frame=_scroll.bounds;_scroll.contentSize=size;}
 CGFloat top=self.view.safeAreaInsets.top+8;_closeGlass.frame=CGRectMake(16,top,46,46);_saveGlass.frame=CGRectMake(size.width-62,top,46,46);_close.frame=_closeGlass.bounds;_save.frame=_saveGlass.bounds;
}
- (void)animateBackdrop:(BOOL)opening{
 void (^changes)(void)=^{self->_backdropBlur.effect=opening?[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]:nil;self.backgroundSnapshot.transform=opening&&!UIAccessibilityIsReduceMotionEnabled()?CGAffineTransformMakeScale(.96,.96):CGAffineTransformIdentity;self.backgroundSnapshot.alpha=opening?.78:1;};
 id<UIViewControllerTransitionCoordinator> transition=self.transitionCoordinator;
 if(!UIAccessibilityIsReduceMotionEnabled()&&transition){[transition animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context){changes();} completion:^(id<UIViewControllerTransitionCoordinatorContext> context){if(context.isCancelled){self->_backdropBlur.effect=!opening?[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]:nil;self.backgroundSnapshot.transform=!opening?CGAffineTransformMakeScale(.96,.96):CGAffineTransformIdentity;self.backgroundSnapshot.alpha=!opening?.78:1;}}];}else changes();
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];if(self.isBeingPresented)[self animateBackdrop:YES];}
- (UIStatusBarStyle)preferredStatusBarStyle{return UIStatusBarStyleLightContent;}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView{return _image;}
- (void)doubleTap:(UITapGestureRecognizer *)gesture{double scale=douglass::previewDoubleTapScale(_scroll.zoomScale);if(scale==1){[_scroll setZoomScale:1 animated:YES];return;}CGPoint point=[gesture locationInView:_image];auto region=douglass::previewZoomRegion(_image.bounds.size.width,_image.bounds.size.height,point.x,point.y,scale);[_scroll zoomToRect:CGRectMake(region.x,region.y,region.width,region.height) animated:YES];}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture{return ![gesture isKindOfClass:UISwipeGestureRecognizer.class]||_scroll.zoomScale<=1.05;}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch{
 if([gesture isKindOfClass:UISwipeGestureRecognizer.class])return ![touch.view isKindOfClass:UIControl.class];
 if(_scroll.zoomScale>1.05)return NO;UIImage *image=_image.image;if(!image)return YES;CGPoint point=[touch locationInView:_image];auto rect=douglass::fittedMedia(image.size.width,image.size.height,{0,0,_image.bounds.size.width,_image.bounds.size.height},false);return !CGRectContainsPoint(CGRectMake(rect.x,rect.y,rect.width,rect.height),point);
}
- (void)save{DGConfirmImageSave(self,self.url);}
- (CGAffineTransform)sourceTransform {
 UIImageView *source=self.originalSource;
 UIImage *image=_image.image;
 if(!source.window||!image||CGRectIsEmpty(_scroll.bounds))return CGAffineTransformMakeScale(.88,.88);
 CGRect target=[source convertRect:source.bounds toView:self.view];
 if(CGRectIsEmpty(target))return CGAffineTransformMakeScale(.88,.88);
 auto fit=douglass::fittedMedia(image.size.width,image.size.height,{0,0,_image.bounds.size.width,_image.bounds.size.height},false);
 if(fit.width<=0||fit.height<=0)return CGAffineTransformIdentity;
 CGRect content=[_image convertRect:CGRectMake(fit.x,fit.y,fit.width,fit.height) toView:_scroll];
 if(CGRectIsEmpty(content))return CGAffineTransformIdentity;
 CGFloat scale=MIN(target.size.width/content.size.width,target.size.height/content.size.height);
 CGFloat x=CGRectGetMidX(target)-_scroll.center.x-scale*(CGRectGetMidX(content)-CGRectGetMidX(_scroll.bounds));
 CGFloat y=CGRectGetMidY(target)-_scroll.center.y-scale*(CGRectGetMidY(content)-CGRectGetMidY(_scroll.bounds));
 return CGAffineTransformMake(scale,0,0,scale,x,y);
}
- (void)showInlineIn:(UIViewController *)presenter {
 [presenter addChildViewController:self];
 self.view.frame=presenter.view.bounds;
 self.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
 [presenter.view addSubview:self.view];
 [self didMoveToParentViewController:presenter];
 [self.view layoutIfNeeded];
 BOOL reduce=UIAccessibilityIsReduceMotionEnabled();
 _scroll.transform=reduce?CGAffineTransformIdentity:[self sourceTransform];
 _scroll.alpha=reduce?0:1;
 _closeGlass.alpha=_saveGlass.alpha=0;_backdrop.alpha=0;
 self.view.backgroundColor=UIColor.clearColor;
 DGAnimate(.24,^{
  self->_scroll.transform=CGAffineTransformIdentity;self->_scroll.alpha=1;
  self->_backdrop.alpha=1;
  self->_backdropBlur.effect=[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark];
  self.backgroundSnapshot.transform=reduce?CGAffineTransformIdentity:CGAffineTransformMakeScale(.96,.96);
  self->_closeGlass.alpha=self->_saveGlass.alpha=1;
 },nil);
}
- (void)complete{
 if(_completed)return;_completed=YES;dispatch_block_t action=self.finished;self.finished=nil;
 [UIView performWithoutAnimation:^{
  if(self.inlinePreview){
   self.originalSource.layer.mask=self.sourceOriginalMask;
   if(objc_getAssociatedObject(self.reader,DGInlinePreviewKey)==self)
    objc_setAssociatedObject(self.reader,DGInlinePreviewKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
   [self willMoveToParentViewController:nil];[self.view removeFromSuperview];[self removeFromParentViewController];
  }else self.originalSource.alpha=self.sourceOriginalAlpha;
  self.originalSource=nil;[self.transitionSource removeFromSuperview];self.transitionSource=nil;if(action)action();
 }];DGDiagnostic(@"image.preview.closed",nil);
}
- (BOOL)finishInlineReturn {if(!_closing||!self.inlinePreview)return NO;[self complete];return YES;}
- (void)close{
 if(_closing)return;
 if([self.reader respondsToSelector:@selector(dgPreviewWillClose)])[self.reader performSelector:@selector(dgPreviewWillClose)];
 if(self.inlinePreview){
  _closing=YES;self.view.userInteractionEnabled=NO;
  CALayer *visible=_scroll.layer.presentationLayer;
  if(visible){CGAffineTransform current=visible.affineTransform;[_scroll.layer removeAllAnimations];_scroll.transform=current;}
  BOOL reduce=UIAccessibilityIsReduceMotionEnabled();
  CGAffineTransform target=reduce?CGAffineTransformIdentity:[self sourceTransform];
  DGAnimate(.24,^{
   self->_scroll.transform=target;self->_scroll.alpha=reduce?0:1;
   self->_backdropBlur.effect=nil;self.backgroundSnapshot.transform=CGAffineTransformIdentity;self->_backdrop.alpha=0;
   self->_closeGlass.alpha=self->_saveGlass.alpha=0;
  },^(BOOL finished){[self complete];});
  return;
 }
 _closing=YES;self.view.userInteractionEnabled=NO;self.presentationController.containerView.userInteractionEnabled=NO;uint64_t priority=DGBeginAnimationPriority(1);[self dismissViewControllerAnimated:YES completion:^{DGEndAnimationPriority(priority);[self complete];}];
}
- (void)viewDidDisappear:(BOOL)animated{[super viewDidDisappear:animated];if(self.isBeingDismissed||!self.presentingViewController)[self complete];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];if(self.isBeingDismissed){[self animateBackdrop:NO];if([self.reader respondsToSelector:@selector(dgPreviewWillClose)])[self.reader performSelector:@selector(dgPreviewWillClose)];}}
- (void)presentationControllerDidDismiss:(UIPresentationController *)controller{[self complete];}
- (void)dealloc{if(_inlinePreview)_originalSource.layer.mask=_sourceOriginalMask;else _originalSource.alpha=_sourceOriginalAlpha;[_transitionSource removeFromSuperview];}
@end
BOOL DGFinishClosingImagePreview(UIViewController *host){
 DGImagePreview *preview=objc_getAssociatedObject(host,DGInlinePreviewKey);
 return [preview finishInlineReturn];
}
BOOL DGShowImageWithCompletion(UIViewController *host,NSString *url,UIImageView *source,dispatch_block_t completion){
 if(!host||!url.length)return NO;UIViewController *presenter=host;while(presenter.parentViewController&&![presenter.parentViewController isKindOfClass:UINavigationController.class])presenter=presenter.parentViewController;
 if(presenter.presentedViewController||!host.viewIfLoaded.window)return NO;
 DGImagePreview *page=[DGImagePreview new];page.url=url;page.source=source;page.reader=host;page.initialImage=source.image;page.originalSource=source;page.sourceOriginalAlpha=source.alpha;page.finished=completion;page.modalPresentationStyle=UIModalPresentationFullScreen;page.modalPresentationCapturesStatusBarAppearance=YES;
 if(completion){
  page.inlinePreview=YES;
  page.sourceOriginalMask=source.layer.mask;
  source.layer.mask=[CALayer layer];
  if([host respondsToSelector:@selector(dgCapturePreviewSnapshot)])[host performSelector:@selector(dgCapturePreviewSnapshot)];
  page.backgroundSnapshot=[presenter.view snapshotViewAfterScreenUpdates:YES];
  objc_setAssociatedObject(host,DGInlinePreviewKey,page,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [page showInlineIn:presenter];
  return YES;
 }
 // A dedicated source participates in UIKit Zoom. Both backdrop snapshots omit
 // it, so the return animation never flies over a second copy of the image.
 if(source.superview&&source.bounds.size.width>0&&source.bounds.size.height>0){UIImageView *proxy=[[UIImageView alloc]initWithImage:source.image];proxy.bounds=source.bounds;proxy.center=source.center;proxy.transform=source.transform;proxy.contentMode=source.contentMode;proxy.clipsToBounds=source.clipsToBounds;proxy.layer.cornerRadius=source.layer.cornerRadius;proxy.autoresizingMask=source.autoresizingMask;proxy.alpha=source.alpha;proxy.userInteractionEnabled=NO;proxy.accessibilityElementsHidden=YES;proxy.hidden=YES;[source.superview insertSubview:proxy aboveSubview:source];page.transitionSource=proxy;page.source=proxy;source.alpha=0;}
 if([host respondsToSelector:@selector(dgCapturePreviewSnapshot)])[host performSelector:@selector(dgCapturePreviewSnapshot)];page.backgroundSnapshot=[presenter.view snapshotViewAfterScreenUpdates:YES];page.transitionSource.hidden=NO;
 if(!UIAccessibilityIsReduceMotionEnabled()){UIZoomTransitionOptions *options=[UIZoomTransitionOptions new];options.dimmingVisualEffect=[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];__weak UIImageView *weak=page.source;page.preferredTransition=[UIViewControllerTransition zoomWithOptions:options sourceViewProvider:^UIView *(UIZoomTransitionSourceViewProviderContext *context){return weak;}];}
 uint64_t priority=DGBeginAnimationPriority(1);[presenter presentViewController:page animated:YES completion:^{DGEndAnimationPriority(priority);}];page.presentationController.delegate=page;return YES;
}
void DGShowImage(UIViewController *host,NSString *url,UIImageView *source){DGShowImageWithCompletion(host,url,source,nil);}
BOOL DGImagePreviewKeepsPlayback(UIViewController *controller){return [controller isKindOfClass:DGImagePreview.class];}
