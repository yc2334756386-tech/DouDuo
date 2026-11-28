#pragma once
#include <cstdint>
#include <memory>
namespace douglass {
enum class ExperimentalMediaFeature : std::uint8_t { spatialSampling=0, frameInterpolation=1 };
bool experimentalMediaRequested(ExperimentalMediaFeature feature,bool stored) noexcept;
struct PicturePreset{double saturation=1,contrast=1,brightness=0;};
PicturePreset picturePreset(unsigned index) noexcept;
class SpatialUpscaler {
public:
    explicit SpatialUpscaler(void *device);
    ~SpatialUpscaler();
    bool encode(void *command,void *input,void *output);
private:
    struct State;std::unique_ptr<State> state_;
};
}
