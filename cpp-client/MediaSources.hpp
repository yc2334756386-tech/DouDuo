#pragma once
#include <string>
#include <vector>

namespace douglass {
struct MediaSource {
    std::vector<std::string> urls;
    double shortSide=0,bitrate=0,fps=0;
    bool avc=true;
};
struct PlaybackSource {
    std::string primary,alternate;
    double fps=0,shortSide=0;
};
struct PlaybackSources {
    PlaybackSource standard,quality,smooth,qualityFPS;
};
PlaybackSources selectPlaybackSources(const std::vector<std::string> &fallback,const std::vector<MediaSource> &sources);
}
