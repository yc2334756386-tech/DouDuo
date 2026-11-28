#pragma once
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

BOOL DGVTFInterpolationAvailable(void);
BOOL DGVTSuperResolutionAvailable(void);
NSString *DGVTFInterpolationUnavailableReason(void);

@interface DGVideoEffects : NSObject
- (void)showForPlayerLayer:(AVPlayerLayer *)layer;
- (void)stop;
- (void)suspendForPaging;
- (void)resetFrames;
- (void)layout;
@end
