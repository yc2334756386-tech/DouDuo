#ifndef DY_RUNTIME_CORE_H
#define DY_RUNTIME_CORE_H
#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct DYDataCache DYDataCache;
DYDataCache *DYCacheCreate(size_t budget);
void DYCacheDestroy(DYDataCache *cache);
void DYCachePut(DYDataCache *cache, const char *key, const void *bytes, size_t size);
size_t DYCacheCopy(DYDataCache *cache, const char *key, void *output, size_t capacity);
void DYCacheRemove(DYDataCache *cache, const char *key);
void DYCacheClear(DYDataCache *cache);
typedef struct DYUniqueIndex DYUniqueIndex;
DYUniqueIndex *DYIndexCreate(void);
void DYIndexDestroy(DYUniqueIndex *index);
bool DYIndexInsert(DYUniqueIndex *index, const char *key);
void DYIndexClear(DYUniqueIndex *index);
bool DYCorePlaybackAllowed(bool active, bool foreground, bool uncovered);
double DYCoreBoostRate(double translation, double screenWidth);
#ifdef __cplusplus
}
#endif
#endif
