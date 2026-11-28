#import "DGMetalFXPlayback.h"
#import "DGVideoFrames.h"
#import "DGMediaEnhancement.h"
#import "DGDiagnostics.h"
#import "DGAnimation.h"
#import <CoreImage/CoreImage.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include "ExperimentalMedia.hpp"
#include <atomic>
#include <cmath>

namespace {
std::atomic_bool renderInFlight{false};

dispatch_queue_t metalFXQueue() {
    static dispatch_queue_t queue=dispatch_queue_create("io.douglass.metalfx",DISPATCH_QUEUE_SERIAL);
    return queue;
}

struct MetalFXRenderer {
    explicit MetalFXRenderer(id<MTLDevice> device):device(device),scaler((__bridge void *)device){}
    id<MTLDevice> device;
    id<MTLCommandQueue> queue;
    CIContext *context;
    id<MTLTexture> sourceTexture,scaledTexture;
    douglass::SpatialUpscaler scaler;

    bool prepareTextures(NSUInteger width,NSUInteger height,MTLPixelFormat format) {
        if(!queue)queue=[device newCommandQueue];
        if(!context)context=[CIContext contextWithMTLDevice:device options:@{kCIContextCacheIntermediates:@NO}];
        if(!queue||!context)return false;
        if(sourceTexture.width==width&&sourceTexture.height==height&&sourceTexture.pixelFormat==format&&scaledTexture)return true;
        sourceTexture=nil;
        scaledTexture=nil;
        auto texture=[&](NSUInteger w,NSUInteger h){
            MTLTextureDescriptor *descriptor=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format width:w height:h mipmapped:NO];
            descriptor.storageMode=MTLStorageModePrivate;
            descriptor.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite|MTLTextureUsageRenderTarget;
            return [device newTextureWithDescriptor:descriptor];
        };
        sourceTexture=texture(width,height);
        if(sourceTexture)scaledTexture=texture(width*douglass::metalFXScale,height*douglass::metalFXScale);
        return sourceTexture&&scaledTexture;
    }
};

bool isHDR(CVPixelBufferRef frame) {
    CFTypeRef transfer=CVBufferGetAttachment(frame,kCVImageBufferTransferFunctionKey,nullptr);
    return transfer&&(CFEqual(transfer,kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)||
                      CFEqual(transfer,kCVImageBufferTransferFunction_ITU_R_2100_HLG));
}
}

@interface DGMetalFXPlayback ()
- (void)tick:(CADisplayLink *)link;
@end

@interface DGMetalFXClock : NSObject
@property(nonatomic,weak) DGMetalFXPlayback *owner;
- (void)tick:(CADisplayLink *)link;
@end

@implementation DGMetalFXClock
- (void)tick:(CADisplayLink *)link {
    DGMetalFXPlayback *owner=self.owner;
    if(owner)[owner tick:link];else [link invalidate];
}
@end

@implementation DGMetalFXPlayback {
    __weak AVPlayerLayer *_playerLayer;
    __weak AVPlayerItem *_item;
    CAMetalLayer *_surface;
    CADisplayLink *_clock;
    CGAffineTransform _orientation;
    CMTime _lastFrameTime;
    CFTimeInterval _lastOutput,_startedAt,_retryAfter;
    NSUInteger _binding,_generation;
    std::shared_ptr<MetalFXRenderer> _renderer;
    std::shared_ptr<std::atomic_bool> _cancel;
    BOOL _loggedOutputSize;
}

- (void)showForPlayerLayer:(AVPlayerLayer *)layer {
    AVPlayerItem *item=layer.player.currentItem;
    if(!DGMetalFXRequested()||!DGMetalFXSpatialAvailable()||!item){[self stop];return;}
    if(_item==item&&_playerLayer==layer&&_clock)return;
    [self stop];
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();
    if(!device)return;
    _playerLayer=layer;
    _item=item;
    _startedAt=CACurrentMediaTime();
    _orientation=CGAffineTransformIdentity;
    _renderer=std::make_shared<MetalFXRenderer>(device);
    _surface=[CAMetalLayer layer];
    _surface.device=device;
    _surface.framebufferOnly=NO;
    _surface.maximumDrawableCount=2;
    _surface.opaque=NO;
    _surface.opacity=0;
    [_playerLayer addSublayer:_surface];
    [self layout];
    DGReportMetalFX(self,@"preparing",@"waiting_for_frame");
    NSUInteger binding=++_binding;
    __weak DGMetalFXPlayback *weak=self;
    [item.asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks,NSError *error){
        AVAssetTrack *track=tracks.firstObject;
        if(!track)return;
        [track loadValuesAsynchronouslyForKeys:@[@"preferredTransform"] completionHandler:^{
            if([track statusOfValueForKey:@"preferredTransform" error:nil]!=AVKeyValueStatusLoaded)return;
            CGAffineTransform transform=track.preferredTransform;
            dispatch_async(dispatch_get_main_queue(),^{
                DGMetalFXPlayback *owner=weak;
                if(!owner||owner->_binding!=binding)return;
                owner->_orientation=transform;
            });
        }];
    }];
    DGMetalFXClock *target=[DGMetalFXClock new];target.owner=self;
    _clock=[CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];
    _clock.preferredFrameRateRange=CAFrameRateRangeMake(30,60,60);
    [_clock addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)layout {
    if(!_surface)return;
    CGRect viewport=CGRectIntersection(_playerLayer.bounds,_playerLayer.videoRect);
    if(CGRectIsNull(viewport))viewport=CGRectZero;
    const CGFloat scale=UIScreen.mainScreen.scale;
    CGSize pixels=CGSizeMake(ceil(viewport.size.width*scale),ceil(viewport.size.height*scale));
    if(CGRectEqualToRect(_surface.frame,viewport)&&CGSizeEqualToSize(_surface.drawableSize,pixels))return;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _surface.frame=viewport;
    if(pixels.width>0&&pixels.height>0)_surface.drawableSize=pixels;
    [CATransaction commit];
}

- (void)showOutput:(BOOL)visible {
    const float opacity=visible?1:0;
    if(_surface.opacity==opacity)return;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _surface.opacity=opacity;
    [CATransaction commit];
}

- (void)resetFrame {
    ++_generation;
    if(_cancel)_cancel->store(true,std::memory_order_relaxed);
    _cancel.reset();
    _lastFrameTime=kCMTimeInvalid;
    _lastOutput=0;
    _retryAfter=0;
    _startedAt=CACurrentMediaTime();
    [self showOutput:NO];
}

- (void)stop {
    if(!_surface)return;
    DGEndMetalFX(self);
    ++_binding;
    [_clock invalidate];_clock=nil;
    [self resetFrame];
    [_surface removeFromSuperlayer];_surface=nil;
    _renderer.reset();
    _playerLayer=nil;
    _item=nil;
    _loggedOutputSize=NO;
}

- (void)tick:(CADisplayLink *)link {
    AVPlayerLayer *layer=_playerLayer;
    AVPlayerItem *item=_item;
    if(!layer||!item||layer.player.currentItem!=item){[self stop];return;}
    if(!layer.readyForDisplay||layer.player.timeControlStatus!=AVPlayerTimeControlStatusPlaying||DGAnimationProcessingDeferred()){
        if(CMTIME_IS_VALID(_lastFrameTime))[self resetFrame];
        return;
    }
    [self layout];
    if(CGRectIsEmpty(_surface.frame))return;
    const auto now=CACurrentMediaTime();
    if(_lastOutput&&now-_lastOutput>.20){
        [self showOutput:NO];
        DGReportMetalFX(self,@"bypassed",@"no_output");
        _lastOutput=0;
    }
    if(now<_retryAfter||renderInFlight.load(std::memory_order_acquire))return;
    CMTime frameTime=kCMTimeInvalid;
    CVPixelBufferRef frame=DGCopyVideoFrame(item,link.targetTimestamp,&frameTime);
    if(!frame||!CMTIME_IS_NUMERIC(frameTime)||CMTimeCompare(frameTime,_lastFrameTime)==0){
        if(frame)CVPixelBufferRelease(frame);
        if(!CMTIME_IS_VALID(_lastFrameTime)&&now-_startedAt>1.2)DGReportMetalFX(self,@"bypassed",@"no_output");
        return;
    }
    _lastFrameTime=frameTime;
    const bool hdr=isHDR(frame);
    CIImage *image=[CIImage imageWithCVPixelBuffer:frame];
    CVPixelBufferRelease(frame);
    CGSize presentation=item.presentationSize;
    CGAffineTransform transform=_orientation;
    const bool quarterTurn=fabs(transform.b)>.5||fabs(transform.c)>.5;
    const bool alreadyOriented=presentation.width>0&&presentation.height>0&&
        ((image.extent.size.width>image.extent.size.height)==(presentation.width>presentation.height));
    if(item.videoComposition||(quarterTurn&&alreadyOriented))transform=CGAffineTransformIdentity;
    image=[image imageByApplyingTransform:transform];
    CGRect extent=image.extent;
    if(CGRectIsEmpty(extent)||CGRectIsInfinite(extent))return;
    image=[image imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x,-extent.origin.y)];
    const NSUInteger width=(NSUInteger)ceil(extent.size.width),height=(NSUInteger)ceil(extent.size.height);
    const MTLPixelFormat format=hdr?MTLPixelFormatRGBA16Float:MTLPixelFormatBGRA8Unorm;
    const auto colorName=hdr?kCGColorSpaceExtendedLinearDisplayP3:kCGColorSpaceSRGB;
    if(renderInFlight.exchange(true,std::memory_order_acq_rel))return;
    CAMetalLayer *surface=_surface;
    if(surface.pixelFormat!=format||!surface.colorspace){
        CGColorSpaceRef color=CGColorSpaceCreateWithName(colorName);
        surface.pixelFormat=format;
        surface.colorspace=color;
        if(color)CGColorSpaceRelease(color);
        surface.wantsExtendedDynamicRangeContent=hdr;
    }
    if(!_cancel)_cancel=std::make_shared<std::atomic_bool>(false);
    auto cancel=_cancel;
    auto renderer=_renderer;
    NSUInteger generation=_generation;
    __weak DGMetalFXPlayback *weak=self;
    void (^finish)(BOOL,NSString *)=^(BOOL ok,NSString *reason){
        renderInFlight.store(false,std::memory_order_release);
        dispatch_async(dispatch_get_main_queue(),^{
            DGMetalFXPlayback *owner=weak;
            if(!owner||owner->_generation!=generation||owner->_surface!=surface)return;
            if(!ok){
                if(reason.length){
                    owner->_retryAfter=CACurrentMediaTime()+1;
                    [owner showOutput:NO];
                    DGReportMetalFX(owner,@"bypassed",reason);
                }
                return;
            }
            owner->_lastOutput=CACurrentMediaTime();
            [owner showOutput:YES];
            DGReportMetalFX(owner,@"active",@"frame_output");
            if(!owner->_loggedOutputSize){
                owner->_loggedOutputSize=YES;
                DGDiagnostic(@"video.metalfx.output",[NSString stringWithFormat:@"width=%lu height=%lu scale=2 hdr=%d",
                    (unsigned long)(width*douglass::metalFXScale),(unsigned long)(height*douglass::metalFXScale),hdr]);
            }
        });
    };
    dispatch_async(metalFXQueue(),^{@autoreleasepool{
        if(cancel->load(std::memory_order_relaxed)){finish(NO,nil);return;}
        @try {
            if(!renderer->prepareTextures(width,height,format)){finish(NO,@"gpu");return;}
            id<CAMetalDrawable> drawable=[surface nextDrawable];
            id<MTLCommandBuffer> command=[renderer->queue commandBuffer];
            if(!drawable||!command){finish(NO,@"renderer");return;}
            id color=CFBridgingRelease(CGColorSpaceCreateWithName(colorName));
            if(!color){finish(NO,@"gpu");return;}
            [renderer->context render:image toMTLTexture:renderer->sourceTexture commandBuffer:command bounds:CGRectMake(0,0,width,height) colorSpace:(__bridge CGColorSpaceRef)color];
            if(!renderer->scaler.encode((__bridge void *)command,(__bridge void *)renderer->sourceTexture,(__bridge void *)renderer->scaledTexture,hdr)){
                finish(NO,@"gpu");
                return;
            }
            CIImage *scaled=[CIImage imageWithMTLTexture:renderer->scaledTexture options:@{kCIImageColorSpace:color}];
            if(!scaled){finish(NO,@"gpu");return;}
            CGFloat w=drawable.texture.width,h=drawable.texture.height;
            CGFloat zoom=MAX(w/scaled.extent.size.width,h/scaled.extent.size.height);
            scaled=[scaled imageByApplyingTransform:CGAffineTransformMakeScale(zoom,zoom)];
            scaled=[scaled imageByApplyingTransform:CGAffineTransformMakeTranslation((w-scaled.extent.size.width)*.5,(h-scaled.extent.size.height)*.5)];
            [renderer->context render:scaled toMTLTexture:drawable.texture commandBuffer:command bounds:CGRectMake(0,0,w,h) colorSpace:(__bridge CGColorSpaceRef)color];
            if(cancel->load(std::memory_order_relaxed)){finish(NO,nil);return;}
            [command presentDrawable:drawable];
            [command addCompletedHandler:^(id<MTLCommandBuffer> buffer){
                // Keep the scaler and its texture resources alive until its GPU work finishes.
                static_cast<void>(renderer);
                if(cancel->load(std::memory_order_relaxed)){finish(NO,nil);return;}
                if(buffer.status==MTLCommandBufferStatusCompleted)finish(YES,nil);
                else finish(NO,@"gpu");
            }];
            [command commit];
        } @catch(NSException *exception) {
            finish(NO,@"gpu");
        }
    }});
}

- (void)dealloc{[self stop];}
@end
