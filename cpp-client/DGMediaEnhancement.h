#pragma once
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
FOUNDATION_EXPORT BOOL DGMetalFXSpatialAvailable(void);
FOUNDATION_EXPORT BOOL DGMetalFXFrameInterpolationAvailable(void);
FOUNDATION_EXPORT BOOL DGVTLowLatencySuperResolutionAvailable(void);
FOUNDATION_EXPORT NSString *DGMediaEnhancementStatus(void);
FOUNDATION_EXPORT void DGMediaEnhancementApply(void);
void DGConfigureMediaEnhancement(AVPlayerItem *item);
void DGPrepareMediaEnhancement(AVPlayerItem *item,dispatch_block_t completion);
void DGSealMediaEnhancement(AVPlayerItem *item);
UIImage *DGApplyPicturePreset(UIImage *image,unsigned preset);
