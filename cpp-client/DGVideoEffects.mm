#import "DGVideoEffects.h"
#import "DGAnimation.h"
#import "DGDiagnostics.h"
#import <VideoToolbox/VideoToolbox.h>
#include <algorithm>
#include <cmath>
#include <memory>

BOOL DGVTFInterpolationAvailable(void) {
    if(@available(iOS 26.0,*))return [VTLowLatencyFrameInterpolationConfiguration isSupported];
    return NO;
}
BOOL DGVTSuperResolutionAvailable(void) {
    if(@available(iOS 26.0,*))return [VTLowLatencySuperResolutionScalerConfiguration isSupported];
    return NO;
}

namespace {
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
        if(interpolation_){
            auto *config=[[VTLowLatencyFrameInterpolationConfiguration alloc] initWithFrameWidth:width frameHeight:height numberOfInterpolatedFrames:1];
            if([config.frameSupportedPixelFormats containsObject:@(format)]){
                auto *session=[VTFrameProcessor new];
                if([session startSessionWithConfiguration:config error:nil]){
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
                    if([session startSessionWithConfiguration:config error:nil]){
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
}

@class DGVideoEffects;
@interface DGVideoEffectsClock : NSObject
@property(nonatomic,weak) DGVideoEffects *owner;
- (void)tick:(CADisplayLink *)link;
@end
@interface DGVideoEffects ()
- (void)tick:(CADisplayLink *)link;
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
    dispatch_queue_t _processing;
    std::shared_ptr<VideoProcessor> _processor;
    FramePair _latest;
    CMTime _lastQueued;
    CFTimeInterval _lastResult;
    CGAffineTransform _trackTransform;
    CGSize _pixelSize;
    OSType _pixelFormat;
    NSUInteger _generation,_consecutiveLate;
    BOOL _interpolation,_resolution,_busy,_unsupported,_orientationReady;
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
    if(!_processing)_processing=dispatch_queue_create("io.douglass.video.effects",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0));
    _output=[[AVPlayerItemVideoOutput alloc]initWithPixelBufferAttributes:@{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey:@{}}];
    [item addOutput:_output];
    _display=[AVSampleBufferDisplayLayer layer];
    _display.hidden=YES;
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
    __weak DGVideoEffects *weak=self;
    [item.asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks,NSError *error){
        AVAssetTrack *track=tracks.firstObject;
        void (^loaded)(CGAffineTransform)=^(CGAffineTransform transform){
            dispatch_async(dispatch_get_main_queue(),^{
                DGVideoEffects *effects=weak;
                if(!effects||effects->_item!=item)return;
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
    DGApplyDisplayLinkRate(_clock,nil);
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
    _latest={};_lastQueued=kCMTimeInvalid;_lastResult=0;_consecutiveLate=0;
    [_display flushAndRemoveImage];_display.hidden=YES;
}
- (void)stop {
    [_clock invalidate];_clock=nil;
    if(_output&&_item)[_item removeOutput:_output];
    [self resetFrames];
    [_display removeFromSuperlayer];_display=nil;_output=nil;_item=nil;_nativeLayer=nil;
    _unsupported=NO;_pixelSize=CGSizeZero;_pixelFormat=0;
    auto previous=std::move(_processor);
    if(previous)dispatch_async(_processing,^{(void)previous;});
}

- (BOOL)queuePixel:(CVPixelBufferRef)pixel atHostTime:(CMTime)time {
    if(!pixel||!_display.readyForMoreMediaData||CMTIME_IS_VALID(_lastQueued)&&CMTimeCompare(time,_lastQueued)<=0)return NO;
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
        if(_lastResult&&CACurrentMediaTime()-_lastResult>.18)[self resetFrames];
        if(!_orientationReady||!_nativeLayer.readyForDisplay||player.timeControlStatus!=AVPlayerTimeControlStatusPlaying||
           player.rate<.75||player.rate>1.25||DGAnimationProcessingDeferred()||
           NSProcessInfo.processInfo.thermalState>=NSProcessInfoThermalStateSerious){
            if(_latest.source||!_display.hidden)[self resetFrames];
            return;
        }
        if(_busy)return;
        CMTime mediaTime=[_output itemTimeForHostTime:link.targetTimestamp];
        if(![_output hasNewPixelBufferForItemTime:mediaTime])return;
        CMTime actual=kCMTimeInvalid;
        auto pixel=ownPixel([_output copyPixelBufferForItemTime:mediaTime itemTimeForDisplay:&actual]);
        if(!pixel||!CMTIME_IS_NUMERIC(actual))return;
        CFTypeRef transfer=CVBufferGetAttachment(pixel.get(),kCVImageBufferTransferFunctionKey,nullptr);
        if(transfer&&(CFEqual(transfer,kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)||CFEqual(transfer,kCVImageBufferTransferFunction_ITU_R_2100_HLG))){
            [self resetFrames];_unsupported=YES;return;
        }
        CGSize size=CGSizeMake(CVPixelBufferGetWidth(pixel.get()),CVPixelBufferGetHeight(pixel.get()));
        OSType format=CVPixelBufferGetPixelFormatType(pixel.get());
        if(!CGSizeEqualToSize(size,_pixelSize)||format!=_pixelFormat){
            [self resetFrames];_pixelSize=size;_pixelFormat=format;
            auto previous=std::move(_processor);
            if(previous)dispatch_async(_processing,^{(void)previous;});
            [self layout];
        }
        const double interval=CMTimeGetSeconds(CMTimeSubtract(actual,_latest.time));
        if(_latest.source&&(!std::isfinite(interval)||interval<=0||interval>.10))[self resetFrames];
        FramePair pair={pixel,interval>=.025&&interval<=.10?_latest.source:PixelBuffer{},actual,_latest.time};
        _latest={pixel,{},actual,kCMTimeInvalid};
        if(!_processor)_processor=std::make_shared<VideoProcessor>(_interpolation,_resolution);
        auto processor=_processor;
        _busy=YES;
        NSUInteger generation=_generation;
        CMTime displayTime=CMTimeAdd(CMClockGetTime(CMClockGetHostTimeClock()),CMTimeMakeWithSeconds(.050,60000));
        __weak DGVideoEffects *weak=self;
        dispatch_async(_processing,^{@autoreleasepool{
            FrameResult result=processor->process(pair);
            dispatch_async(dispatch_get_main_queue(),^{
                DGVideoEffects *effects=weak;
                if(!effects)return;
                effects->_busy=NO;
                if(effects->_generation!=generation||!effects->_display)return;
                if(!result.supported){[effects resetFrames];effects->_unsupported=YES;return;}
                CMTime now=CMClockGetTime(CMClockGetHostTimeClock());
                if(!result.current||CMTimeCompare(displayTime,now)<=0){
                    if(++effects->_consecutiveLate>=3||effects->_display.status==AVQueuedSampleBufferRenderingStatusFailed)[effects resetFrames];
                    return;
                }
                if(result.midpoint){
                    CMTime midpoint=CMTimeSubtract(displayTime,CMTimeMakeWithSeconds(interval/2,60000));
                    if(CMTimeCompare(midpoint,now)>0)[effects queuePixel:result.midpoint.get() atHostTime:midpoint];
                }
                if([effects queuePixel:result.current.get() atHostTime:displayTime]){
                    effects->_lastResult=CACurrentMediaTime();effects->_consecutiveLate=0;
                    if(effects->_display.readyForDisplay)effects->_display.hidden=NO;
                }
            });
        }});
    }
}
- (void)dealloc{[self stop];}
@end
