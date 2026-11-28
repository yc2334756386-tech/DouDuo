#pragma once
#include <array>
#include <atomic>
#include <cstddef>
namespace douglass {
struct AudioControls{
 std::atomic_bool enabled{false},adaptive{false};std::atomic_int style{0};
 std::array<std::atomic<float>,8> gains{};
};
AudioControls &audioControls() noexcept;
class AudioEnhancer{
public:
 void prepare(double sampleRate,unsigned channels) noexcept;
 void reset() noexcept;
 void process(float *const *data,unsigned buffers,unsigned channels,std::size_t frames,bool interleaved) noexcept;
private:
 struct Biquad{double b0=1,b1=0,b2=0,a1=0,a2=0;std::array<double,8> z1{},z2{};double tick(double input,unsigned channel) noexcept;};
 std::array<Biquad,8> filters_{};std::array<double,8> current_{};double sampleRate_=48000,low_=0,mid_=0,high_=0,slow_=0,fast_=0,preamp_=1;unsigned channels_=2;std::size_t analyzed_=0;
 void configure(unsigned band,double gain) noexcept;
};
}
