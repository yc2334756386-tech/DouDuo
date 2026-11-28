#include "ContrastMap.hpp"
#include <algorithm>
#include <cmath>
#include <limits>
#include <array>
#include <utility>

namespace douglass {
MediaRect fittedMedia(double sourceWidth,double sourceHeight,MediaRect viewport,bool fill) noexcept{
    if(!std::isfinite(sourceWidth)||!std::isfinite(sourceHeight)||sourceWidth<=0||sourceHeight<=0||!std::isfinite(viewport.width)||!std::isfinite(viewport.height)||viewport.width<=0||viewport.height<=0)return {};
    const double sx=viewport.width/sourceWidth,sy=viewport.height/sourceHeight,scale=fill?std::max(sx,sy):std::min(sx,sy),width=sourceWidth*scale,height=sourceHeight*scale;
    return {viewport.x+(viewport.width-width)/2,viewport.y+(viewport.height-height)/2,width,height};
}
static const std::array<float,256> &linearComponents(){
    static const auto values=[](){std::array<float,256> values{};for(std::size_t i=0;i<values.size();++i){const double encoded=i/255.;values[i]=static_cast<float>(encoded<=.04045?encoded/12.92:std::pow((encoded+.055)/1.055,2.4));}return values;}();return values;
}
std::shared_ptr<const ContrastFrame> ContrastMap::makeFrame(const std::uint8_t *rgba,std::size_t width,std::size_t height,std::size_t stride) const {
    if(!rgba||!width||!height||width>2048||height>2048||stride<width*4||height>std::numeric_limits<std::size_t>::max()/stride)return {};
    auto frame=std::make_shared<ContrastFrame>();frame->width=width;frame->height=height;frame->luminance.resize(width*height);const auto &linear=linearComponents();
    for(std::size_t y=0;y<height;++y)for(std::size_t x=0;x<width;++x){const auto *p=rgba+y*stride+x*4;frame->luminance[y*width+x]=.2126f*linear[p[0]]+.7152f*linear[p[1]]+.0722f*linear[p[2]];}
    return frame;
}
int ContrastFrame::inkFor(MediaRect region) const noexcept {
    if(!width||!height||luminance.size()!=width*height||!std::isfinite(region.x)||!std::isfinite(region.y)||!std::isfinite(region.width)||!std::isfinite(region.height)||region.width<=0||region.height<=0)return -1;
    const double left=std::max(0.,region.x),top=std::max(0.,region.y),right=std::min(double(width),region.x+region.width),bottom=std::min(double(height),region.y+region.height);
    if(right<=left||bottom<=top||(right-left)*(bottom-top)<region.width*region.height*.95)return -1;
    const auto x0=static_cast<std::size_t>(std::floor(left)),x1=std::min(width,static_cast<std::size_t>(std::ceil(right)));
    const auto y0=static_cast<std::size_t>(std::floor(top)),y1=std::min(height,static_cast<std::size_t>(std::ceil(bottom)));
    double blackArea=0,whiteArea=0,total=0;
    for(auto y=y0;y<y1;++y)for(auto x=x0;x<x1;++x){
        const double area=(std::min(right,double(x+1))-std::max(left,double(x)))*(std::min(bottom,double(y+1))-std::max(top,double(y)));
        const double light=luminance[y*width+x],blackContrast=(light+.05)/(.018+.05),whiteContrast=(.955+.05)/(light+.05);
        if(blackContrast>=3.6&&blackContrast>whiteContrast*1.18)blackArea+=area;
        else if(whiteContrast>=3.0&&whiteContrast>blackContrast*1.18)whiteArea+=area;
        total+=area;
    }
    // Each whole character needs a broadly consistent background. Small corners
    // and narrow strokes do not classify a character, much less a two-glyph group.
    return total>0&&blackArea/total>=.60?1:total>0&&whiteArea/total>=.60?0:-1;
}
void GroupedInk::setGlyphs(std::vector<InkGlyph> glyphs){
    glyphs_=std::move(glyphs);groups_.clear();if(glyphs_.size()<2)return;
    std::sort(glyphs_.begin(),glyphs_.end(),[](const InkGlyph &a,const InkGlyph &b){return a.x<b.x;});
    for(std::size_t i=0;i<glyphs_.size();){const auto count=glyphs_.size()-i==3?3u:2u;groups_.push_back({i,std::min(glyphs_.size(),i+count)});i+=count;}
}
bool GroupedInk::update(const ContrastFrame &frame,MediaRect text,double overlayWidth,double overlayHeight) noexcept {
    if(!std::isfinite(overlayWidth)||!std::isfinite(overlayHeight)||overlayWidth<=0||overlayHeight<=0)return false;
    const double sx=frame.width/overlayWidth,sy=frame.height/overlayHeight;bool changed=false;
    for(auto &group:groups_){
        unsigned votes[2]{};
        for(auto i=group.begin;i<group.end;++i){
            const auto &glyph=glyphs_[i];
            const auto ink=frame.inkFor({(text.x+glyph.x)*sx,text.y*sy,glyph.width*sx,text.height*sy});
            if(ink>=0)++votes[ink];
        }
        const int wanted=votes[1]>=2&&!votes[0]?1:votes[0]>=2&&!votes[1]?0:-1;
        if(wanted<0||wanted==int(group.dark)){group.pending=-1;group.votes=0;continue;}
        if(group.pending!=wanted){group.pending=wanted;group.votes=1;}else ++group.votes;
        if(group.votes>=2){group.dark=wanted==1;group.votes=0;group.pending=-1;changed=true;}
    }
    return changed;
}
void GroupedInk::masks(std::size_t width,std::uint8_t *white,std::uint8_t *black) const noexcept {
    if(!white||!black||!width||width>4096)return;std::fill_n(white,width*4,255);std::fill_n(black,width*4,0);
    double left=0;
    for(std::size_t g=0;g<groups_.size();++g){const auto &group=groups_[g];double right=double(width);
        if(g+1<groups_.size()){const auto &last=glyphs_[group.end-1];right=(last.x+last.width+glyphs_[groups_[g+1].begin].x)/2;}
        const auto first=static_cast<std::size_t>(std::clamp(std::round(left),0.,double(width))),end=static_cast<std::size_t>(std::clamp(std::round(right),0.,double(width)));
        if(group.dark&&end>first){std::fill(white+first*4,white+end*4,0);std::fill(black+first*4,black+end*4,255);}left=right;
    }
}
}
