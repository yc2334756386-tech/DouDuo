#import "DGCommon.h"
#import "DGAnimation.h"
#import "DGDiagnostics.h"
#include "InteractionState.hpp"
#include "ContrastMap.hpp"

@interface DGImagePreview:UIViewController<UIScrollViewDelegate,UIGestureRecognizerDelegate,UIAdaptivePresentationControllerDelegate>
@property(nonatomic,copy) NSString *url;
@property(nonatomic,strong) UIImage *initialImage;
@property(nonatomic,weak) UIImageView *source;
@property(nonatomic,copy) dispatch_block_t finished;
@end
@implementation DGImagePreview{
 UIScrollView *_scroll;DGImage *_image;UIVisualEffectView *_closeGlass,*_saveGlass;UIButton *_close,*_save;
 BOOL _closing,_completed;CGSize _layoutSize;
}
- (void)viewDidLoad{
 [super viewDidLoad];self.view.backgroundColor=UIColor.blackColor;
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
 [super viewDidLayoutSubviews];CGSize size=self.view.bounds.size;_scroll.frame=self.view.bounds;
 if(!CGSizeEqualToSize(size,_layoutSize)){_layoutSize=size;[_scroll setZoomScale:1 animated:NO];_image.frame=_scroll.bounds;_scroll.contentSize=size;}
 CGFloat top=self.view.safeAreaInsets.top+8;_closeGlass.frame=CGRectMake(16,top,46,46);_saveGlass.frame=CGRectMake(size.width-62,top,46,46);_close.frame=_closeGlass.bounds;_save.frame=_saveGlass.bounds;
}
- (UIStatusBarStyle)preferredStatusBarStyle{return UIStatusBarStyleLightContent;}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView{return _image;}
- (void)doubleTap:(UITapGestureRecognizer *)gesture{double scale=douglass::previewDoubleTapScale(_scroll.zoomScale);if(scale==1){[_scroll setZoomScale:1 animated:YES];return;}CGPoint point=[gesture locationInView:_image];auto region=douglass::previewZoomRegion(_image.bounds.size.width,_image.bounds.size.height,point.x,point.y,scale);[_scroll zoomToRect:CGRectMake(region.x,region.y,region.width,region.height) animated:YES];}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture{return ![gesture isKindOfClass:UISwipeGestureRecognizer.class]||_scroll.zoomScale<=1.05;}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch{
 if([gesture isKindOfClass:UISwipeGestureRecognizer.class])return ![touch.view isKindOfClass:UIControl.class];
 if(_scroll.zoomScale>1.05)return NO;UIImage *image=_image.image;if(!image)return YES;CGPoint point=[touch locationInView:_image];auto rect=douglass::fittedMedia(image.size.width,image.size.height,{0,0,_image.bounds.size.width,_image.bounds.size.height},false);return !CGRectContainsPoint(CGRectMake(rect.x,rect.y,rect.width,rect.height),point);
}
- (void)save{DGConfirmImageSave(self,self.url);}
- (void)complete{
 if(_completed)return;_completed=YES;dispatch_block_t action=self.finished;self.finished=nil;if(action)action();DGDiagnostic(@"image.preview.closed",nil);[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];
}
- (void)close{
 if(_closing)return;
 _closing=YES;uint64_t priority=DGBeginAnimationPriority(1);[self dismissViewControllerAnimated:YES completion:^{DGEndAnimationPriority(priority);[self complete];}];
}
- (void)viewDidDisappear:(BOOL)animated{[super viewDidDisappear:animated];if(self.isBeingDismissed||!self.presentingViewController)[self complete];}
- (void)presentationControllerDidDismiss:(UIPresentationController *)controller{[self complete];}
@end
BOOL DGShowImageWithCompletion(UIViewController *host,NSString *url,UIImageView *source,dispatch_block_t completion){
 if(!host||!url.length)return NO;UIViewController *presenter=host;while(presenter.parentViewController&&![presenter.parentViewController isKindOfClass:UINavigationController.class])presenter=presenter.parentViewController;
 if(presenter.presentedViewController||!host.viewIfLoaded.window)return NO;
 DGImagePreview *page=[DGImagePreview new];page.url=url;page.source=source;page.initialImage=source.image;page.finished=completion;page.modalPresentationStyle=UIModalPresentationFullScreen;page.modalPresentationCapturesStatusBarAppearance=YES;
 if(!UIAccessibilityIsReduceMotionEnabled()){UIZoomTransitionOptions *options=[UIZoomTransitionOptions new];options.dimmingVisualEffect=[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];__weak UIImageView *weak=source;page.preferredTransition=[UIViewControllerTransition zoomWithOptions:options sourceViewProvider:^UIView *(UIZoomTransitionSourceViewProviderContext *context){return weak;}];}
 uint64_t priority=DGBeginAnimationPriority(1);[presenter presentViewController:page animated:YES completion:^{DGEndAnimationPriority(priority);}];page.presentationController.delegate=page;return YES;
}
void DGShowImage(UIViewController *host,NSString *url,UIImageView *source){DGShowImageWithCompletion(host,url,source,nil);}
