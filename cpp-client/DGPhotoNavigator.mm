#import "DGPhotoNavigator.h"
#import "DGAnimation.h"
#include "InteractionState.hpp"
@interface DGPhotoNavigator()<UIGestureRecognizerDelegate>
- (void)edgeTick:(CADisplayLink *)link;
@end
@interface DGPhotoEdgeClock:NSObject
@property(nonatomic,weak) DGPhotoNavigator *owner;
@end
@implementation DGPhotoEdgeClock
- (void)tick:(CADisplayLink *)link{DGPhotoNavigator *owner=_owner;if(owner)[owner edgeTick:link];else [link invalidate];}
@end
@implementation DGPhotoNavigator{
 NSArray<NSString *> *_urls;NSMutableArray<DGImage *> *_images;NSInteger _index;
 BOOL _browsing;NSUInteger _imageGeneration;douglass::GalleryScrubber _scrubber;
 UIPanGestureRecognizer *_pan;UIView *_thumbnails;UILabel *_count;CALayer *_selection;
 CADisplayLink *_edgeLink;CFTimeInterval _edgeTimestamp;
}
- (instancetype)initWithFrame:(CGRect)frame{
 if((self=[super initWithFrame:frame])){
  self.backgroundColor=UIColor.clearColor;self.clipsToBounds=NO;_images=[NSMutableArray array];
  _thumbnails=[UIView new];_thumbnails.clipsToBounds=YES;_thumbnails.userInteractionEnabled=NO;_thumbnails.hidden=YES;[self addSubview:_thumbnails];_selection=[CALayer layer];_selection.borderColor=UIColor.whiteColor.CGColor;_selection.borderWidth=1.5;_selection.cornerRadius=5;_selection.hidden=YES;[self.layer addSublayer:_selection];
  _pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)];_pan.maximumNumberOfTouches=1;_pan.delegate=self;[self addGestureRecognizer:_pan];
  [self addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tap:)]];
  _count=Label(15,UIFontWeightMedium);_count.textAlignment=NSTextAlignmentCenter;_count.hidden=YES;_count.layer.shadowColor=UIColor.blackColor.CGColor;_count.layer.shadowOpacity=.55;_count.layer.shadowRadius=2;_count.layer.shadowOffset=CGSizeMake(0,1);[self addSubview:_count];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationInactive:) name:UIApplicationWillResignActiveNotification object:nil];
 }return self;
}
- (void)dealloc{[_edgeLink invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)applicationInactive:(NSNotification *)notification{[self cancelBrowsing];}
- (BOOL)browsing{return _browsing;}
- (UIImage *)selectedThumbnail{return _index>=0&&_index<(NSInteger)_images.count?_images[_index].image:nil;}
- (void)setBrowsing:(BOOL)value{
 if(!value)[self stopEdgeClock];
 if(_browsing==value)return;_browsing=value;_thumbnails.hidden=!value;_selection.hidden=!value;_count.hidden=!value;
 if(value){_thumbnails.alpha=0;_count.alpha=0;[self loadVisibleThumbnails];}else for(DGImage *image in _images)[image remote:@""];
 [self setNeedsDisplay];[self setNeedsLayout];if(self.onBrowsingChanged)self.onBrowsingChanged(value);
 if(value)DGAnimate(.12,^{self->_thumbnails.alpha=1;self->_count.alpha=1;},nil);
}
- (void)cancelBrowsing{
 [self stopEdgeClock];
 if(!_browsing)return;[self finishBrowsing];_pan.enabled=NO;_pan.enabled=YES;
}
- (void)images:(NSArray<NSString *> *)urls{
 [self cancelBrowsing];NSUInteger generation=++_imageGeneration;_urls=urls.copy;_index=0;_count.attributedText=nil;
 for(UIView *image in _images)[image removeFromSuperview];[_images removeAllObjects];
 __weak DGPhotoNavigator *weak=self;NSUInteger position=0;for(NSString *url in urls){NSUInteger index=position++;DGImage *image=[DGImage new];image.imageReady=^(UIImage *thumbnail){DGPhotoNavigator *view=weak;if(view&&generation==view->_imageGeneration&&view->_browsing&&view->_index==(NSInteger)index&&view.onThumbnailReady)view.onThumbnailReady(thumbnail);};image.maximumPixelSize=144;image.lowPriority=YES;image.contentMode=UIViewContentModeScaleAspectFill;image.clipsToBounds=YES;image.backgroundColor=[UIColor colorWithWhite:1 alpha:.12];image.showsLoadingIndicator=YES;[_thumbnails addSubview:image];[_images addObject:image];}
 [self page:0];[self setNeedsLayout];
}
- (void)page:(NSInteger)index{
 index=MIN(MAX(0,index),MAX(0,(NSInteger)_urls.count-1));BOOL changed=index!=_index;_index=index;
 if(!changed&&_count.attributedText.length)return;
 NSString *current=[NSString stringWithFormat:@"%ld",_urls.count?(long)_index+1:0];NSMutableAttributedString *text=[[NSMutableAttributedString alloc]initWithString:[current stringByAppendingFormat:@"  /  %lu",(unsigned long)_urls.count] attributes:@{NSFontAttributeName:_count.font,NSForegroundColorAttributeName:[UIColor colorWithWhite:1 alpha:.48]}];[text addAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.whiteColor} range:NSMakeRange(0,current.length)];_count.attributedText=text;
 if(_browsing)[self loadVisibleThumbnails];[self setNeedsDisplay];[self setNeedsLayout];
}
- (void)loadVisibleThumbnails{
 for(NSUInteger i=0;i<_images.count;i++){double x=_scrubber.thumbnailX(i);[_images[i]remote:x>=-70&&x<=self.bounds.size.width+70?_urls[i]:@""];}
}
- (void)layoutSubviews{
 [super layoutSubviews];CGFloat width=self.bounds.size.width;_thumbnails.frame=CGRectMake(0,-14,width,58);_count.frame=CGRectMake(0,48,width,21);
 if(!_browsing)return;
 [CATransaction begin];[CATransaction setDisableActions:YES];_selection.frame=CGRectMake(width/2-18,-12,36,54);
 for(NSUInteger i=0;i<_images.count;i++){CGFloat focus=MAX(0,1-fabs((double)i-_scrubber.position())),w=24+10*focus,h=38+14*focus;DGImage *image=_images[i];image.frame=CGRectMake(_scrubber.thumbnailX(i)-w/2,(58-h)/2,w,h);image.layer.cornerRadius=4;image.layer.borderWidth=0;}
 [CATransaction commit];
}
- (void)drawRect:(CGRect)rect{
 CGContextClearRect(UIGraphicsGetCurrentContext(),self.bounds);if(_browsing)return;
 NSInteger count=MIN((NSInteger)15,(NSInteger)_urls.count);CGFloat total=MAX(0,count-1)*12,start=(self.bounds.size.width-total)/2;NSInteger first=MIN(MAX(0,_index-count/2),MAX(0,(NSInteger)_urls.count-count));
 for(NSInteger dot=0;dot<count;dot++){BOOL active=first+dot==_index;[(active?UIColor.whiteColor:[UIColor colorWithWhite:1 alpha:.35])setFill];CGFloat size=active?6:4;[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(start+dot*12-size/2,(self.bounds.size.height-size)/2,size,size)]fill];}
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event{
 if(_browsing)return CGRectContainsPoint(CGRectMake(0,-16,self.bounds.size.width,88),point);
 CGFloat band=MIN(self.bounds.size.width,MAX(44,(MIN((NSInteger)15,(NSInteger)_urls.count)-1)*12+28));return CGRectContainsPoint(CGRectMake((self.bounds.size.width-band)/2,-6,band,self.bounds.size.height+12),point);
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture{
 if(gesture!=_pan)return YES;CGPoint speed=[_pan velocityInView:self];return _urls.count>1&&fabs(speed.x)>fabs(speed.y);
}
- (void)didMoveToWindow{
 [super didMoveToWindow];if(!self.window){[self cancelBrowsing];return;}
 for(UIView *view=self.superview;view;view=view.superview)if([view isKindOfClass:UIScrollView.class])[((UIScrollView *)view).panGestureRecognizer requireGestureRecognizerToFail:_pan];
}
- (void)applyScrub{
 NSInteger index=(NSInteger)llround(_scrubber.position());if(index!=_index){DGHaptic();[self page:index];if(self.onSelect)self.onSelect(index);}
 [self setNeedsLayout];[self layoutIfNeeded];[self loadVisibleThumbnails];
}
- (void)stopEdgeClock{[_edgeLink invalidate];_edgeLink=nil;_edgeTimestamp=0;}
- (void)updateEdgeClock{
 if(!_browsing||!self.window||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||!_scrubber.canAdvanceAtEdge()){[self stopEdgeClock];return;}
 if(_edgeLink)return;DGPhotoEdgeClock *clock=[DGPhotoEdgeClock new];clock.owner=self;_edgeTimestamp=0;_edgeLink=[CADisplayLink displayLinkWithTarget:clock selector:@selector(tick:)];DGApplyDisplayLinkRate(_edgeLink,self);[_edgeLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)edgeTick:(CADisplayLink *)link{
 if(link!=_edgeLink)return;
 if(!_browsing||!self.window||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||(_pan.state!=UIGestureRecognizerStateBegan&&_pan.state!=UIGestureRecognizerStateChanged)){[self cancelBrowsing];return;}
 CFTimeInterval elapsed=_edgeTimestamp?link.timestamp-_edgeTimestamp:0;_edgeTimestamp=link.timestamp;
 if(_scrubber.advanceEdge(elapsed))[self applyScrub];if(!_scrubber.canAdvanceAtEdge())[self stopEdgeClock];
}
- (void)finishBrowsing{
 [self stopEdgeClock];
 if(!_browsing)return;NSInteger index=(NSInteger)_scrubber.finish();[self page:index];if(self.onSelect)self.onSelect(index);[self setBrowsing:NO];
}
- (void)pan:(UIPanGestureRecognizer *)gesture{
 CGPoint point=[gesture locationInView:self];
 if(gesture.state==UIGestureRecognizerStateBegan){CGPoint delta=[gesture translationInView:self];_scrubber.begin(_index,point.x-delta.x,self.bounds.size.width,_urls.count);[self setBrowsing:YES];}
 if(gesture.state==UIGestureRecognizerStateBegan||gesture.state==UIGestureRecognizerStateChanged){_scrubber.move(point.x);[self applyScrub];[self updateEdgeClock];}
 if(gesture.state==UIGestureRecognizerStateEnded||gesture.state==UIGestureRecognizerStateCancelled||gesture.state==UIGestureRecognizerStateFailed)[self finishBrowsing];
}
- (void)tap:(UITapGestureRecognizer *)gesture{
 if(!_urls.count)return;CGPoint point=[gesture locationInView:self];NSInteger index;
 if(_browsing)index=(NSInteger)_scrubber.indexAt(point.x);
 else{NSInteger count=MIN((NSInteger)15,(NSInteger)_urls.count),first=MIN(MAX(0,_index-count/2),MAX(0,(NSInteger)_urls.count-count));CGFloat start=(self.bounds.size.width-MAX(0,count-1)*12)/2;index=first+MIN(MAX(0,(NSInteger)llround((point.x-start)/12)),count-1);}
 index=MIN(MAX(0,index),MAX(0,(NSInteger)_urls.count-1));if(index!=_index)DGHaptic();[self page:index];if(self.onSelect)self.onSelect(index);if(_browsing)[self setBrowsing:NO];
}
@end
