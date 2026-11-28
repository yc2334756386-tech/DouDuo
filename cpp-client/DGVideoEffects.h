#pragma once
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

BOOL DGVTFSystemInterpolationAvailable(void);
BOOL DGVTSuperResolutionAvailable(void);
BOOL DGSuperResolutionTransitionProtection(void);
extern NSString *const DGInterpolationProtectionKey;
BOOL DGInterpolationTransitionProtection(void);
extern NSString *const DGInterpolationMultiplierKey;
unsigned DGInterpolationMultiplier(void);
void DGPrepareVideoFrameOutput(AVPlayerItem *item);
CVPixelBufferRef DGCopyVideoFrame(AVPlayerItem *item, CFTimeInterval hostTime, CMTime *presentationTime) CF_RETURNS_RETAINED;
void DGReleaseVideoFrameCache(AVPlayerItem *item);

@interface DGVideoEffects : NSObject
- (void)showForPlayerLayer:(AVPlayerLayer *)layer;
- (void)stop;
- (void)suspendForPaging;
- (void)resetFrames;
- (void)layout;
@end
