#pragma once
#include <cstddef>
#include <optional>
#include <string>
#include <unordered_map>

namespace douglass {
struct ChannelState {
    std::string cursor="0";
    std::size_t selected=0;
    double position=0;
    int refreshIndex=1,emptyPages=0;
    bool paused=false,more=true;
};
class ChannelSessions {
public:
    bool setScope(std::string scope);
    void clear();
    void save(std::string channel,ChannelState state,std::size_t recordCount);
    std::optional<ChannelState> take(const std::string &channel);
private:
    std::string scope_;
    std::unordered_map<std::string,ChannelState> states_;
};
}
