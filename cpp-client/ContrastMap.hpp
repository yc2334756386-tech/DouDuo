#pragma once
#include <cstddef>
#include <cstdint>
#include <vector>
#include <memory>

namespace douglass {
struct MediaRect {double x=0,y=0,width=0,height=0;};
MediaRect fittedMedia(double sourceWidth,double sourceHeight,MediaRect viewport,bool fill) noexcept;
struct ContrastFrame {
    std::size_t width=0,height=0;
    std::vector<float> luminance;
    // -1 is mixed/uncertain; 0 requests white, 1 requests dark ink.
    int inkFor(MediaRect region) const noexcept;
};
struct InkGlyph { double x=0,width=0; };
// State belongs to complete text groups, never to individual background pixels.
class GroupedInk {
public:
    void setGlyphs(std::vector<InkGlyph> glyphs);
    bool update(const ContrastFrame &frame,MediaRect text,double overlayWidth,double overlayHeight) noexcept;
    void masks(std::size_t width,std::uint8_t *white,std::uint8_t *black) const noexcept;
private:
    struct Group {std::size_t begin=0,end=0;bool dark=false;int pending=-1;unsigned votes=0;};
    std::vector<InkGlyph> glyphs_;
    std::vector<Group> groups_;
};
// A small screen-space map shared by all visible comments, never a video-sized buffer.
class ContrastMap {
public:
    std::shared_ptr<const ContrastFrame> makeFrame(const std::uint8_t *rgba,std::size_t width,std::size_t height,std::size_t stride) const;
};
}
