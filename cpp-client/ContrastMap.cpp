#include "ContrastMap.hpp"
#include <limits>

namespace douglass {
void ContrastMap::makeMasks(const std::uint8_t *rgba,std::size_t width,std::size_t height,
                            std::size_t stride,std::uint8_t *white,std::uint8_t *black) {
    if(!rgba||!white||!black||!width||!height||width>2048||height>2048||
       stride<width*4||height>std::numeric_limits<std::size_t>::max()/stride)return;
    const bool fresh=width!=width_||height!=height_;
    if(fresh){width_=width;height_=height;darkInk_.assign(width*height,0);}
    for(std::size_t y=0;y<height;++y)for(std::size_t x=0;x<width;++x){
        const auto *pixel=rgba+y*stride+x*4;
        const unsigned light=54u*pixel[0]+183u*pixel[1]+19u*pixel[2];
        auto &dark=darkInk_[y*width+x];
        // The dead band prevents repeated flipping on noisy midtones.
        if(fresh)dark=light>=128u*256u;
        else if(light>140u*256u)dark=1;
        else if(light<116u*256u)dark=0;
        const std::size_t offset=(y*width+x)*4;
        for(unsigned channel=0;channel<4;++channel){
            white[offset+channel]=dark?0:255;black[offset+channel]=dark?255:0;
        }
    }
}
}
