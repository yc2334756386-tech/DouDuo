#pragma once
#include <cstddef>
#include <cstdint>
#include <vector>

namespace douglass {
// A small screen-space map shared by all visible comments, never a video-sized buffer.
class ContrastMap {
public:
    void makeMasks(const std::uint8_t *rgba,std::size_t width,std::size_t height,
                   std::size_t stride,std::uint8_t *white,std::uint8_t *black,double lineHeight=0);
private:
    std::size_t width_=0,height_=0;
    double lineHeight_=0;
    std::vector<std::uint8_t> darkInk_;
    std::vector<float> light_,opacity_;
    std::vector<std::uint32_t> integral_;
    std::vector<float> opacityIntegral_;
};
}
