#import "DGCommon.h"
#import <MediaToolbox/MediaToolbox.h>
#import <objc/runtime.h>
#include <atomic>
#include <array>
#include <cstdint>

namespace {
std::atomic<float> Gains[3];std::atomic<unsigned> Revision{1};
struct Band{double b0=1,b1=0,b2=0,a1=0,a2=0;};
struct State{AudioStreamBasicDescription format{};Band bands[3];double z1[8][3]{},z2[8][3]{};unsigned revision=0;double headroom=1;};
void Init(MTAudioProcessingTapRef,void *client,void **storage){*storage=client;}
void Finalize(MTAudioProcessingTapRef tap){delete static_cast<State *>(MTAudioProcessingTapGetStorage(tap));}
void Prepare(MTAudioProcessingTapRef tap,CMItemCount,const AudioStreamBasicDescription *format){State *state=static_cast<State *>(MTAudioProcessingTapGetStorage(tap));state->format=*format;state->revision=0;for(auto &row:state->z1)for(double &value:row)value=0;for(auto &row:state->z2)for(double &value:row)value=0;}
void Unprepare(MTAudioProcessingTapRef){}
void Update(State &state){unsigned revision=Revision.load(std::memory_order_acquire);if(revision==state.revision)return;state.revision=revision;const double frequencies[3]={100,1000,8000};double maxGain=0,sampleRate=state.format.mSampleRate;if(sampleRate<1)return;
 for(int index=0;index<3;index++){double gain=Gains[index].load(std::memory_order_relaxed);maxGain=std::max(maxGain,gain);double a=std::pow(10.,gain/40),w=2*M_PI*std::min(frequencies[index],sampleRate*.44)/sampleRate,alpha=std::sin(w)/2,den=1+alpha/a;state.bands[index]={(1+alpha*a)/den,(-2*std::cos(w))/den,(1-alpha*a)/den,(-2*std::cos(w))/den,(1-alpha/a)/den};}state.headroom=std::pow(10.,-maxGain/20);
}
double Filter(State &state,double input,unsigned channel){double value=input*state.headroom;for(int index=0;index<3;index++){const Band &b=state.bands[index];double output=b.b0*value+state.z1[channel][index];state.z1[channel][index]=b.b1*value-b.a1*output+state.z2[channel][index];state.z2[channel][index]=b.b2*value-b.a2*output;value=output;}return std::clamp(value,-1.,1.);}
void Process(MTAudioProcessingTapRef tap,CMItemCount frames,MTAudioProcessingTapFlags,AudioBufferList *buffers,CMItemCount *produced,MTAudioProcessingTapFlags *flags){
 if(MTAudioProcessingTapGetSourceAudio(tap,frames,buffers,flags,nullptr,produced)!=noErr){*produced=0;return;}State &state=*static_cast<State *>(MTAudioProcessingTapGetStorage(tap));Update(state);if(state.format.mFormatID!=kAudioFormatLinearPCM||(state.format.mFormatFlags&kAudioFormatFlagIsBigEndian))return;bool floating=state.format.mFormatFlags&kAudioFormatFlagIsFloat,signedInt=state.format.mFormatFlags&kAudioFormatFlagIsSignedInteger;unsigned bits=state.format.mBitsPerChannel,channelBase=0;
 for(UInt32 bufferIndex=0;bufferIndex<buffers->mNumberBuffers;bufferIndex++){AudioBuffer &buffer=buffers->mBuffers[bufferIndex];unsigned channels=std::max(1u,buffer.mNumberChannels),bytes=bits/8;if(!buffer.mData||!bytes){channelBase+=channels;continue;}std::size_t samples=std::min<std::size_t>(*produced*channels,buffer.mDataByteSize/bytes);for(std::size_t sample=0;sample<samples;sample++){unsigned channel=channelBase+sample%channels;if(channel>=8)continue;if(floating&&bits==32){auto *values=static_cast<float *>(buffer.mData);values[sample]=Filter(state,values[sample],channel);}else if(floating&&bits==64){auto *values=static_cast<double *>(buffer.mData);values[sample]=Filter(state,values[sample],channel);}else if(signedInt&&bits==16){auto *values=static_cast<int16_t *>(buffer.mData);values[sample]=static_cast<int16_t>(Filter(state,values[sample]/32768.,channel)*32767);}else if(signedInt&&bits==32){auto *values=static_cast<int32_t *>(buffer.mData);values[sample]=static_cast<int32_t>(Filter(state,values[sample]/2147483648.,channel)*2147483647);}}channelBase+=channels;}
}
}
static NSHashTable<AVPlayerItem *> *Items(){static NSHashTable *items;static dispatch_once_t once;dispatch_once(&once,^{items=[NSHashTable weakObjectsHashTable];});return items;}
static const void *PendingKey=&PendingKey;
static void Apply(AVPlayerItem *item){
 BOOL spatial=[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.dolby"];item.allowedAudioSpatializationFormats=spatial?AVAudioSpatializationFormatMonoAndStereo|AVAudioSpatializationFormatMultichannel:AVAudioSpatializationFormatNone;
 BOOL enabled=[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.eq.enabled"]&&!spatial;NSUInteger nonce=[objc_getAssociatedObject(item,PendingKey)unsignedIntegerValue]+1;objc_setAssociatedObject(item,PendingKey,@(nonce),OBJC_ASSOCIATION_RETAIN_NONATOMIC);if(!enabled){item.audioMix=nil;return;}if(item.audioMix)return;
 __weak AVPlayerItem *weak=item;[item.asset loadTracksWithMediaType:AVMediaTypeAudio completionHandler:^(NSArray<AVAssetTrack *> *tracks,NSError *error){dispatch_async(dispatch_get_main_queue(),^{AVPlayerItem *item=weak;if(!item||[objc_getAssociatedObject(item,PendingKey)unsignedIntegerValue]!=nonce||error)return;NSMutableArray *parameters=[NSMutableArray array];for(AVAssetTrack *track in tracks){State *state=new State;MTAudioProcessingTapCallbacks callbacks={kMTAudioProcessingTapCallbacksVersion_0,state,Init,Finalize,Prepare,Unprepare,Process};MTAudioProcessingTapRef tap=nullptr;OSStatus status=MTAudioProcessingTapCreate(kCFAllocatorDefault,&callbacks,kMTAudioProcessingTapCreationFlag_PostEffects,&tap);if(status!=noErr||!tap){delete state;continue;}AVMutableAudioMixInputParameters *input=[AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];input.audioTapProcessor=tap;CFRelease(tap);[parameters addObject:input];}if(parameters.count){AVMutableAudioMix *mix=[AVMutableAudioMix audioMix];mix.inputParameters=parameters;item.audioMix=mix;}});}];
}
void DGConfigureAudio(AVPlayerItem *item){if(!item)return;static dispatch_once_t once;dispatch_once(&once,^{DGRefreshAudioPreferences();});[Items()addObject:item];Apply(item);}
void DGRefreshAudioPreferences(void){NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;NSArray *keys=@[@"douglass.eq.low",@"douglass.eq.mid",@"douglass.eq.high"];for(NSUInteger i=0;i<3;i++)Gains[i].store(std::clamp([prefs floatForKey:keys[i]],-12.f,12.f),std::memory_order_relaxed);Revision.fetch_add(1,std::memory_order_release);[AVAudioSession sharedInstance].supportsMultichannelContent=[prefs boolForKey:@"douglass.dolby"];for(AVPlayerItem *item in Items().allObjects)Apply(item);}
