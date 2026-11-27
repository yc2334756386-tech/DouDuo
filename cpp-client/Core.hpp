#pragma once
#include <cstdint>
#include <string>
#include <unordered_set>
#include <vector>
#include <utility>

namespace douglass {
struct Work {
    std::string id, contentKey, caption, author, avatar, cover, play, alternate, music;
    std::string authorID, authorUID, musicID, musicTitle, musicAuthor, location, locationKind;
    std::vector<std::string> images;
    std::int64_t comments = 0, likes = 0, collects = 0, publishedAt = 0;
    bool liked = false, collected = false;
    bool isAd = false, isLive = false;
    double duration = 0;
    bool photo() const noexcept { return !images.empty(); }
    bool playable() const noexcept { return !id.empty() && (photo() || !play.empty()); }
};
struct Comment {
    std::string id, text, author, avatar, location;
    std::string authorID, sticker, replyToID, replyToAuthor;
    std::vector<std::pair<std::string,std::string>> emoticons;
    std::vector<std::string> images;
    std::int64_t likes = 0, replies = 0, timestamp = 0;
    bool liked = false;
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
double relativeProgress(double initial,double displacement,double trackWidth,double minimum,double maximum) noexcept;
}
