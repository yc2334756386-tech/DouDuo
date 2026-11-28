#pragma once
#include <cstdint>
#include <memory>
namespace douglass {
inline constexpr unsigned metalFXScale = 2;
struct PicturePreset{double saturation=1,contrast=1,brightness=0,texture=0,clarity=0;};
PicturePreset picturePreset(unsigned index) noexcept;
class SpatialUpscaler {
public:
    explicit SpatialUpscaler(void *device);
    ~SpatialUpscaler();
    bool encode(void *command,void *input,void *output,bool hdr);
private:
    struct State;std::unique_ptr<State> state_;
};
}
