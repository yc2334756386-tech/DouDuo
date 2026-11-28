#include "InteractionState.hpp"
#include <algorithm>
#include <cmath>

namespace douglass {
double GalleryScrubber::bounded(double value) const noexcept{
    return count_&&std::isfinite(value)?std::clamp(value,0.,static_cast<double>(count_-1)):0.;
}
void GalleryScrubber::begin(std::size_t index,double x,double width,std::size_t count) noexcept{
    count_=count;width_=std::isfinite(width)?std::max(44.,width):44.;
    start_=position_=bounded(static_cast<double>(index));
    anchor_=std::isfinite(x)?x:width_/2;
    // A direct displacement mapping has no timer, velocity cap or easing lag.
    stride_=28.;
}
void GalleryScrubber::move(double x) noexcept{
    if(std::isfinite(x))position_=bounded(start_+(x-anchor_)/stride_);
}
std::size_t GalleryScrubber::finish() noexcept{
    position_=std::round(bounded(position_));return static_cast<std::size_t>(position_);
}
double GalleryScrubber::thumbnailX(std::size_t index) const noexcept{
    // The selection aperture stays in the middle. Only its underlying rail moves.
    const double delta=static_cast<double>(index)-position_;
    const double gap=std::clamp(delta,-1.,1.)*7.;
    return width_/2+delta*stride_+gap;
}
std::size_t GalleryScrubber::indexAt(double x) const noexcept{
    return static_cast<std::size_t>(std::round(bounded(position_+(x-width_/2)/stride_)));
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
