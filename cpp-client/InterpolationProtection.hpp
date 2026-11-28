#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace douglass {

struct InterpolationSample {
    static constexpr int grid = 32;
    static constexpr int chromaGrid = 8;
    std::array<std::uint8_t, grid * grid> luma{};
    std::array<std::uint8_t, chromaGrid * chromaGrid * 2> chroma{};
};

InterpolationSample sampleInterpolationFrame(const std::uint8_t *luma, std::size_t lumaStride,
                                             const std::uint8_t *chroma, std::size_t chromaStride,
                                             std::size_t width, std::size_t height);

enum class InterpolationHazard { none, sceneChange, fastMotion, unstable };

class InterpolationProtection {
public:
    InterpolationHazard assess(std::uint64_t generation, const InterpolationSample *previous,
                               const InterpolationSample *current, double frameInterval);
    bool protecting(std::uint64_t generation) const;
private:
    std::uint64_t generation_ = 0;
    bool protecting_ = false;
    double stableSeconds_ = 0;
};

}
