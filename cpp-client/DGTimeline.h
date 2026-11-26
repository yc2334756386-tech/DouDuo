#pragma once
#import <UIKit/UIKit.h>
@interface DGTimeline:UISlider
@property(nonatomic,readonly) BOOL scrubbing;
@property(nonatomic,copy) void (^trackingBegan)(void);
@property(nonatomic,copy) void (^trackingChanged)(void);
@property(nonatomic,copy) void (^trackingEnded)(BOOL cancelled);
@end

