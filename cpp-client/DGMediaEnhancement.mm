#import "DGMediaEnhancement.h"
#import "DGVideoEffects.h"
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
BOOL DGMetalFXSpatialAvailable(void){return DGSupports(NSClassFromString(@"MTLFXSpatialScalerDescriptor"),MTLCreateSystemDefaultDevice());}
NSString *DGMediaEnhancementStatus(void){
 return [NSString stringWithFormat:@"MetalFX 空间放大 %@ · VideoToolbox 插帧 %@ · 低延迟超分 %@",
         DGMetalFXSpatialAvailable()?@"支持":@"不支持",
         DGVTFInterpolationAvailable()?@"支持":@"不支持",
         DGVTSuperResolutionAvailable()?@"支持":@"不支持"];
}
void DGMediaEnhancementApply(void){
 DGDiagnostic(@"experimental.media.settings",DGMediaEnhancementStatus());
 [NSNotificationCenter.defaultCenter postNotificationName:@"DGMediaEnhancementChanged" object:nil];
}
@interface DGSpatialSession:NSObject
@property(nonatomic) double scale;
- (void)filter:(AVAsynchronousCIImageFilteringRequest *)request preset:(NSInteger)preset spatial:(BOOL)spatial;
@end
@implementation DGSpatialSession{ id<MTLDevice> _device;id<MTLCommandQueue> _queue;CIContext *_context;id<MTLTexture> _input,_output;std::unique_ptr<douglass::SpatialUpscaler> _scaler;std::atomic_bool _busy;}
- (void)filter:(AVAsynchronousCIImageFilteringRequest *)request preset:(NSInteger)preset spatial:(BOOL)spatial{
 CIImage *source=request.sourceImage;CGRect extent=source.extent;CIImage *image=source;double factor=MAX(1,self.scale);
 if(preset)image=DGFilterPicture(image,(unsigned)preset,!DGAnimationProcessingDeferred());
 CIImage *fallback=[image imageByApplyingTransform:CGAffineTransformMakeScale(factor,factor)];
 if(!spatial||factor<=1||extent.size.width<1||extent.size.height<1||DGAnimationProcessingDeferred()||NSProcessInfo.processInfo.thermalState>=NSProcessInfoThermalStateSerious||_busy.exchange(true)){[request finishWithImage:fallback context:nil];return;}
 @try{
  // Preparing adjacent URLs must not construct another GPU pipeline on the UI
  // thread. Allocate only when a real, non-deferred frame needs enhancement.
  if(!_context){_device=MTLCreateSystemDefaultDevice();_queue=[_device newCommandQueue];if(_device){_context=[CIContext contextWithMTLDevice:_device options:@{kCIContextCacheIntermediates:@NO}];_scaler=std::make_unique<douglass::SpatialUpscaler>((__bridge void *)_device);}}
  if(!_context||!_queue||!_scaler){_busy=false;[request finishWithImage:fallback context:nil];return;}
  NSUInteger w=(NSUInteger)extent.size.width,h=(NSUInteger)extent.size.height;NSUInteger ow=(NSUInteger)ceil(w*factor),oh=(NSUInteger)ceil(h*factor);
  if(!_input||_input.width!=w||_input.height!=h){MTLTextureDescriptor *in=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:NO];in.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite|MTLTextureUsageRenderTarget;in.storageMode=MTLStorageModePrivate;_input=[_device newTextureWithDescriptor:in];}
  // CI retains the finished output beyond the GPU callback. Give each published
  // image ownership of its texture instead of overwriting a previous frame.
  MTLTextureDescriptor *out=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:ow height:oh mipmapped:NO];out.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite|MTLTextureUsageRenderTarget;out.storageMode=MTLStorageModePrivate;_output=[_device newTextureWithDescriptor:out];
  id<MTLCommandBuffer> command=[_queue commandBuffer];if(!_input||!_output||!command){_busy=false;[request finishWithImage:fallback context:nil];return;}
  CIImage *normalized=[image imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x,-extent.origin.y)];CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);[_context render:normalized toMTLTexture:_input commandBuffer:command bounds:CGRectMake(0,0,w,h) colorSpace:space];CGColorSpaceRelease(space);
  if(!_scaler->encode((__bridge void *)command,(__bridge void *)_input,(__bridge void *)_output)){_busy=false;[request finishWithImage:fallback context:nil];return;}
  id<MTLTexture> output=_output;CIContext *context=_context;__weak DGSpatialSession *weak=self;
  [command addCompletedHandler:^(id<MTLCommandBuffer> buffer){@autoreleasepool{DGSpatialSession *session=weak;CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);CIImage *result=buffer.status==MTLCommandBufferStatusCompleted?[CIImage imageWithMTLTexture:output options:@{kCIImageColorSpace:(__bridge id)color}]:nil;CGColorSpaceRelease(color);
    if(result)result=[result imageByApplyingTransform:CGAffineTransformMakeTranslation(extent.origin.x*factor,extent.origin.y*factor)];[request finishWithImage:result?:fallback context:context];if(session)session->_busy=false;}}];[command commit];
 }@catch(NSException *error){_busy=false;[request finishWithImage:fallback context:nil];}
}
@end
@interface DGPicturePreparation:NSObject
@property(nonatomic) BOOL sealed,completed;
@property(nonatomic,copy) dispatch_block_t completion;
- (void)finish;
@end
@implementation DGPicturePreparation
- (void)finish{if(_completed)return;_completed=YES;dispatch_block_t completion=_completion;_completion=nil;if(completion)completion();}
@end
static const void *DGPicturePreparationKey=&DGPicturePreparationKey;
void DGPrepareMediaEnhancement(AVPlayerItem *item,dispatch_block_t completion){
 if(!item){if(completion)completion();return;}NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;BOOL spatial=[prefs boolForKey:@"douglass.experimental.metalfx"]&&DGMetalFXSpatialAvailable();NSInteger preset=[prefs integerForKey:@"douglass.experimental.picturePreset"];
 DGPicturePreparation *stage=[DGPicturePreparation new];stage.completion=completion;objc_setAssociatedObject(item,DGPicturePreparationKey,stage,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 if(!spatial&&!preset){item.videoComposition=nil;[stage finish];return;}
 DGSpatialSession *session=[DGSpatialSession new];__weak AVPlayerItem *weak=item;AVAsset *asset=item.asset;
 // Reading an unloaded AVAsset property synchronously can hold up player
 // construction. Resolve it asynchronously and keep playback independent.
 [asset loadValuesAsynchronouslyForKeys:@[@"hasProtectedContent"] completionHandler:^{
  if([asset statusOfValueForKey:@"hasProtectedContent" error:nil]!=AVKeyValueStatusLoaded||asset.hasProtectedContent){dispatch_async(dispatch_get_main_queue(),^{[stage finish];});return;}
  [AVVideoComposition videoCompositionWithAsset:asset applyingCIFiltersWithHandler:^(AVAsynchronousCIImageFilteringRequest *request){[session filter:request preset:preset spatial:spatial];} completionHandler:^(AVVideoComposition *composition,NSError *error){dispatch_async(dispatch_get_main_queue(),^{AVPlayerItem *current=weak;if(!current||objc_getAssociatedObject(current,DGPicturePreparationKey)!=stage||stage.sealed||!composition){[stage finish];return;}CGSize size=composition.renderSize;double longest=MAX(size.width,size.height);session.scale=spatial&&longest>0?MAX(1.,MIN(1.5,1920./longest)):1.;AVMutableVideoComposition *configured=[composition mutableCopy];configured.renderSize=CGSizeMake(ceil(size.width*session.scale),ceil(size.height*session.scale));current.videoComposition=configured;DGDiagnostic(@"video.enhancement.attached",[NSString stringWithFormat:@"spatial=%d scale=%.2f preset=%ld input_w=%.0f input_h=%.0f",spatial,session.scale,(long)preset,size.width,size.height]);[stage finish];});}];
 }];
}
void DGConfigureMediaEnhancement(AVPlayerItem *item){DGPrepareMediaEnhancement(item,nil);}
void DGSealMediaEnhancement(AVPlayerItem *item){DGPicturePreparation *stage=objc_getAssociatedObject(item,DGPicturePreparationKey);if(!stage)return;if(!stage.completed)DGDiagnostic(@"video.enhancement.bypass",@"reason=playback_started_before_optional_processing_ready");stage.sealed=YES;[stage finish];}
UIImage *DGApplyPicturePreset(UIImage *image,unsigned preset){
 if(!image||!image.CGImage||!preset||image.images.count)return image;
 static CIContext *context;static dispatch_once_t once;dispatch_once(&once,^{context=[CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}];});
 CIImage *input=[CIImage imageWithCGImage:image.CGImage];CIImage *output=DGFilterPicture(input,preset,YES);CGImageRef result=[context createCGImage:output fromRect:input.extent];if(!result)return image;UIImage *picture=[UIImage imageWithCGImage:result scale:image.scale orientation:image.imageOrientation];CGImageRelease(result);return picture;
}
