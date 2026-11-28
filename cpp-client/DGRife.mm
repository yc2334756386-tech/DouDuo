#import "DGRife.h"
#import "DGDiagnostics.h"
#import <CoreImage/CoreImage.h>
#import <CoreML/CoreML.h>
#import <QuartzCore/QuartzCore.h>
#import <VideoToolbox/VideoToolbox.h>
#include <algorithm>
#include <cmath>
#include <memory>
#include <type_traits>

namespace {
constexpr size_t modelWidth=320,modelHeight=192;
enum class ComputeCheck { idle,pending,allowed,rejected };
std::atomic<ComputeCheck> computeCheck{ComputeCheck::idle};

NSURL *rifeModelURL() {
    return [NSBundle.mainBundle URLForResource:@"RIFE425" withExtension:@"mlmodelc"];
}

MLModelConfiguration *rifeConfiguration() {
    MLModelConfiguration *config=[MLModelConfiguration new];
    config.computeUnits=MLComputeUnitsCPUAndNeuralEngine;
    return config;
}

void requestComputePlan() {
    auto expected=ComputeCheck::idle;
    if(!computeCheck.compare_exchange_strong(expected,ComputeCheck::pending))return;
    NSURL *url=rifeModelURL();
    if(!url){computeCheck=ComputeCheck::rejected;return;}
    [MLComputePlan loadContentsOfURL:url configuration:rifeConfiguration() completionHandler:^(MLComputePlan *plan,NSError *error){
        auto *program=plan.modelStructure.program;
        NSArray *operations=program.functions[@"main"].block.operations;
        NSUInteger convolutionCount=0,aneCount=0,resampleOnCPU=0;
        for(MLModelStructureProgramOperation *op in operations){
            if(![op.operatorName isEqualToString:@"conv"]&&![op.operatorName isEqualToString:@"conv_transpose"]&&
               ![op.operatorName isEqualToString:@"resample"])continue;
            MLComputePlanDeviceUsage *usage=[plan computeDeviceUsageForMLProgramOperation:op];
            BOOL ane=[usage.preferredComputeDevice isKindOfClass:MLNeuralEngineComputeDevice.class];
            if([op.operatorName isEqualToString:@"resample"]){
                if(!ane)++resampleOnCPU;
            }else{
                ++convolutionCount;
                if(ane)++aneCount;
            }
        }
        BOOL allowed=convolutionCount>0&&aneCount*2>=convolutionCount;
        computeCheck=allowed?ComputeCheck::allowed:ComputeCheck::rejected;
        DGDiagnostic(@"video.rife.compute_plan",[NSString stringWithFormat:@"accepted=%d ane_conv=%lu total_conv=%lu non_ane_resample=%lu code=%ld",
            allowed,(unsigned long)aneCount,(unsigned long)convolutionCount,(unsigned long)resampleOnCPU,(long)error.code]);
    }];
}

struct PixelDeleter {
    void operator()(CVPixelBufferRef pixel) const {if(pixel)CVPixelBufferRelease(pixel);}
};
using OwnedPixel=std::unique_ptr<std::remove_pointer_t<CVPixelBufferRef>,PixelDeleter>;

CVPixelBufferPoolRef makePool(size_t width,size_t height,OSType format) {
    CVPixelBufferPoolRef pool=nullptr;
    NSDictionary *attributes=@{
        (__bridge NSString *)kCVPixelBufferWidthKey:@(width),
        (__bridge NSString *)kCVPixelBufferHeightKey:@(height),
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:@(format),
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey:@{},
        (__bridge NSString *)kCVPixelBufferMetalCompatibilityKey:@YES
    };
    CVPixelBufferPoolCreate(kCFAllocatorDefault,nullptr,(__bridge CFDictionaryRef)attributes,&pool);
    return pool;
}

OwnedPixel nextPixel(CVPixelBufferPoolRef pool,NSNumber *limit=@4) {
    CVPixelBufferRef buffer=nullptr;
    NSDictionary *options=@{(__bridge NSString *)kCVPixelBufferPoolAllocationThresholdKey:limit};
    if(pool)CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,pool,
        (__bridge CFDictionaryRef)options,&buffer);
    return OwnedPixel(buffer);
}

CIImage *transformSource(CVPixelBufferRef input,bool rotate) {
    CIImage *image=[CIImage imageWithCVPixelBuffer:input];
    if(rotate)image=[image imageByApplyingOrientation:6];
    CGRect extent=image.extent;
    return [image imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x,-extent.origin.y)];
}
}

BOOL DGRifeAvailable(void) {
    static BOOL available=NO;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        if(!rifeModelURL())return;
        for(id device in [MLModel availableComputeDevices]){
            if([device isKindOfClass:MLNeuralEngineComputeDevice.class]){
                available=YES;
                break;
            }
        }
    });
    return available;
}

BOOL DGRifeRequested(void) {
    return [NSUserDefaults.standardUserDefaults integerForKey:@"douglass.experimental.interpolationBackend"]==2;
}

struct DGRife::State {
    MLModel *__strong model=nil;
    MLMultiArray *__strong phase=nil;
    CIContext *__strong context=nil;
    CVPixelBufferPoolRef inputs=nullptr,rgbOutput=nullptr,outputs=nullptr;
    VTPixelTransferSessionRef transfer=nullptr;
    CGColorSpaceRef color=nullptr;
    size_t width=0,height=0;
    bool unavailable=false;
    ~State(){
        if(inputs)CVPixelBufferPoolRelease(inputs);
        if(rgbOutput)CVPixelBufferPoolRelease(rgbOutput);
        if(outputs)CVPixelBufferPoolRelease(outputs);
        if(transfer){VTPixelTransferSessionInvalidate(transfer);CFRelease(transfer);}
        if(color)CGColorSpaceRelease(color);
    }
};

DGRife::DGRife():state_(new State){}
DGRife::~DGRife(){delete state_;}
bool DGRife::rejected() const {
    return state_->unavailable||computeCheck.load()==ComputeCheck::rejected;
}

std::array<CVPixelBufferRef,3> DGRife::copyInterpolatedFrames(CVPixelBufferRef previous,CVPixelBufferRef current,
                                                              double midpointDeadline,double quarterDeadline,
                                                              const std::atomic_bool &cancelled) {
    if(cancelled.load()||rejected()||!previous||!current)return {};
    const size_t width=CVPixelBufferGetWidth(current),height=CVPixelBufferGetHeight(current);
    if(width<128||height<128||std::max(width,height)>1920||width*height>1920*1080||
       width!=CVPixelBufferGetWidth(previous)||height!=CVPixelBufferGetHeight(previous))return {};
    requestComputePlan();
    if(computeCheck.load()!=ComputeCheck::allowed)return {};
    State &state=*state_;
    if(!state.model){
        NSError *error=nil;
        state.model=[MLModel modelWithContentsOfURL:rifeModelURL() configuration:rifeConfiguration() error:&error];
        if(state.model)state.phase=[[MLMultiArray alloc] initWithShape:@[@1,@1,@1,@1] dataType:MLMultiArrayDataTypeFloat32 error:&error];
        if(!state.model||!state.phase){
            state.unavailable=true;
            DGDiagnostic(@"video.rife.load",[NSString stringWithFormat:@"code=%ld",(long)error.code]);
            return {};
        }
    }
    if(cancelled.load()||CACurrentMediaTime()>=midpointDeadline)return {};
    if(!state.context){
        state.context=[CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}];
        state.color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        state.inputs=makePool(modelWidth,modelHeight,kCVPixelFormatType_32BGRA);
        VTPixelTransferSessionCreate(kCFAllocatorDefault,&state.transfer);
    }
    if(state.width!=width||state.height!=height){
        if(state.outputs)CVPixelBufferPoolRelease(state.outputs);
        if(state.rgbOutput)CVPixelBufferPoolRelease(state.rgbOutput);
        state.rgbOutput=makePool(width,height,kCVPixelFormatType_32BGRA);
        state.outputs=makePool(width,height,CVPixelBufferGetPixelFormatType(current));
        state.width=width;state.height=height;
    }
    auto first=nextPixel(state.inputs),second=nextPixel(state.inputs);
    if(!first||!second||!state.color||!state.outputs||!state.transfer)return {};
    const bool rotated=height>width;
    const CGRect modelBounds=CGRectMake(0,0,modelWidth,modelHeight);
    const double w=rotated?height:width,h=rotated?width:height;
    const double scale=std::min(modelWidth/w,modelHeight/h);
    const CGRect content=CGRectMake((modelWidth-w*scale)/2,(modelHeight-h*scale)/2,w*scale,h*scale);
    auto prepare=[&](CVPixelBufferRef input,CVPixelBufferRef output){
        CIImage *image=[transformSource(input,rotated) imageByApplyingTransform:CGAffineTransformMakeScale(scale,scale)];
        image=[image imageByApplyingTransform:CGAffineTransformMakeTranslation(content.origin.x,content.origin.y)];
        image=[[image imageByClampingToExtent] imageByCroppingToRect:modelBounds];
        [state.context render:image toCVPixelBuffer:output bounds:modelBounds colorSpace:state.color];
    };
    prepare(previous,first.get());
    if(cancelled.load()||CACurrentMediaTime()>=midpointDeadline)return {};
    prepare(current,second.get());
    NSError *error=nil;
    NSDictionary *features=@{
        @"previous":[MLFeatureValue featureValueWithPixelBuffer:first.get()],
        @"current":[MLFeatureValue featureValueWithPixelBuffer:second.get()],
        @"phase":[MLFeatureValue featureValueWithMultiArray:state.phase]
    };
    auto *provider=[[MLDictionaryFeatureProvider alloc] initWithDictionary:features error:&error];
    if(!provider)return {};
    const auto predict=[&](float phase,double deadline)->OwnedPixel {
        @autoreleasepool {
            const auto started=CACurrentMediaTime();
            if(cancelled.load()||started>=deadline)return {};
            *static_cast<float *>(state.phase.dataPointer)=phase;
            NSError *predictionError=nil;
            id<MLFeatureProvider> prediction=[state.model predictionFromFeatures:provider error:&predictionError];
            CVPixelBufferRef imageBuffer=[prediction featureValueForName:@"midpoint"].imageBufferValue;
            if(!imageBuffer||cancelled.load()||CACurrentMediaTime()>=deadline){
                if(phase==.5f&&DGDiagnosticEnabled())DGDiagnostic(@"video.rife.frame_skipped",
                    [NSString stringWithFormat:@"inference_ms=%.1f code=%ld",(CACurrentMediaTime()-started)*1000,(long)predictionError.code]);
                return {};
            }
            auto rgb=nextPixel(state.rgbOutput),output=nextPixel(state.outputs,quarterDeadline>0?@6:@4);
            if(!rgb||!output)return {};
            CIImage *image=[[CIImage imageWithCVPixelBuffer:imageBuffer] imageByCroppingToRect:content];
            image=[image imageByApplyingTransform:CGAffineTransformMakeTranslation(-content.origin.x,-content.origin.y)];
            image=[image imageByApplyingTransform:CGAffineTransformMakeScale(1/scale,1/scale)];
            if(rotated)image=[image imageByApplyingOrientation:8];
            CGRect extent=image.extent;
            image=[image imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x,-extent.origin.y)];
            [state.context render:image toCVPixelBuffer:rgb.get() bounds:CGRectMake(0,0,width,height) colorSpace:state.color];
            CVBufferSetAttachment(rgb.get(),kCVImageBufferColorPrimariesKey,kCVImageBufferColorPrimaries_ITU_R_709_2,kCVAttachmentMode_ShouldPropagate);
            CVBufferSetAttachment(rgb.get(),kCVImageBufferTransferFunctionKey,kCVImageBufferTransferFunction_sRGB,kCVAttachmentMode_ShouldPropagate);
            CVBufferPropagateAttachments(current,output.get());
            if(VTPixelTransferSessionTransferImage(state.transfer,rgb.get(),output.get())!=noErr)return {};
            if(cancelled.load()||CACurrentMediaTime()>=deadline)return {};
            return output;
        }
    };
    const auto started=CACurrentMediaTime();
    auto midpoint=predict(.5f,midpointDeadline);
    if(!midpoint)return {};
    const double cost=CACurrentMediaTime()-started;
    if(CACurrentMediaTime()+2*cost+.002<quarterDeadline){
        auto firstQuarter=predict(.25f,quarterDeadline);
        if(firstQuarter&&CACurrentMediaTime()+cost<quarterDeadline){
            auto thirdQuarter=predict(.75f,quarterDeadline);
            if(thirdQuarter)return {firstQuarter.release(),midpoint.release(),thirdQuarter.release()};
        }
    }
    return {nullptr,midpoint.release(),nullptr};
}
