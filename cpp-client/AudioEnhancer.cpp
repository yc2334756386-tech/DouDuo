#include "AudioEnhancer.hpp"
#include <algorithm>
#include <cmath>
#include <numbers>
namespace douglass {
AudioControls &audioControls() noexcept{static AudioControls controls;return controls;}
double AudioEnhancer::Biquad::tick(double x,unsigned c) noexcept{double y=b0*x+z1[c];z1[c]=b1*x-a1*y+z2[c];z2[c]=b2*x-a2*y;if(!std::isfinite(y)){z1[c]=z2[c]=0;return 0;}return y;}
void AudioEnhancer::prepare(double rate,unsigned channels) noexcept{sampleRate_=std::isfinite(rate)&&rate>8000?rate:48000;channels_=std::clamp(channels,1u,8u);current_.fill(0);preamp_=1;reset();for(unsigned i=0;i<8;++i)configure(i,0);}
void AudioEnhancer::reset() noexcept{for(auto &filter:filters_){filter.z1.fill(0);filter.z2.fill(0);}low_=mid_=high_=slow_=fast_=0;analyzed_=0;}
void AudioEnhancer::configure(unsigned band,double gain) noexcept{
 static constexpr double frequencies[]{60,150,400,1000,2400,5000,9000,14000};double omega=2*std::numbers::pi*std::min(frequencies[band],sampleRate_*.44)/sampleRate_,a=std::pow(10.,gain/40.),alpha=std::sin(omega)/(2*.8),cosine=std::cos(omega),a0=1+alpha/a;auto &f=filters_[band];f.b0=(1+alpha*a)/a0;f.b1=-2*cosine/a0;f.b2=(1-alpha*a)/a0;f.a1=-2*cosine/a0;f.a2=(1-alpha/a)/a0;
}
void AudioEnhancer::process(float *const *data,unsigned buffers,unsigned channels,std::size_t frames,bool interleaved) noexcept{
 auto &controls=audioControls();if(!controls.enabled.load(std::memory_order_relaxed)||!data||!frames)return;channels=std::min({channels,channels_,8u});if(!channels||(!interleaved&&buffers<channels)||!data[0])return;
 const bool adaptive=controls.adaptive.load(std::memory_order_relaxed);const int style=controls.style.load(std::memory_order_relaxed);double maximum=0;
 for(unsigned band=0;band<8;++band){double target=std::clamp(double(controls.gains[band].load(std::memory_order_relaxed)),-12.,12.);if(adaptive&&analyzed_>sampleRate_/2){double power=band<2?low_:band<5?mid_:high_,reference=(low_+mid_+high_)/3+1e-8;double correction=std::clamp(3.*std::log10(reference/(power+1e-8)),-2.5,2.5);if(style==1&&band>=2&&band<=4)correction+=1.;if(style==2&&band<2)correction+=1.5;if(style==3&&band>5)correction-=1.5;target+=correction;}current_[band]+=(target-current_[band])*.035;configure(band,current_[band]);maximum=std::max(maximum,current_[band]);}
 preamp_+=(std::pow(10.,-(maximum+1.)/20)-preamp_)*.04;double slowAlpha=1-std::exp(-2*std::numbers::pi*250/sampleRate_),fastAlpha=1-std::exp(-2*std::numbers::pi*4000/sampleRate_),envelope=1-std::exp(-1./sampleRate_);
 for(std::size_t frame=0;frame<frames;++frame){double mono=0;for(unsigned c=0;c<channels;++c){if(!interleaved&&!data[c])continue;float &sample=interleaved?data[0][frame*channels+c]:data[c][frame];double input=std::isfinite(sample)?sample:0;mono+=input/channels;double value=input*preamp_;for(auto &filter:filters_)value=filter.tick(value,c);sample=static_cast<float>(std::clamp(value,-.98,.98));}slow_+=(mono-slow_)*slowAlpha;fast_+=(mono-fast_)*fastAlpha;double low=slow_,mid=fast_-slow_,high=mono-fast_;low_+=(low*low-low_)*envelope;mid_+=(mid*mid-mid_)*envelope;high_+=(high*high-high_)*envelope;}analyzed_+=frames;
}
}
