#pragma once
#include <cstdint>
#include <string>
#include <unordered_set>
#include <vector>

namespace douglass {
struct Work {
    std::string id, caption, author, avatar, cover, play, alternate, music;
    std::vector<std::string> images;
    std::int64_t comments = 0, likes = 0;
    double duration = 0;
    bool photo() const noexcept { return !images.empty(); }
    bool playable() const noexcept { return !id.empty() && (photo() || !play.empty()); }
};
struct Comment {
    std::string id, text, author, avatar, location;
    std::vector<std::string> images;
    std::int64_t likes = 0, replies = 0, timestamp = 0;
};
class Feed {
public:
    std::vector<Work> works;
    bool more = true;
    std::size_t append(std::vector<Work> incoming, bool hasMore, bool replace);
    void clear();
private:
    std::unordered_set<std::string> ids_;
};
std::string compact(std::int64_t value);
}
