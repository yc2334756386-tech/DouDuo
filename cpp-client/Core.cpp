#include "Core.hpp"
#include <cstdio>
#include <utility>

namespace douglass {
std::size_t Feed::append(std::vector<Work> incoming, bool hasMore, bool replace) {
    if (replace) clear();
    std::size_t added = 0;
    for (auto &work : incoming) {
        if (work.playable() && ids_.insert(work.id).second) {
            works.emplace_back(std::move(work));
            ++added;
        }
    }
    more = hasMore;
    return added;
}
void Feed::clear() { works.clear(); ids_.clear(); more = true; }
std::string compact(std::int64_t value) {
    if (value < 0) value = 0;
    if (value < 10000) return std::to_string(value);
    char output[48];
    std::snprintf(output, sizeof(output), "%.1f%s", value / (value >= 100000000 ? 100000000.0 : 10000.0),
                  value >= 100000000 ? "亿" : "万");
    return output;
}
}
