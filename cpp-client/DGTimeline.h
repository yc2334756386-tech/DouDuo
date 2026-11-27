#pragma once
#import <UIKit/UIKit.h>
@class AVPlayer;
@interface DGTimeline:UIControl
@property(nonatomic) float minimumValue,maximumValue,value;
@property(nonatomic,strong) UIColor *maximumTrackTintColor;
@property(nonatomic,readonly) BOOL scrubbing;
@property(nonatomic,copy) void (^trackingBegan)(void);
@property(nonatomic,copy) void (^trackingChanged)(void);
@property(nonatomic,copy) void (^trackingEnded)(BOOL cancelled);
- (void)followPlayer:(AVPlayer *)player duration:(double)duration;
- (void)stopFollowing;
@end
