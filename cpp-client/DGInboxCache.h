#pragma once
#import <UIKit/UIKit.h>
NSDictionary *DGReadInboxCache(NSString *key);
void DGWriteInboxCache(NSString *key,NSDictionary *payload);
void DGClearInboxCache(void);
NSArray<NSDictionary *> *DGMergeInboxRows(NSArray *previous,NSArray *incoming,BOOL newestFirst,NSUInteger limit);
void DGReloadInboxRows(UITableView *table,NSArray *previous,NSArray *next);
void DGInboxUpdateNoticeCounts(NSArray *counts);
void DGInboxMarkNoticesRead(NSInteger group);
BOOL DGInboxCategoryUnread(BOOL followers);
void DGInboxMarkConversationRead(NSString *identifier);
