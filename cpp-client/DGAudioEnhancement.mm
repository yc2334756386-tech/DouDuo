#import "DGAudioEnhancement.h"
#import "DGDiagnostics.h"
#import <MediaToolbox/MediaToolbox.h>
#import <objc/runtime.h>
#include "AudioEnhancer.hpp"
#include <memory>
#include <algorithm>
#include <cmath>
#import <QuartzCore/QuartzCore.h>

struct DGAudioTapTelemetry {
 std::atomic<int> sourceError{0};
 std::atomic<unsigned> failures{0},emptyReads{0};
 std::atomic<uint64_t> suppliedFrames{0};
};
struct DGAudioTapState{douglass::AudioEnhancer processor;AudioStreamBasicDescription format{};bool supported=false;std::shared_ptr<DGAudioTapTelemetry> telemetry;};
@interface DGAudioPreparation:NSObject{
 @public
 std::shared_ptr<DGAudioTapTelemetry> telemetry;
 uint64_t observedFrames;
 CMTime lastMediaTime;
 double missingAudioDuration;
}
@property(nonatomic) BOOL sealed,completed,bypassed;
@property(nonatomic,copy) dispatch_block_t completion;
- (void)finish;
@end
@implementation DGAudioPreparation
- (void)finish{if(_completed)return;_completed=YES;dispatch_block_t completion=_completion;_completion=nil;if(completion)completion();}
@end
static const void *DGAudioPreparationKey=&DGAudioPreparationKey;
static void DGTapInit(MTAudioProcessingTapRef tap,void *client,void **storage){*storage=client;}
static void DGTapFinalize(MTAudioProcessingTapRef tap){delete static_cast<DGAudioTapState *>(MTAudioProcessingTapGetStorage(tap));}
static void DGTapPrepare(MTAudioProcessingTapRef tap,CMItemCount maxFrames,const AudioStreamBasicDescription *format){auto *state=static_cast<DGAudioTapState *>(MTAudioProcessingTapGetStorage(tap));state->format=*format;state->supported=format->mFormatID==kAudioFormatLinearPCM&&(format->mFormatFlags&kAudioFormatFlagIsFloat)&&format->mBitsPerChannel==32&&format->mChannelsPerFrame>0&&format->mChannelsPerFrame<=8;state->processor.prepare(format->mSampleRate,format->mChannelsPerFrame);}
static void DGTapUnprepare(MTAudioProcessingTapRef tap){static_cast<DGAudioTapState *>(MTAudioProcessingTapGetStorage(tap))->processor.reset();}
static void DGTapProcess(MTAudioProcessingTapRef tap,CMItemCount frames,MTAudioProcessingTapFlags flags,AudioBufferList *buffers,CMItemCount *outFrames,MTAudioProcessingTapFlags *outFlags){
 auto *state=static_cast<DGAudioTapState *>(MTAudioProcessingTapGetStorage(tap));OSStatus result=MTAudioProcessingTapGetSourceAudio(tap,frames,buffers,outFlags,nullptr,outFrames);
 if(result!=noErr){state->telemetry->sourceError.store(result,std::memory_order_relaxed);state->telemetry->failures.fetch_add(1,std::memory_order_relaxed);*outFrames=0;*outFlags=0;return;}
 state->telemetry->failures.store(0,std::memory_order_relaxed);
 if(*outFrames<=0){if(!(*outFlags&kMTAudioProcessingTapFlag_EndOfStream))state->telemetry->emptyReads.fetch_add(1,std::memory_order_relaxed);return;}
 state->telemetry->emptyReads.store(0,std::memory_order_relaxed);
 state->telemetry->suppliedFrames.fetch_add((uint64_t)*outFrames,std::memory_order_relaxed);
 if(!state->supported)return;
 if(*outFlags&kMTAudioProcessingTapFlag_StartOfStream)state->processor.reset();float *data[8]{};unsigned count=MIN(8u,buffers->mNumberBuffers);bool interleaved=!(state->format.mFormatFlags&kAudioFormatFlagIsNonInterleaved);
 for(unsigned i=0;i<count;++i){data[i]=static_cast<float *>(buffers->mBuffers[i].mData);std::size_t required=(std::size_t)*outFrames*sizeof(float)*(interleaved?state->format.mChannelsPerFrame:1);if(buffers->mBuffers[i].mDataByteSize<required)return;}
 state->processor.process(data,count,state->format.mChannelsPerFrame,(std::size_t)*outFrames,interleaved);
}
void DGUpdateAudioControls(void){NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;auto &controls=douglass::audioControls();controls.enabled=[prefs boolForKey:@"douglass.experimental.audio"];for(unsigned i=0;i<8;++i){float gain=[prefs floatForKey:[NSString stringWithFormat:@"douglass.experimental.eq.%u",i]];controls.gains[i]=std::isfinite(gain)?std::clamp(gain,-12.f,12.f):0;}}
void DGPrepareAudioEnhancement(AVPlayerItem *item,dispatch_block_t completion){
 if(!item){if(completion)completion();return;}DGUpdateAudioControls();DGAudioPreparation *stage=[DGAudioPreparation new];stage->telemetry=std::make_shared<DGAudioTapTelemetry>();stage.completion=completion;objc_setAssociatedObject(item,DGAudioPreparationKey,stage,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 if(!douglass::audioControls().enabled){[stage finish];return;}
 if([item.asset isKindOfClass:AVURLAsset.class]&&[((AVURLAsset *)item.asset).URL.pathExtension.lowercaseString isEqualToString:@"m3u8"]){DGDiagnostic(@"audio.tap.bypass",@"reason=hls_baseline_not_supported");[stage finish];return;}
 __weak AVPlayerItem *weak=item;AVAsset *asset=item.asset;
 [asset loadValuesAsynchronouslyForKeys:@[@"hasProtectedContent"] completionHandler:^{
  if([asset statusOfValueForKey:@"hasProtectedContent" error:nil]!=AVKeyValueStatusLoaded||asset.hasProtectedContent){dispatch_async(dispatch_get_main_queue(),^{[stage finish];});return;}
  [asset loadTracksWithMediaType:AVMediaTypeAudio completionHandler:^(NSArray<AVAssetTrack *> *tracks,NSError *error){
   dispatch_async(dispatch_get_main_queue(),^{
    AVPlayerItem *current=weak;if(!current||objc_getAssociatedObject(current,DGAudioPreparationKey)!=stage||stage.sealed){[stage finish];return;}
    if(error||!tracks.count){[stage finish];return;}NSMutableArray *inputs=[NSMutableArray array];
    for(AVAssetTrack *track in tracks){
     auto *state=new DGAudioTapState;state->telemetry=stage->telemetry;MTAudioProcessingTapCallbacks callbacks={kMTAudioProcessingTapCallbacksVersion_0,state,DGTapInit,DGTapFinalize,DGTapPrepare,DGTapUnprepare,DGTapProcess};MTAudioProcessingTapRef tap=nullptr;
     OSStatus status=MTAudioProcessingTapCreate(kCFAllocatorDefault,&callbacks,kMTAudioProcessingTapCreationFlag_PostEffects,&tap);if(status!=noErr){delete state;continue;}
     AVMutableAudioMixInputParameters *input=[AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];input.audioTapProcessor=tap;CFRelease(tap);[inputs addObject:input];
    }
    if(inputs.count){AVMutableAudioMix *mix=[AVMutableAudioMix audioMix];mix.inputParameters=inputs;current.audioMix=mix;DGDiagnostic(@"audio.tap.attached",[NSString stringWithFormat:@"tracks=%lu before_playback=1",(unsigned long)inputs.count]);}
    [stage finish];
   });
  }];
 }];
}
void DGSealAudioEnhancement(AVPlayerItem *item){DGAudioPreparation *stage=objc_getAssociatedObject(item,DGAudioPreparationKey);if(!stage)return;if(!stage.completed)DGDiagnostic(@"audio.tap.bypass",@"reason=playback_started_before_optional_processing_ready");stage.sealed=YES;[stage finish];}
BOOL DGRecoverAudioEnhancement(AVPlayer *player){
 AVPlayerItem *item=player.currentItem;
 DGAudioPreparation *stage=item?objc_getAssociatedObject(item,DGAudioPreparationKey):nil;
 if(!stage||stage.bypassed||!item.audioMix)return NO;
 if(player.timeControlStatus!=AVPlayerTimeControlStatusPlaying||player.rate<=0){
  stage->lastMediaTime=kCMTimeInvalid;
  stage->missingAudioDuration=0;
  return NO;
 }
 const CMTime now=player.currentTime;
 const double advanced=CMTimeGetSeconds(CMTimeSubtract(now,stage->lastMediaTime));
 stage->lastMediaTime=now;
 const auto frames=stage->telemetry->suppliedFrames.load(std::memory_order_relaxed);
 if(frames!=stage->observedFrames||!std::isfinite(advanced)||advanced<0||advanced>2.5){
  stage->observedFrames=frames;
  stage->missingAudioDuration=0;
 }else if(advanced>0){
  stage->missingAudioDuration+=advanced/player.rate;
 }
 const auto failures=stage->telemetry->failures.load(std::memory_order_relaxed);
 const auto empty=stage->telemetry->emptyReads.load(std::memory_order_relaxed);
 const double duration=CMTimeGetSeconds(item.duration),position=CMTimeGetSeconds(now);
 if(std::isfinite(duration)&&duration-position<.35)return NO;
 const bool sourceFailed=stage->missingAudioDuration>=.35&&(failures>=3||empty>=8);
 if(!sourceFailed&&stage->missingAudioDuration<.75)return NO;
 stage.bypassed=YES;
 [player pause];
 item.audioMix=nil;
 DGDiagnostic(@"audio.tap.recovered_original",[NSString stringWithFormat:@"reason=%@ error=%d failures=%u empty_reads=%u missing_ms=%.0f",
     sourceFailed?@"source_read":@"no_output",stage->telemetry->sourceError.load(std::memory_order_relaxed),
     failures,empty,stage->missingAudioDuration*1000]);
 return YES;
}
AVPlayer *DGMakeAudioPlayer(AVPlayerItem *item,void (^ready)(AVPlayer *)){
 AVPlayer *player=[AVPlayer new];player.automaticallyWaitsToMinimizeStalling=NO;__weak AVPlayer *weak=player;__block BOOL bound=NO;
 dispatch_block_t commit=^{if(bound)return;bound=YES;DGSealAudioEnhancement(item);AVPlayer *current=weak;if(!current)return;[current replaceCurrentItemWithPlayerItem:item];if(ready)ready(current);};
 DGPrepareAudioEnhancement(item,commit);dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),commit);return player;
}
