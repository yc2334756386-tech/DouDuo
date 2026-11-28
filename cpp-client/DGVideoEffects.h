#pragma once
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

BOOL DGVTFInterpolationAvailable(void);
BOOL DGVTSuperResolutionAvailable(void);

@interface DGVideoEffects : NSObject
- (void)showForPlayerLayer:(AVPlayerLayer *)layer;
- (void)stop;
- (void)resetFrames;
- (void)layout;
@end
