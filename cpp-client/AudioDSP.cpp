#include "AudioDSP.hpp"
#include <algorithm>
#include <cmath>

namespace douglass::audio {
std::atomic<float> Gains[N],Frequencies[N],Quality[N],Effects[EffectCount];
std::atomic<unsigned> Revision{1};
std::atomic<bool> Adaptive{false},AirPods{false},Enhance{false},Metering{false},SystemSpatial{false};
std::atomic<int> ListeningStyle{0};
Band Peak(double frequency,double quality,double gain,double rate){
 double a=pow(10.,gain/40),w=2*M_PI*std::clamp(frequency,10.,rate*.44)/rate,alpha=sin(w)/(2*quality),den=1+alpha/a;
 return {(1+alpha*a)/den,(-2*cos(w))/den,(1-alpha*a)/den,(-2*cos(w))/den,(1-alpha/a)/den};
}
Band Shelf(double frequency,double gain,double rate,bool high){
 double a=pow(10.,gain/40),w=2*M_PI*std::clamp(frequency,10.,rate*.44)/rate,c=cos(w),root=2*sqrt(a)*sin(w)/sqrt(2.),d;
 if(high){d=(a+1)-(a-1)*c+root;return {a*((a+1)+(a-1)*c+root)/d,-2*a*((a-1)+(a+1)*c)/d,a*((a+1)+(a-1)*c-root)/d,2*((a-1)-(a+1)*c)/d,((a+1)-(a-1)*c-root)/d};}
 d=(a+1)+(a-1)*c+root;return {a*((a+1)-(a-1)*c+root)/d,2*a*((a-1)-(a+1)*c)/d,a*((a+1)-(a-1)*c-root)/d,-2*((a-1)+(a+1)*c)/d,((a+1)+(a-1)*c-root)/d};
}
Band Pass(double frequency,double rate){double w=2*M_PI*std::min(frequency,rate*.44)/rate,alpha=sin(w)/(2*.9),den=1+alpha;return {alpha/den,0,-alpha/den,-2*cos(w)/den,(1-alpha)/den};}
double Run(const Band &band,Memory &memory,double input){double out=band.b0*input+memory.a;memory.a=band.b1*input-band.a1*out+memory.b;memory.b=band.b2*input-band.a2*out;if(!std::isfinite(out)){memory={};return input;}return out;}
void Reset(State &s){for(auto &channel:s.history)for(auto &m:channel)m={};for(auto &channel:s.toneHistory)for(auto &m:channel)m={};for(auto &m:s.analysisHistory)m={};for(auto &channel:s.delay)channel.fill(0);s.position=0;s.envelope=0;s.limiter=1;}
void Update(State &s){
 unsigned revision=Revision.load(std::memory_order_acquire);if(revision==s.revision)return;s.revision=revision;
 double rate=s.sampleRate;if(rate<1)return;
 for(int i=0;i<N;i++){s.target[i]=Gains[i].load();s.frequency[i]=Frequencies[i].load();s.q[i]=Quality[i].load();s.analysis[i]=Pass(s.frequency[i],rate);}
 for(int i=0;i<EffectCount;i++)s.effect[i]=Effects[i].load();
 s.spatial=SystemSpatial.load();
 double air=AirPods.load()&&Enhance.load()?s.effect[AirStrength]/100:0;
 // Independent tonal controls; all are frequency-selective, not a master-volume adjustment.
 s.tone[0]=Shelf(160,s.effect[Low]*.09+s.effect[Bass]*.075+air*2.5,rate,false);
 s.tone[1]=Peak(1050,.65,s.effect[Mid]*.09,rate);
 s.tone[2]=Shelf(5200,s.effect[High]*.09+s.effect[Transparency]*.025+air*1.5,rate,true);
 s.tone[3]=Peak(330,.8,-s.effect[Transparency]*.045-air,rate);
 s.tone[4]=Peak(2900,.85,s.effect[Clarity]*.055+air*2,rate);
 s.tone[5]=Peak(90,.8,air*1.8,rate);
 for(int i=0;i<6;i++)s.toneActive[i]=fabs(s.tone[i].b0-1)>1e-8;
}
double Read(const Channel &c,size_t frame,bool floating,unsigned bits){size_t index=frame*c.stride+c.offset;if(index>=c.samples)return 0;if(floating&&bits==32)return static_cast<float *>(c.data)[index];if(floating&&bits==64)return static_cast<double *>(c.data)[index];if(bits==16)return static_cast<int16_t *>(c.data)[index]/32768.;return static_cast<int32_t *>(c.data)[index]/2147483648.;}
void Write(const Channel &c,size_t frame,double value,bool floating,unsigned bits){size_t index=frame*c.stride+c.offset;if(index>=c.samples)return;if(floating&&bits==32)static_cast<float *>(c.data)[index]=value;else if(floating&&bits==64)static_cast<double *>(c.data)[index]=value;else if(bits==16)static_cast<int16_t *>(c.data)[index]=int16_t(value*32767);else static_cast<int32_t *>(c.data)[index]=int32_t(value*2147483647);}
void ProcessSamples(State &s,const Channel *channels,unsigned count,size_t frames,bool floating,unsigned bits){
 Update(s);const double rate=s.sampleRate;
 const double styles[5][N]={{0,0,0,0,0,0,0,0,0,0},{-2,-2,-1,0,1,2,2,1,0,-1},{2,2,1,0,0,0,-1,-1,-1,-2},{-1,-1,0,0,0,1,2,2,2,1},{-1,-1,0,0,0,-1,-2,-2,-3,-3}};
 bool adaptive=Adaptive.load(),analyze=adaptive||Metering.load();int style=std::clamp(ListeningStyle.load(),0,4);
 double smooth=1-exp(-double(frames)/rate/.045),autoSmooth=1-exp(-double(frames)/rate/.8),mean=0,sums[N]{};
 if(adaptive){for(double energy:s.energy)mean+=10*log10(std::max(1e-9,energy));mean/=N;}
 for(int i=0;i<N;i++){double db=10*log10(std::max(1e-9,s.energy[i]));double correction=adaptive&&mean>-75?std::clamp((mean-db)*.16+styles[style][i],-4.5,4.5):0;s.correction[i]+=(correction-s.correction[i])*autoSmooth;s.current[i]+=(std::clamp(s.target[i]+s.correction[i],-18.,18.)-s.current[i])*smooth;s.bands[i]=Peak(s.frequency[i],s.q[i],s.current[i],rate);s.metrics->adjust[i].store(s.correction[i],std::memory_order_relaxed);}
 double wetMix=std::clamp(s.effect[Mix]/100,0.,1.),width=s.spatial?0:s.effect[Width]/100*.85,room=s.spatial?0:s.effect[Room]/100;
 if(wetMix==0&&!analyze){s.metrics->frames.fetch_add(frames,std::memory_order_relaxed);return;}
 bool bandActive[N]{};for(int i=0;i<N;i++)bandActive[i]=fabs(s.current[i])>.01;
 double dynamics=s.effect[Dynamics]/100,attack=exp(-1/(rate*.003)),release=exp(-1/(rate*.12)),limiterRelease=exp(-1/(rate*.065)),peak=0;
 unsigned delays[4]={unsigned(std::min(rate*.031,double(DelaySize-1))),unsigned(std::min(rate*.043,double(DelaySize-1))),unsigned(std::min(rate*.067,double(DelaySize-1))),unsigned(std::min(rate*.089,double(DelaySize-1)))};
 for(size_t frame=0;frame<frames;frame++){
  double dry[MaxChannels]{},wet[MaxChannels]{},samplePeak=0;
  for(unsigned c=0;c<count;c++){double sample=Read(channels[c],frame,floating,bits);dry[c]=std::isfinite(sample)?sample:0;double out=dry[c];if(wetMix>0){for(int i=0;i<N;i++)if(bandActive[i])out=Run(s.bands[i],s.history[c][i],out);for(int i=0;i<6;i++)if(s.toneActive[i])out=Run(s.tone[i],s.toneHistory[c][i],out);}wet[c]=out;}
  if(analyze){double mono=count>1?(dry[0]+dry[1])*.5:dry[0];for(int i=0;i<N;i++){double value=Run(s.analysis[i],s.analysisHistory[i],mono);sums[i]+=value*value;}}
  if(wetMix==0)continue;
  if(count==2&&(width>0||room>0)){double mid=(wet[0]+wet[1])*.5,side=(wet[0]-wet[1])*.5*(1+width);wet[0]=mid+side;wet[1]=mid-side;
   if(room>0){unsigned p=s.position;double left=s.delay[0][(p-delays[0])&(DelaySize-1)]*.46+s.delay[1][(p-delays[2])&(DelaySize-1)]*.24,right=s.delay[1][(p-delays[1])&(DelaySize-1)]*.46+s.delay[0][(p-delays[3])&(DelaySize-1)]*.24;s.delay[0][p]=std::clamp(wet[0]+left*.2,-3.,3.);s.delay[1][p]=std::clamp(wet[1]+right*.2,-3.,3.);wet[0]+=left*room*.45;wet[1]+=right*room*.45;s.position=(p+1)&(DelaySize-1);}
  }
  for(unsigned c=0;c<count;c++)samplePeak=std::max(samplePeak,fabs(wet[c]));
  s.envelope=(samplePeak>s.envelope?attack:release)*s.envelope+(1-(samplePeak>s.envelope?attack:release))*samplePeak;
  double compression=dynamics>0?(1+dynamics*.28)/(1+dynamics*3*std::max(0.,s.envelope-.2)):1,maximum=0;
  for(unsigned c=0;c<count;c++){wet[c]=dry[c]+wetMix*(wet[c]*compression-dry[c]);maximum=std::max(maximum,fabs(wet[c]));}
  double limit=maximum>.97?.97/maximum:1;s.limiter=limit<s.limiter?limit:limiterRelease*s.limiter+(1-limiterRelease)*limit;
  for(unsigned c=0;c<count;c++){double out=wet[c]*s.limiter;if(!std::isfinite(out))out=dry[c];out=std::clamp(out,-.999, .999);Write(channels[c],frame,out,floating,bits);peak=std::max(peak,fabs(out));}
 }
 if(analyze)for(int i=0;i<N;i++){s.energy[i]+=(sums[i]/double(frames)-s.energy[i])*autoSmooth;double db=10*log10(std::max(1e-9,s.energy[i]));s.metrics->levels[i].store(std::clamp((db+72)/60.,0.,1.),std::memory_order_relaxed);}
 s.metrics->peak=peak;s.metrics->frames.fetch_add(frames,std::memory_order_relaxed);
}
}
