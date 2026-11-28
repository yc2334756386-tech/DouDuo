#import "DGVideoFrames.h"
#import <objc/runtime.h>

// Both playback enhancement and ambient sampling access this output on the main thread.
@interface DGVideoFrameSource : NSObject {
@public
    CVPixelBufferRef latest;
    CMTime presentationTime;
}
@property(nonatomic,strong) AVPlayerItemVideoOutput *output;
@end
@implementation DGVideoFrameSource
- (void)dealloc {
    if(latest)CVPixelBufferRelease(latest);
}
@end

static const void *DGVideoFrameSourceKey=&DGVideoFrameSourceKey;

void DGPrepareVideoFrameOutput(AVPlayerItem *item) {
    if(!item||objc_getAssociatedObject(item,DGVideoFrameSourceKey))return;
    DGVideoFrameSource *source=[DGVideoFrameSource new];
    source->presentationTime=kCMTimeInvalid;
    source.output=[[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{
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
        CVPixelBufferRef pixel=[source.output copyPixelBufferForItemTime:time itemTimeForDisplay:&actual];
        if(pixel&&CMTIME_IS_NUMERIC(actual)){
            if(source->latest)CVPixelBufferRelease(source->latest);
            source->latest=pixel;
            source->presentationTime=actual;
        }else if(pixel)CVPixelBufferRelease(pixel);
    }
    if(presentationTime)*presentationTime=source->presentationTime;
    return source->latest?CVPixelBufferRetain(source->latest):nullptr;
}

void DGReleaseVideoFrameCache(AVPlayerItem *item) {
    if(!item)return;
    DGVideoFrameSource *source=objc_getAssociatedObject(item,DGVideoFrameSourceKey);
    if(!source)return;
    if(source->latest)CVPixelBufferRelease(source->latest);
    source->latest=nullptr;
    source->presentationTime=kCMTimeInvalid;
}
