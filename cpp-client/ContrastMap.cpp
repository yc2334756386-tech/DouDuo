#include "ContrastMap.hpp"
#include <algorithm>
#include <cmath>
#include <limits>

namespace douglass {
void ContrastMap::makeMasks(const std::uint8_t *rgba,std::size_t width,std::size_t height,
                            std::size_t stride,std::uint8_t *white,std::uint8_t *black) {
    if(!rgba||!white||!black||!width||!height||width>2048||height>2048||
       stride<width*4||height>std::numeric_limits<std::size_t>::max()/stride)return;
    const bool fresh=width!=width_||height!=height_;
    const std::size_t pixels=width*height,pitch=width+1;
    if(fresh){width_=width;height_=height;darkInk_.assign(pixels,0);light_.assign(pixels,0);opacity_.assign(pixels,0);}
    integral_.assign(pitch*(height+1),0);opacityIntegral_.assign(pitch*(height+1),0);
    for(std::size_t y=0;y<height;++y){
        std::uint32_t row=0;
        for(std::size_t x=0;x<width;++x){
            const auto *p=rgba+y*stride+x*4;row+=(54u*p[0]+183u*p[1]+19u*p[2])>>8;
            integral_[(y+1)*pitch+x+1]=integral_[y*pitch+x+1]+row;
        }
    }
    // The sampler uses about 128 columns. This neighborhood spans several glyph
    // strokes, so texture/noise does not split text into rapidly flashing specks.
    const std::size_t radius=std::max<std::size_t>(2,width/28);
    for(std::size_t y=0;y<height;++y){
        float row=0;
        for(std::size_t x=0;x<width;++x){
            const auto left=x>radius?x-radius:0,top=y>radius?y-radius:0;
            const auto right=std::min(width,x+radius+1),bottom=std::min(height,y+radius+1);
            const auto sum=integral_[bottom*pitch+right]-integral_[top*pitch+right]-integral_[bottom*pitch+left]+integral_[top*pitch+left];
            const float average=static_cast<float>(sum)/(255.f*(right-left)*(bottom-top));
            const std::size_t i=y*width+x;auto &dark=darkInk_[i];
            if(fresh){light_[i]=average;dark=average>=.55f;opacity_[i]=dark?1.f:0.f;}
            else{
                light_[i]+=(average-light_[i])*.35f;
                if(light_[i]>.65f)dark=1;else if(light_[i]<.38f)dark=0;
                opacity_[i]+=((dark?1.f:0.f)-opacity_[i])*.38f;
            }
            row+=opacity_[i];opacityIntegral_[(y+1)*pitch+x+1]=opacityIntegral_[y*pitch+x+1]+row;
        }
    }
    const std::size_t feather=std::max<std::size_t>(1,width/64);
    for(std::size_t y=0;y<height;++y)for(std::size_t x=0;x<width;++x){
        const auto left=x>feather?x-feather:0,top=y>feather?y-feather:0;
        const auto right=std::min(width,x+feather+1),bottom=std::min(height,y+feather+1);
        const float sum=opacityIntegral_[bottom*pitch+right]-opacityIntegral_[top*pitch+right]-opacityIntegral_[bottom*pitch+left]+opacityIntegral_[top*pitch+left];
        const auto alpha=static_cast<std::uint8_t>(std::lround(255*std::clamp(sum/((right-left)*(bottom-top)),0.f,1.f)));
        const std::size_t offset=(y*width+x)*4;
        for(unsigned channel=0;channel<4;++channel){white[offset+channel]=255-alpha;black[offset+channel]=alpha;}
    }
}
}
