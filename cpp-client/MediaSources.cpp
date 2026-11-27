#include "MediaSources.hpp"
#include <algorithm>
#include <cmath>

namespace douglass {
namespace {
bool webURL(const std::string &url) {return url.starts_with("https://")||url.starts_with("http://");}
bool redirected(const std::string &url) {return webURL(url)&&url.find("/aweme/v1/play/")!=std::string::npos;}
PlaybackSource choose(const std::vector<std::string> &preferred,const std::vector<std::string> &alternates) {
    PlaybackSource selected;
    const auto direct=std::find_if(preferred.begin(),preferred.end(),[](const std::string &url){return webURL(url)&&!redirected(url);});
    auto preferredRedirect=std::find_if(preferred.begin(),preferred.end(),redirected);
    auto otherRedirect=std::find_if(alternates.begin(),alternates.end(),redirected);
    if(direct!=preferred.end())selected.primary=*direct;
    else if(preferredRedirect!=preferred.end())selected.primary=*preferredRedirect;
    else if(auto other=std::find_if(alternates.begin(),alternates.end(),[](const std::string &url){return webURL(url)&&!redirected(url);});other!=alternates.end())selected.primary=*other;
    else if(otherRedirect!=alternates.end())selected.primary=*otherRedirect;
    if(preferredRedirect!=preferred.end()&&*preferredRedirect!=selected.primary)selected.alternate=*preferredRedirect;
    else if(otherRedirect!=alternates.end()&&*otherRedirect!=selected.primary)selected.alternate=*otherRedirect;
    else {
        auto distinct=[&](const std::string &url){return webURL(url)&&url!=selected.primary;};
        if(auto next=std::find_if(preferred.begin(),preferred.end(),distinct);next!=preferred.end())selected.alternate=*next;
        else if(auto other=std::find_if(alternates.begin(),alternates.end(),distinct);other!=alternates.end())selected.alternate=*other;
    }
    return selected;
}
double standardScore(const MediaSource &source) {
    return (source.shortSide>=540?0.:100000000.)+std::abs((source.bitrate>0?source.bitrate:1200000.)-1200000.);
}
bool higherQuality(const MediaSource &a,const MediaSource &b) {
    return a.shortSide!=b.shortSide?a.shortSide>b.shortSide:a.bitrate>b.bitrate;
}
PlaybackSource variant(const MediaSource *source) {
    if(!source)return {};
    auto result=choose(source->urls,{});result.shortSide=source->shortSide;result.fps=source->fps;
    return result;
}
}
PlaybackSources selectPlaybackSources(const std::vector<std::string> &fallback,const std::vector<MediaSource> &sources) {
    const auto hasURL=[](const MediaSource &source){return std::any_of(source.urls.begin(),source.urls.end(),webURL);};
    const bool preferAVC=std::any_of(sources.begin(),sources.end(),[&](const MediaSource &source){return source.avc&&hasURL(source);});
    const MediaSource *standard=nullptr,*quality=nullptr,*smooth=nullptr;
    std::vector<std::string> alternates=fallback;
    for(const auto &source:sources){
        if(!hasURL(source))continue;
        alternates.insert(alternates.end(),source.urls.begin(),source.urls.end());
        if(preferAVC&&!source.avc)continue;
        if(!standard||standardScore(source)<standardScore(*standard))standard=&source;
        if(!quality||higherQuality(source,*quality))quality=&source;
        if(source.fps>0&&(!smooth||source.fps>smooth->fps||(source.fps==smooth->fps&&higherQuality(source,*smooth))))smooth=&source;
    }
    return {choose(standard?standard->urls:fallback,alternates),variant(quality),variant(smooth),variant(smooth?smooth:quality)};
}
}
