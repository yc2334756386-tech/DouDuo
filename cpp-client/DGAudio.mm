#import "DGAudio.h"
#import <MediaToolbox/MediaToolbox.h>
#import <objc/runtime.h>
#include "AudioDSP.hpp"

using namespace douglass::audio;
namespace {
struct TapState {State dsp;AudioStreamBasicDescription format{};};
void Init(MTAudioProcessingTapRef,void *client,void **storage){*storage=client;}
void Finalize(MTAudioProcessingTapRef tap){delete static_cast<TapState *>(MTAudioProcessingTapGetStorage(tap));}
void Prepare(MTAudioProcessingTapRef tap,CMItemCount,const AudioStreamBasicDescription *format){
 auto &tapState=*static_cast<TapState *>(MTAudioProcessingTapGetStorage(tap));
 tapState.format=*format;
 tapState.dsp.sampleRate=format->mSampleRate;
 tapState.dsp.revision=0;
 tapState.dsp.metrics->channels=format->mChannelsPerFrame;
 Reset(tapState.dsp);
}
void Unprepare(MTAudioProcessingTapRef){}
void Process(MTAudioProcessingTapRef tap,CMItemCount frames,MTAudioProcessingTapFlags,AudioBufferList *buffers,CMItemCount *produced,MTAudioProcessingTapFlags *flags){
 auto &tapState=*static_cast<TapState *>(MTAudioProcessingTapGetStorage(tap));
 State &s=tapState.dsp;
 if(MTAudioProcessingTapGetSourceAudio(tap,frames,buffers,flags,nullptr,produced)!=noErr){s.metrics->faults.fetch_add(1);*produced=0;return;}
 if(!*produced)return;if(*flags&kMTAudioProcessingTapFlag_StartOfStream)Reset(s);
 double rate=tapState.format.mSampleRate;unsigned bits=tapState.format.mBitsPerChannel;
 bool floating=tapState.format.mFormatFlags&kAudioFormatFlagIsFloat,signedInt=tapState.format.mFormatFlags&kAudioFormatFlagIsSignedInteger;
 bool supported=rate>0&&tapState.format.mFormatID==kAudioFormatLinearPCM&&!(tapState.format.mFormatFlags&kAudioFormatFlagIsBigEndian)&&((floating&&(bits==32||bits==64))||(signedInt&&(bits==16||bits==32)));
 s.metrics->supported=supported;if(!supported)return;
 Channel channels[MaxChannels];unsigned count=0;
 for(UInt32 b=0;b<buffers->mNumberBuffers;b++){AudioBuffer &buffer=buffers->mBuffers[b];if(!buffer.mData)continue;unsigned stride=std::max(1u,buffer.mNumberChannels);for(unsigned i=0;i<stride&&count<MaxChannels;i++)channels[count++]={buffer.mData,stride,i,buffer.mDataByteSize/(bits/8)};}
 if(!count)return;s.metrics->channels=count;
 ProcessSamples(s,channels,count,*produced,floating,bits);
}
}
@interface DGAudioProbe:NSObject{@public std::shared_ptr<Metrics> metrics;}
@property(nonatomic) BOOL bypassed;
@property(nonatomic,copy) NSString *message;
@end
@implementation DGAudioProbe
- (instancetype)init{if((self=[super init]))metrics=std::make_shared<Metrics>();return self;}
@end
static NSHashTable<AVPlayerItem *> *Items(){static NSHashTable *items;static dispatch_once_t once;dispatch_once(&once,^{items=[NSHashTable weakObjectsHashTable];});return items;}
static const void *PendingKey=&PendingKey,*ProbeKey=&ProbeKey;
static __weak AVPlayer *ActivePlayer;
BOOL DGAirPodsConnected(void){for(AVAudioSessionPortDescription *output in AVAudioSession.sharedInstance.currentRoute.outputs){BOOL bluetooth=[@[AVAudioSessionPortBluetoothA2DP,AVAudioSessionPortBluetoothLE,AVAudioSessionPortBluetoothHFP]containsObject:output.portType];if(bluetooth&&[output.portName rangeOfString:@"AirPods" options:NSCaseInsensitiveSearch].location!=NSNotFound)return YES;}return NO;}
NSString *DGAudioOutputName(void){NSMutableArray *names=[NSMutableArray array];for(AVAudioSessionPortDescription *output in AVAudioSession.sharedInstance.currentRoute.outputs)[names addObject:output.portName];return [names componentsJoinedByString:@" · "];}
static AVMutableAudioMixInputParameters *TapParameters(AVAssetTrack *track,DGAudioProbe *probe,BOOL mixed){
 TapState *state=new TapState;state->dsp.metrics=probe->metrics;
 MTAudioProcessingTapCallbacks callbacks={kMTAudioProcessingTapCallbacksVersion_0,state,Init,Finalize,Prepare,Unprepare,Process};MTAudioProcessingTapRef tap=nullptr;OSStatus status;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
 if(@available(iOS 27.0,*))status=MTAudioProcessingTapCreateWithPreferredFormat(kCFAllocatorDefault,&callbacks,kMTAudioProcessingTapCreationFlag_PostEffects,nullptr,&tap);
 else
#endif
 status=MTAudioProcessingTapCreate(kCFAllocatorDefault,&callbacks,kMTAudioProcessingTapCreationFlag_PostEffects,&tap);
 if(status!=noErr||!tap){delete state;probe.message=@"当前音轨无法建立音效处理，保留原声";return nil;}
 AVMutableAudioMixInputParameters *input=[AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
 if(@available(iOS 27.0,*)){if(mixed)input.trackID=AVAudioMixInputParametersTrackMixID;}
#endif
 input.audioTapProcessor=tap;CFRelease(tap);return input;
}
static void Apply(AVPlayerItem *item){
 if(!item)return;NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;BOOL spatial=[prefs boolForKey:@"douglass.dolby"];
 auto formats=spatial?AVAudioSpatializationFormatMonoAndStereo|AVAudioSpatializationFormatMultichannel:AVAudioSpatializationFormatNone;
 if(item.allowedAudioSpatializationFormats!=formats)item.allowedAudioSpatializationFormats=formats;
 BOOL enabled=[prefs boolForKey:@"douglass.eq.enabled"];
 if(!enabled){objc_setAssociatedObject(item,PendingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);if(item.audioMix)item.audioMix=nil;return;}
 DGAudioProbe *probe=objc_getAssociatedObject(item,ProbeKey);if(probe.bypassed||item.audioMix||objc_getAssociatedObject(item,PendingKey))return;
 probe=[DGAudioProbe new];objc_setAssociatedObject(item,ProbeKey,probe,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
 if(@available(iOS 27.0,*)){AVMutableAudioMixInputParameters *input=TapParameters(nil,probe,YES);if(input){AVMutableAudioMix *mix=[AVMutableAudioMix audioMix];mix.inputParameters=@[input];item.audioMix=mix;}return;}
#endif
 // Older systems use per-track processing. HLS does not support this route.
 if([item.asset isKindOfClass:AVURLAsset.class]&&[[((AVURLAsset *)item.asset).URL.absoluteString lowercaseString]containsString:@".m3u8"]){probe.message=@"当前系统的 HLS 音轨不支持自定义 EQ，保留原声";return;}
 NSObject *pending=[NSObject new];objc_setAssociatedObject(item,PendingKey,pending,OBJC_ASSOCIATION_RETAIN_NONATOMIC);__weak AVPlayerItem *weak=item;
 [item.asset loadTracksWithMediaType:AVMediaTypeAudio completionHandler:^(NSArray<AVAssetTrack *> *tracks,NSError *error){dispatch_async(dispatch_get_main_queue(),^{AVPlayerItem *item=weak;if(!item||objc_getAssociatedObject(item,PendingKey)!=pending)return;objc_setAssociatedObject(item,PendingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);if(![NSUserDefaults.standardUserDefaults boolForKey:@"douglass.eq.enabled"])return;if(error||!tracks.count){probe.message=@"尚未取得可处理音轨，当前保持原声";return;}NSMutableArray *parameters=[NSMutableArray array];for(AVAssetTrack *track in tracks){AVMutableAudioMixInputParameters *input=TapParameters(track,probe,NO);if(input)[parameters addObject:input];}if(parameters.count){AVMutableAudioMix *mix=[AVMutableAudioMix audioMix];mix.inputParameters=parameters;item.audioMix=mix;}});}];
}
@interface DGAudioRouteObserver:NSObject
@end
@implementation DGAudioRouteObserver
- (void)interruption:(NSNotification *)note{if([note.userInfo[AVAudioSessionInterruptionTypeKey]integerValue]==AVAudioSessionInterruptionTypeEnded&&([note.userInfo[AVAudioSessionInterruptionOptionKey]unsignedIntegerValue]&AVAudioSessionInterruptionOptionShouldResume)){[AVAudioSession.sharedInstance setActive:YES error:nil];[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}}
- (void)changed:(NSNotification *)note{DGRefreshAudioPreferences();[NSNotificationCenter.defaultCenter postNotificationName:@"DGAudioRouteChanged" object:nil];}
@end
void DGConfigureAudio(AVPlayerItem *item){if(!item)return;static dispatch_once_t once;dispatch_once(&once,^{static DGAudioRouteObserver *observer;observer=[DGAudioRouteObserver new];[NSNotificationCenter.defaultCenter addObserver:observer selector:@selector(changed:) name:AVAudioSessionRouteChangeNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:observer selector:@selector(interruption:) name:AVAudioSessionInterruptionNotification object:nil];DGRefreshAudioPreferences();});[Items()addObject:item];Apply(item);}
void DGRefreshAudioPreferences(void){
 NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;NSArray *old=@[@"douglass.eq.low",@"douglass.eq.mid",@"douglass.eq.high"];
 for(int i=0;i<N;i++){id gain=[prefs objectForKey:[NSString stringWithFormat:@"douglass.eq.gain.%d",i]],frequency=[prefs objectForKey:[NSString stringWithFormat:@"douglass.eq.freq.%d",i]],q=[prefs objectForKey:[NSString stringWithFormat:@"douglass.eq.q.%d",i]];Gains[i].store(std::clamp(gain?[gain floatValue]:[prefs floatForKey:old[i<3?0:i<7?1:2]],-18.f,18.f));Frequencies[i].store(frequency?std::clamp([frequency floatValue],20.f,20000.f):DefaultF[i]);Quality[i].store(q?std::clamp([q floatValue],.2f,8.f):1.1f);}
 NSArray *keys=@[@"tone.low",@"tone.mid",@"tone.high",@"width",@"room",@"mix",@"transparency",@"clarity",@"dynamics",@"bass",@"airpods.strength"];
 for(int i=0;i<EffectCount;i++){id value=[prefs objectForKey:[@"douglass.audio." stringByAppendingString:keys[i]]];float number=value?[value floatValue]:i==Mix?100:i==AirStrength?60:0;Effects[i].store(std::clamp(number,i<=High?-100.f:0.f,100.f));}
 Adaptive=[prefs boolForKey:@"douglass.eq.adaptive"];ListeningStyle=std::clamp((int)[prefs integerForKey:@"douglass.eq.style"],0,4);AirPods=DGAirPodsConnected();Enhance=[prefs boolForKey:@"douglass.airpods.enhance"];SystemSpatial=[prefs boolForKey:@"douglass.dolby"];Revision.fetch_add(1,std::memory_order_release);
 if(AVAudioSession.sharedInstance.supportsMultichannelContent!=[prefs boolForKey:@"douglass.dolby"])[AVAudioSession.sharedInstance setSupportsMultichannelContent:[prefs boolForKey:@"douglass.dolby"] error:nil];for(AVPlayerItem *item in Items().allObjects)Apply(item);
}
void DGRepairPlayerAudio(AVPlayer *player){if(!player)return;ActivePlayer=player;if(player.muted)player.muted=NO;if(player.volume<.99)player.volume=1;DGAudioProbe *probe=objc_getAssociatedObject(player.currentItem,ProbeKey);if(probe&&probe->metrics->faults.load()>=3&&!probe.bypassed){probe.bypassed=YES;player.currentItem.audioMix=nil;}BOOL selected=NO;AVPlayerItemTrack *candidate=nil;for(AVPlayerItemTrack *track in player.currentItem.tracks)if([track.assetTrack.mediaType isEqualToString:AVMediaTypeAudio]){if(track.enabled)selected=YES;if(!candidate)candidate=track;}if(!selected&&candidate)candidate.enabled=YES;}
void DGSetAudioMetering(BOOL enabled){Metering=enabled;}
NSDictionary *DGAudioSnapshot(void){DGAudioProbe *probe=objc_getAssociatedObject(ActivePlayer.currentItem,ProbeKey);NSMutableArray *levels=[NSMutableArray array],*adjust=[NSMutableArray array];BOOL attached=ActivePlayer.currentItem.audioMix!=nil;for(int i=0;i<N;i++){[levels addObject:@(probe&&attached&&ActivePlayer.rate>0?probe->metrics->levels[i].load():0)];[adjust addObject:@(probe?probe->metrics->adjust[i].load():0)];}return @{@"levels":levels,@"adjust":adjust,@"frames":@(probe?probe->metrics->frames.load():0),@"channels":@(probe?probe->metrics->channels.load():0),@"peak":@(probe?probe->metrics->peak.load():0),@"supported":@(!probe||probe->metrics->supported.load()),@"bypassed":@(probe.bypassed),@"playing":@(ActivePlayer.rate>0),@"attached":@(attached),@"message":probe.message?:@""};}
