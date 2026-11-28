#include "InteractionState.hpp"
#include <algorithm>
#include <cmath>
#include <utility>

namespace douglass {
double GalleryScrubber::bounded(double value) const noexcept{
    return count_&&std::isfinite(value)?std::clamp(value,0.,static_cast<double>(count_-1)):0.;
}
void GalleryScrubber::begin(std::size_t index,double x,double width,std::size_t count) noexcept{
    count_=count;width_=std::isfinite(width)?std::max(44.,width):44.;
    position_=bounded(static_cast<double>(index));
    anchor_=std::isfinite(x)?x:width_/2;
    // Ordinary dragging follows displacement directly; only an edge hold uses time.
    stride_=28.;
}
void GalleryScrubber::move(double x) noexcept{
    if(!std::isfinite(x))return;
    position_=bounded(position_+(x-anchor_)/stride_);anchor_=x;
}
double GalleryScrubber::edgeVelocity() const noexcept{
    if(count_<2)return 0.;
    const double zone=std::min(32.,width_/4);
    if(anchor_<zone)return -(3.+13.*std::clamp((zone-anchor_)/zone,0.,1.));
    if(anchor_>width_-zone)return 3.+13.*std::clamp((anchor_-(width_-zone))/zone,0.,1.);
    return 0.;
}
bool GalleryScrubber::canAdvanceAtEdge() const noexcept{
    const double velocity=edgeVelocity();
    return (velocity<0.&&position_>0.)||(velocity>0.&&position_<bounded(static_cast<double>(count_)));
}
bool GalleryScrubber::advanceEdge(double elapsed) noexcept{
    if(!std::isfinite(elapsed)||elapsed<=0.)return false;
    const double previous=position_;
    position_=bounded(position_+edgeVelocity()*std::min(elapsed,.05));
    return position_!=previous;
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
void ReadingPosition::capture(std::string parent,std::string row,double inset,double fallback){
    parent_=std::move(parent);row_=std::move(row);inset_=std::isfinite(inset)?inset:0;fallback_=std::isfinite(fallback)?fallback:0;valid_=true;
}
double ReadingPosition::offset(double rowTop,bool found,double minimum,double maximum) const noexcept{
    if(!std::isfinite(minimum))minimum=0;if(!std::isfinite(maximum)||maximum<minimum)maximum=minimum;
    const double result=found&&std::isfinite(rowTop)?rowTop+inset_:fallback_;
    return std::clamp(std::isfinite(result)?result:minimum,minimum,maximum);
}
double previewDoubleTapScale(double current) noexcept{return std::isfinite(current)&&current>1.05?1.:2.5;}
ZoomRegion previewZoomRegion(double width,double height,double x,double y,double scale) noexcept{
    if(!std::isfinite(width)||!std::isfinite(height)||width<=0||height<=0)return {};
    if(!std::isfinite(scale))scale=1;scale=std::clamp(scale,1.,4.);
    const double w=width/scale,h=height/scale;
    x=std::isfinite(x)?x:width/2;y=std::isfinite(y)?y:height/2;
    return {std::clamp(x-w/2,0.,width-w),std::clamp(y-h/2,0.,height-h),w,h};
}
}
