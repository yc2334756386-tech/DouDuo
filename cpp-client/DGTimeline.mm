#import "DGTimeline.h"
#include <cmath>
@interface DGTimeline()<UIGestureRecognizerDelegate>
@end
@implementation DGTimeline{UIPanGestureRecognizer *_pan;BOOL _scrubbing;float _originalValue;}
- (instancetype)initWithFrame:(CGRect)frame{if((self=[super initWithFrame:frame])){_maximumValue=1;self.backgroundColor=UIColor.clearColor;self.isAccessibilityElement=YES;self.accessibilityLabel=@"视频播放进度";self.accessibilityTraits=UIAccessibilityTraitAdjustable;_pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)];_pan.maximumNumberOfTouches=1;_pan.delegate=self;[self addGestureRecognizer:_pan];}return self;}
- (BOOL)scrubbing{return _scrubbing;}
- (void)setValue:(float)value{_value=MIN(_maximumValue,MAX(_minimumValue,value));self.accessibilityValue=[NSString stringWithFormat:@"%.0f%%",100*(_value-_minimumValue)/MAX(.001,_maximumValue-_minimumValue)];[self setNeedsDisplay];}
- (void)setMaximumTrackTintColor:(UIColor *)color{_maximumTrackTintColor=color;[self setNeedsDisplay];}
- (void)setThumbImage:(UIImage *)image forState:(UIControlState)state{}
- (void)tintColorDidChange{[super tintColorDidChange];[self setNeedsDisplay];}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event{return CGRectContainsPoint(CGRectInset(self.bounds,-8,-14),point);}
- (void)drawRect:(CGRect)rect{CGFloat width=self.bounds.size.width,y=self.bounds.size.height/2,ratio=(_value-_minimumValue)/MAX(.001,_maximumValue-_minimumValue),x=ratio*width;[(_maximumTrackTintColor?:[UIColor colorWithWhite:1 alpha:.2])setFill];[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,y-1.5,width,3) cornerRadius:1.5]fill];[(self.tintColor?:UIColor.whiteColor)setFill];[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,y-1.5,x,3) cornerRadius:1.5]fill];[UIColor.whiteColor setFill];[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(MAX(0,MIN(width-25,x-12.5)),y-3,25,6) cornerRadius:3]fill];}
- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gesture{CGPoint velocity=[gesture velocityInView:self];return fabs(velocity.x)>fabs(velocity.y);}
- (void)didMoveToWindow{[super didMoveToWindow];for(UIView *view=self.superview;view;view=view.superview)if([view isKindOfClass:UIScrollView.class])[((UIScrollView *)view).panGestureRecognizer requireGestureRecognizerToFail:_pan];}
- (void)update:(CGPoint)point{self.value=_minimumValue+(_maximumValue-_minimumValue)*MIN(1,MAX(0,point.x/MAX(1,self.bounds.size.width)));if(self.trackingChanged)self.trackingChanged();}
- (void)pan:(UIPanGestureRecognizer *)gesture{if(gesture.state==UIGestureRecognizerStateBegan){_scrubbing=YES;_originalValue=self.value;if(self.trackingBegan)self.trackingBegan();[self update:[gesture locationInView:self]];}else if(gesture.state==UIGestureRecognizerStateChanged)[self update:[gesture locationInView:self]];else if(gesture.state==UIGestureRecognizerStateEnded){[self update:[gesture locationInView:self]];if(self.trackingEnded)self.trackingEnded(NO);_scrubbing=NO;}else if(gesture.state==UIGestureRecognizerStateCancelled||gesture.state==UIGestureRecognizerStateFailed){self.value=_originalValue;if(self.trackingEnded)self.trackingEnded(YES);_scrubbing=NO;}}
- (void)accessibilityIncrement{_scrubbing=YES;if(self.trackingBegan)self.trackingBegan();self.value+=(_maximumValue-_minimumValue)*.05;if(self.trackingChanged)self.trackingChanged();if(self.trackingEnded)self.trackingEnded(NO);_scrubbing=NO;}
- (void)accessibilityDecrement{_scrubbing=YES;if(self.trackingBegan)self.trackingBegan();self.value-=(_maximumValue-_minimumValue)*.05;if(self.trackingChanged)self.trackingChanged();if(self.trackingEnded)self.trackingEnded(NO);_scrubbing=NO;}
@end
