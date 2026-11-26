#pragma once
#import <UIKit/UIKit.h>
@interface DGTimeline:UIControl
@property(nonatomic) float minimumValue,maximumValue,value;
@property(nonatomic,strong) UIColor *maximumTrackTintColor;
@property(nonatomic,readonly) BOOL scrubbing;
@property(nonatomic,copy) void (^trackingBegan)(void);
@property(nonatomic,copy) void (^trackingChanged)(void);
@property(nonatomic,copy) void (^trackingEnded)(BOOL cancelled);
- (void)setThumbImage:(UIImage *)image forState:(UIControlState)state;
@end
