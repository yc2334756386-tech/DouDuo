#import "DGVideoEffects.h"
#import "DGAnimation.h"
#import "DGDiagnostics.h"
#import <VideoToolbox/VideoToolbox.h>
#import <objc/runtime.h>
#include <arm_neon.h>
#include <sys/sysctl.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <memory>
#include <type_traits>

BOOL DGVTFSystemInterpolationAvailable(void) {
    if(@available(iOS 26.0,*)){
        static BOOL supported;
        static dispatch_once_t once;
        dispatch_once(&once,^{
            char machine[64]={};
            size_t length=sizeof(machine);
            NSOperatingSystemVersion version=NSProcessInfo.processInfo.operatingSystemVersion;
            BOOL affected=version.majorVersion==27&&version.minorVersion==0&&version.patchVersion==1&&
                sysctlbyname("hw.machine",machine,&length,nullptr,0)==0&&std::strcmp(machine,"iPhone16,2")==0;
            supported=!affected&&[VTLowLatencyFrameInterpolationConfiguration isSupported];
        });
        return supported;
    }
    return NO;
}
BOOL DGSuperResolutionTransitionProtection(void) {
    NSNumber *saved=[NSUserDefaults.standardUserDefaults objectForKey:@"douglass.experimental.transitionProtection"];
    return !saved||saved.boolValue;
}
BOOL DGVTSuperResolutionAvailable(void) {
    if(@available(iOS 26.0,*)){
        static BOOL supported=NO;
        static dispatch_once_t once;
        dispatch_once(&once,^{supported=[VTLowLatencySuperResolutionScalerConfiguration isSupported];});
        return supported;
    }
    return NO;
}

namespace {
constexpr double effectsSettleDelay=.20;
constexpr double protectedSettleDelay=.55;
constexpr double renderLead=.048;
constexpr unsigned minimumReadyFrames=3;

dispatch_queue_t effectsQueue(){
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        queue=dispatch_queue_create("io.douglass.video.effects",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0));
    });
    return queue;
}

NSURL *sessionMarkerURL(NSString *kind) {
    NSURL *folder=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    if(!folder)return nil;
    folder=[folder URLByAppendingPathComponent:@"VideoEffects" isDirectory:YES];
    if(![NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil])return nil;
    NSOperatingSystemVersion os=NSProcessInfo.processInfo.operatingSystemVersion;
    NSString *name=[NSString stringWithFormat:@"%@-%ld.%ld.%ld.pending",kind,(long)os.majorVersion,(long)os.minorVersion,(long)os.patchVersion];
    return [folder URLByAppendingPathComponent:name];
}

BOOL startEffectSession(VTFrameProcessor *session,id<VTFrameProcessorConfiguration> configuration,NSString *kind) API_AVAILABLE(ios(26.0));
BOOL startEffectSession(VTFrameProcessor *session,id<VTFrameProcessorConfiguration> configuration,NSString *kind) {
    if(!configuration)return NO;
    // A native crash cannot be caught here. On the next launch, skip the
    // effect that was starting and keep the player usable.
    NSURL *marker=sessionMarkerURL(kind);
    NSFileManager *files=NSFileManager.defaultManager;
    if(!marker||[files fileExistsAtPath:marker.path]||
       ![[NSData dataWithBytes:"1" length:1] writeToURL:marker options:NSDataWritingAtomic error:nil]){
        DGDiagnostic(@"video.vt.bypass",[NSString stringWithFormat:@"effect=%@ reason=session_start_guard",kind]);
        return NO;
    }
    NSError *error=nil;
    BOOL started=[session startSessionWithConfiguration:configuration error:&error];
    [files removeItemAtURL:marker error:nil];
    if(!started)DGDiagnostic(@"video.vt.session_failed",[NSString stringWithFormat:@"effect=%@ code=%ld",kind,(long)error.code]);
    return started;
}

bool supportsInterpolationSize(size_t width,size_t height) API_AVAILABLE(ios(26.0));
bool supportsInterpolationSize(size_t width,size_t height) {
    if(!width||!height||width%2||height%2)return false;
    if(@available(iOS 27.0,*)){
        auto dimension=[VTLowLatencyFrameInterpolationConfiguration maximumDimensionForSpatialScaleFactor:1];
        auto pixels=[VTLowLatencyFrameInterpolationConfiguration maximumPixelCountForSpatialScaleFactor:1];
        if(dimension<=0||pixels<=0||std::max(width,height)>static_cast<size_t>(dimension)||width>static_cast<size_t>(pixels)/height)return false;
    }
    return std::max(width,height)<=1920&&width*height<=1920*1080;
}

using PixelBuffer=std::shared_ptr<std::remove_pointer_t<CVPixelBufferRef>>;
PixelBuffer ownPixel(CVPixelBufferRef pixel){return PixelBuffer(pixel,[](CVPixelBufferRef buffer){if(buffer)CVPixelBufferRelease(buffer);});}

CVPixelBufferPoolRef makePool(NSDictionary *attributes,size_t width,size_t height,OSType format) {
    NSMutableDictionary *values=[attributes mutableCopy]?:[NSMutableDictionary dictionary];
    values[(__bridge NSString *)kCVPixelBufferWidthKey]=@(width);
    values[(__bridge NSString *)kCVPixelBufferHeightKey]=@(height);
    values[(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey]=@(format);
    values[(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey]=@{};
    CVPixelBufferPoolRef pool=nullptr;
    CVPixelBufferPoolCreate(kCFAllocatorDefault,nullptr,(__bridge CFDictionaryRef)values,&pool);
    return pool;
}
PixelBuffer allocate(CVPixelBufferPoolRef pool,CVPixelBufferRef source) {
    if(!pool)return {};
    CVPixelBufferRef pixel=nullptr;
    NSDictionary *limits=@{(__bridge NSString *)kCVPixelBufferPoolAllocationThresholdKey:@6};
    if(CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,pool,(__bridge CFDictionaryRef)limits,&pixel)!=kCVReturnSuccess)return {};
    CVBufferPropagateAttachments(source,pixel);
    return ownPixel(pixel);
}

class LockedPixel {
public:
    LockedPixel(CVPixelBufferRef pixel,CVPixelBufferLockFlags flags):pixel_(pixel),flags_(flags) {
        locked_=pixel&&CVPixelBufferLockBaseAddress(pixel,flags)==kCVReturnSuccess;
    }
    ~LockedPixel(){if(locked_)CVPixelBufferUnlockBaseAddress(pixel_,flags_);}
    explicit operator bool() const {return locked_;}
private:
    CVPixelBufferRef pixel_;
    CVPixelBufferLockFlags flags_;
    bool locked_=false;
};

// Blending constructs a real midpoint without starting the affected system
// interpolation session. Keep scene cuts on the original frame cadence.
PixelBuffer blendMidpoint(CVPixelBufferPoolRef pool,CVPixelBufferRef previous,CVPixelBufferRef current,
                          const std::atomic_bool &cancelled) {
    if(!previous||!current||CVPixelBufferGetPlaneCount(previous)!=2||CVPixelBufferGetPlaneCount(current)!=2)return {};
    if(CVPixelBufferGetWidth(previous)!=CVPixelBufferGetWidth(current)||CVPixelBufferGetHeight(previous)!=CVPixelBufferGetHeight(current))return {};
    LockedPixel readPrevious(previous,kCVPixelBufferLock_ReadOnly),readCurrent(current,kCVPixelBufferLock_ReadOnly);
    if(!readPrevious||!readCurrent||cancelled.load(std::memory_order_relaxed))return {};
    auto *first=static_cast<const uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(previous,0));
    auto *second=static_cast<const uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(current,0));
    if(!first||!second)return {};
    const size_t width=CVPixelBufferGetWidth(current),height=CVPixelBufferGetHeight(current);
    auto stride0=CVPixelBufferGetBytesPerRowOfPlane(previous,0);
    auto stride1=CVPixelBufferGetBytesPerRowOfPlane(current,0);
    size_t sum=0,count=0;
    for(size_t y=0;y<height;y+=24)for(size_t x=0;x<width;x+=24){
        sum+=std::abs(int(first[y*stride0+x])-int(second[y*stride1+x]));++count;
    }
    if(count&&sum>count*45)return {};
    auto output=allocate(pool,current);
    LockedPixel write(output.get(),0);
    if(!write)return {};
    for(size_t plane=0;plane<2;++plane){
        const auto *a=static_cast<const uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(previous,plane));
        const auto *b=static_cast<const uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(current,plane));
        auto *out=static_cast<uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(output.get(),plane));
        const size_t bytes=CVPixelBufferGetWidthOfPlane(current,plane)*(plane?2:1);
        const size_t aStride=CVPixelBufferGetBytesPerRowOfPlane(previous,plane);
        const size_t bStride=CVPixelBufferGetBytesPerRowOfPlane(current,plane);
        const size_t outStride=CVPixelBufferGetBytesPerRowOfPlane(output.get(),plane);
        if(!a||!b||!out||std::min({aStride,bStride,outStride})<bytes)return {};
        for(size_t y=0;y<CVPixelBufferGetHeightOfPlane(current,plane);++y){
            if((y&31)==0&&cancelled.load(std::memory_order_relaxed))return {};
            size_t x=0;
            for(;x+16<=bytes;x+=16)vst1q_u8(out+x,vrhaddq_u8(vld1q_u8(a+x),vld1q_u8(b+x)));
            for(;x<bytes;++x)out[x]=(unsigned(a[x])+unsigned(b[x])+1)/2;
            a+=aStride;b+=bStride;out+=outStride;
        }
    }
    return output;
}

struct FramePair {
    PixelBuffer source,previous;
    CMTime time=kCMTimeInvalid,previousTime=kCMTimeInvalid;
};
struct FrameResult {
    PixelBuffer current,midpoint;
    bool supported=false,compatibility=false,upscaled=false;
};

struct ProcessorKey {
    size_t width=0,height=0;
    OSType format=0;
    bool interpolation=false,systemInterpolation=false,resolution=false;
    bool operator==(const ProcessorKey &) const=default;
};

class VideoProcessor {
public:
    explicit VideoProcessor(ProcessorKey key):key_(key){}
    ~VideoProcessor(){
        if(@available(iOS 26.0,*)){
            [interpolationSession_ endSession];
            [resolutionSession_ endSession];
        }
        if(interpolationPool_)CVPixelBufferPoolRelease(interpolationPool_);
        if(resolutionPool_)CVPixelBufferPoolRelease(resolutionPool_);
        if(blendPool_)CVPixelBufferPoolRelease(blendPool_);
    }
    FrameResult process(const FramePair &pair,const std::atomic_bool &cancelled) {
        if(cancelled.load(std::memory_order_relaxed))return {};
        if(!configured_){
            configured_=true;
            if(@available(iOS 26.0,*))configure(cancelled);
            if(key_.interpolation&&std::max(key_.width,key_.height)<=2560&&key_.width*key_.height<=1920*1080)
                blendPool_=makePool(@{},key_.width,key_.height,key_.format);
        }
        FrameResult frames;
        frames.supported=interpolationSession_||resolutionSession_||blendPool_;
        if(cancelled.load(std::memory_order_relaxed)||!frames.supported)return frames;
        if(@available(iOS 26.0,*))processSystem(pair,cancelled,frames);
        if(!frames.midpoint&&pair.previous&&blendPool_){
            frames.midpoint=blendMidpoint(blendPool_,pair.previous.get(),pair.source.get(),cancelled);
            frames.compatibility=bool(frames.midpoint);
        }
        if(!frames.current)frames.current=pair.source;
        return frames;
    }
private:
    void processSystem(const FramePair &pair,const std::atomic_bool &cancelled,FrameResult &frames) API_AVAILABLE(ios(26.0)) {
        if(!interpolationSession_&&!resolutionSession_)return;
        VTFrameProcessorFrame *source=[[VTFrameProcessorFrame alloc] initWithBuffer:pair.source.get() presentationTimeStamp:pair.time];
        if(!source)return;
        if(interpolationSession_&&pair.previous){
            auto midpoint=allocate(interpolationPool_,pair.source.get());
            CMTime time=CMTimeAdd(pair.previousTime,CMTimeMultiplyByFloat64(CMTimeSubtract(pair.time,pair.previousTime),.5));
            VTFrameProcessorFrame *destination=midpoint?[[VTFrameProcessorFrame alloc] initWithBuffer:midpoint.get() presentationTimeStamp:time]:nil;
            VTFrameProcessorFrame *previous=[[VTFrameProcessorFrame alloc] initWithBuffer:pair.previous.get() presentationTimeStamp:pair.previousTime];
            if(previous&&destination){
                auto *parameters=[[VTLowLatencyFrameInterpolationParameters alloc] initWithSourceFrame:source previousFrame:previous interpolationPhase:@[@.5] destinationFrames:@[destination]];
                if(parameters&&[interpolationSession_ processWithParameters:parameters error:nil])frames.midpoint=std::move(midpoint);
            }
        }
        if(resolutionSession_&&!cancelled.load(std::memory_order_relaxed)){
            auto upscaled=allocate(resolutionPool_,pair.source.get());
            VTFrameProcessorFrame *destination=upscaled?[[VTFrameProcessorFrame alloc] initWithBuffer:upscaled.get() presentationTimeStamp:pair.time]:nil;
            if(destination){
                auto *parameters=[[VTLowLatencySuperResolutionScalerParameters alloc] initWithSourceFrame:source destinationFrame:destination];
                if(parameters&&[resolutionSession_ processWithParameters:parameters error:nil]){
                    frames.current=std::move(upscaled);
                    frames.upscaled=true;
                }
            }
        }
    }
    void configure(const std::atomic_bool &cancelled) API_AVAILABLE(ios(26.0)) {
        const auto [width,height,format,interpolation,systemInterpolation,resolution]=key_;
        if(interpolation&&systemInterpolation&&supportsInterpolationSize(width,height)){
            auto *config=[[VTLowLatencyFrameInterpolationConfiguration alloc] initWithFrameWidth:width frameHeight:height numberOfInterpolatedFrames:1];
            if([config.frameSupportedPixelFormats containsObject:@(format)]){
                auto *session=[VTFrameProcessor new];
                if(startEffectSession(session,config,@"interpolation")){
                    interpolationPool_=makePool(config.destinationPixelBufferAttributes,width,height,format);
                    if(interpolationPool_)interpolationSession_=session;
                    else [session endSession];
                }
            }
        }
        if(resolution&&!cancelled.load(std::memory_order_relaxed)){
            NSArray<NSNumber *> *factors=[VTLowLatencySuperResolutionScalerConfiguration supportedScaleFactorsForFrameWidth:width frameHeight:height];
            double factor=0;
            for(NSNumber *candidate in factors){
                double ratio=candidate.doubleValue;
                if(ratio>1&&std::max(width,height)*ratio<=2560&&(factor==0||ratio<factor))factor=ratio;
            }
            if(factor>1){
                auto *config=[[VTLowLatencySuperResolutionScalerConfiguration alloc] initWithFrameWidth:width frameHeight:height scaleFactor:factor];
                if([config.frameSupportedPixelFormats containsObject:@(format)]){
                    auto *session=[VTFrameProcessor new];
                    if(startEffectSession(session,config,@"super-resolution")){
                        resolutionPool_=makePool(config.destinationPixelBufferAttributes,std::llround(width*factor),std::llround(height*factor),format);
                        if(resolutionPool_)resolutionSession_=session;
                        else [session endSession];
                    }
                }
            }
        }
        DGDiagnostic(@"video.vt.configured",[NSString stringWithFormat:@"width=%zu height=%zu interpolation=%d scale=%.2f",width,height,interpolationSession_!=nil,resolutionSession_?factorForLog(width):1.]);
    }
    double factorForLog(size_t width) const {
        auto attributes=(__bridge NSDictionary *)CVPixelBufferPoolGetPixelBufferAttributes(resolutionPool_);
        return [attributes[(__bridge NSString *)kCVPixelBufferWidthKey] doubleValue]/width;
    }
    ProcessorKey key_;
    bool configured_=false;
    VTFrameProcessor *__strong interpolationSession_=nil,*__strong resolutionSession_=nil;
    CVPixelBufferPoolRef interpolationPool_=nullptr,resolutionPool_=nullptr,blendPool_=nullptr;
};

// All cells use one worker. Paging clears the current processor before the
// selected cell can start another session.
class SharedVideoProcessor {
public:
    FrameResult process(const ProcessorKey &key,const FramePair &pair,const std::atomic_bool &cancelled) {
        if(!processor_||key_!=key){
            processor_.reset();
            key_=key;
            processor_=std::make_unique<VideoProcessor>(key);
        }
        return processor_->process(pair,cancelled);
    }
    void clear(){processor_.reset();}
private:
    ProcessorKey key_;
    std::unique_ptr<VideoProcessor> processor_;
};

SharedVideoProcessor &sharedVideoProcessor(){
    static SharedVideoProcessor processor;
    return processor;
}

std::atomic_bool processingFrame{false};
}

// Attach once, before the item is bound or prerolled. All consumers share the
// decoded output, so enabling effects never reconfigures an active decoder.
@interface DGVideoFrameSource : NSObject {
@public
    PixelBuffer latest;
    CMTime presentationTime;
}
@property(nonatomic,strong) AVPlayerItemVideoOutput *output;
@end
@implementation DGVideoFrameSource
@end

static const void *DGVideoFrameSourceKey=&DGVideoFrameSourceKey;

void DGPrepareVideoFrameOutput(AVPlayerItem *item) {
    if(!item||objc_getAssociatedObject(item,DGVideoFrameSourceKey))return;
    DGVideoFrameSource *source=[DGVideoFrameSource new];
    source->presentationTime=kCMTimeInvalid;
    source.output=[[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey:@{}
    }];
    [item addOutput:source.output];
    objc_setAssociatedObject(item,DGVideoFrameSourceKey,source,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

CVPixelBufferRef DGCopyVideoFrame(AVPlayerItem *item,CFTimeInterval hostTime,CMTime *presentationTime) {
    if(!item)return nullptr;
    DGVideoFrameSource *source=objc_getAssociatedObject(item,DGVideoFrameSourceKey);
    if(!source)return nullptr;
    CMTime time=[source.output itemTimeForHostTime:hostTime];
    if(CMTIME_IS_NUMERIC(time)&&[source.output hasNewPixelBufferForItemTime:time]){
        CMTime actual=kCMTimeInvalid;
        auto pixel=ownPixel([source.output copyPixelBufferForItemTime:time itemTimeForDisplay:&actual]);
        if(pixel&&CMTIME_IS_NUMERIC(actual)){
            source->latest=std::move(pixel);
            source->presentationTime=actual;
        }
    }
    if(presentationTime)*presentationTime=source->presentationTime;
    return source->latest?CVPixelBufferRetain(source->latest.get()):nullptr;
}

void DGReleaseVideoFrameCache(AVPlayerItem *item){
    if(!item)return;
    DGVideoFrameSource *source=objc_getAssociatedObject(item,DGVideoFrameSourceKey);
    if(source){source->latest.reset();source->presentationTime=kCMTimeInvalid;}
}

@class DGVideoEffects;
@interface DGVideoEffectsClock : NSObject
@property(nonatomic,weak) DGVideoEffects *owner;
- (void)tick:(CADisplayLink *)link;
@end
@interface DGVideoEffects ()
- (void)tick:(CADisplayLink *)link;
- (void)releaseProcessing;
@end
@implementation DGVideoEffectsClock
- (void)tick:(CADisplayLink *)link{DGVideoEffects *owner=self.owner;if(owner)[owner tick:link];else [link invalidate];}
@end

@implementation DGVideoEffects {
    __weak AVPlayerLayer *_nativeLayer;
    __weak AVPlayerItem *_item;
    AVSampleBufferDisplayLayer *_display;
    CADisplayLink *_clock;
    FramePair _latest;
    CMTime _lastQueued;
    CFTimeInterval _lastResult,_expectedGap;
    CGAffineTransform _trackTransform;
    CGSize _pixelSize;
    OSType _pixelFormat;
    NSUInteger _generation,_binding,_readyFrames,_consecutiveLate;
    BOOL _interpolation,_resolution,_preferResolution,_unsupported,_orientationReady,_reportedDisplay,_protection;
    std::shared_ptr<std::atomic_bool> _cancellation;
}

- (void)showForPlayerLayer:(AVPlayerLayer *)layer {
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    BOOL interpolation=[prefs boolForKey:@"douglass.experimental.frameInterpolation"];
    BOOL resolution=[prefs boolForKey:@"douglass.experimental.vtSuperResolution"]&&DGVTSuperResolutionAvailable();
    BOOL protection=DGSuperResolutionTransitionProtection();
    AVPlayerItem *item=layer.player.currentItem;
    if(item&&item==_item&&layer==_nativeLayer&&interpolation==_interpolation&&resolution==_resolution&&protection==_protection)return;
    [self stop];
    if(!item||(!interpolation&&!resolution))return;
    _nativeLayer=layer;_item=item;_interpolation=interpolation;_resolution=resolution;_protection=protection;
    NSUInteger binding=++_binding;
    __weak DGVideoEffects *weak=self;
    double delay=protection?protectedSettleDelay:effectsSettleDelay;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        DGVideoEffects *effects=weak;
        if(effects&&effects->_binding==binding)[effects beginSampling];
    });
}

- (void)beginSampling {
    AVPlayerLayer *layer=_nativeLayer;
    AVPlayerItem *item=_item;
    if(!layer||!item||item!=layer.player.currentItem)return;
    if(DGAnimationProcessingDeferred()||!layer.readyForDisplay||layer.player.timeControlStatus!=AVPlayerTimeControlStatusPlaying){
        NSUInteger binding=_binding;
        __weak DGVideoEffects *weak=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            DGVideoEffects *effects=weak;
            if(effects&&effects->_binding==binding)[effects beginSampling];
        });
        return;
    }
    _display=[AVSampleBufferDisplayLayer layer];
    _display.hidden=YES;
    _display.masksToBounds=YES;
    _display.videoGravity=layer.videoGravity;
    [layer addSublayer:_display];
    CMTimebaseRef timebase=nullptr;
    if(CMTimebaseCreateWithSourceClock(kCFAllocatorDefault,CMClockGetHostTimeClock(),&timebase)==noErr){
        CMTimebaseSetTime(timebase,CMClockGetTime(CMClockGetHostTimeClock()));
        CMTimebaseSetRate(timebase,1);
        _display.controlTimebase=timebase;
        CFRelease(timebase);
    }
    _trackTransform=CGAffineTransformIdentity;
    _orientationReady=NO;
    NSUInteger binding=_binding;
    __weak DGVideoEffects *weak=self;
    [item.asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks,NSError *error){
        AVAssetTrack *track=tracks.firstObject;
        void (^loaded)(CGAffineTransform)=^(CGAffineTransform transform){
            dispatch_async(dispatch_get_main_queue(),^{
                DGVideoEffects *effects=weak;
                if(!effects||effects->_binding!=binding||effects->_item!=item)return;
                effects->_trackTransform=transform;effects->_orientationReady=YES;
                [effects layout];
            });
        };
        if(!track){loaded(CGAffineTransformIdentity);return;}
        [track loadValuesAsynchronouslyForKeys:@[@"preferredTransform"] completionHandler:^{
            loaded([track statusOfValueForKey:@"preferredTransform" error:nil]==AVKeyValueStatusLoaded?track.preferredTransform:CGAffineTransformIdentity);
        }];
    }];
    DGVideoEffectsClock *target=[DGVideoEffectsClock new];target.owner=self;
    _clock=[CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];
    _clock.preferredFrameRateRange=CAFrameRateRangeMake(30,60,60);
    [_clock addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    [self layout];
}

- (void)layout {
    if(!_display)return;
    CGRect bounds=_nativeLayer.bounds;
    CGAffineTransform transform=_trackTransform;transform.tx=transform.ty=0;
    CGSize presentation=_item.presentationSize;
    BOOL quarterTurn=std::abs(transform.b)>.5||std::abs(transform.c)>.5;
    if(_item.videoComposition||(quarterTurn&&_pixelSize.width>0&&presentation.width>0&&(_pixelSize.width>_pixelSize.height)==(presentation.width>presentation.height))){
        transform=CGAffineTransformIdentity;quarterTurn=NO;
    }
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _display.bounds=CGRectMake(0,0,quarterTurn?bounds.size.height:bounds.size.width,quarterTurn?bounds.size.width:bounds.size.height);
    _display.position=CGPointMake(CGRectGetMidX(bounds),CGRectGetMidY(bounds));
    _display.affineTransform=transform;
    _display.videoGravity=_nativeLayer.videoGravity;
    [CATransaction commit];
}

- (void)resetFrames {
    ++_generation;
    if(_cancellation)_cancellation->store(true,std::memory_order_relaxed);
    _latest={};_lastQueued=kCMTimeInvalid;_lastResult=0;_expectedGap=0;_readyFrames=0;
    DGReleaseVideoFrameCache(_item);
    _display.hidden=YES;
    [_display.sampleBufferRenderer flushWithRemovalOfDisplayedImage:YES completionHandler:nil];
}
- (void)releaseProcessing {
    if(!_cancellation)return;
    _cancellation->store(true,std::memory_order_relaxed);
    _cancellation.reset();
    dispatch_async(effectsQueue(),^{sharedVideoProcessor().clear();});
}
- (void)suspendForPaging { [self stop]; }
- (void)stop {
    ++_binding;
    [_clock invalidate];_clock=nil;
    [self resetFrames];
    [self releaseProcessing];
    [_display removeFromSuperlayer];
    _display=nil;_item=nil;_nativeLayer=nil;
    _unsupported=NO;_reportedDisplay=NO;_preferResolution=NO;_consecutiveLate=0;
    _pixelSize=CGSizeZero;_pixelFormat=0;
}

- (void)missedFrame {
    ++_consecutiveLate;
    if(!_display.hidden||_readyFrames)[self resetFrames];
    if(_consecutiveLate<3)return;
    if(_interpolation&&_resolution&&!_preferResolution){
        _preferResolution=YES;
        _consecutiveLate=0;
        DGDiagnostic(@"video.vt.bypass",@"effect=interpolation reason=frame_budget");
        return;
    }
    _unsupported=YES;
    _clock.paused=YES;
    [self releaseProcessing];
    DGDiagnostic(@"video.vt.bypass",@"effect=clip reason=frame_budget");
}

- (BOOL)queuePixel:(CVPixelBufferRef)pixel atHostTime:(CMTime)time {
    if(!pixel||!_display.readyForMoreMediaData||
       (CMTIME_IS_VALID(_lastQueued)&&CMTimeCompare(time,_lastQueued)<=0))return NO;
    CMVideoFormatDescriptionRef format=nullptr;
    if(CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault,pixel,&format)!=noErr)return NO;
    CMSampleTimingInfo timing={kCMTimeInvalid,time,kCMTimeInvalid};
    CMSampleBufferRef sample=nullptr;
    OSStatus status=CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,pixel,format,&timing,&sample);
    CFRelease(format);
    if(status!=noErr||!sample)return NO;
    [_display enqueueSampleBuffer:sample];CFRelease(sample);_lastQueued=time;
    return YES;
}

- (void)tick:(CADisplayLink *)link {
        AVPlayer *player=_nativeLayer.player;
        if(!player||player.currentItem!=_item){[self stop];return;}
        if(_unsupported)return;
        if(_lastResult&&CACurrentMediaTime()-_lastResult>std::max(.085,_expectedGap*2.4))[self missedFrame];
        if(_unsupported)return;
        if(!_orientationReady||!_nativeLayer.readyForDisplay||player.timeControlStatus!=AVPlayerTimeControlStatusPlaying||
           player.rate<.75||player.rate>1.25||DGAnimationProcessingDeferred()||
           NSProcessInfo.processInfo.thermalState>=NSProcessInfoThermalStateSerious){
            if(_latest.source||!_display.hidden)[self resetFrames];
            return;
        }
        CMTime actual=kCMTimeInvalid;
        auto pixel=ownPixel(DGCopyVideoFrame(_item,link.targetTimestamp,&actual));
        if(!pixel||!CMTIME_IS_NUMERIC(actual))return;
        if(_latest.source&&CMTimeCompare(actual,_latest.time)==0)return;
        CFTypeRef transfer=CVBufferGetAttachment(pixel.get(),kCVImageBufferTransferFunctionKey,nullptr);
        if(transfer&&(CFEqual(transfer,kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)||CFEqual(transfer,kCVImageBufferTransferFunction_ITU_R_2100_HLG))){
            [self resetFrames];[self releaseProcessing];_unsupported=YES;_clock.paused=YES;return;
        }
        CGSize size=CGSizeMake(CVPixelBufferGetWidth(pixel.get()),CVPixelBufferGetHeight(pixel.get()));
        OSType format=CVPixelBufferGetPixelFormatType(pixel.get());
        if(!CGSizeEqualToSize(size,_pixelSize)||format!=_pixelFormat){
            [self resetFrames];_pixelSize=size;_pixelFormat=format;
            _consecutiveLate=0;
            [self layout];
        }
        const double interval=CMTimeGetSeconds(CMTimeSubtract(actual,_latest.time));
        if(_latest.source&&(!std::isfinite(interval)||interval<=0||interval>.10))[self resetFrames];
        const bool interpolate=_interpolation&&!_preferResolution&&interval>=.025&&interval<=.10;
        const CMTime now=CMClockGetTime(CMClockGetHostTimeClock());
        FramePair pair={pixel,interpolate?_latest.source:PixelBuffer{},now,
                        interpolate?CMTimeSubtract(now,CMTimeMakeWithSeconds(interval,60000)):kCMTimeInvalid};
        _latest={pixel,{},actual,kCMTimeInvalid};
        if(_interpolation&&!_resolution&&!pair.previous)return;
        if(processingFrame.exchange(true,std::memory_order_acq_rel))return;
        ProcessorKey key={static_cast<size_t>(size.width),static_cast<size_t>(size.height),format,
                          _interpolation&&!_preferResolution,DGVTFSystemInterpolationAvailable(),_resolution};
        if(!_cancellation||_cancellation->load(std::memory_order_relaxed))
            _cancellation=std::make_shared<std::atomic_bool>(false);
        auto cancellation=_cancellation;
        NSUInteger generation=_generation;
        CMTime displayTime=CMTimeAdd(now,CMTimeMakeWithSeconds(renderLead,60000));
        __weak DGVideoEffects *weak=self;
        dispatch_async(effectsQueue(),^{@autoreleasepool{
            const bool deferred=DGAnimationProcessingDeferred()||cancellation->load(std::memory_order_relaxed);
            FrameResult result=deferred?FrameResult{}:sharedVideoProcessor().process(key,pair,*cancellation);
            dispatch_async(dispatch_get_main_queue(),^{
                processingFrame.store(false,std::memory_order_release);
                DGVideoEffects *effects=weak;
                if(!effects)return;
                if(deferred||cancellation->load(std::memory_order_relaxed)||effects->_generation!=generation||!effects->_display||DGAnimationProcessingDeferred())return;
                if(!result.supported){
                    [effects resetFrames];[effects releaseProcessing];effects->_unsupported=YES;effects->_clock.paused=YES;
                    return;
                }
                CMTime now=CMClockGetTime(CMClockGetHostTimeClock());
                if(!result.current||CMTimeCompare(displayTime,now)<=0){
                    [effects missedFrame];
                    return;
                }
                BOOL queuedMidpoint=NO;
                if(result.midpoint){
                    CMTime midpoint=CMTimeSubtract(displayTime,CMTimeMakeWithSeconds(interval/2,60000));
                    if(CMTimeCompare(midpoint,now)>0)queuedMidpoint=[effects queuePixel:result.midpoint.get() atHostTime:midpoint];
                }
                if(!result.upscaled&&!queuedMidpoint){
                    if(result.midpoint||!effects->_interpolation||effects->_preferResolution){
                        [effects missedFrame];
                        return;
                    }
                    if(!effects->_readyFrames)return;
                }
                if([effects queuePixel:result.current.get() atHostTime:displayTime]){
                    effects->_lastResult=CACurrentMediaTime();effects->_consecutiveLate=0;
                    effects->_expectedGap=std::isfinite(interval)?interval:1./30;
                    ++effects->_readyFrames;
                    if(effects->_readyFrames>=minimumReadyFrames&&effects->_display.readyForDisplay){
                        effects->_display.hidden=NO;
                        if(!effects->_reportedDisplay){
                            effects->_reportedDisplay=YES;
                            DGDiagnostic(@"video.vt.display",[NSString stringWithFormat:@"midpoint=%d compatibility=%d width=%zu",queuedMidpoint,result.compatibility,CVPixelBufferGetWidth(result.current.get())]);
                        }
                    }
                }else [effects missedFrame];
            });
        }});
}
- (void)dealloc{[self stop];}
@end
