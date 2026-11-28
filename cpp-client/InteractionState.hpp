#pragma once
#include <cstddef>

namespace douglass {
class GalleryScrubber {
public:
    void begin(std::size_t index,double fingerX,double width,std::size_t count) noexcept;
    void move(double fingerX) noexcept;
    std::size_t finish() noexcept;
    double position() const noexcept{return position_;}
    double thumbnailX(std::size_t index) const noexcept;
    std::size_t indexAt(double x) const noexcept;
private:
    double bounded(double value) const noexcept;
    std::size_t count_=0;
    double start_=0,position_=0,anchor_=0,width_=0,stride_=28;
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
}
