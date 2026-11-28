#import "DGVideoEffects.h"
#import "DGAnimation.h"
#import "DGDiagnostics.h"
#import <VideoToolbox/VideoToolbox.h>
#include <sys/sysctl.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <memory>
#include <type_traits>

NSString *DGVTFInterpolationUnavailableReason(void) {
    if(@available(iOS 26.0,*)){
        static NSString *reason;
        static dispatch_once_t once;
        dispatch_once(&once,^{
            char machine[64]={};
            size_t length=sizeof(machine);
            NSOperatingSystemVersion version=NSProcessInfo.processInfo.operatingSystemVersion;
            BOOL affected=version.majorVersion==27&&version.minorVersion==0&&version.patchVersion==1&&
                sysctlbyname("hw.machine",machine,&length,nullptr,0)==0&&std::strcmp(machine,"iPhone16,2")==0;
            if(affected)reason=@"此机型的 iOS 27.0.1 插帧会话会闪退，暂用原帧率";
            else if(![VTLowLatencyFrameInterpolationConfiguration isSupported])reason=@"当前设备不支持低延迟插帧";
        });
        return reason;
    }
    return @"低延迟插帧需要 iOS 26 或更新版本";
}
BOOL DGVTFInterpolationAvailable(void) {
    return DGVTFInterpolationUnavailableReason()==nil;
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
constexpr double effectsSettleDelay=.45;
constexpr double renderLead=.055;
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

struct FramePair {
    PixelBuffer source,previous;
    CMTime time=kCMTimeInvalid,previousTime=kCMTimeInvalid;
};
struct FrameResult {
    PixelBuffer current,midpoint;
    bool supported=false;
};

struct ProcessorKey {
    size_t width=0,height=0;
    OSType format=0;
    bool interpolation=false,resolution=false;
    bool operator==(const ProcessorKey &) const=default;
};

class API_AVAILABLE(ios(26.0)) VideoProcessor {
public:
    VideoProcessor(bool interpolation,bool resolution):interpolation_(interpolation),resolution_(resolution){}
    ~VideoProcessor(){
        [interpolationSession_ endSession];
        [resolutionSession_ endSession];
        if(interpolationPool_)CVPixelBufferPoolRelease(interpolationPool_);
        if(resolutionPool_)CVPixelBufferPoolRelease(resolutionPool_);
    }
    FrameResult process(const FramePair &pair) {
        if(!configured_)configure(pair.source.get());
        FrameResult frames;
        frames.supported=interpolationSession_||resolutionSession_;
        if(!frames.supported)return frames;
        VTFrameProcessorFrame *source=[[VTFrameProcessorFrame alloc] initWithBuffer:pair.source.get() presentationTimeStamp:pair.time];
        if(!source)return frames;
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
        if(resolutionSession_){
            auto upscaled=allocate(resolutionPool_,pair.source.get());
            VTFrameProcessorFrame *destination=upscaled?[[VTFrameProcessorFrame alloc] initWithBuffer:upscaled.get() presentationTimeStamp:pair.time]:nil;
            if(destination){
                auto *parameters=[[VTLowLatencySuperResolutionScalerParameters alloc] initWithSourceFrame:source destinationFrame:destination];
                if(parameters&&[resolutionSession_ processWithParameters:parameters error:nil])frames.current=std::move(upscaled);
            }
        }
        if(!frames.current&&frames.midpoint)frames.current=pair.source;
        return frames;
    }
private:
    void configure(CVPixelBufferRef source) {
        configured_=true;
        size_t width=CVPixelBufferGetWidth(source),height=CVPixelBufferGetHeight(source);
        OSType format=CVPixelBufferGetPixelFormatType(source);
        if(interpolation_&&supportsInterpolationSize(width,height)){
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
        if(resolution_){
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
    bool interpolation_,resolution_,configured_=false;
    VTFrameProcessor *__strong interpolationSession_=nil,*__strong resolutionSession_=nil;
    CVPixelBufferPoolRef interpolationPool_=nullptr,resolutionPool_=nullptr;
};

// All cells use this one worker. End incompatible sessions before creating
// replacements, and keep matching sessions warm across adjacent works.
class API_AVAILABLE(ios(26.0)) SharedVideoProcessor {
public:
    FrameResult process(const ProcessorKey &key,const FramePair &pair) {
        if(!processor_||key_!=key){
            processor_.reset();
            key_=key;
            processor_=std::make_unique<VideoProcessor>(key.interpolation,key.resolution);
        }
        return processor_->process(pair);
    }
    void clear(){processor_.reset();}
private:
    ProcessorKey key_;
    std::unique_ptr<VideoProcessor> processor_;
};

SharedVideoProcessor &sharedVideoProcessor() API_AVAILABLE(ios(26.0));
SharedVideoProcessor &sharedVideoProcessor(){
    static SharedVideoProcessor processor;
    return processor;
}

std::atomic_bool processingFrame{false};
// Main thread only.
NSUInteger processingLease=0;
}

@class DGVideoEffects;
@interface DGVideoEffectsClock : NSObject
@property(nonatomic,weak) DGVideoEffects *owner;
- (void)tick:(CADisplayLink *)link;
@end
@interface DGVideoEffects ()
- (void)tick:(CADisplayLink *)link;
- (void)stopDeferringOutputRemoval:(BOOL)defer;
@end
@implementation DGVideoEffectsClock
- (void)tick:(CADisplayLink *)link{DGVideoEffects *owner=self.owner;if(owner)[owner tick:link];else [link invalidate];}
@end

@implementation DGVideoEffects {
    __weak AVPlayerLayer *_nativeLayer;
    __weak AVPlayerItem *_item;
    AVPlayerItemVideoOutput *_output;
    AVSampleBufferDisplayLayer *_display;
    CADisplayLink *_clock;
    FramePair _latest;
    CMTime _lastQueued;
    CFTimeInterval _lastResult,_expectedGap;
    CGAffineTransform _trackTransform;
    CGSize _pixelSize;
    OSType _pixelFormat;
    NSUInteger _generation,_binding,_readyFrames,_consecutiveLate;
    BOOL _interpolation,_resolution,_preferResolution,_unsupported,_orientationReady,_reportedDisplay;
}

- (void)showForPlayerLayer:(AVPlayerLayer *)layer {
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    BOOL interpolation=[prefs boolForKey:@"douglass.experimental.frameInterpolation"]&&DGVTFInterpolationAvailable();
    BOOL resolution=[prefs boolForKey:@"douglass.experimental.vtSuperResolution"]&&DGVTSuperResolutionAvailable();
    AVPlayerItem *item=layer.player.currentItem;
    if(item&&item==_item&&layer==_nativeLayer&&interpolation==_interpolation&&resolution==_resolution)return;
    [self stop];
    if(!item||(!interpolation&&!resolution))return;
    _nativeLayer=layer;_item=item;_interpolation=interpolation;_resolution=resolution;
    NSUInteger binding=++_binding;
    __weak DGVideoEffects *weak=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(effectsSettleDelay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
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
    _output=[[AVPlayerItemVideoOutput alloc]initWithPixelBufferAttributes:@{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey:@{}}];
    [item addOutput:_output];
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
    _latest={};_lastQueued=kCMTimeInvalid;_lastResult=0;_expectedGap=0;_readyFrames=0;
    [_display flushAndRemoveImage];_display.hidden=YES;
}
- (void)stop { [self stopDeferringOutputRemoval:NO]; }
- (void)suspendForPaging { [self stopDeferringOutputRemoval:YES]; }
- (void)stopDeferringOutputRemoval:(BOOL)defer {
    BOOL wasSampling=_output!=nil;++_binding;
    [_clock invalidate];_clock=nil;
    AVPlayerItem *item=_item;
    AVPlayerItemVideoOutput *output=_output;
    AVSampleBufferDisplayLayer *display=_display;
    if(defer&&output){
        // Let the native player take over immediately. Renderer flushing and
        // output detachment can wait until the current swipe is underway.
        ++_generation;
        _latest={};_lastResult=0;_readyFrames=0;_lastQueued=kCMTimeInvalid;
        [CATransaction begin];[CATransaction setDisableActions:YES];
        display.hidden=YES;[display removeFromSuperlayer];[CATransaction commit];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
            [item removeOutput:output];
            [display flushAndRemoveImage];
        });
    }else{
        if(output&&item)[item removeOutput:output];
        [self resetFrames];
        [display removeFromSuperlayer];
    }
    _display=nil;_output=nil;_item=nil;_nativeLayer=nil;
    _unsupported=NO;_reportedDisplay=NO;_preferResolution=NO;_consecutiveLate=0;
    _pixelSize=CGSizeZero;_pixelFormat=0;
    if(wasSampling){
        NSUInteger lease=processingLease;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if(processingLease==lease){
                if(@available(iOS 26.0,*))dispatch_async(effectsQueue(),^{sharedVideoProcessor().clear();});
            }
        });
    }
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
    if(@available(iOS 26.0,*)){
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
        CMTime mediaTime=[_output itemTimeForHostTime:link.targetTimestamp];
        if(![_output hasNewPixelBufferForItemTime:mediaTime])return;
        CMTime actual=kCMTimeInvalid;
        auto pixel=ownPixel([_output copyPixelBufferForItemTime:mediaTime itemTimeForDisplay:&actual]);
        if(!pixel||!CMTIME_IS_NUMERIC(actual))return;
        CFTypeRef transfer=CVBufferGetAttachment(pixel.get(),kCVImageBufferTransferFunctionKey,nullptr);
        if(transfer&&(CFEqual(transfer,kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)||CFEqual(transfer,kCVImageBufferTransferFunction_ITU_R_2100_HLG))){
            [self resetFrames];_unsupported=YES;_clock.paused=YES;return;
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
                          _interpolation&&!_preferResolution,_resolution};
        ++processingLease;
        NSUInteger generation=_generation;
        CMTime displayTime=CMTimeAdd(now,CMTimeMakeWithSeconds(renderLead,60000));
        __weak DGVideoEffects *weak=self;
        dispatch_async(effectsQueue(),^{@autoreleasepool{
            const bool deferred=DGAnimationProcessingDeferred();
            FrameResult result=deferred?FrameResult{}:sharedVideoProcessor().process(key,pair);
            dispatch_async(dispatch_get_main_queue(),^{
                processingFrame.store(false,std::memory_order_release);
                DGVideoEffects *effects=weak;
                if(!effects)return;
                if(deferred||effects->_generation!=generation||!effects->_display||DGAnimationProcessingDeferred())return;
                if(!result.supported){
                    [effects resetFrames];effects->_unsupported=YES;effects->_clock.paused=YES;
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
                if(!effects->_resolution&&!queuedMidpoint){[effects missedFrame];return;}
                if([effects queuePixel:result.current.get() atHostTime:displayTime]){
                    effects->_lastResult=CACurrentMediaTime();effects->_consecutiveLate=0;
                    effects->_expectedGap=std::isfinite(interval)?interval:1./30;
                    ++effects->_readyFrames;
                    if(effects->_readyFrames>=minimumReadyFrames&&effects->_display.readyForDisplay){
                        effects->_display.hidden=NO;
                        if(!effects->_reportedDisplay){
                            effects->_reportedDisplay=YES;
                            DGDiagnostic(@"video.vt.display",[NSString stringWithFormat:@"midpoint=%d width=%zu",queuedMidpoint,CVPixelBufferGetWidth(result.current.get())]);
                        }
                    }
                }else [effects missedFrame];
            });
        }});
    }
}
- (void)dealloc{[self stop];}
@end
