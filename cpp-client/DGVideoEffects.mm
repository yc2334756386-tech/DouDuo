#import "DGVideoEffects.h"
#import "DGAnimation.h"
#import "DGDiagnostics.h"
#import "DGRife.h"
#import "DGMediaEnhancement.h"
#include "InterpolationProtection.hpp"
#import <VideoToolbox/VideoToolbox.h>
#import <objc/runtime.h>
#include <arm_neon.h>
#include <sys/sysctl.h>
#include <algorithm>
#include <array>
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
NSString *const DGInterpolationProtectionKey=@"douglass.experimental.interpolationProtection";
BOOL DGInterpolationTransitionProtection(void) {
    NSNumber *saved=[NSUserDefaults.standardUserDefaults objectForKey:DGInterpolationProtectionKey];
    return !saved||saved.boolValue;
}
NSString *const DGInterpolationMultiplierKey=@"douglass.experimental.interpolationMultiplier";
unsigned DGInterpolationMultiplier(void) {
    NSInteger value=[NSUserDefaults.standardUserDefaults integerForKey:DGInterpolationMultiplierKey];
    return value>=2&&value<=4?static_cast<unsigned>(value):2;
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
constexpr double renderLead=.048;
constexpr unsigned minimumReadyFrames=3;
constexpr double interpolationHeadroom=.004;
constexpr double fourTimesBackoff=1.5;
constexpr std::array<double,3> phases{.25,.5,.75};
constexpr std::array<double,3> thirdPhases{1./3,.5,2./3};

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

bool sampleForInterpolation(CVPixelBufferRef pixel,douglass::InterpolationSample &sample) {
    if(!pixel||CVPixelBufferGetPlaneCount(pixel)!=2)return false;
    const auto format=CVPixelBufferGetPixelFormatType(pixel);
    if(format!=kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange&&
       format!=kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)return false;
    const auto width=CVPixelBufferGetWidthOfPlane(pixel,0);
    const auto height=CVPixelBufferGetHeightOfPlane(pixel,0);
    const auto yStride=CVPixelBufferGetBytesPerRowOfPlane(pixel,0);
    const auto uvStride=CVPixelBufferGetBytesPerRowOfPlane(pixel,1);
    if(width<2||height<2||yStride<width||uvStride<width/2*2||
       CVPixelBufferGetWidthOfPlane(pixel,1)<width/2||CVPixelBufferGetHeightOfPlane(pixel,1)<height/2)return false;
    LockedPixel read(pixel,kCVPixelBufferLock_ReadOnly);
    if(!read)return false;
    const auto *y=static_cast<const uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(pixel,0));
    const auto *uv=static_cast<const uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(pixel,1));
    if(!y||!uv)return false;
    sample=douglass::sampleInterpolationFrame(y,yStride,uv,uvStride,width,height);
    return true;
}

using InsertedFrames=std::array<PixelBuffer,3>;

uint8x16_t blendQuarter(uint8x16_t nearFrame,uint8x16_t farFrame) {
    const auto weight=vdup_n_u8(3);
    auto low=vaddw_u8(vmull_u8(vget_low_u8(nearFrame),weight),vget_low_u8(farFrame));
    auto high=vaddw_u8(vmull_u8(vget_high_u8(nearFrame),weight),vget_high_u8(farFrame));
    return vcombine_u8(vrshrn_n_u16(low,2),vrshrn_n_u16(high,2));
}

uint8x16_t blendThird(uint8x16_t nearFrame,uint8x16_t farFrame) {
    auto low=vaddw_u8(vshll_n_u8(vget_low_u8(nearFrame),1),vget_low_u8(farFrame));
    auto high=vaddw_u8(vshll_n_u8(vget_high_u8(nearFrame),1),vget_high_u8(farFrame));
    return vcombine_u8(vmovn_u16(vreinterpretq_u16_s16(vqrdmulhq_n_s16(vreinterpretq_s16_u16(low),10923))),
                       vmovn_u16(vreinterpretq_u16_s16(vqrdmulhq_n_s16(vreinterpretq_s16_u16(high),10923))));
}

// Compatibility interpolation avoids starting the affected system session.
InsertedFrames blendFrames(CVPixelBufferPoolRef pool,CVPixelBufferRef previous,CVPixelBufferRef current,
                           bool checkCut,unsigned multiplier,double extraDeadline,const std::atomic_bool &cancelled) {
    if(!previous||!current||CVPixelBufferGetPlaneCount(previous)!=2||CVPixelBufferGetPlaneCount(current)!=2)return {};
    if(CVPixelBufferGetWidth(previous)!=CVPixelBufferGetWidth(current)||CVPixelBufferGetHeight(previous)!=CVPixelBufferGetHeight(current))return {};
    LockedPixel readPrevious(previous,kCVPixelBufferLock_ReadOnly),readCurrent(current,kCVPixelBufferLock_ReadOnly);
    if(!readPrevious||!readCurrent||cancelled.load(std::memory_order_relaxed))return {};
    if(checkCut){
        auto *first=static_cast<const uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(previous,0));
        auto *second=static_cast<const uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(current,0));
        if(!first||!second)return {};
        const size_t width=CVPixelBufferGetWidth(current),height=CVPixelBufferGetHeight(current);
        const auto stride0=CVPixelBufferGetBytesPerRowOfPlane(previous,0);
        const auto stride1=CVPixelBufferGetBytesPerRowOfPlane(current,0);
        size_t sum=0,count=0;
        for(size_t y=0;y<height;y+=24)for(size_t x=0;x<width;x+=24){
            sum+=std::abs(int(first[y*stride0+x])-int(second[y*stride1+x]));++count;
        }
        if(count&&sum>count*45)return {};
    }
    InsertedFrames output;
    output[1]=allocate(pool,current);
    LockedPixel write(output[1].get(),0);
    if(!write)return {};
    if(extraDeadline>CACurrentMediaTime()){
        output[0]=allocate(pool,current);
        output[2]=allocate(pool,current);
    }
    LockedPixel writeQuarter(output[0].get(),0),writeThreeQuarters(output[2].get(),0);
    bool extra=writeQuarter&&writeThreeQuarters;
    const bool thirds=multiplier==3;
    for(size_t plane=0;plane<2;++plane){
        const auto *a=static_cast<const uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(previous,plane));
        const auto *b=static_cast<const uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(current,plane));
        auto *out=static_cast<uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(output[1].get(),plane));
        const size_t bytes=CVPixelBufferGetWidthOfPlane(current,plane)*(plane?2:1);
        const size_t aStride=CVPixelBufferGetBytesPerRowOfPlane(previous,plane);
        const size_t bStride=CVPixelBufferGetBytesPerRowOfPlane(current,plane);
        const size_t outStride=CVPixelBufferGetBytesPerRowOfPlane(output[1].get(),plane);
        if(!a||!b||!out||std::min({aStride,bStride,outStride})<bytes)return {};
        auto *quarter=extra?static_cast<uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(output[0].get(),plane)):nullptr;
        auto *threeQuarters=extra?static_cast<uint8_t *>(CVPixelBufferGetBaseAddressOfPlane(output[2].get(),plane)):nullptr;
        const size_t quarterStride=extra?CVPixelBufferGetBytesPerRowOfPlane(output[0].get(),plane):0;
        const size_t threeQuarterStride=extra?CVPixelBufferGetBytesPerRowOfPlane(output[2].get(),plane):0;
        extra=extra&&quarter&&threeQuarters&&std::min(quarterStride,threeQuarterStride)>=bytes;
        for(size_t y=0;y<CVPixelBufferGetHeightOfPlane(current,plane);++y){
            if((y&31)==0){
                if(cancelled.load(std::memory_order_relaxed))return {};
                if(extra&&CACurrentMediaTime()>=extraDeadline)extra=false;
            }
            size_t x=0;
            for(;x+16<=bytes;x+=16){
                const auto first=vld1q_u8(a+x),second=vld1q_u8(b+x);
                vst1q_u8(out+x,vrhaddq_u8(first,second));
                if(extra){
                    vst1q_u8(quarter+y*quarterStride+x,thirds?blendThird(first,second):blendQuarter(first,second));
                    vst1q_u8(threeQuarters+y*threeQuarterStride+x,thirds?blendThird(second,first):blendQuarter(second,first));
                }
            }
            for(;x<bytes;++x){
                out[x]=(unsigned(a[x])+unsigned(b[x])+1)/2;
                if(extra){
                    const unsigned nearWeight=thirds?2:3;
                    const unsigned round=thirds?1:2;
                    quarter[y*quarterStride+x]=(nearWeight*a[x]+b[x]+round)/(nearWeight+1);
                    threeQuarters[y*threeQuarterStride+x]=(a[x]+nearWeight*b[x]+round)/(nearWeight+1);
                }
            }
            a+=aStride;b+=bStride;out+=outStride;
        }
    }
    if(!extra){
        // The locks must be destroyed before returning their buffers to the pool.
        return InsertedFrames{PixelBuffer{},output[1],PixelBuffer{}};
    }
    return output;
}

struct FramePair {
    PixelBuffer source,previous;
    CMTime time=kCMTimeInvalid,previousTime=kCMTimeInvalid;
    bool allowsHigherRate=false;
};
struct FrameResult {
    PixelBuffer current;
    InsertedFrames inserted;
    bool supported=false,compatibility=false,upscaled=false,rife=false;
    bool thirds=false;
    douglass::InterpolationHazard interpolationHazard=douglass::InterpolationHazard::none;
};

struct ProcessorKey {
    size_t width=0,height=0;
    OSType format=0;
    bool interpolation=false,systemInterpolation=false,resolution=false;
    bool rife=false,protectInterpolation=false;
    unsigned multiplier=2;
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
    FrameResult process(FramePair pair,uint64_t frameGeneration,double midpointDeadline,double quarterDeadline,
                        const std::atomic_bool &cancelled) {
        if(cancelled.load(std::memory_order_relaxed))return {};
        FrameResult frames;
        const bool wasProtected=transitionGuard_.protecting(frameGeneration);
        if(key_.protectInterpolation){
            if(pair.previous){
                douglass::InterpolationSample previous,current;
                const bool havePrevious=sampleForInterpolation(pair.previous.get(),previous);
                const bool haveCurrent=sampleForInterpolation(pair.source.get(),current);
                const double interval=CMTimeGetSeconds(CMTimeSubtract(pair.time,pair.previousTime));
                frames.interpolationHazard=transitionGuard_.assess(frameGeneration,havePrevious?&previous:nullptr,
                                                                  haveCurrent?&current:nullptr,interval);
            }else if(wasProtected){
                frames.interpolationHazard=douglass::InterpolationHazard::unstable;
            }
        }
        const bool protectedFrame=frames.interpolationHazard!=douglass::InterpolationHazard::none;
        if(protectedFrame){
            // Return immediately on entry so the main thread can drop queued
            // midpoints before doing any further enhancement work.
            if(!wasProtected||!key_.resolution){
                frames.supported=true;
                return frames;
            }
            pair.previous.reset();
        }
        if(cancelled.load(std::memory_order_relaxed))return {};
        if(!interpolationConfigured_&&pair.previous&&key_.interpolation){
            interpolationConfigured_=true;
            if(@available(iOS 26.0,*))configureInterpolation();
            if(std::max(key_.width,key_.height)<=2560&&key_.width*key_.height<=1920*1080)
                blendPool_=makePool(@{},key_.width,key_.height,key_.format);
        }
        if(!resolutionConfigured_&&key_.resolution&&!cancelled.load(std::memory_order_relaxed)){
            resolutionConfigured_=true;
            if(@available(iOS 26.0,*))configureResolution();
        }
        const auto started=CACurrentMediaTime();
        const bool requestHigher=pair.previous&&pair.allowsHigherRate&&started>=fourTimesBackoffUntil_;
        const double extraDeadline=requestHigher?quarterDeadline:0.;
        if(key_.rife&&pair.previous){
            if(!rife_)rife_=std::make_unique<DGRife>();
            const auto pixels=rife_->copyInterpolatedFrames(pair.previous.get(),pair.source.get(),midpointDeadline,extraDeadline,key_.multiplier,cancelled);
            for(size_t i=0;i<pixels.size();++i)if(pixels[i])frames.inserted[i]=ownPixel(pixels[i]);
            frames.rife=frames.inserted[1]||frames.inserted[0];
        }
        frames.supported=protectedFrame||interpolationSession_||resolutionSession_||blendPool_||
                         (key_.rife&&(!rife_||!rife_->rejected()))||
                         (key_.interpolation&&!interpolationConfigured_);
        if(cancelled.load(std::memory_order_relaxed)||!frames.supported)return frames;
        if(@available(iOS 26.0,*))processSystem(pair,midpointDeadline,extraDeadline,cancelled,frames);
        if(!frames.inserted[1]&&!frames.inserted[0]&&pair.previous&&blendPool_){
            frames.inserted=blendFrames(blendPool_,pair.previous.get(),pair.source.get(),!key_.protectInterpolation,key_.multiplier,extraDeadline,cancelled);
            frames.compatibility=bool(frames.inserted[1]);
        }
        if(requestHigher&&(!frames.inserted[0]||!frames.inserted[2]||CACurrentMediaTime()>=quarterDeadline)){
            frames.inserted[0].reset();
            frames.inserted[2].reset();
            fourTimesBackoffUntil_=CACurrentMediaTime()+fourTimesBackoff;
        }
        frames.thirds=key_.multiplier==3&&frames.inserted[0]&&frames.inserted[2];
        if(!frames.current)frames.current=pair.source;
        return frames;
    }
private:
    InsertedFrames interpolateSystem(const FramePair &pair,VTFrameProcessorFrame *source,bool four) API_AVAILABLE(ios(26.0)) {
        VTFrameProcessorFrame *previous=[[VTFrameProcessorFrame alloc] initWithBuffer:pair.previous.get() presentationTimeStamp:pair.previousTime];
        if(!previous)return {};
        NSMutableArray<NSNumber *> *phaseValues=[NSMutableArray arrayWithCapacity:four?3:1];
        NSMutableArray<VTFrameProcessorFrame *> *destinations=[NSMutableArray arrayWithCapacity:four?3:1];
        InsertedFrames inserted;
        const CMTime gap=CMTimeSubtract(pair.time,pair.previousTime);
        for(size_t index=four?0:1,end=four?3:2;index<end;++index){
            const double phase=phases[index];
            inserted[index]=allocate(interpolationPool_,pair.source.get());
            if(!inserted[index])return {};
            const CMTime pts=CMTimeAdd(pair.previousTime,CMTimeMultiplyByFloat64(gap,phase));
            auto *destination=[[VTFrameProcessorFrame alloc] initWithBuffer:inserted[index].get() presentationTimeStamp:pts];
            if(!destination)return {};
            [phaseValues addObject:@(phase)];
            [destinations addObject:destination];
        }
        auto *parameters=[[VTLowLatencyFrameInterpolationParameters alloc] initWithSourceFrame:source previousFrame:previous interpolationPhase:phaseValues destinationFrames:destinations];
        if(!parameters||![interpolationSession_ processWithParameters:parameters error:nil])return {};
        return inserted;
    }
    void processSystem(const FramePair &pair,double midpointDeadline,double quarterDeadline,
                       const std::atomic_bool &cancelled,FrameResult &frames) API_AVAILABLE(ios(26.0)) {
        if(!interpolationSession_&&!resolutionSession_)return;
        VTFrameProcessorFrame *source=[[VTFrameProcessorFrame alloc] initWithBuffer:pair.source.get() presentationTimeStamp:pair.time];
        if(!source)return;
        // VideoToolbox's published phases are dyadic. The compatibility path produces exact thirds.
        if(interpolationSession_&&pair.previous&&!(key_.multiplier==3&&blendPool_&&quarterDeadline>CACurrentMediaTime())){
            if(systemPhases_==2&&quarterDeadline>CACurrentMediaTime()){
                frames.inserted=interpolateSystem(pair,source,true);
            }
            if(!frames.inserted[1]&&midpointDeadline>CACurrentMediaTime()&&!cancelled.load(std::memory_order_relaxed))
                frames.inserted=interpolateSystem(pair,source,false);
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
    bool configureInterpolationSession(NSInteger level,NSString *kind) API_AVAILABLE(ios(26.0)) {
        const auto width=key_.width,height=key_.height;
        const auto format=key_.format;
        auto *config=[[VTLowLatencyFrameInterpolationConfiguration alloc] initWithFrameWidth:width frameHeight:height numberOfInterpolatedFrames:level];
        if(![config.frameSupportedPixelFormats containsObject:@(format)])return false;
        auto *session=[VTFrameProcessor new];
        if(!startEffectSession(session,config,kind))return false;
        interpolationPool_=makePool(config.destinationPixelBufferAttributes,width,height,format);
        if(!interpolationPool_){
            [session endSession];
            return false;
        }
        interpolationSession_=session;
        systemPhases_=level;
        return true;
    }
    void configureInterpolation() API_AVAILABLE(ios(26.0)) {
        const auto width=key_.width,height=key_.height;
        if(key_.systemInterpolation&&supportsInterpolationSize(width,height)){
            if(key_.multiplier!=4||!configureInterpolationSession(2,@"interpolation-4x"))
                configureInterpolationSession(1,@"interpolation");
        }
        DGDiagnostic(@"video.vt.configured",[NSString stringWithFormat:@"width=%zu height=%zu interpolation=%d interpolation_multiplier=%ld",width,height,interpolationSession_!=nil,systemPhases_==2?4L:2L]);
    }
    void configureResolution() API_AVAILABLE(ios(26.0)) {
        const auto width=key_.width,height=key_.height;
        const auto format=key_.format;
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
        DGDiagnostic(@"video.vt.configured",[NSString stringWithFormat:@"width=%zu height=%zu scale=%.2f",width,height,resolutionSession_?factorForLog(width):1.]);
    }
    double factorForLog(size_t width) const {
        auto attributes=(__bridge NSDictionary *)CVPixelBufferPoolGetPixelBufferAttributes(resolutionPool_);
        return [attributes[(__bridge NSString *)kCVPixelBufferWidthKey] doubleValue]/width;
    }
    ProcessorKey key_;
    bool interpolationConfigured_=false,resolutionConfigured_=false;
    NSInteger systemPhases_=0;
    double fourTimesBackoffUntil_=0;
    douglass::InterpolationProtection transitionGuard_;
    VTFrameProcessor *__strong interpolationSession_=nil,*__strong resolutionSession_=nil;
    CVPixelBufferPoolRef interpolationPool_=nullptr,resolutionPool_=nullptr,blendPool_=nullptr;
    std::unique_ptr<DGRife> rife_;
};

// All cells use one worker. Paging clears the current processor before the
// selected cell can start another session.
class SharedVideoProcessor {
public:
    FrameResult process(const ProcessorKey &key,const FramePair &pair,uint64_t frameGeneration,
                        double midpointDeadline,double quarterDeadline,const std::atomic_bool &cancelled) {
        if(!processor_||key_!=key){
            processor_.reset();
            key_=key;
            processor_=std::make_unique<VideoProcessor>(key);
        }
        return processor_->process(pair,frameGeneration,midpointDeadline,quarterDeadline,cancelled);
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
std::atomic_uint64_t nextFrameGeneration{0};
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
    CFTimeInterval _lastEffectStateChange;
    unsigned _reportedMultiplier;
    NSString *__strong _reportedBackend;
    CGAffineTransform _trackTransform;
    CGSize _pixelSize;
    OSType _pixelFormat;
    uint64_t _generation;
    NSUInteger _binding,_readyFrames,_consecutiveLate;
    BOOL _interpolation,_rife,_resolution,_preferResolution,_unsupported,_orientationReady,_reportedDisplay,_protection;
    BOOL _protectInterpolation,_interpolationProtected;
    unsigned _interpolationMultiplier;
    double _displayHz,_rendererFourTimesBackoffUntil;
    std::shared_ptr<std::atomic_bool> _cancellation;
}

- (void)showForPlayerLayer:(AVPlayerLayer *)layer {
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    BOOL rife=DGRifeRequested()&&DGRifeAvailable();
    BOOL interpolation=rife||(!DGRifeRequested()&&[prefs boolForKey:@"douglass.experimental.frameInterpolation"]);
    BOOL resolution=[prefs boolForKey:@"douglass.experimental.vtSuperResolution"]&&DGVTSuperResolutionAvailable();
    BOOL protection=DGSuperResolutionTransitionProtection();
    BOOL protectInterpolation=interpolation&&DGInterpolationTransitionProtection();
    unsigned multiplier=interpolation?DGInterpolationMultiplier():2;
    AVPlayerItem *item=layer.player.currentItem;
    if(item&&item==_item&&layer==_nativeLayer&&interpolation==_interpolation&&rife==_rife&&
       resolution==_resolution&&protection==_protection&&protectInterpolation==_protectInterpolation&&
       multiplier==_interpolationMultiplier)return;
    [self stop];
    if(!item||(!interpolation&&!resolution))return;
    _nativeLayer=layer;_item=item;_interpolation=interpolation;_rife=rife;_resolution=resolution;
    _protection=protection;_protectInterpolation=protectInterpolation;_interpolationMultiplier=multiplier;
    if(_interpolation)DGReportVideoEffect(DGVideoEffectInterpolation,self,@"preparing",@"waiting_for_frame");
    if(_resolution)DGReportVideoEffect(DGVideoEffectSuperResolution,self,@"preparing",@"waiting_for_frame");
    NSUInteger binding=++_binding;
    __weak DGVideoEffects *weak=self;
    dispatch_async(dispatch_get_main_queue(),^{
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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,80*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
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
    _displayHz=std::clamp<double>(UIScreen.mainScreen.maximumFramesPerSecond,30,120);
    const float preferredHz=_interpolationMultiplier>2?_displayHz:std::min(60.,_displayHz);
    _clock.preferredFrameRateRange=CAFrameRateRangeMake(30,preferredHz,preferredHz);
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

- (void)discardRenderedFrames {
    const BOOL flush=_display&&(!_display.hidden||CMTIME_IS_VALID(_lastQueued));
    _lastQueued=kCMTimeInvalid;_lastResult=0;_expectedGap=0;_readyFrames=0;
    _reportedMultiplier=0;_reportedBackend=nil;
    _display.hidden=YES;
    if(flush)[_display.sampleBufferRenderer flushWithRemovalOfDisplayedImage:YES completionHandler:nil];
}
- (void)resetFrames {
    _generation=1+nextFrameGeneration.fetch_add(1,std::memory_order_relaxed);
    if(_cancellation)_cancellation->store(true,std::memory_order_relaxed);
    _latest={};_interpolationProtected=NO;
    DGReleaseVideoFrameCache(_item);
    [self discardRenderedFrames];
}
- (void)releaseProcessing {
    if(!_cancellation)return;
    _cancellation->store(true,std::memory_order_relaxed);
    _cancellation.reset();
    dispatch_async(effectsQueue(),^{sharedVideoProcessor().clear();});
}
- (void)suspendForPaging {
    if(_item&&_protectInterpolation){
        const BOOL hadProcessing=_cancellation!=nullptr;
        [self stop];
        if(hadProcessing)DGDiagnostic(@"video.interpolation.release",@"reason=clip_switch");
    }else if(_interpolation||_protection)[self stop];
}
- (void)stop {
    if(_interpolation)DGEndVideoEffect(DGVideoEffectInterpolation,self);
    if(_resolution)DGEndVideoEffect(DGVideoEffectSuperResolution,self);
    ++_binding;
    [_clock invalidate];_clock=nil;
    [self resetFrames];
    [self releaseProcessing];
    [_display removeFromSuperlayer];
    _display=nil;_item=nil;_nativeLayer=nil;
    _unsupported=NO;_reportedDisplay=NO;_preferResolution=NO;_consecutiveLate=0;
    _interpolation=NO;_resolution=NO;_protectInterpolation=NO;_protection=NO;
    _lastEffectStateChange=0;
    _rendererFourTimesBackoffUntil=0;
    _pixelSize=CGSizeZero;_pixelFormat=0;
}

- (void)missedFrame {
    ++_consecutiveLate;
    if(!_display.hidden||_readyFrames)[self resetFrames];
    if(_interpolation&&!_preferResolution)DGReportVideoEffect(DGVideoEffectInterpolation,self,@"bypassed",@"frame_budget");
    if(_resolution)DGReportVideoEffect(DGVideoEffectSuperResolution,self,@"bypassed",@"frame_budget");
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
        if(!_orientationReady||!_nativeLayer.readyForDisplay||player.timeControlStatus!=AVPlayerTimeControlStatusPlaying||
           player.rate<.75||player.rate>1.25||DGAnimationProcessingDeferred()){
            if(_latest.source||!_display.hidden)[self resetFrames];
            if(_lastEffectStateChange){
                if(_interpolation&&!_preferResolution)DGReportVideoEffect(DGVideoEffectInterpolation,self,@"preparing",@"waiting_for_frame");
                if(_resolution)DGReportVideoEffect(DGVideoEffectSuperResolution,self,@"preparing",@"waiting_for_frame");
                _lastEffectStateChange=0;
            }
            return;
        }
        if(_lastResult&&CACurrentMediaTime()-_lastResult>std::max(.085,_expectedGap*2.4)){
            if(_interpolationProtected)[self discardRenderedFrames];
            else [self missedFrame];
        }
        if(_unsupported)return;
        CMTime actual=kCMTimeInvalid;
        auto pixel=ownPixel(DGCopyVideoFrame(_item,link.targetTimestamp,&actual));
        if(!pixel||!CMTIME_IS_NUMERIC(actual))return;
        if(_latest.source&&CMTimeCompare(actual,_latest.time)==0)return;
        CFTypeRef transfer=CVBufferGetAttachment(pixel.get(),kCVImageBufferTransferFunctionKey,nullptr);
        if(transfer&&(CFEqual(transfer,kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)||CFEqual(transfer,kCVImageBufferTransferFunction_ITU_R_2100_HLG))){
            if(_interpolation)DGReportVideoEffect(DGVideoEffectInterpolation,self,@"bypassed",@"unsupported_source");
            if(_resolution)DGReportVideoEffect(DGVideoEffectSuperResolution,self,@"bypassed",@"unsupported_source");
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
        const bool interpolate=_latest.source&&_interpolation&&!_preferResolution&&interval>=.025&&interval<=.10;
        const unsigned multiplier=_interpolationMultiplier;
        const double refreshInterval=link.targetTimestamp-link.timestamp;
        const double earliestOffset=interval*(1.-1./multiplier);
        const bool allowsHigherRate=interpolate&&multiplier>2&&interval*_displayHz>=multiplier*.99&&refreshInterval>0&&
            interval>=refreshInterval*multiplier*.975&&earliestOffset+interpolationHeadroom<renderLead&&
            CACurrentMediaTime()>=_rendererFourTimesBackoffUntil&&!NSProcessInfo.processInfo.lowPowerModeEnabled;
        const CMTime now=CMClockGetTime(CMClockGetHostTimeClock());
        FramePair pair={pixel,interpolate?_latest.source:PixelBuffer{},now,
                        interpolate?CMTimeSubtract(now,CMTimeMakeWithSeconds(interval,60000)):kCMTimeInvalid,allowsHigherRate};
        _latest={pixel,{},actual,kCMTimeInvalid};
        if(_interpolation&&!_resolution&&!pair.previous){
            if(interval>0&&interval<.025)DGReportVideoEffect(DGVideoEffectInterpolation,self,@"bypassed",@"source_rate");
            return;
        }
        if(processingFrame.exchange(true,std::memory_order_acq_rel))return;
        const BOOL rife=_rife&&!_preferResolution;
        ProcessorKey key={static_cast<size_t>(size.width),static_cast<size_t>(size.height),format,
                          _interpolation&&!_preferResolution&&!_rife,DGVTFSystemInterpolationAvailable(),_resolution,
                          bool(rife),bool(_protectInterpolation&&!_preferResolution),multiplier};
        if(!_cancellation||_cancellation->load(std::memory_order_relaxed))
            _cancellation=std::make_shared<std::atomic_bool>(false);
        auto cancellation=_cancellation;
        uint64_t generation=_generation;
        CMTime displayTime=CMTimeAdd(now,CMTimeMakeWithSeconds(renderLead,60000));
        const double targetHostTime=CACurrentMediaTime()+renderLead;
        const double midpointDeadline=interpolate?targetHostTime-interval*.5-interpolationHeadroom:0.;
        const double quarterDeadline=allowsHigherRate?targetHostTime-earliestOffset-interpolationHeadroom:0.;
        __weak DGVideoEffects *weak=self;
        dispatch_async(effectsQueue(),^{@autoreleasepool{
            const bool deferred=DGAnimationProcessingDeferred()||cancellation->load(std::memory_order_relaxed);
            FrameResult result=deferred?FrameResult{}:sharedVideoProcessor().process(key,pair,generation,midpointDeadline,quarterDeadline,*cancellation);
            dispatch_async(dispatch_get_main_queue(),^{
                processingFrame.store(false,std::memory_order_release);
                DGVideoEffects *effects=weak;
                if(!effects)return;
                if(deferred||cancellation->load(std::memory_order_relaxed)||effects->_generation!=generation||!effects->_display||DGAnimationProcessingDeferred())return;
                const auto hazard=result.interpolationHazard;
                const BOOL protectedFrame=hazard!=douglass::InterpolationHazard::none;
                if(protectedFrame!=effects->_interpolationProtected){
                    effects->_interpolationProtected=protectedFrame;
                    if(protectedFrame){
                        [effects discardRenderedFrames];
                        effects->_consecutiveLate=0;
                        NSString *reason=hazard==douglass::InterpolationHazard::sceneChange?@"scene_change":
                                         hazard==douglass::InterpolationHazard::fastMotion?@"fast_motion":@"unstable";
                        DGDiagnostic(@"video.interpolation.protected",reason);
                        DGReportVideoEffect(DGVideoEffectInterpolation,effects,@"protected",reason);
                        if(effects->_resolution)DGReportVideoEffect(DGVideoEffectSuperResolution,effects,@"preparing",@"waiting_for_frame");
                    }else{
                        DGDiagnostic(@"video.interpolation.resumed",nil);
                        DGReportVideoEffect(DGVideoEffectInterpolation,effects,@"preparing",@"waiting_for_frame");
                    }
                }
                if(!result.supported){
                    if(effects->_interpolation&&!effects->_preferResolution)DGReportVideoEffect(DGVideoEffectInterpolation,effects,@"bypassed",@"unsupported_source");
                    if(effects->_resolution)DGReportVideoEffect(DGVideoEffectSuperResolution,effects,@"bypassed",@"unsupported_source");
                    [effects resetFrames];[effects releaseProcessing];effects->_unsupported=YES;effects->_clock.paused=YES;
                    return;
                }
                CMTime now=CMClockGetTime(CMClockGetHostTimeClock());
                if(protectedFrame&&(!result.upscaled||CMTimeCompare(displayTime,now)<=0)){
                    [effects discardRenderedFrames];
                    return;
                }
                if(!result.current||CMTimeCompare(displayTime,now)<=0){
                    [effects missedFrame];
                    return;
                }
                unsigned queuedInserted=0;
                if(result.inserted[1]||result.thirds){
                    auto timeAtPhase=[&](double phase){
                        return CMTimeSubtract(displayTime,CMTimeMakeWithSeconds(interval*(1-phase),60000));
                    };
                    const auto &schedule=result.thirds?thirdPhases:phases;
                    const CMTime firstInserted=timeAtPhase(schedule[0]);
                    const bool useHigher=result.inserted[0]&&result.inserted[2]&&CMTimeCompare(firstInserted,now)>0&&
                        (!CMTIME_IS_VALID(effects->_lastQueued)||CMTimeCompare(firstInserted,effects->_lastQueued)>0);
                    if(useHigher){
                        for(size_t i=0;i<phases.size();++i){
                            if(result.thirds&&i==1)continue;
                            if(![effects queuePixel:result.inserted[i].get() atHostTime:timeAtPhase(schedule[i])])break;
                            ++queuedInserted;
                        }
                        if(queuedInserted!=(result.thirds?2:3)){
                            effects->_rendererFourTimesBackoffUntil=CACurrentMediaTime()+fourTimesBackoff;
                            if(queuedInserted){
                                [effects discardRenderedFrames];
                                DGReportVideoEffect(DGVideoEffectInterpolation,effects,@"bypassed",@"renderer");
                                return;
                            }
                        }
                    }
                    if(!queuedInserted&&result.inserted[1]){
                        const CMTime midpoint=timeAtPhase(phases[1]);
                        if(CMTimeCompare(midpoint,now)>0&&[effects queuePixel:result.inserted[1].get() atHostTime:midpoint])queuedInserted=1;
                    }
                }
                if(!result.upscaled&&!queuedInserted){
                    if(result.inserted[1]||!effects->_interpolation||effects->_preferResolution){
                        [effects missedFrame];
                        return;
                    }
                    if(!effects->_readyFrames){
                        if(effects->_interpolation)DGReportVideoEffect(DGVideoEffectInterpolation,effects,@"bypassed",@"no_output");
                        if(effects->_resolution)DGReportVideoEffect(DGVideoEffectSuperResolution,effects,@"bypassed",@"no_output");
                        return;
                    }
                }
                if([effects queuePixel:result.current.get() atHostTime:displayTime]){
                    effects->_lastResult=CACurrentMediaTime();effects->_consecutiveLate=0;
                    effects->_expectedGap=std::isfinite(interval)?interval:1./30;
                    ++effects->_readyFrames;
                    if(effects->_readyFrames>=minimumReadyFrames&&effects->_display.readyForDisplay){
                        effects->_display.hidden=NO;
                        if(effects->_resolution)DGReportVideoEffect(DGVideoEffectSuperResolution,effects,result.upscaled?@"active":@"bypassed",result.upscaled?@"frame_output":@"no_output");
                        if(queuedInserted){
                            NSString *backend=result.rife?@"rife":(result.compatibility?@"compatibility":@"system");
                            if(!effects->_reportedMultiplier||CACurrentMediaTime()-effects->_lastEffectStateChange>.35){
                                unsigned multiplier=queuedInserted+1;
                                if(effects->_reportedMultiplier!=multiplier||![effects->_reportedBackend isEqualToString:backend]){
                                    effects->_reportedMultiplier=multiplier;
                                    effects->_reportedBackend=backend;
                                    effects->_lastEffectStateChange=CACurrentMediaTime();
                                    DGReportVideoEffect(DGVideoEffectInterpolation,effects,@"active",
                                                        multiplier<effects->_interpolationMultiplier?@"adaptive_fallback":@"frame_output",multiplier,backend);
                                }
                            }
                        }else if(effects->_interpolation&&!effects->_preferResolution&&!protectedFrame){
                            effects->_reportedMultiplier=0;
                            DGReportVideoEffect(DGVideoEffectInterpolation,effects,@"bypassed",interval>0&&interval<.025?@"source_rate":@"no_output");
                        }
                        if(!effects->_reportedDisplay){
                            effects->_reportedDisplay=YES;
                            DGDiagnostic(@"video.vt.display",[NSString stringWithFormat:@"midpoint=%d compatibility=%d rife=%d multiplier=%u width=%zu",queuedInserted!=0,result.compatibility,result.rife,queuedInserted+1,CVPixelBufferGetWidth(result.current.get())]);
                        }
                    }
                }else if(queuedInserted>=2){
                    effects->_rendererFourTimesBackoffUntil=CACurrentMediaTime()+fourTimesBackoff;
                    [effects discardRenderedFrames];
                }else if(protectedFrame)[effects discardRenderedFrames];
                else [effects missedFrame];
            });
        }});
}
- (void)dealloc{[self stop];}
@end
