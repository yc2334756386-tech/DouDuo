#import "DGMediaEnhancement.h"
#import "DGDiagnostics.h"
#import "DGAnimation.h"
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#include "ExperimentalMedia.hpp"

NSString *const DGMetalFXKey=@"douglass.experimental.metalfx";
NSNotificationName const DGVideoEffectStatusChanged=@"DGVideoEffectStatusChanged";

BOOL DGMetalFXSpatialAvailable(void) {
    static BOOL supported;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        id<MTLDevice> device=MTLCreateSystemDefaultDevice();
        supported=device&&[MTLFXSpatialScalerDescriptor supportsDevice:device];
    });
    return supported;
}

BOOL DGMetalFXRequested(void) {
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    return [prefs boolForKey:DGMetalFXKey];
}

void DGMigrateMetalFXPreference(void) {
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    if([prefs boolForKey:@"douglass.experimental.vtSuperResolution"])[prefs setBool:YES forKey:DGMetalFXKey];
    for(NSString *removed in @[@"vtSuperResolution",@"frameInterpolation",@"interpolationBackend",@"interpolationMultiplier",@"interpolationProtection"]){
        [prefs removeObjectForKey:[@"douglass.experimental." stringByAppendingString:removed]];
    }
}

BOOL DGMetalFXTransitionProtection(void) {
    NSNumber *saved=[NSUserDefaults.standardUserDefaults objectForKey:@"douglass.experimental.transitionProtection"];
    return !saved||saved.boolValue;
}

static __weak id statusOwner;
static NSString *statusState,*statusReason;

void DGLogVideoEffectSnapshot(void) {
    if(!DGDiagnosticEnabled())return;
    BOOL selected=DGMetalFXRequested();
    NSString *state=selected?(statusOwner?statusState:@"idle"):@"off";
    NSString *reason=selected?(statusOwner?statusReason:@"no_active_video"):@"setting";
    DGDiagnostic(@"video.effect.status",[NSString stringWithFormat:@"effect=metalfx state=%@ reason=%@ selected=%d requested=%u effective=%u",
                 state,reason,selected,selected?douglass::metalFXScale:0,
                 selected&&[state isEqualToString:@"active"]?douglass::metalFXScale:0]);
}

void DGReportMetalFX(id owner,NSString *state,NSString *reason) {
    if(statusOwner==owner&&[statusState isEqualToString:state]&&[statusReason isEqualToString:reason])return;
    statusOwner=owner;
    statusState=state;
    statusReason=reason;
    DGLogVideoEffectSnapshot();
    [NSNotificationCenter.defaultCenter postNotificationName:DGVideoEffectStatusChanged object:nil];
}

void DGEndMetalFX(id owner) {
    if(statusOwner==owner)DGReportMetalFX(nil,@"idle",@"no_active_video");
}

NSString *DGMetalFXStatusText(void) {
    if(!DGMetalFXRequested())return @"未启用";
    if(!DGMetalFXSpatialAvailable())return @"此设备不支持 MetalFX";
    if(!statusOwner)return @"等待播放视频";
    if([statusState isEqualToString:@"active"])return @"已启用 · 2×";
    if([statusState isEqualToString:@"bypassed"]){
        if([statusReason isEqualToString:@"no_output"])return @"暂未取得视频帧";
        if([statusReason isEqualToString:@"renderer"])return @"显示暂未就绪 · 正在播放原画";
        return @"GPU 暂未完成 2× 放大 · 正在播放原画";
    }
    return @"正在准备";
}

void DGMediaEnhancementApply(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:@"DGMediaEnhancementChanged" object:nil];
}

static CIImage *DGSharpenLuma(CIImage *image,double radius,double sharpness) {
    if(sharpness<=0)return image;
    CIFilter *filter=[CIFilter filterWithName:@"CISharpenLuminance"];
    if(!filter)return image;
    BOOL hasRadius=[filter.inputKeys containsObject:@"inputRadius"];
    if(radius>1&&!hasRadius)return image;
    [filter setValue:[image imageByClampingToExtent] forKey:kCIInputImageKey];
    [filter setValue:@(sharpness) forKey:@"inputSharpness"];
    if(hasRadius)[filter setValue:@(radius) forKey:@"inputRadius"];
    return filter.outputImage?[filter.outputImage imageByCroppingToRect:image.extent]:image;
}

static CIImage *DGFilterPicture(CIImage *image,unsigned preset) {
    auto values=douglass::picturePreset(preset);
    if(values.saturation!=1||values.contrast!=1||values.brightness!=0){
        image=[image imageByApplyingFilter:@"CIColorControls" withInputParameters:@{
            kCIInputSaturationKey:@(values.saturation),
            kCIInputContrastKey:@(values.contrast),
            kCIInputBrightnessKey:@(values.brightness)
        }];
    }
    image=DGSharpenLuma(image,2.4,values.texture);
    return DGSharpenLuma(image,.8,values.clarity);
}

@interface DGPicturePreparation : NSObject
@property(nonatomic) BOOL sealed,completed;
@property(nonatomic,copy) dispatch_block_t completion;
- (void)finish;
@end

@implementation DGPicturePreparation
- (void)finish {
    if(_completed)return;
    _completed=YES;
    dispatch_block_t completion=_completion;
    _completion=nil;
    if(completion)completion();
}
@end

static const void *DGPicturePreparationKey=&DGPicturePreparationKey;

void DGPrepareMediaEnhancement(AVPlayerItem *item,dispatch_block_t completion) {
    if(!item){if(completion)completion();return;}
    NSInteger preset=[NSUserDefaults.standardUserDefaults integerForKey:@"douglass.experimental.picturePreset"];
    DGPicturePreparation *stage=[DGPicturePreparation new];
    stage.completion=completion;
    objc_setAssociatedObject(item,DGPicturePreparationKey,stage,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(!preset){item.videoComposition=nil;[stage finish];return;}
    __weak AVPlayerItem *weak=item;
    [AVVideoComposition videoCompositionWithAsset:item.asset
                  applyingCIFiltersWithHandler:^(AVAsynchronousCIImageFilteringRequest *request){
        CIImage *image=request.sourceImage;
        if(!DGAnimationProcessingDeferred())image=DGFilterPicture(image,(unsigned)preset);
        [request finishWithImage:image context:nil];
    } completionHandler:^(AVVideoComposition *composition,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            AVPlayerItem *current=weak;
            if(current&&objc_getAssociatedObject(current,DGPicturePreparationKey)==stage&&!stage.sealed&&composition){
                current.videoComposition=composition;
            }
            [stage finish];
        });
    }];
}

void DGConfigureMediaEnhancement(AVPlayerItem *item){DGPrepareMediaEnhancement(item,nil);}

void DGSealMediaEnhancement(AVPlayerItem *item) {
    DGPicturePreparation *stage=objc_getAssociatedObject(item,DGPicturePreparationKey);
    stage.sealed=YES;
    [stage finish];
}

UIImage *DGApplyPicturePreset(UIImage *image,unsigned preset) {
    if(!image||!image.CGImage||!preset||image.images.count)return image;
    static CIContext *context;
    static dispatch_once_t once;
    dispatch_once(&once,^{context=[CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}];});
    CIImage *input=[CIImage imageWithCGImage:image.CGImage];
    CIImage *output=DGFilterPicture(input,preset);
    CGImageRef result=[context createCGImage:output fromRect:input.extent];
    if(!result)return image;
    UIImage *picture=[UIImage imageWithCGImage:result scale:image.scale orientation:image.imageOrientation];
    CGImageRelease(result);
    return picture;
}
