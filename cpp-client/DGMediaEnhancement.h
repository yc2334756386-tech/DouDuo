#pragma once
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
FOUNDATION_EXPORT BOOL DGMetalFXSpatialAvailable(void);
FOUNDATION_EXPORT NSString *DGMediaEnhancementStatus(void);
FOUNDATION_EXPORT void DGMediaEnhancementApply(void);
typedef NS_ENUM(NSUInteger, DGVideoEffect) {
    DGVideoEffectMetalFX, DGVideoEffectSuperResolution, DGVideoEffectInterpolation,
};
FOUNDATION_EXPORT NSNotificationName const DGVideoEffectStatusChanged;
void DGReportVideoEffect(DGVideoEffect effect,id owner,NSString *state,NSString *reason,unsigned multiplier=0,NSString *backend=nil);
void DGEndVideoEffect(DGVideoEffect effect,id owner);
NSString *DGVideoEffectStatusText(DGVideoEffect effect);
void DGLogVideoEffectSnapshot(void);
void DGConfigureMediaEnhancement(AVPlayerItem *item);
void DGPrepareMediaEnhancement(AVPlayerItem *item,dispatch_block_t completion);
void DGSealMediaEnhancement(AVPlayerItem *item);
void DGSetMetalFXPlaybackActive(AVPlayerItem *item,BOOL active);
UIImage *DGApplyPicturePreset(UIImage *image,unsigned preset);
