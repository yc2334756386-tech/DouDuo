#import "DGPhotoNavigator.h"
#import "DGAnimation.h"
@interface DGPhotoNavigator()<UIGestureRecognizerDelegate>
@end
@implementation DGPhotoNavigator{
 NSArray<NSString *> *_urls;NSMutableArray<DGImage *> *_images;NSInteger _index,_edgeDirection;
 BOOL _browsing,_edgeQueued;NSUInteger _collapseToken,_edgeToken;
 double _scrubPosition,_lastTranslation;CGFloat _padding;
 UIPanGestureRecognizer *_pan;UIScrollView *_thumbnails;UILabel *_count;
}
- (instancetype)initWithFrame:(CGRect)frame{
 if((self=[super initWithFrame:frame])){
  self.backgroundColor=UIColor.clearColor;self.clipsToBounds=NO;
  _pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)];_pan.delegate=self;_pan.maximumNumberOfTouches=1;[self addGestureRecognizer:_pan];
  [self addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tap:)]];
  _images=[NSMutableArray array];_thumbnails=[UIScrollView new];_thumbnails.backgroundColor=UIColor.clearColor;_thumbnails.showsHorizontalScrollIndicator=NO;_thumbnails.scrollEnabled=NO;_thumbnails.userInteractionEnabled=NO;_thumbnails.hidden=YES;[self addSubview:_thumbnails];
  _count=Label(15,UIFontWeightMedium);_count.textAlignment=NSTextAlignmentCenter;_count.hidden=YES;_count.layer.shadowColor=UIColor.blackColor.CGColor;_count.layer.shadowOpacity=.55;_count.layer.shadowRadius=2;_count.layer.shadowOffset=CGSizeMake(0,1);[self addSubview:_count];
 }return self;
}
- (BOOL)browsing{return _browsing;}
- (void)cancelBrowsing{if(_pan.state==UIGestureRecognizerStateBegan||_pan.state==UIGestureRecognizerStateChanged){_pan.enabled=NO;_pan.enabled=YES;}[self setBrowsing:NO];}
- (void)setBrowsing:(BOOL)value{
 ++_collapseToken;if(_browsing==value)return;_browsing=value;++_edgeToken;_edgeQueued=NO;_edgeDirection=0;
 if(value){_scrubPosition=_index;_thumbnails.hidden=NO;_count.hidden=NO;_thumbnails.alpha=0;_count.alpha=0;[self loadVisibleThumbnails];}
 [self setNeedsDisplay];[self setNeedsLayout];if(self.onBrowsingChanged)self.onBrowsingChanged(value);
 DGAnimate(.18,^{self->_thumbnails.alpha=value?1:0;self->_count.alpha=value?1:0;[self layoutIfNeeded];},^(BOOL done){if(!self->_browsing){self->_thumbnails.hidden=YES;self->_count.hidden=YES;for(DGImage *image in self->_images)[image remote:@""];}});
}
- (void)images:(NSArray<NSString *> *)urls{
 [self cancelBrowsing];_urls=urls.copy;_index=0;_scrubPosition=0;_count.attributedText=nil;
 for(UIView *image in _images)[image removeFromSuperview];[_images removeAllObjects];
 for(NSString *url in urls){DGImage *image=[DGImage new];image.maximumPixelSize=160;image.lowPriority=YES;image.contentMode=UIViewContentModeScaleAspectFill;image.clipsToBounds=YES;image.backgroundColor=[UIColor colorWithWhite:1 alpha:.12];image.showsLoadingIndicator=YES;[_thumbnails addSubview:image];[_images addObject:image];}
 [self page:0];
}
- (void)page:(NSInteger)index{
 index=MIN(MAX(0,index),MAX(0,(NSInteger)_urls.count-1));BOOL changed=index!=_index;_index=index;if(!_browsing)_scrubPosition=index;if(!changed&&_count.attributedText.length)return;
 NSString *current=[NSString stringWithFormat:@"%ld",_urls.count?(long)_index+1:0];NSMutableAttributedString *text=[[NSMutableAttributedString alloc]initWithString:[current stringByAppendingFormat:@"  /  %lu",(unsigned long)_urls.count] attributes:@{NSFontAttributeName:_count.font,NSForegroundColorAttributeName:[UIColor colorWithWhite:1 alpha:.48]}];[text addAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.whiteColor} range:NSMakeRange(0,current.length)];_count.attributedText=text;
 if(_browsing)[self loadVisibleThumbnails];[self setNeedsDisplay];[self setNeedsLayout];
}
- (void)loadVisibleThumbnails{
 NSInteger nearby=MAX(3,(NSInteger)ceil(self.bounds.size.width/76)+1);
 for(NSUInteger i=0;i<_images.count;i++)[_images[i]remote:labs((long)i-_index)<=nearby?_urls[i]:@""];
}
- (void)layoutSubviews{
 [super layoutSubviews];CGFloat width=self.bounds.size.width;_thumbnails.frame=CGRectMake(0,-13,width,58);_count.frame=CGRectMake(0,49,width,21);
 _padding=MAX(6,(width-_urls.count*38)/2);_thumbnails.contentSize=CGSizeMake(MAX(width,_urls.count*38+12),58);
 for(NSUInteger i=0;i<_images.count;i++){BOOL current=i==_index;CGFloat w=current?44:30,h=current?56:44;DGImage *image=_images[i];image.frame=CGRectMake(_padding+i*38+(38-w)/2,(58-h)/2,w,h);image.layer.cornerRadius=current?6:4;image.layer.borderColor=UIColor.whiteColor.CGColor;image.layer.borderWidth=current?1.5:0;}
 CGFloat center=_padding+_scrubPosition*38+19,offset=MIN(MAX(0,center-width/2),MAX(0,_thumbnails.contentSize.width-width));[_thumbnails setContentOffset:CGPointMake(offset,0) animated:NO];
}
- (void)drawRect:(CGRect)rect{
 CGContextClearRect(UIGraphicsGetCurrentContext(),self.bounds);if(_browsing)return;
 NSInteger count=MIN((NSInteger)15,(NSInteger)_urls.count);CGFloat total=MAX(0,count-1)*12,start=(self.bounds.size.width-total)/2;NSInteger first=MIN(MAX(0,_index-count/2),MAX(0,(NSInteger)_urls.count-count));
 for(NSInteger dot=0;dot<count;dot++){BOOL active=first+dot==_index;[(active?UIColor.whiteColor:[UIColor colorWithWhite:1 alpha:.35])setFill];CGFloat size=active?6:4;[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(start+dot*12-size/2,(self.bounds.size.height-size)/2,size,size)]fill];}
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event{return CGRectContainsPoint(_browsing?CGRectMake(0,-16,self.bounds.size.width,88):CGRectInset(self.bounds,0,-6),point);}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture{if(gesture!=_pan)return YES;CGPoint velocity=[_pan velocityInView:self];return _urls.count>1&&fabs(velocity.x)>fabs(velocity.y);}
- (void)didMoveToWindow{[super didMoveToWindow];if(!self.window){[self setBrowsing:NO];return;}for(UIView *view=self.superview;view;view=view.superview)if([view isKindOfClass:UIScrollView.class])[((UIScrollView *)view).panGestureRecognizer requireGestureRecognizerToFail:_pan];}
- (void)selectIndex:(NSInteger)index{
 index=MIN(MAX(0,index),MAX(0,(NSInteger)_urls.count-1));if(index==_index)return;DGHaptic();[self page:index];if(self.onSelect)self.onSelect(index);
}
- (void)scrubBy:(double)distance{
 _scrubPosition=douglass::photoScrubPosition(_scrubPosition,distance,38,_urls.count);[self selectIndex:(NSInteger)llround(_scrubPosition)];[self setNeedsLayout];[self layoutIfNeeded];
}
- (void)queueEdgeStep{
 if(_edgeQueued||!_edgeDirection||!_browsing)return;_edgeQueued=YES;NSUInteger token=_edgeToken;__weak DGPhotoNavigator *weak=self;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{DGPhotoNavigator *self=weak;if(!self||token!=self->_edgeToken)return;self->_edgeQueued=NO;if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||!self.window||!self->_browsing||!self->_edgeDirection||(self->_pan.state!=UIGestureRecognizerStateChanged&&self->_pan.state!=UIGestureRecognizerStateBegan))return;double previous=self->_scrubPosition;[self scrubBy:-self->_edgeDirection*17.1];if(fabs(self->_scrubPosition-previous)>.001)[self queueEdgeStep];});
}
- (void)collapseSoon{
 NSUInteger token=++_collapseToken;__weak DGPhotoNavigator *weak=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,650*NSEC_PER_MSEC),dispatch_get_main_queue(),^{DGPhotoNavigator *self=weak;if(self&&token==self->_collapseToken)[self setBrowsing:NO];});
}
- (void)pan:(UIPanGestureRecognizer *)gesture{
 if(gesture.state==UIGestureRecognizerStateBegan){_lastTranslation=0;[self setBrowsing:YES];}
 if(gesture.state==UIGestureRecognizerStateBegan||gesture.state==UIGestureRecognizerStateChanged){double x=[gesture translationInView:self].x;[self scrubBy:x-_lastTranslation];_lastTranslation=x;CGPoint point=[gesture locationInView:self];_edgeDirection=point.x<18?1:point.x>self.bounds.size.width-18?-1:0;if(!_edgeDirection){++_edgeToken;_edgeQueued=NO;}else[self queueEdgeStep];}
 if(gesture.state==UIGestureRecognizerStateEnded||gesture.state==UIGestureRecognizerStateCancelled||gesture.state==UIGestureRecognizerStateFailed){++_edgeToken;_edgeQueued=NO;_edgeDirection=0;_scrubPosition=_index;[self setNeedsLayout];[self collapseSoon];}
}
- (void)tap:(UITapGestureRecognizer *)gesture{
 if(!_urls.count)return;CGPoint point=[gesture locationInView:self];
 if(_browsing){[self selectIndex:(NSInteger)llround((point.x+_thumbnails.contentOffset.x-_padding-19)/38)];_scrubPosition=_index;[self setNeedsLayout];[self collapseSoon];}
 else{NSInteger count=MIN((NSInteger)15,(NSInteger)_urls.count),first=MIN(MAX(0,_index-count/2),MAX(0,(NSInteger)_urls.count-count));CGFloat start=(self.bounds.size.width-MAX(0,count-1)*12)/2;NSInteger local=(NSInteger)llround((point.x-start)/12);[self selectIndex:first+MIN(MAX(0,local),count-1)];}
}
@end
