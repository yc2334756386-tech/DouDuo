#pragma once
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include "ContrastMap.hpp"
@interface DGAmbient:UIView
@property(nonatomic,copy) void (^contrastReady)(std::shared_ptr<const douglass::ContrastFrame> sample);
- (void)item:(AVPlayerItem *)item imageView:(UIImageView *)image;
- (void)active:(BOOL)active;
- (void)adaptive:(BOOL)enabled;
- (void)contrastInRect:(CGRect)region playerLayer:(AVPlayerLayer *)layer;
@end

