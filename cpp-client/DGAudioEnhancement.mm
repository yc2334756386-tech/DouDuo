#import "DGAudioEnhancement.h"
#import "DGDiagnostics.h"
#import <MediaToolbox/MediaToolbox.h>
#import <objc/runtime.h>
#include "AudioEnhancer.hpp"
struct DGAudioTapState{douglass::AudioEnhancer processor;AudioStreamBasicDescription format{};bool supported=false;};
static void DGTapInit(MTAudioProcessingTapRef tap,void *client,void **storage){*storage=client;}
static void DGTapFinalize(MTAudioProcessingTapRef tap){delete static_cast<DGAudioTapState *>(MTAudioProcessingTapGetStorage(tap));}
static void DGTapPrepare(MTAudioProcessingTapRef tap,CMItemCount maxFrames,const AudioStreamBasicDescription *format){auto *state=static_cast<DGAudioTapState *>(MTAudioProcessingTapGetStorage(tap));state->format=*format;state->supported=format->mFormatID==kAudioFormatLinearPCM&&(format->mFormatFlags&kAudioFormatFlagIsFloat)&&format->mBitsPerChannel==32&&format->mChannelsPerFrame<=8;state->processor.prepare(format->mSampleRate,format->mChannelsPerFrame);DGDiagnostic(@"audio.tap.prepared",[NSString stringWithFormat:@"supported=%d rate=%.0f channels=%u bits=%u",state->supported,format->mSampleRate,(unsigned)format->mChannelsPerFrame,(unsigned)format->mBitsPerChannel]);}
static void DGTapUnprepare(MTAudioProcessingTapRef tap){static_cast<DGAudioTapState *>(MTAudioProcessingTapGetStorage(tap))->processor.reset();}
static void DGTapProcess(MTAudioProcessingTapRef tap,CMItemCount frames,MTAudioProcessingTapFlags flags,AudioBufferList *buffers,CMItemCount *outFrames,MTAudioProcessingTapFlags *outFlags){OSStatus result=MTAudioProcessingTapGetSourceAudio(tap,frames,buffers,outFlags,nullptr,outFrames);if(result!=noErr){*outFrames=0;return;}auto *state=static_cast<DGAudioTapState *>(MTAudioProcessingTapGetStorage(tap));if(!state->supported||*outFrames<=0)return;if(*outFlags&kMTAudioProcessingTapFlag_StartOfStream)state->processor.reset();float *data[8]{};unsigned count=MIN(8u,buffers->mNumberBuffers);bool interleaved=!(state->format.mFormatFlags&kAudioFormatFlagIsNonInterleaved);for(unsigned i=0;i<count;++i){data[i]=static_cast<float *>(buffers->mBuffers[i].mData);std::size_t required=(std::size_t)*outFrames*sizeof(float)*(interleaved?state->format.mChannelsPerFrame:1);if(buffers->mBuffers[i].mDataByteSize<required)return;}state->processor.process(data,count,state->format.mChannelsPerFrame,(std::size_t)*outFrames,interleaved);}
void DGUpdateAudioControls(void){NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;auto &controls=douglass::audioControls();controls.enabled=[prefs boolForKey:@"douglass.experimental.audio"];controls.adaptive=[prefs boolForKey:@"douglass.experimental.adaptiveAudio"];controls.style=(int)[prefs integerForKey:@"douglass.experimental.audioStyle"];for(unsigned i=0;i<8;++i)controls.gains[i]=[prefs floatForKey:[NSString stringWithFormat:@"douglass.experimental.eq.%u",i]];}
void DGConfigureAudioEnhancement(AVPlayerItem *item){
 if(!item)return;DGUpdateAudioControls();static const void *key=&key;id token=[NSObject new];objc_setAssociatedObject(item,key,token,OBJC_ASSOCIATION_RETAIN_NONATOMIC);if(!douglass::audioControls().enabled){item.audioMix=nil;return;}
 if([item.asset isKindOfClass:AVURLAsset.class]&&[((AVURLAsset *)item.asset).URL.pathExtension.lowercaseString isEqualToString:@"m3u8"]){DGDiagnostic(@"audio.tap.bypass",@"reason=hls_baseline_not_supported");return;}
 __weak AVPlayerItem *weak=item;AVAsset *asset=item.asset;
 [asset loadValuesAsynchronouslyForKeys:@[@"hasProtectedContent"] completionHandler:^{
 if([asset statusOfValueForKey:@"hasProtectedContent" error:nil]!=AVKeyValueStatusLoaded||asset.hasProtectedContent)return;
 [asset loadTracksWithMediaType:AVMediaTypeAudio completionHandler:^(NSArray<AVAssetTrack *> *tracks,NSError *error){
  dispatch_async(dispatch_get_main_queue(),^{
   AVPlayerItem *current=weak;if(!current||objc_getAssociatedObject(current,key)!=token||error||!tracks.count)return;NSMutableArray *inputs=[NSMutableArray array];
   for(AVAssetTrack *track in tracks){
    MTAudioProcessingTapCallbacks callbacks={kMTAudioProcessingTapCallbacksVersion_0,new DGAudioTapState,DGTapInit,DGTapFinalize,DGTapPrepare,DGTapUnprepare,DGTapProcess};MTAudioProcessingTapRef tap=nullptr;
    OSStatus status=MTAudioProcessingTapCreate(kCFAllocatorDefault,&callbacks,kMTAudioProcessingTapCreationFlag_PostEffects,&tap);
    if(status!=noErr){delete static_cast<DGAudioTapState *>(callbacks.clientInfo);continue;}
    AVMutableAudioMixInputParameters *input=[AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];input.audioTapProcessor=tap;CFRelease(tap);[inputs addObject:input];
   }
   if(inputs.count){AVMutableAudioMix *mix=[AVMutableAudioMix audioMix];mix.inputParameters=inputs;current.audioMix=mix;}
  });
 }];
 }];
}
