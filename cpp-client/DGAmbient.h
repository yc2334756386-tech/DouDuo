#pragma once
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
@interface DGAmbient:UIView
@property(nonatomic,copy) void (^contrastReady)(UIImage *white,UIImage *black);
- (void)item:(AVPlayerItem *)item imageView:(UIImageView *)image;
- (void)active:(BOOL)active;
- (void)adaptive:(BOOL)enabled;
- (void)contrastInRect:(CGRect)region playerLayer:(AVPlayerLayer *)layer;
@end

