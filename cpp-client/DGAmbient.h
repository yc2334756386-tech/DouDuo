#pragma once
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
@interface DGAmbient:UIView
- (void)item:(AVPlayerItem *)item imageView:(UIImageView *)image;
- (void)active:(BOOL)active;
@end

