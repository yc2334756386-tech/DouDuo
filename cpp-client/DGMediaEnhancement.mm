#import "DGMediaEnhancement.h"
#import "DGDiagnostics.h"
#import <Metal/Metal.h>
#import <VideoToolbox/VideoToolbox.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <CoreImage/CoreImage.h>
#import "DGAnimation.h"
#include <atomic>
#include "ExperimentalMedia.hpp"
static BOOL DGSupports(Class cls,id device){if(!cls||!device)return NO;SEL selector=NSSelectorFromString(@"supportsDevice:");if(![cls respondsToSelector:selector])return NO;BOOL(*message)(id,SEL,id)=(BOOL(*)(id,SEL,id))objc_msgSend;return message(cls,selector,device);}
BOOL DGMetalFXSpatialAvailable(void){return DGSupports(NSClassFromString(@"MTLFXSpatialScalerDescriptor"),MTLCreateSystemDefaultDevice());}
BOOL DGMetalFXFrameInterpolationAvailable(void){return DGSupports(NSClassFromString(@"MTLFXFrameInterpolatorDescriptor"),MTLCreateSystemDefaultDevice());}
BOOL DGVTLowLatencySuperResolutionAvailable(void){return NSClassFromString(@"VTLowLatencySuperResolutionScalerConfiguration")!=Nil&&NSClassFromString(@"VTFrameProcessor")!=Nil;}
NSString *DGMediaEnhancementStatus(void){return [NSString stringWithFormat:@"MetalFX 空间放大 %@；插帧接口 %@（尚未接入视频）；VT 低延迟超分 API %@（未接入）",DGMetalFXSpatialAvailable()?@"支持":@"不支持",DGMetalFXFrameInterpolationAvailable()?@"支持":@"不支持",DGVTLowLatencySuperResolutionAvailable()?@"存在":@"不存在"];}
void DGMediaEnhancementApply(void){BOOL spatial=[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.experimental.metalfx"],interpolation=[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.experimental.frameInterpolation"];if(spatial&&!DGMetalFXSpatialAvailable())[NSUserDefaults.standardUserDefaults setBool:NO forKey:@"douglass.experimental.metalfx"];if(interpolation&&!DGMetalFXFrameInterpolationAvailable())[NSUserDefaults.standardUserDefaults setBool:NO forKey:@"douglass.experimental.frameInterpolation"];DGDiagnostic(@"experimental.media.settings",[NSString stringWithFormat:@"metalfx=%d interpolation=%d status=%@",[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.experimental.metalfx"],[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.experimental.frameInterpolation"],DGMediaEnhancementStatus()]);[NSNotificationCenter.defaultCenter postNotificationName:@"DGMediaEnhancementChanged" object:nil];}
@interface DGSpatialSession:NSObject
@property(nonatomic) double scale;
- (void)filter:(AVAsynchronousCIImageFilteringRequest *)request preset:(NSInteger)preset spatial:(BOOL)spatial;
@end
@implementation DGSpatialSession{ id<MTLDevice> _device;id<MTLCommandQueue> _queue;CIContext *_context;id<MTLTexture> _input,_output;std::unique_ptr<douglass::SpatialUpscaler> _scaler;std::atomic_bool _busy;}
- (void)filter:(AVAsynchronousCIImageFilteringRequest *)request preset:(NSInteger)preset spatial:(BOOL)spatial{
 CIImage *source=request.sourceImage;CGRect extent=source.extent;CIImage *image=source;double factor=MAX(1,self.scale);
 if(preset){auto values=douglass::picturePreset((unsigned)preset);image=[image imageByApplyingFilter:@"CIColorControls" withInputParameters:@{kCIInputSaturationKey:@(values.saturation),kCIInputContrastKey:@(values.contrast),kCIInputBrightnessKey:@(values.brightness)}];}
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
void DGConfigureMediaEnhancement(AVPlayerItem *item){
 if(!item)return;NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;BOOL spatial=[prefs boolForKey:@"douglass.experimental.metalfx"]&&DGMetalFXSpatialAvailable();NSInteger preset=[prefs integerForKey:@"douglass.experimental.picturePreset"];
 static const void *key=&key;id token=[NSObject new];objc_setAssociatedObject(item,key,token,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 if(!spatial&&!preset){item.videoComposition=nil;return;}
 DGSpatialSession *session=[DGSpatialSession new];__weak AVPlayerItem *weak=item;AVAsset *asset=item.asset;
 // Reading an unloaded AVAsset property synchronously can hold up player
 // construction. Resolve it asynchronously and keep playback independent.
 [asset loadValuesAsynchronouslyForKeys:@[@"hasProtectedContent"] completionHandler:^{
  if([asset statusOfValueForKey:@"hasProtectedContent" error:nil]!=AVKeyValueStatusLoaded||asset.hasProtectedContent)return;
  [AVVideoComposition videoCompositionWithAsset:asset applyingCIFiltersWithHandler:^(AVAsynchronousCIImageFilteringRequest *request){[session filter:request preset:preset spatial:spatial];} completionHandler:^(AVVideoComposition *composition,NSError *error){dispatch_async(dispatch_get_main_queue(),^{AVPlayerItem *current=weak;if(!current||objc_getAssociatedObject(current,key)!=token||!composition)return;CGSize size=composition.renderSize;double longest=MAX(size.width,size.height);session.scale=spatial&&longest>0?MAX(1.,MIN(1.5,1920./longest)):1.;AVMutableVideoComposition *configured=[composition mutableCopy];configured.renderSize=CGSizeMake(ceil(size.width*session.scale),ceil(size.height*session.scale));current.videoComposition=configured;DGDiagnostic(@"video.enhancement.attached",[NSString stringWithFormat:@"spatial=%d scale=%.2f preset=%ld input_w=%.0f input_h=%.0f",spatial,session.scale,(long)preset,size.width,size.height]);});}];
 }];
}
UIImage *DGApplyPicturePreset(UIImage *image,unsigned preset){
 if(!image||!image.CGImage||!preset||image.images.count)return image;
 static CIContext *context;static dispatch_once_t once;dispatch_once(&once,^{context=[CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}];});
 auto values=douglass::picturePreset(preset);CIImage *input=[CIImage imageWithCGImage:image.CGImage];CIImage *output=[input imageByApplyingFilter:@"CIColorControls" withInputParameters:@{kCIInputSaturationKey:@(values.saturation),kCIInputContrastKey:@(values.contrast),kCIInputBrightnessKey:@(values.brightness)}];CGImageRef result=[context createCGImage:output fromRect:input.extent];if(!result)return image;UIImage *picture=[UIImage imageWithCGImage:result scale:image.scale orientation:image.imageOrientation];CGImageRelease(result);return picture;
}
