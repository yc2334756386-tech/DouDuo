#include "InterpolationProtection.hpp"
#include <algorithm>
#include <cstdlib>

namespace douglass {

InterpolationSample sampleInterpolationFrame(const std::uint8_t *luma, std::size_t lumaStride,
                                             const std::uint8_t *chroma, std::size_t chromaStride,
                                             std::size_t width, std::size_t height) {
    InterpolationSample sample;
    constexpr int grid = InterpolationSample::grid;
    constexpr int chromaGrid = InterpolationSample::chromaGrid;
    for (int y = 0; y < grid; ++y) {
        const auto *top = luma + ((4*y+1)*height/(4*grid))*lumaStride;
        const auto *bottom = luma + ((4*y+3)*height/(4*grid))*lumaStride;
        for (int x = 0; x < grid; ++x) {
            const auto left = (4*x+1)*width/(4*grid);
            const auto right = (4*x+3)*width/(4*grid);
            sample.luma[y*grid+x] = (top[left]+top[right]+bottom[left]+bottom[right]+2)/4;
        }
    }
    for (int y = 0; y < chromaGrid; ++y) {
        const auto *row = chroma + ((2*y+1)*(height/2)/(2*chromaGrid))*chromaStride;
        for (int x = 0; x < chromaGrid; ++x) {
            const auto column = 2*((2*x+1)*(width/2)/(2*chromaGrid));
            sample.chroma[2*(y*chromaGrid+x)] = row[column];
            sample.chroma[2*(y*chromaGrid+x)+1] = row[column+1];
        }
    }
    return sample;
}

namespace {
constexpr int grid = InterpolationSample::grid;

// Search a small neighborhood on a subsampled grid. A large displacement
// that explains much of the frame difference catches pans even in dim scenes.
bool fastPan(const InterpolationSample &a, const InterpolationSample &b, double interval) {
    constexpr int radius = 3;
    const auto distance = [&](int dx, int dy) {
        int total = 0;
        for (int y = radius; y < grid-radius; y += 2) {
            for (int x = radius; x < grid-radius; x += 2) {
                total += std::abs(int(a.luma[(y+dy)*grid+x+dx])-int(b.luma[y*grid+x]));
            }
        }
        return total;
    };
    const int aligned = distance(0,0);
    constexpr int sampleCount = ((grid-2*radius)/2)*((grid-2*radius)/2);
    if (aligned < 6*sampleCount) return false;
    int nearby = aligned, displaced = aligned;
    const double minShift = std::clamp(interval*30., 1., 3.);
    for (int dy = -radius; dy <= radius; ++dy) {
        for (int dx = -radius; dx <= radius; ++dx) {
            if (!dx && !dy) continue;
            if (dx*dx+dy*dy+.15 < minShift*minShift) nearby = std::min(nearby,distance(dx,dy));
            else displaced = std::min(displaced,distance(dx,dy));
        }
    }
    return displaced*100 <= aligned*72 && displaced*100 <= nearby*85;
}

InterpolationHazard detect(const InterpolationSample &a, const InterpolationSample &b, double interval) {
    int lumaDelta = 0, strongBlocks = 0;
    constexpr int block = grid/4;
    for (int by = 0; by < grid; by += block) {
        for (int bx = 0; bx < grid; bx += block) {
            int blockDelta = 0;
            for (int y = by; y < by+block; ++y) {
                for (int x = bx; x < bx+block; ++x) {
                    blockDelta += std::abs(int(a.luma[y*grid+x])-int(b.luma[y*grid+x]));
                }
            }
            lumaDelta += blockDelta;
            strongBlocks += blockDelta >= 25*block*block;
        }
    }
    int chromaDelta = 0;
    for (std::size_t i = 0; i < a.chroma.size(); ++i) {
        chromaDelta += std::abs(int(a.chroma[i])-int(b.chroma[i]));
    }
    const int luma = lumaDelta/(grid*grid);
    const int chroma = chromaDelta/static_cast<int>(a.chroma.size());
    if (luma >= 42 || chroma >= 23 || (luma >= 23 && strongBlocks >= 8)) {
        return InterpolationHazard::sceneChange;
    }
    // Include blur, rotation, zoom and block transitions that lack a single
    // direction of motion. For lower residuals require coherent displacement.
    if ((strongBlocks >= 4 && luma >= 13) ||
        (luma >= 9 && fastPan(a,b,interval))) {
        return InterpolationHazard::fastMotion;
    }
    return InterpolationHazard::none;
}
}

bool InterpolationProtection::protecting(std::uint64_t generation) const {
    return generation_ == generation && protecting_;
}

InterpolationHazard InterpolationProtection::assess(std::uint64_t generation,
                                                    const InterpolationSample *previous,
                                                    const InterpolationSample *current,
                                                    double frameInterval) {
    if (generation_ != generation) {
        generation_ = generation;
        stableSeconds_ = 0;
        protecting_ = false;
    }
    const auto hazard = previous && current ? detect(*previous,*current,frameInterval)
                                           : InterpolationHazard::unstable;
    if (hazard != InterpolationHazard::none) {
        protecting_ = true;
        stableSeconds_ = 0;
        return hazard;
    }
    if (protecting_) {
        stableSeconds_ += frameInterval;
        if (stableSeconds_ < .12) return InterpolationHazard::unstable;
        protecting_ = false;
    }
    return InterpolationHazard::none;
}

}
