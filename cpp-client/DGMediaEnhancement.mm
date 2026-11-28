#import "DGMediaEnhancement.h"
#import "DGVideoEffects.h"
#import "DGRife.h"
#import "DGDiagnostics.h"
#import <Metal/Metal.h>
#import <VideoToolbox/VideoToolbox.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <CoreImage/CoreImage.h>
#import "DGAnimation.h"
#include <atomic>
#include "ExperimentalMedia.hpp"
static CIImage *DGSharpenLuma(CIImage *image,double radius,double sharpness){
 if(sharpness<=0)return image;CIFilter *filter=[CIFilter filterWithName:@"CISharpenLuminance"];if(!filter)return image;
 BOOL hasRadius=[filter.inputKeys containsObject:@"inputRadius"];if(radius>1&&!hasRadius)return image;
 [filter setValue:[image imageByClampingToExtent] forKey:kCIInputImageKey];[filter setValue:@(sharpness) forKey:@"inputSharpness"];if(hasRadius)[filter setValue:@(radius) forKey:@"inputRadius"];
 return filter.outputImage?[filter.outputImage imageByCroppingToRect:image.extent]:image;
}
static CIImage *DGFilterPicture(CIImage *image,unsigned preset,BOOL details){
 auto values=douglass::picturePreset(preset);
 if(values.saturation!=1||values.contrast!=1||values.brightness!=0)image=[image imageByApplyingFilter:@"CIColorControls" withInputParameters:@{kCIInputSaturationKey:@(values.saturation),kCIInputContrastKey:@(values.contrast),kCIInputBrightnessKey:@(values.brightness)}];
 // The original-color preset only sharpens luminance at two scales. It does not
 // set saturation, hue, white balance or a global contrast/color grade.
 if(details){image=DGSharpenLuma(image,2.4,values.texture);image=DGSharpenLuma(image,.8,values.clarity);}return image;
}
static BOOL DGSupports(Class cls,id device){if(!cls||!device)return NO;SEL selector=NSSelectorFromString(@"supportsDevice:");if(![cls respondsToSelector:selector])return NO;BOOL(*message)(id,SEL,id)=(BOOL(*)(id,SEL,id))objc_msgSend;return message(cls,selector,device);}
BOOL DGMetalFXSpatialAvailable(void){
 static BOOL supported;
 static dispatch_once_t once;
 dispatch_once(&once,^{supported=DGSupports(NSClassFromString(@"MTLFXSpatialScalerDescriptor"),MTLCreateSystemDefaultDevice());});
 return supported;
}
NSNotificationName const DGVideoEffectStatusChanged=@"DGVideoEffectStatusChanged";

@interface DGVideoEffectStatus:NSObject
@property(nonatomic,weak) id owner;
@property(nonatomic,copy) NSString *state,*reason,*backend;
@property(nonatomic) unsigned multiplier;
@end
@implementation DGVideoEffectStatus
@end

static DGVideoEffectStatus *DGEffectStatus(DGVideoEffect effect) {
 static NSArray<DGVideoEffectStatus *> *statuses;
 static dispatch_once_t once;
 dispatch_once(&once,^{statuses=@[[DGVideoEffectStatus new],[DGVideoEffectStatus new],[DGVideoEffectStatus new]];});
 return statuses[effect];
}
static NSString *DGEffectName(DGVideoEffect effect) {
 return @[@"metalfx",@"low_latency_super_resolution",@"interpolation"][effect];
}
static BOOL DGEffectRequested(DGVideoEffect effect) {
 NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
 if(effect==DGVideoEffectInterpolation)return DGRifeRequested()||[prefs boolForKey:@"douglass.experimental.frameInterpolation"];
 return [prefs boolForKey:effect==DGVideoEffectMetalFX?@"douglass.experimental.metalfx":@"douglass.experimental.vtSuperResolution"];
}
static void DGLogEffect(DGVideoEffect effect,DGVideoEffectStatus *status) {
 if(!DGDiagnosticEnabled())return;
 BOOL requested=DGEffectRequested(effect);
 unsigned target=effect==DGVideoEffectInterpolation&&requested?DGInterpolationMultiplier():0;
 DGDiagnostic(@"video.effect.status",[NSString stringWithFormat:@"effect=%@ state=%@ reason=%@ selected=%d requested=%u effective=%u backend=%@",
     DGEffectName(effect),requested?(status.state?:@"idle"):@"off",requested?(status.reason?:@"no_active_video"):@"setting",
     requested,target,requested?status.multiplier:0,status.backend.length?status.backend:@"none"]);
}
void DGLogVideoEffectSnapshot(void) {
 if(!DGDiagnosticEnabled())return;
 for(DGVideoEffect effect:{DGVideoEffectMetalFX,DGVideoEffectSuperResolution,DGVideoEffectInterpolation})
  DGLogEffect(effect,DGEffectStatus(effect));
}
void DGReportVideoEffect(DGVideoEffect effect,id owner,NSString *state,NSString *reason,unsigned multiplier,NSString *backend) {
 DGVideoEffectStatus *status=DGEffectStatus(effect);
 const BOOL changedOwner=status.owner!=owner;
 if(!changedOwner&&[status.state isEqualToString:state]&&[status.reason isEqualToString:reason]&&
    status.multiplier==multiplier&&[status.backend isEqualToString:backend?:@""])return;
 status.owner=owner;
 status.state=state;
 status.reason=reason;
 status.multiplier=multiplier;
 status.backend=backend?:@"";
 DGLogEffect(effect,status);
 [NSNotificationCenter.defaultCenter postNotificationName:DGVideoEffectStatusChanged object:nil];
}
void DGEndVideoEffect(DGVideoEffect effect,id owner) {
 DGVideoEffectStatus *status=DGEffectStatus(effect);
 if(status.owner!=owner)return;
 DGReportVideoEffect(effect,nil,@"idle",@"no_active_video");
}
NSString *DGVideoEffectStatusText(DGVideoEffect effect) {
 if(!DGEffectRequested(effect))return @"未启用";
 if((effect==DGVideoEffectMetalFX&&!DGMetalFXSpatialAvailable())||
    (effect==DGVideoEffectSuperResolution&&!DGVTSuperResolutionAvailable()&&!DGMetalFXSpatialAvailable()))return @"当前设备不支持";
 DGVideoEffectStatus *status=DGEffectStatus(effect);
 if(!status.owner||[status.state isEqualToString:@"idle"])return @"等待播放视频";
 if([status.state isEqualToString:@"active"]){
  if(effect!=DGVideoEffectInterpolation)
   return [status.backend isEqualToString:@"metalfx_fallback"]?@"已启用 · MetalFX 兼容":@"已启用";
  NSString *backend=[status.backend isEqualToString:@"rife"]?@"RIFE":([status.backend isEqualToString:@"system"]?@"系统":@"兼容");
  return [NSString stringWithFormat:@"已启用 · %@ %u×%@",backend,status.multiplier,status.multiplier<DGInterpolationMultiplier()?@"（已降档）":@""];
 }
 if([status.state isEqualToString:@"protected"])return @"转场保护中 · 播放原始帧";
 if([status.state isEqualToString:@"bypassed"]){
  NSDictionary *reasons=@{@"protected_content":@"受保护的视频", @"hdr":@"保留 HDR 原画",
      @"composition_error":@"视频合成初始化失败", @"interpolation_backend":@"插帧后端未能处理当前画面",
      @"resolution_backend":@"超分后端未能处理当前画面",
      @"source_rate":@"当前屏幕刷新率不足以翻倍",@"frame_budget":@"处理超时",@"no_output":@"暂未收到增强帧",
      @"renderer":@"渲染队列繁忙",@"gpu":@"GPU 未能完成超分",@"size_limit":@"当前画面已达到尺寸上限"};
  NSString *reason=reasons[status.reason];
  return reason.length?[NSString stringWithFormat:@"暂未启用 · %@",reason]:@"暂未启用 · 当前片源未输出增强帧";
 }
 return @"正在准备";
}
NSString *DGMediaEnhancementStatus(void){
 return [NSString stringWithFormat:@"MetalFX 空间放大 %@ · VideoToolbox 插帧 %@ · 低延迟超分 %@",
         DGMetalFXSpatialAvailable()?@"支持":@"不支持",
         DGVTFSystemInterpolationAvailable()?@"系统支持":@"兼容模式",
         DGVTSuperResolutionAvailable()?@"支持":@"不支持"];
}
void DGMediaEnhancementApply(void){
 DGDiagnostic(@"experimental.media.settings",DGMediaEnhancementStatus());
 [NSNotificationCenter.defaultCenter postNotificationName:@"DGMediaEnhancementChanged" object:nil];
}
@interface DGSpatialSession:NSObject
@property(nonatomic) double scale;
@property(nonatomic) BOOL spatialEnabled;
@property(nonatomic) BOOL resolutionFallback;
@property(nonatomic,copy) NSString *unavailableReason;
- (void)publishWaitingState;
- (void)setPlaybackActive:(BOOL)active;
- (void)filter:(AVAsynchronousCIImageFilteringRequest *)request preset:(NSInteger)preset spatial:(BOOL)spatial;
@end
@implementation DGSpatialSession{
 id<MTLDevice> _device;id<MTLCommandQueue> _queue;CIContext *_context;
 id<MTLTexture> _input;std::unique_ptr<douglass::SpatialUpscaler> _scaler;
 std::atomic_bool _busy;
 std::atomic<double> _activeAfter;
 std::atomic<unsigned> _reportedOutput;
}
- (void)releaseGPUResources {
 _scaler.reset();_input=nil;_context=nil;_queue=nil;_device=nil;
}
- (void)setPlaybackActive:(BOOL)active {
 const double previous=_activeAfter.load(std::memory_order_acquire);
 if(active){
  if(previous==0){
   _reportedOutput.store(0);
   _activeAfter.store(CACurrentMediaTime(),std::memory_order_release);
   [self publishWaitingState];
  }
  return;
 }
 _activeAfter.store(0,std::memory_order_release);
 if(previous!=0&&_spatialEnabled)DGEndVideoEffect(_resolutionFallback?DGVideoEffectSuperResolution:DGVideoEffectMetalFX,self);
 if(previous!=0&&!_busy.exchange(true,std::memory_order_acq_rel)){
  [self releaseGPUResources];
  _busy.store(false,std::memory_order_release);
 }
}
- (void)publishWaitingState {
 if(!_spatialEnabled||_activeAfter.load()==0)return;
 const auto effect=_resolutionFallback?DGVideoEffectSuperResolution:DGVideoEffectMetalFX;
 NSString *backend=_resolutionFallback?@"metalfx_fallback":@"metalfx";
 if(_unavailableReason.length)DGReportVideoEffect(effect,self,@"bypassed",_unavailableReason,0,backend);
 else DGReportVideoEffect(effect,self,@"preparing",@"waiting_for_frame",0,backend);
}
- (void)reportSpatialOutput:(unsigned)output activation:(double)activation {
 if(!activation||_activeAfter.load()!=activation||_reportedOutput.exchange(output)==output)return;
 __weak DGSpatialSession *weak=self;
 dispatch_async(dispatch_get_main_queue(),^{
  DGSpatialSession *session=weak;
  if(!session||session->_activeAfter.load()!=activation||session->_reportedOutput.load()!=output)return;
  NSString *reason=output==1?@"frame_output":@"gpu";
  const BOOL fallback=session.resolutionFallback;
  DGReportVideoEffect(fallback?DGVideoEffectSuperResolution:DGVideoEffectMetalFX,session,
                      output==1?@"active":@"bypassed",reason,0,fallback?@"metalfx_fallback":@"metalfx");
 });
}
- (void)finishGPUWork {
 if(_activeAfter.load(std::memory_order_acquire)==0)[self releaseGPUResources];
 _busy.store(false,std::memory_order_release);
 // Handle deactivation between the initial check and relinquishing the GPU.
 if(_activeAfter.load(std::memory_order_acquire)==0&&!_busy.exchange(true,std::memory_order_acq_rel)){
  [self releaseGPUResources];
  _busy.store(false,std::memory_order_release);
 }
}
- (void)filter:(AVAsynchronousCIImageFilteringRequest *)request preset:(NSInteger)preset spatial:(BOOL)spatial{
 CIImage *source=request.sourceImage;CGRect extent=source.extent;CIImage *image=source;double factor=MAX(1,self.scale);
 double activeAfter=_activeAfter.load(std::memory_order_acquire);
 BOOL protectedFrame=activeAfter==0||DGAnimationProcessingDeferred();
 if(preset&&!protectedFrame)image=DGFilterPicture(image,(unsigned)preset,YES);
 CIImage *fallback=[image imageByApplyingTransform:CGAffineTransformMakeScale(factor,factor)];
 if(!spatial||factor<=1||extent.size.width<1||extent.size.height<1||protectedFrame){[request finishWithImage:fallback context:nil];return;}
 if(_busy.exchange(true)){[request finishWithImage:fallback context:nil];return;}
 @try{
  if(_activeAfter.load(std::memory_order_acquire)!=activeAfter||DGAnimationProcessingDeferred()){
   [self finishGPUWork];[request finishWithImage:fallback context:nil];return;
  }
  // Preparing adjacent URLs must not construct another GPU pipeline on the UI
  // thread. Allocate only when a real, non-deferred frame needs enhancement.
  if(!_context){_device=MTLCreateSystemDefaultDevice();_queue=[_device newCommandQueue];if(_device){_context=[CIContext contextWithMTLDevice:_device options:@{kCIContextCacheIntermediates:@NO}];_scaler=std::make_unique<douglass::SpatialUpscaler>((__bridge void *)_device);}}
  if(!_context||!_queue||!_scaler){[self reportSpatialOutput:3 activation:activeAfter];[self finishGPUWork];[request finishWithImage:fallback context:nil];return;}
  NSUInteger w=(NSUInteger)extent.size.width,h=(NSUInteger)extent.size.height;NSUInteger ow=(NSUInteger)ceil(w*factor),oh=(NSUInteger)ceil(h*factor);
  if(!_input||_input.width!=w||_input.height!=h){MTLTextureDescriptor *in=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:NO];in.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite|MTLTextureUsageRenderTarget;in.storageMode=MTLStorageModePrivate;_input=[_device newTextureWithDescriptor:in];}
  // CI retains the finished output beyond the GPU callback. Give each published
  // image ownership of its texture instead of overwriting a previous frame.
  MTLTextureDescriptor *out=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:ow height:oh mipmapped:NO];out.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite|MTLTextureUsageRenderTarget;out.storageMode=MTLStorageModePrivate;id<MTLTexture> output=[_device newTextureWithDescriptor:out];
  id<MTLCommandBuffer> command=[_queue commandBuffer];if(!_input||!output||!command){[self finishGPUWork];[request finishWithImage:fallback context:nil];return;}
  CIImage *normalized=[image imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x,-extent.origin.y)];CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);[_context render:normalized toMTLTexture:_input commandBuffer:command bounds:CGRectMake(0,0,w,h) colorSpace:space];CGColorSpaceRelease(space);
  if(!_scaler->encode((__bridge void *)command,(__bridge void *)_input,(__bridge void *)output)){[self reportSpatialOutput:3 activation:activeAfter];[self finishGPUWork];[request finishWithImage:fallback context:nil];return;}
  CIContext *context=_context;__weak DGSpatialSession *weak=self;
  [command addCompletedHandler:^(id<MTLCommandBuffer> buffer){@autoreleasepool{DGSpatialSession *session=weak;CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);CIImage *result=buffer.status==MTLCommandBufferStatusCompleted?[CIImage imageWithMTLTexture:output options:@{kCIImageColorSpace:(__bridge id)color}]:nil;CGColorSpaceRelease(color);
    if(result)result=[result imageByApplyingTransform:CGAffineTransformMakeTranslation(extent.origin.x*factor,extent.origin.y*factor)];[request finishWithImage:result?:fallback context:context];[session reportSpatialOutput:result?1:3 activation:activeAfter];[session finishGPUWork];}}];[command commit];
 }@catch(NSException *error){[self reportSpatialOutput:3 activation:activeAfter];[self finishGPUWork];[request finishWithImage:fallback context:nil];}
}
@end
@interface DGPicturePreparation:NSObject
@property(nonatomic) BOOL sealed,completed;
@property(nonatomic) BOOL retryWhenActive;
@property(nonatomic) BOOL playbackActive;
@property(nonatomic,strong) DGSpatialSession *session;
@property(nonatomic,copy) dispatch_block_t completion;
- (void)finish;
@end
@implementation DGPicturePreparation
- (void)finish{if(_completed)return;_completed=YES;dispatch_block_t completion=_completion;_completion=nil;if(completion)completion();}
@end
static const void *DGPicturePreparationKey=&DGPicturePreparationKey;
static void DGPreparePicture(AVPlayerItem *item,dispatch_block_t completion,BOOL resolutionFallback){
 if(!item){if(completion)completion();return;}
 NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
 BOOL spatial=(resolutionFallback||[prefs boolForKey:@"douglass.experimental.metalfx"])&&DGMetalFXSpatialAvailable();
 NSInteger preset=[prefs integerForKey:@"douglass.experimental.picturePreset"];
 DGPicturePreparation *previous=objc_getAssociatedObject(item,DGPicturePreparationKey);
 DGPicturePreparation *stage=[DGPicturePreparation new];stage.completion=completion;stage.playbackActive=previous.playbackActive;
 [previous.session setPlaybackActive:NO];
 objc_setAssociatedObject(item,DGPicturePreparationKey,stage,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 if(!spatial&&!preset){item.videoComposition=nil;[stage finish];return;}
 DGSpatialSession *session=[DGSpatialSession new];
 session.spatialEnabled=spatial;
 session.resolutionFallback=resolutionFallback;
 stage.session=session;
 [session setPlaybackActive:stage.playbackActive];
 __weak AVPlayerItem *weak=item;AVAsset *asset=item.asset;
 // Reading an unloaded AVAsset property synchronously can hold up player
 // construction. Resolve it asynchronously and keep playback independent.
 [asset loadValuesAsynchronouslyForKeys:@[@"hasProtectedContent"] completionHandler:^{
  if([asset statusOfValueForKey:@"hasProtectedContent" error:nil]==AVKeyValueStatusLoaded&&asset.hasProtectedContent){
   dispatch_async(dispatch_get_main_queue(),^{session.unavailableReason=@"protected_content";[session publishWaitingState];[stage finish];});
   return;
  }
  [AVVideoComposition videoCompositionWithAsset:asset applyingCIFiltersWithHandler:^(AVAsynchronousCIImageFilteringRequest *request){[session filter:request preset:preset spatial:spatial];} completionHandler:^(AVVideoComposition *composition,NSError *error){dispatch_async(dispatch_get_main_queue(),^{
   AVPlayerItem *current=weak;
   if(!current||objc_getAssociatedObject(current,DGPicturePreparationKey)!=stage||stage.sealed){[stage finish];return;}
   if(!composition){
    session.unavailableReason=@"composition_error";[session publishWaitingState];
    DGDiagnostic(@"video.enhancement.composition_error",[NSString stringWithFormat:@"code=%ld",(long)error.code]);
    [stage finish];return;
   }
   CGSize size=composition.renderSize;double longest=MAX(size.width,size.height);
   session.scale=spatial&&longest>0?MAX(1.,MIN(1.5,2560./longest)):1.;
   if(spatial&&session.scale<=1){session.unavailableReason=@"size_limit";[session publishWaitingState];}
   AVMutableVideoComposition *configured=[composition mutableCopy];
   configured.renderSize=CGSizeMake(ceil(size.width*session.scale),ceil(size.height*session.scale));
   current.videoComposition=configured;
   DGDiagnostic(@"video.enhancement.attached",[NSString stringWithFormat:@"spatial=%d scale=%.2f preset=%ld input_w=%.0f input_h=%.0f",spatial,session.scale,(long)preset,size.width,size.height]);
   [stage finish];
  });}];
 }];
}
void DGPrepareMediaEnhancement(AVPlayerItem *item,dispatch_block_t completion){
 BOOL fallback=[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.experimental.vtSuperResolution"]&&
               !DGVTSuperResolutionAvailable()&&DGMetalFXSpatialAvailable();
 DGPreparePicture(item,completion,fallback);
}
void DGConfigureMediaEnhancement(AVPlayerItem *item){
 BOOL fallback=[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.experimental.vtSuperResolution"]&&
               (DGHasMetalFXFallback(item)||!DGVTSuperResolutionAvailable())&&DGMetalFXSpatialAvailable();
 DGPreparePicture(item,nil,fallback);
}
BOOL DGHasMetalFXFallback(AVPlayerItem *item){
 DGPicturePreparation *stage=item?objc_getAssociatedObject(item,DGPicturePreparationKey):nil;
 return stage.session.resolutionFallback;
}
BOOL DGUseMetalFXFallback(AVPlayerItem *item){
 if(!item||!DGMetalFXSpatialAvailable()||![NSUserDefaults.standardUserDefaults boolForKey:@"douglass.experimental.vtSuperResolution"])return NO;
 if(!DGHasMetalFXFallback(item)){
  DGDiagnostic(@"video.super_resolution.fallback",@"backend=metalfx");
  DGPreparePicture(item,nil,YES);
 }
 return YES;
}
void DGSealMediaEnhancement(AVPlayerItem *item){
 DGPicturePreparation *stage=objc_getAssociatedObject(item,DGPicturePreparationKey);
 if(!stage)return;
 if(!stage.completed){
  stage.retryWhenActive=stage.session.spatialEnabled;
  stage.session.unavailableReason=@"no_output";
  [stage.session publishWaitingState];
  DGDiagnostic(@"video.enhancement.bypass",@"reason=playback_started_before_optional_processing_ready");
 }
 stage.sealed=YES;
 [stage finish];
}
void DGSetMetalFXPlaybackActive(AVPlayerItem *item,BOOL active){
 if(!item)return;
 DGPicturePreparation *stage=objc_getAssociatedObject(item,DGPicturePreparationKey);
 stage.playbackActive=active;
 if(active&&stage.retryWhenActive){
  stage.retryWhenActive=NO;
  DGPreparePicture(item,nil,stage.session.resolutionFallback);
  return;
 }
 [stage.session setPlaybackActive:active];
}
UIImage *DGApplyPicturePreset(UIImage *image,unsigned preset){
 if(!image||!image.CGImage||!preset||image.images.count)return image;
 static CIContext *context;static dispatch_once_t once;dispatch_once(&once,^{context=[CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}];});
 CIImage *input=[CIImage imageWithCGImage:image.CGImage];CIImage *output=DGFilterPicture(input,preset,YES);CGImageRef result=[context createCGImage:output fromRect:input.extent];if(!result)return image;UIImage *picture=[UIImage imageWithCGImage:result scale:image.scale orientation:image.imageOrientation];CGImageRelease(result);return picture;
}
