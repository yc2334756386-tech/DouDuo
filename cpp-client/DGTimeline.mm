#import "DGTimeline.h"
#import "DGAnimation.h"
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#include <cmath>
#include "Core.hpp"

@interface DGTimelineClock:NSObject
@property(nonatomic,weak) DGTimeline *timeline;
- (void)step:(CADisplayLink *)link;
@end
@interface DGTimeline()<UIGestureRecognizerDelegate>
- (void)updateFromPlayer;
@end
@implementation DGTimelineClock
- (void)step:(CADisplayLink *)link {
    DGTimeline *timeline=self.timeline;
    if(timeline)[timeline updateFromPlayer];else [link invalidate];
}
@end

@implementation DGTimeline {
    UIPanGestureRecognizer *_pan;
    CALayer *_track,*_progress,*_thumb;
    CADisplayLink *_displayLink;
    __weak AVPlayer *_player;
    double _duration;
    BOOL _scrubbing;
    float _originalValue;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){
        _maximumValue=1;self.backgroundColor=UIColor.clearColor;[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshRateChanged) name:@"DGRefreshRateChanged" object:nil];
        self.isAccessibilityElement=YES;self.accessibilityLabel=@"视频播放进度";self.accessibilityTraits=UIAccessibilityTraitAdjustable;
        _track=[CALayer layer];_track.cornerRadius=1.5;
        _progress=[CALayer layer];_progress.cornerRadius=1.5;_progress.anchorPoint=CGPointMake(0,.5);
        _thumb=[CALayer layer];_thumb.cornerRadius=3;_thumb.backgroundColor=UIColor.whiteColor.CGColor;
        for(CALayer *layer in @[_track,_progress,_thumb])[self.layer addSublayer:layer];
        [self updateColors];
        _pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)];_pan.maximumNumberOfTouches=1;_pan.delegate=self;[self addGestureRecognizer:_pan];
    }return self;
}
- (BOOL)scrubbing{return _scrubbing;}
- (void)setValue:(float)value {
    if(!std::isfinite(value))return;
    float next=std::clamp(value,_minimumValue,_maximumValue);if(next==_value)return;_value=next;
    [self layoutProgress];
}
- (NSString *)accessibilityValue{return [NSString stringWithFormat:@"%.0f%%",100*(_value-_minimumValue)/MAX(.001,_maximumValue-_minimumValue)];}
- (void)setMaximumTrackTintColor:(UIColor *)color{_maximumTrackTintColor=color;[self updateColors];}
- (void)tintColorDidChange{[super tintColorDidChange];[self updateColors];}
- (void)updateColors {
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _track.backgroundColor=(_maximumTrackTintColor?:[UIColor colorWithWhite:1 alpha:.2]).CGColor;
    _progress.backgroundColor=(self.tintColor?:UIColor.whiteColor).CGColor;
    [CATransaction commit];
}
- (void)layoutSubviews {[super layoutSubviews];[self layoutProgress];}
- (void)layoutProgress {
    CGFloat width=CGRectGetWidth(self.bounds),y=CGRectGetMidY(self.bounds);
    CGFloat progress=width*(_value-_minimumValue)/MAX(.001,_maximumValue-_minimumValue);
    CGFloat thumbWidth=MIN(25,width);
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _track.frame=CGRectMake(0,y-1.5,width,3);
    _progress.position=CGPointMake(0,y);_progress.bounds=CGRectMake(0,0,progress,3);
    _thumb.bounds=CGRectMake(0,0,thumbWidth,6);_thumb.position=CGPointMake(std::clamp(progress,thumbWidth/2,width-thumbWidth/2),y);
    [CATransaction commit];
}
- (void)followPlayer:(AVPlayer *)player duration:(double)duration {
    if(!player||!std::isfinite(duration)||duration<=0||self.hidden||!self.window||_scrubbing){[self stopFollowing];return;}
    _player=player;_duration=duration;[self updateFromPlayer];
    if(_displayLink||player.timeControlStatus!=AVPlayerTimeControlStatusPlaying)return;
    DGTimelineClock *clock=[DGTimelineClock new];clock.timeline=self;
    _displayLink=[CADisplayLink displayLinkWithTarget:clock selector:@selector(step:)];DGApplyDisplayLinkRate(_displayLink,self);
    [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)updateFromPlayer {
    AVPlayer *player=_player;
    if(!player||self.hidden||!self.window||_scrubbing){[self stopFollowing];return;}
    double seconds=CMTimeGetSeconds(player.currentTime);
    if(std::isfinite(seconds)&&_duration>0)self.value=seconds/_duration;
    if(player.timeControlStatus!=AVPlayerTimeControlStatusPlaying)[self stopFollowing];
}
- (void)refreshRateChanged{DGApplyDisplayLinkRate(_displayLink,self);}
- (void)stopFollowing {[_displayLink invalidate];_displayLink=nil;_player=nil;}
- (void)setHidden:(BOOL)hidden{[super setHidden:hidden];if(hidden)[self stopFollowing];}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event{return CGRectContainsPoint(CGRectInset(self.bounds,-8,-14),point);}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture{
    if(gesture!=_pan)return [super gestureRecognizerShouldBegin:gesture];
    CGPoint velocity=[_pan velocityInView:self];return fabs(velocity.x)>fabs(velocity.y);
}
- (void)didMoveToWindow{
    [super didMoveToWindow];if(!self.window){[self stopFollowing];return;}
    for(UIView *view=self.superview;view;view=view.superview)if([view isKindOfClass:UIScrollView.class])[((UIScrollView *)view).panGestureRecognizer requireGestureRecognizerToFail:_pan];
}
- (void)update:(CGPoint)point {
    self.value=douglass::relativeProgress(_originalValue,point.x,self.bounds.size.width,_minimumValue,_maximumValue);
    if(self.trackingChanged)self.trackingChanged();
}
- (void)pan:(UIPanGestureRecognizer *)gesture {
    switch(gesture.state){
        case UIGestureRecognizerStateBegan:
            _scrubbing=YES;_originalValue=self.value;[self stopFollowing];if(self.trackingBegan)self.trackingBegan();
            [self update:[gesture translationInView:self]];break;
        case UIGestureRecognizerStateChanged:[self update:[gesture translationInView:self]];break;
        case UIGestureRecognizerStateEnded:
            [self update:[gesture translationInView:self]];if(self.trackingEnded)self.trackingEnded(NO);_scrubbing=NO;break;
        case UIGestureRecognizerStateCancelled:case UIGestureRecognizerStateFailed:
            if(!_scrubbing)break;self.value=_originalValue;if(self.trackingEnded)self.trackingEnded(YES);_scrubbing=NO;break;
        default:break;
    }
}
- (void)adjustAccessibility:(float)direction {
    [self stopFollowing];_scrubbing=YES;if(self.trackingBegan)self.trackingBegan();
    self.value+=direction*(_maximumValue-_minimumValue)*.05;if(self.trackingChanged)self.trackingChanged();
    if(self.trackingEnded)self.trackingEnded(NO);_scrubbing=NO;
}
- (void)accessibilityIncrement{[self adjustAccessibility:1];}
- (void)accessibilityDecrement{[self adjustAccessibility:-1];}
- (void)dealloc{[_displayLink invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
