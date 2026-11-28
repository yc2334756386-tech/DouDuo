#include "ContrastMap.hpp"
#include <algorithm>
#include <cmath>
#include <limits>
#include <array>

namespace douglass {
MediaRect fittedMedia(double sourceWidth,double sourceHeight,MediaRect viewport,bool fill) noexcept{
    if(!std::isfinite(sourceWidth)||!std::isfinite(sourceHeight)||sourceWidth<=0||sourceHeight<=0||!std::isfinite(viewport.width)||!std::isfinite(viewport.height)||viewport.width<=0||viewport.height<=0)return {};
    const double sx=viewport.width/sourceWidth,sy=viewport.height/sourceHeight,scale=fill?std::max(sx,sy):std::min(sx,sy),width=sourceWidth*scale,height=sourceHeight*scale;
    return {viewport.x+(viewport.width-width)/2,viewport.y+(viewport.height-height)/2,width,height};
}
static const std::array<float,256> &linearComponents(){
    static const auto values=[](){std::array<float,256> values{};for(std::size_t i=0;i<values.size();++i){const double encoded=i/255.;values[i]=static_cast<float>(encoded<=.04045?encoded/12.92:std::pow((encoded+.055)/1.055,2.4));}return values;}();return values;
}
void ContrastMap::makeMasks(const std::uint8_t *rgba,std::size_t width,std::size_t height,
                            std::size_t stride,std::uint8_t *white,std::uint8_t *black,double lineHeight) {
    if(!rgba||!white||!black||!width||!height||width>2048||height>2048||
       stride<width*4||height>std::numeric_limits<std::size_t>::max()/stride)return;
    if(!std::isfinite(lineHeight)||lineHeight<1)lineHeight=0;
    const bool fresh=width!=width_||height!=height_||std::abs(lineHeight-lineHeight_)>.01;
    const std::size_t pixels=width*height,pitch=width+1;
    if(fresh){width_=width;height_=height;lineHeight_=lineHeight;darkInk_.assign(pixels,0);candidate_.assign(pixels,0);votes_.assign(pixels,0);light_.assign(pixels,0);opacity_.assign(pixels,0);}
    integral_.assign(pitch*(height+1),0);squared_.assign(pitch*(height+1),0);opacityIntegral_.assign(pitch*(height+1),0);
    const auto &linear=linearComponents();
    for(std::size_t y=0;y<height;++y){
        double row=0,squareRow=0;
        for(std::size_t x=0;x<width;++x){
            const auto *p=rgba+y*stride+x*4;const double light=.2126*linear[p[0]]+.7152*linear[p[1]]+.0722*linear[p[2]];row+=light;squareRow+=light*light;
            integral_[(y+1)*pitch+x+1]=integral_[y*pitch+x+1]+row;
            squared_[(y+1)*pitch+x+1]=squared_[y*pitch+x+1]+squareRow;
        }
    }
    // The sampler uses about 128 columns. This neighborhood spans several glyph
    // strokes, so texture/noise does not split text into rapidly flashing specks.
    const std::size_t radius=std::max<std::size_t>(3,width/16);
    for(std::size_t y=0;y<height;++y){
        for(std::size_t x=0;x<width;++x){
            const auto left=x>radius?x-radius:0,right=std::min(width,x+radius+1);
            const std::size_t top=lineHeight?std::min(height-1,static_cast<std::size_t>(std::floor(std::floor(y/lineHeight)*lineHeight))):(y>radius?y-radius:0);
            const std::size_t bottom=lineHeight?std::min(height,static_cast<std::size_t>(std::ceil((std::floor(y/lineHeight)+1)*lineHeight))):std::min(height,y+radius+1);
            const auto sum=integral_[bottom*pitch+right]-integral_[top*pitch+right]-integral_[bottom*pitch+left]+integral_[top*pitch+left];
            const float average=static_cast<float>(sum/((right-left)*(bottom-top)));
            const auto squareSum=squared_[bottom*pitch+right]-squared_[top*pitch+right]-squared_[bottom*pitch+left]+squared_[top*pitch+left];
            const float variance=std::max(0.f,static_cast<float>(squareSum/((right-left)*(bottom-top)))-average*average);
            const std::size_t i=y*width+x;auto &dark=darkInk_[i];
            if(fresh)light_[i]=average;else light_[i]=std::abs(average-light_[i])>.10f?average:light_[i]+(average-light_[i])*.75f;
            // Compare the actual near-white and charcoal inks in linear sRGB.
            // Texture widens the dead band; it never unconditionally forces white.
            const float blackContrast=(light_[i]+.05f)/(.015f+.05f),whiteContrast=(.955f+.05f)/(light_[i]+.05f),margin=variance>.06f?1.26f:1.16f;
            const bool blackReadable=blackContrast>=3.6f,whiteReadable=whiteContrast>=3.0f;
            const bool preferBlack=blackReadable&&(!whiteReadable||blackContrast>whiteContrast*margin);
            const bool preferWhite=whiteReadable&&(!blackReadable||whiteContrast>blackContrast*margin);
            candidate_[i]=preferBlack?1:preferWhite?0:dark;
        }
    }
    // Smooth each local background sample over time without a text-length gate.
    for(std::size_t y=0;y<height;++y){
        float row=0;
        for(std::size_t x=0;x<width;++x){
            const std::size_t index=y*width+x;
            if(candidate_[index]!=darkInk_[index]){
                if(++votes_[index]>=2){darkInk_[index]=candidate_[index];votes_[index]=0;}
            }else votes_[index]=0;
            opacity_[index]+=((darkInk_[index]?1.f:0.f)-opacity_[index])*.38f;
            row+=opacity_[index];
            opacityIntegral_[(y+1)*pitch+x+1]=opacityIntegral_[y*pitch+x+1]+row;
        }
    }
    const std::size_t feather=std::max<std::size_t>(2,width/40);
    for(std::size_t y=0;y<height;++y)for(std::size_t x=0;x<width;++x){
        const auto left=x>feather?x-feather:0,top=lineHeight?y:(y>feather?y-feather:0);
        const auto right=std::min(width,x+feather+1),bottom=lineHeight?y+1:std::min(height,y+feather+1);
        const float sum=opacityIntegral_[bottom*pitch+right]-opacityIntegral_[top*pitch+right]-opacityIntegral_[bottom*pitch+left]+opacityIntegral_[top*pitch+left];
        const auto alpha=static_cast<std::uint8_t>(std::lround(255*std::clamp(sum/((right-left)*(bottom-top)),0.f,1.f)));
        const std::size_t offset=(y*width+x)*4;
        for(unsigned channel=0;channel<4;++channel){white[offset+channel]=255-alpha;black[offset+channel]=alpha;}
    }
}
}
