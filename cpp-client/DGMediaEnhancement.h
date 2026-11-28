#pragma once
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
FOUNDATION_EXPORT BOOL DGMetalFXSpatialAvailable(void);
FOUNDATION_EXPORT NSString *const DGMetalFXKey;
BOOL DGMetalFXRequested(void);
BOOL DGMetalFXTransitionProtection(void);
void DGMigrateMetalFXPreference(void);
FOUNDATION_EXPORT void DGMediaEnhancementApply(void);
FOUNDATION_EXPORT NSNotificationName const DGVideoEffectStatusChanged;
void DGReportMetalFX(id owner,NSString *state,NSString *reason);
void DGEndMetalFX(id owner);
NSString *DGMetalFXStatusText(void);
void DGLogVideoEffectSnapshot(void);
void DGConfigureMediaEnhancement(AVPlayerItem *item);
void DGPrepareMediaEnhancement(AVPlayerItem *item,dispatch_block_t completion);
void DGSealMediaEnhancement(AVPlayerItem *item);
UIImage *DGApplyPicturePreset(UIImage *image,unsigned preset);
