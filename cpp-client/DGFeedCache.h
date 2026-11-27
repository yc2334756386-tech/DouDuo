#pragma once
#import "DGCommon.h"
NSString *DGCurrentFeedScope(void);
void DGRestoreFeedScope(void);
BOOL DGIsSeenWork(const Work &work);
void DGRecordViewed(const Work &work);
void DGFlushSeen(void);
NSString *DGWorkIdentity(const Work &work);

void DGCacheSetScope(NSString *scope);
NSArray<NSDictionary *> *DGCacheReadyItems(void);
NSUInteger DGCachePendingCount(void);
void DGCacheIngest(NSArray<NSDictionary *> *records);
void DGCacheSelectWork(NSString *identifier);
void DGCacheConsume(NSString *identifier);
NSURL *DGCacheLocalVideo(NSString *identifier);
void DGCacheSetIdle(BOOL idle);

void DGCacheCancelPrefetch(void);
