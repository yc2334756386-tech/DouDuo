#include "ClientPolicy.hpp"
#include <charconv>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <string>

namespace douglass {
CountValue parseCount(std::string_view text,bool provided) {
    if(!provided||text.empty())return {};
    std::int64_t integer=0;
    const auto result=std::from_chars(text.data(),text.data()+text.size(),integer);
    if(result.ec==std::errc{}&&result.ptr==text.data()+text.size())return integer>=0?CountValue{integer,true}:CountValue{};
    const std::string value(text);char *end=nullptr;
    const double number=std::strtod(value.c_str(),&end);
    if(end!=value.c_str()+value.size()||!std::isfinite(number)||number<0||number>=std::ldexp(1.,63)||std::floor(number)!=number)return {};
    return {static_cast<std::int64_t>(number),true};
}
bool isFollowing(std::int64_t status) noexcept {return status==1||status==2;}
bool matchesAuthor(std::string_view sec,std::string_view uid,std::string_view targetSec,std::string_view targetUID) noexcept {return (!targetSec.empty()&&sec==targetSec)||(!targetUID.empty()&&uid==targetUID);}
double holdRate(double upward,double maximum) noexcept {
    if(!std::isfinite(upward)||upward<28)return 1.5;
    if(upward<64)return 2.;
    return std::isfinite(maximum)&&maximum>=2&&maximum<=4?maximum:3.;
}
bool fillsPortrait(bool enabled,bool compact,bool photo,double width,double height,double viewportWidth,double viewportHeight) noexcept {
    if(!enabled||compact||photo||!std::isfinite(width)||!std::isfinite(height)||width<=0||height<=width||!std::isfinite(viewportWidth)||!std::isfinite(viewportHeight)||viewportWidth<=0||viewportHeight<=0)return false;
    const double sourceRatio=width/height,viewportRatio=viewportWidth/viewportHeight;
    if(!std::isfinite(sourceRatio)||!std::isfinite(viewportRatio)||sourceRatio<=0||viewportRatio<=0)return false;
    // Aspect-fill may trim only a small margin: retain at least 88% of the source.
    const double retained=std::min(sourceRatio/viewportRatio,viewportRatio/sourceRatio);
    return retained>=.88;
}
double photoScrubPosition(double current,double displacement,double stride,std::size_t count) noexcept {
    if(count==0)return 0;
    if(!std::isfinite(current))current=0;
    if(std::isfinite(displacement)&&std::isfinite(stride)&&stride>0)current-=displacement/stride;
    return std::clamp(current,0.,static_cast<double>(count-1));
}
AccountState assessAccount(bool requestOK,bool reportedSignedIn,std::string_view uid,bool expired,bool sessionHint,unsigned attempt) noexcept {
    if(requestOK&&reportedSignedIn&&!uid.empty()&&uid!="0")return AccountState::authenticated;
    if(expired)return AccountState::expired;
    if(requestOK&&attempt>=2&&!sessionHint)return AccountState::signedOut;
    return AccountState::unconfirmed;
}
}
