#pragma once
#include <cstddef>
#include <string>

namespace douglass {
class GalleryScrubber {
public:
    void begin(std::size_t index,double fingerX,double width,std::size_t count) noexcept;
    void move(double fingerX) noexcept;
    bool advanceEdge(double elapsed) noexcept;
    bool canAdvanceAtEdge() const noexcept;
    std::size_t finish() noexcept;
    double position() const noexcept{return position_;}
    double thumbnailX(std::size_t index) const noexcept;
    std::size_t indexAt(double x) const noexcept;
private:
    double bounded(double value) const noexcept;
    double edgeVelocity() const noexcept;
    std::size_t count_=0;
    double position_=0,anchor_=0,width_=0,stride_=28;
};

enum class SearchBack { input,close };
class SearchFlow {
public:
    bool firstAppearance(bool restored) noexcept;
    void input() noexcept{results_=false;}
    void results() noexcept{results_=true;}
    bool showingResults() const noexcept{return results_;}
    SearchBack back() noexcept;
private:
    bool appeared_=false,results_=false;
};
bool keepGalleryAwake(bool appActive,bool visible,bool gallery,bool inactive) noexcept;
class ReadingPosition {
public:
    void capture(std::string parent,std::string row,double inset,double fallback);
    double offset(double rowTop,bool found,double minimum,double maximum) const noexcept;
    const std::string &parent() const noexcept{return parent_;}
    const std::string &row() const noexcept{return row_;}
    bool valid() const noexcept{return valid_;}
private:
    std::string parent_,row_;
    double inset_=0,fallback_=0;
    bool valid_=false;
};
struct ZoomRegion {double x=0,y=0,width=0,height=0;};
ZoomRegion previewZoomRegion(double width,double height,double x,double y,double scale) noexcept;
double previewDoubleTapScale(double current) noexcept;
}
