#include "DYRuntimeCore.h"
#include <cstring>
#include <algorithm>
#include <list>
#include <mutex>
#include <new>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

struct DYDataCache {
    struct Entry { std::string key; std::vector<uint8_t> bytes; };
    std::mutex mutex;
    std::list<Entry> lru;
    std::unordered_map<std::string, std::list<Entry>::iterator> entries;
    size_t budget;
    size_t cost = 0;
    explicit DYDataCache(size_t value) : budget(value) {}
};

DYDataCache *DYCacheCreate(size_t budget) { return new (std::nothrow) DYDataCache(budget); }
void DYCacheDestroy(DYDataCache *cache) { delete cache; }

void DYCachePut(DYDataCache *cache, const char *key, const void *bytes, size_t size) {
    if (!cache || !key || !bytes || size > cache->budget) return;
    std::lock_guard<std::mutex> lock(cache->mutex);
    const auto existing = cache->entries.find(key);
    if (existing != cache->entries.end()) {
        cache->cost -= existing->second->bytes.size();
        cache->lru.erase(existing->second);
        cache->entries.erase(existing);
    }
    const auto *first = static_cast<const uint8_t *>(bytes);
    cache->lru.push_front({key, std::vector<uint8_t>(first, first + size)});
    cache->entries.emplace(key, cache->lru.begin());
    cache->cost += size;
    while (cache->cost > cache->budget && !cache->lru.empty()) {
        auto &oldest = cache->lru.back();
        cache->cost -= oldest.bytes.size();
        cache->entries.erase(oldest.key);
        cache->lru.pop_back();
    }
}

size_t DYCacheCopy(DYDataCache *cache, const char *key, void *output, size_t capacity) {
    if (!cache || !key) return 0;
    std::lock_guard<std::mutex> lock(cache->mutex);
    const auto found = cache->entries.find(key);
    if (found == cache->entries.end()) return 0;
    cache->lru.splice(cache->lru.begin(), cache->lru, found->second);
    const auto &data = found->second->bytes;
    if (output && capacity >= data.size()) std::memcpy(output, data.data(), data.size());
    return data.size();
}

void DYCacheRemove(DYDataCache *cache, const char *key) {
    if (!cache || !key) return;
    std::lock_guard<std::mutex> lock(cache->mutex);
    const auto found = cache->entries.find(key);
    if (found == cache->entries.end()) return;
    cache->cost -= found->second->bytes.size();
    cache->lru.erase(found->second);
    cache->entries.erase(found);
}

void DYCacheClear(DYDataCache *cache) {
    if (!cache) return;
    std::lock_guard<std::mutex> lock(cache->mutex);
    cache->entries.clear();
    cache->lru.clear();
    cache->cost = 0;
}

struct DYUniqueIndex { std::unordered_set<std::string> keys; };
DYUniqueIndex *DYIndexCreate(void) { return new (std::nothrow) DYUniqueIndex; }
void DYIndexDestroy(DYUniqueIndex *index) { delete index; }
bool DYIndexInsert(DYUniqueIndex *index, const char *key) {
    return index && key && *key && index->keys.emplace(key).second;
}
void DYIndexClear(DYUniqueIndex *index) { if (index) index->keys.clear(); }
bool DYCorePlaybackAllowed(bool active, bool foreground, bool uncovered) {
    return active && foreground && uncovered;
}

double DYCoreBoostRate(double translation, double screenWidth) {
    const double distance = std::max(8.0, std::min(180.0, screenWidth * 0.65));
    return 1.5 + 1.5 * std::max(0.0, std::min(1.0, translation / distance));
}
