#include "ChannelState.hpp"
#include <algorithm>
#include <cmath>
#include <utility>

namespace douglass {
bool ChannelSessions::setScope(std::string scope) {
    if(scope_==scope)return false;
    states_.clear();scope_=std::move(scope);return true;
}
void ChannelSessions::clear(){states_.clear();scope_.clear();}
void ChannelSessions::save(std::string channel,ChannelState state,std::size_t count) {
    if((channel!="feed"&&channel!="followFeed")||count==0)return;
    state.selected=std::min(state.selected,count-1);
    if(!std::isfinite(state.position)||state.position<0)state.position=0;
    state.refreshIndex=std::max(1,state.refreshIndex);state.emptyPages=std::max(0,state.emptyPages);
    if(state.cursor.empty())state.cursor="0";
    states_[std::move(channel)]=std::move(state);
}
std::optional<ChannelState> ChannelSessions::take(const std::string &channel) {
    const auto found=states_.find(channel);if(found==states_.end())return std::nullopt;
    ChannelState state=std::move(found->second);states_.erase(found);return state;
}
}
