#pragma once
#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>

namespace douglass::audio {
inline constexpr int N=10, MaxChannels=8, DelaySize=16384;
inline constexpr double DefaultF[N]={63,122,225,416,770,1420,2640,4890,9060,13890};
enum Effect {Low,Mid,High,Width,Room,Mix,Transparency,Clarity,Dynamics,Bass,AirStrength,EffectCount};
extern std::atomic<float> Gains[N], Frequencies[N], Quality[N], Effects[EffectCount];
extern std::atomic<unsigned> Revision;
extern std::atomic<bool> Adaptive, AirPods, Enhance, Metering, SystemSpatial;
extern std::atomic<int> ListeningStyle;
struct Band {double b0=1,b1=0,b2=0,a1=0,a2=0;};
struct Memory {double a=0,b=0;};
struct Metrics {
 std::atomic<float> levels[N],adjust[N],peak{0};
 std::atomic<unsigned> faults{0},channels{0};
 std::atomic<uint64_t> frames{0};
 std::atomic<bool> supported{true};
 Metrics(){for(int i=0;i<N;i++){levels[i]=0;adjust[i]=0;}}
};
struct State {
 double sampleRate=0;
 Band bands[N],analysis[N],tone[6];Memory history[MaxChannels][N],toneHistory[MaxChannels][6],analysisHistory[N];
 double energy[N]{},correction[N]{},target[N]{},current[N]{},frequency[N]{},q[N]{},effect[EffectCount]{};
 std::array<std::array<float,DelaySize>,2> delay{};
 unsigned revision=0,position=0;double envelope=0,limiter=1;bool spatial=false;
 bool toneActive[6]{};
 std::shared_ptr<Metrics> metrics;
};
struct Channel {void *data=nullptr;unsigned stride=1,offset=0;size_t samples=0;};
void Reset(State &state);
void ProcessSamples(State &state,const Channel *channels,unsigned channelCount,size_t frames,bool floating,unsigned bits);
}
