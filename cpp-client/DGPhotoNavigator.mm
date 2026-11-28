#import "DGPhotoNavigator.h"
#import "DGAnimation.h"
@interface DGPhotoStrip:UIScrollView
@property(nonatomic) BOOL allowsBrowsing;
@end
@implementation DGPhotoStrip
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture{
 if(gesture==self.panGestureRecognizer){CGPoint velocity=[self.panGestureRecognizer velocityInView:self];return _allowsBrowsing&&fabs(velocity.x)>fabs(velocity.y);}
 return [super gestureRecognizerShouldBegin:gesture];
}
@end
@interface DGPhotoNavigator()<UIScrollViewDelegate>
@end
@implementation DGPhotoNavigator{
 NSArray<NSString *> *_urls;NSMutableArray<DGImage *> *_images;NSInteger _index;
 BOOL _browsing;NSUInteger _collapseToken;double _position;CGFloat _layoutWidth;
 DGPhotoStrip *_thumbnails;UILabel *_count;
}
- (instancetype)initWithFrame:(CGRect)frame{
 if((self=[super initWithFrame:frame])){
  self.backgroundColor=UIColor.clearColor;self.clipsToBounds=NO;
  _images=[NSMutableArray array];_thumbnails=[DGPhotoStrip new];_thumbnails.backgroundColor=UIColor.clearColor;_thumbnails.showsHorizontalScrollIndicator=NO;_thumbnails.showsVerticalScrollIndicator=NO;_thumbnails.alwaysBounceVertical=NO;_thumbnails.directionalLockEnabled=YES;_thumbnails.decelerationRate=UIScrollViewDecelerationRateFast;_thumbnails.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;_thumbnails.delegate=self;[_thumbnails.panGestureRecognizer addTarget:self action:@selector(panState:)];[self addSubview:_thumbnails];
  [self addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tap:)]];
  _count=Label(15,UIFontWeightMedium);_count.textAlignment=NSTextAlignmentCenter;_count.hidden=YES;_count.layer.shadowColor=UIColor.blackColor.CGColor;_count.layer.shadowOpacity=.55;_count.layer.shadowRadius=2;_count.layer.shadowOffset=CGSizeMake(0,1);[self addSubview:_count];
 }return self;
}
- (BOOL)browsing{return _browsing;}
- (void)cancelBrowsing{
 ++_collapseToken;[_thumbnails setContentOffset:_thumbnails.contentOffset animated:NO];_thumbnails.panGestureRecognizer.enabled=NO;_thumbnails.panGestureRecognizer.enabled=YES;
 if(_browsing)[self finishBrowsing];[self setBrowsing:NO];
}
- (void)setBrowsing:(BOOL)value{
 ++_collapseToken;if(_browsing==value)return;_browsing=value;
 for(DGImage *image in _images){image.hidden=!value;image.alpha=value?0:1;}
 if(value){_count.hidden=NO;_count.alpha=0;[self loadVisibleThumbnails];}
 [self setNeedsDisplay];[self setNeedsLayout];if(self.onBrowsingChanged)self.onBrowsingChanged(value);
 DGAnimate(.18,^{for(DGImage *image in self->_images)image.alpha=value?1:0;self->_count.alpha=value?1:0;},^(BOOL done){if(!self->_browsing){self->_count.hidden=YES;for(DGImage *image in self->_images)[image remote:@""];}});
}
- (void)images:(NSArray<NSString *> *)urls{
 [self cancelBrowsing];_urls=urls.copy;_index=0;_position=0;_count.attributedText=nil;_layoutWidth=0;_thumbnails.allowsBrowsing=urls.count>1;
 for(UIView *image in _images)[image removeFromSuperview];[_images removeAllObjects];
 for(NSString *url in urls){DGImage *image=[DGImage new];image.maximumPixelSize=160;image.lowPriority=YES;image.contentMode=UIViewContentModeScaleAspectFill;image.clipsToBounds=YES;image.backgroundColor=[UIColor colorWithWhite:1 alpha:.12];image.showsLoadingIndicator=YES;image.hidden=YES;[_thumbnails addSubview:image];[_images addObject:image];}
 [self page:0];[self setNeedsLayout];
}
- (void)page:(NSInteger)index{
 index=MIN(MAX(0,index),MAX(0,(NSInteger)_urls.count-1));BOOL changed=index!=_index;_index=index;
 if(!_browsing){_position=index;if(!_thumbnails.dragging&&!_thumbnails.decelerating)[_thumbnails setContentOffset:CGPointMake(index*38,0) animated:NO];}
 if(!changed&&_count.attributedText.length)return;
 NSString *current=[NSString stringWithFormat:@"%ld",_urls.count?(long)_index+1:0];NSMutableAttributedString *text=[[NSMutableAttributedString alloc]initWithString:[current stringByAppendingFormat:@"  /  %lu",(unsigned long)_urls.count] attributes:@{NSFontAttributeName:_count.font,NSForegroundColorAttributeName:[UIColor colorWithWhite:1 alpha:.48]}];[text addAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.whiteColor} range:NSMakeRange(0,current.length)];_count.attributedText=text;
 if(_browsing)[self loadVisibleThumbnails];[self setNeedsDisplay];[self setNeedsLayout];
}
- (void)loadVisibleThumbnails{
 NSInteger nearby=MAX(3,(NSInteger)ceil(self.bounds.size.width/76)+1);
 for(NSUInteger i=0;i<_images.count;i++)[_images[i] remote:labs((long)i-_index)<=nearby?_urls[i]:@""];
}
- (void)layoutSubviews{
 [super layoutSubviews];CGFloat width=self.bounds.size.width;BOOL resized=fabs(width-_layoutWidth)>.5;_layoutWidth=width;
 _thumbnails.frame=CGRectMake(0,-13,width,58);_count.frame=CGRectMake(0,49,width,21);
 CGSize content=CGSizeMake(width+MAX(0,(NSInteger)_urls.count-1)*38,58);if(!CGSizeEqualToSize(content,_thumbnails.contentSize))_thumbnails.contentSize=content;
 for(NSUInteger i=0;i<_images.count;i++){CGFloat selected=MAX(0,1-fabs((double)i-_position)),w=30+14*selected,h=44+12*selected;DGImage *image=_images[i];image.frame=CGRectMake(width/2+i*38-w/2,(58-h)/2,w,h);image.layer.cornerRadius=4+selected*2;image.layer.borderColor=UIColor.whiteColor.CGColor;image.layer.borderWidth=i==_index?1.5:0;}
 if(resized&&!_thumbnails.dragging&&!_thumbnails.decelerating)[_thumbnails setContentOffset:CGPointMake(_position*38,0) animated:NO];
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
- (void)didMoveToWindow{
 [super didMoveToWindow];if(!self.window){[self cancelBrowsing];return;}
 for(UIView *view=self.superview;view;view=view.superview)if([view isKindOfClass:UIScrollView.class])[((UIScrollView *)view).panGestureRecognizer requireGestureRecognizerToFail:_thumbnails.panGestureRecognizer];
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scroll{[self setBrowsing:YES];}
- (void)scrollViewDidScroll:(UIScrollView *)scroll{
 if(!_browsing)return;
 _position=douglass::photoScrubPosition(0,-scroll.contentOffset.x,38,_urls.count);NSInteger index=(NSInteger)llround(_position);if(index!=_index){DGHaptic();[self page:index];}
 [self setNeedsLayout];if(self.onScrub)self.onScrub(_position,NO);
}
- (void)scrollViewWillEndDragging:(UIScrollView *)scroll withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)target{
 if(!target)return;double position=douglass::photoScrubPosition(0,-target->x,38,_urls.count);target->x=llround(position)*38;target->y=0;
}
- (void)finishBrowsing{
 if(!_browsing)return;_position=llround(douglass::photoScrubPosition(0,-_thumbnails.contentOffset.x,38,_urls.count));
 [_thumbnails setContentOffset:CGPointMake(_position*38,0) animated:NO];[self page:(NSInteger)_position];if(self.onScrub)self.onScrub(_position,YES);[self collapseSoon];
}
- (void)settle{
 double position=llround(douglass::photoScrubPosition(0,-_thumbnails.contentOffset.x,38,_urls.count));
 if(fabs(_thumbnails.contentOffset.x-position*38)<.5)[self finishBrowsing];else [_thumbnails setContentOffset:CGPointMake(position*38,0) animated:YES];
}
- (void)scrollViewDidEndDragging:(UIScrollView *)scroll willDecelerate:(BOOL)decelerate{if(!decelerate)[self settle];}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scroll{[self finishBrowsing];}
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scroll{[self finishBrowsing];}
- (void)panState:(UIPanGestureRecognizer *)gesture{
 if(gesture.state!=UIGestureRecognizerStateCancelled&&gesture.state!=UIGestureRecognizerStateFailed)return;
 NSUInteger token=_collapseToken;__weak DGPhotoNavigator *weak=self;dispatch_async(dispatch_get_main_queue(),^{DGPhotoNavigator *self=weak;if(self&&token==self->_collapseToken&&self->_browsing&&!self->_thumbnails.dragging&&!self->_thumbnails.decelerating)[self settle];});
}
- (void)collapseSoon{
 NSUInteger token=++_collapseToken;__weak DGPhotoNavigator *weak=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,650*NSEC_PER_MSEC),dispatch_get_main_queue(),^{DGPhotoNavigator *self=weak;if(self&&token==self->_collapseToken&&!self->_thumbnails.dragging&&!self->_thumbnails.decelerating)[self setBrowsing:NO];});
}
- (void)tap:(UITapGestureRecognizer *)gesture{
 if(!_urls.count)return;CGPoint point=[gesture locationInView:self];NSInteger index;
 if(_browsing)index=(NSInteger)llround((point.x+_thumbnails.contentOffset.x-self.bounds.size.width/2)/38);
 else{NSInteger count=MIN((NSInteger)15,(NSInteger)_urls.count),first=MIN(MAX(0,_index-count/2),MAX(0,(NSInteger)_urls.count-count));CGFloat start=(self.bounds.size.width-MAX(0,count-1)*12)/2;index=first+MIN(MAX(0,(NSInteger)llround((point.x-start)/12)),count-1);}
 index=MIN(MAX(0,index),MAX(0,(NSInteger)_urls.count-1));if(index!=_index)DGHaptic();_position=index;[self page:index];if(self.onSelect)self.onSelect(index);if(_browsing){[_thumbnails setContentOffset:CGPointMake(index*38,0) animated:YES];[self collapseSoon];}
}
@end
