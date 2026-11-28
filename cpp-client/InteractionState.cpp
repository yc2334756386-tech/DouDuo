#include "InteractionState.hpp"
#include <algorithm>
#include <cmath>

namespace douglass {
double GalleryScrubber::bounded(double value) const noexcept{
    return count_&&std::isfinite(value)?std::clamp(value,0.,static_cast<double>(count_-1)):0.;
}
void GalleryScrubber::begin(std::size_t index,double x,double width,std::size_t count) noexcept{
    count_=count;width_=std::isfinite(width)?std::max(44.,width):44.;
    start_=base_=position_=bounded(static_cast<double>(index));
    anchor_=finger_=std::isfinite(x)?std::clamp(x,18.,width_-18):width_/2;
    stride_=std::clamp(width_/12.,24.,38.);edge_=0;
}
void GalleryScrubber::move(double x) noexcept{
    if(!std::isfinite(x))return;
    const double direction=x-finger_;finger_=x;
    position_=bounded(base_+(x-anchor_)/stride_);
    edge_=x>width_-18&&direction>=0?1:x<18&&direction<=0?-1:0;
}
bool GalleryScrubber::advanceEdge(double seconds) noexcept{
    if(!edge_||!std::isfinite(seconds)||seconds<=0)return false;
    const double before=position_;base_+=edge_*std::min(seconds,.15)*6.;
    position_=bounded(base_+(finger_-anchor_)/stride_);
    if(position_==before)base_=position_-(finger_-anchor_)/stride_;
    return std::abs(position_-before)>.0001;
}
std::size_t GalleryScrubber::finish() noexcept{
    edge_=0;position_=std::round(bounded(position_));return static_cast<std::size_t>(position_);
}
double GalleryScrubber::shift() const noexcept{
    const double selected=anchor_+(position_-start_)*stride_;
    return selected>width_-22?selected-(width_-22):selected<22?selected-22:0;
}
double GalleryScrubber::thumbnailX(std::size_t index) const noexcept{
    return anchor_+(static_cast<double>(index)-start_)*stride_-shift();
}
std::size_t GalleryScrubber::indexAt(double x) const noexcept{
    return static_cast<std::size_t>(std::round(bounded(start_+(x+shift()-anchor_)/stride_)));
}
bool SearchFlow::firstAppearance(bool restored) noexcept{
    const bool focus=!appeared_&&!restored;appeared_=true;return focus;
}
SearchBack SearchFlow::back() noexcept{
    if(results_){results_=false;return SearchBack::input;}return SearchBack::close;
}
bool keepGalleryAwake(bool appActive,bool visible,bool gallery,bool inactive) noexcept{
    return appActive&&visible&&gallery&&!inactive;
}
}
