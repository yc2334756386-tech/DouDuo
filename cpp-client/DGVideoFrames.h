#pragma once
#import <AVFoundation/AVFoundation.h>

void DGPrepareVideoFrameOutput(AVPlayerItem *item);
CVPixelBufferRef DGCopyVideoFrame(AVPlayerItem *item, CFTimeInterval hostTime, CMTime *presentationTime) CF_RETURNS_RETAINED;
void DGReleaseVideoFrameCache(AVPlayerItem *item);
