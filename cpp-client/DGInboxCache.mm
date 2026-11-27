#import "DGInboxCache.h"
#import "DGCommon.h"
#import "DGFeedCache.h"
#import <CommonCrypto/CommonDigest.h>

namespace {
constexpr NSUInteger EntryLimit=768*1024;
dispatch_queue_t IO(){static dispatch_queue_t q;static dispatch_once_t once;dispatch_once(&once,^{q=dispatch_queue_create("com.douglass.inbox-cache",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0));});return q;}
NSCache *Memory(){static NSCache *cache;static dispatch_once_t once;dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=12;cache.totalCostLimit=2*1024*1024;});return cache;}
NSURL *Folder(){return [[NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"InboxSnapshots" isDirectory:YES];}
NSString *CacheKey(NSString *key){NSString *scope=DGCurrentFeedScope();if(!key.length||[scope isEqual:@"anonymous"])return nil;NSData *data=[[scope stringByAppendingFormat:@"\n%@",key]dataUsingEncoding:NSUTF8StringEncoding];unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString *name=[NSMutableString string];for(NSUInteger i=0;i<sizeof(digest);i++)[name appendFormat:@"%02x",digest[i]];return name;}
NSURL *File(NSString *key){return [Folder()URLByAppendingPathComponent:[key stringByAppendingPathExtension:@"json"]];}
void Trim(){NSFileManager *files=NSFileManager.defaultManager;NSArray *all=[[files contentsOfDirectoryAtURL:Folder() includingPropertiesForKeys:@[NSURLContentModificationDateKey,NSURLFileSizeKey] options:0 error:nil]sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){NSDate *da=nil,*db=nil;[a getResourceValue:&da forKey:NSURLContentModificationDateKey error:nil];[b getResourceValue:&db forKey:NSURLContentModificationDateKey error:nil];return [db?:NSDate.distantPast compare:da?:NSDate.distantPast];}];NSUInteger count=0;unsigned long long bytes=0;for(NSURL *file in all){NSNumber *size=nil;[file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];bytes+=size.unsignedLongLongValue;if(++count>24||bytes>8*1024*1024)[files removeItemAtURL:file error:nil];}}
}
NSDictionary *DGReadInboxCache(NSString *key){
 NSString *name=CacheKey(key);if(!name)return @{};NSDictionary *saved=[Memory()objectForKey:name];
 if(!saved){NSNumber *size=nil;[File(name)getResourceValue:&size forKey:NSURLFileSizeKey error:nil];if(!size||size.unsignedIntegerValue>EntryLimit)return @{};NSData *data=[NSData dataWithContentsOfURL:File(name)];id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;if(![value isKindOfClass:NSDictionary.class])return @{};saved=value;[Memory()setObject:saved forKey:name cost:data.length];}
 if(![saved[@"time"]isKindOfClass:NSNumber.class]||![saved[@"payload"]isKindOfClass:NSDictionary.class])return @{};double age=NSDate.date.timeIntervalSince1970-[saved[@"time"]doubleValue];return age>=0&&age<=86400?saved[@"payload"]:@{};
}
void DGWriteInboxCache(NSString *key,NSDictionary *payload){
 NSString *name=CacheKey(key);if(!name||!payload)return;NSDictionary *saved=@{@"time":@(NSDate.date.timeIntervalSince1970),@"payload":payload};NSData *data=[NSJSONSerialization dataWithJSONObject:saved options:0 error:nil];if(!data.length||data.length>EntryLimit)return;[Memory()setObject:saved forKey:name cost:data.length];
 dispatch_async(IO(),^{NSFileManager *files=NSFileManager.defaultManager;[files createDirectoryAtURL:Folder() withIntermediateDirectories:YES attributes:nil error:nil];[data writeToURL:File(name) options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:nil];Trim();});
}
void DGClearInboxCache(void){[Memory()removeAllObjects];dispatch_async(IO(),^{[NSFileManager.defaultManager removeItemAtURL:Folder() error:nil];});}
NSArray<NSDictionary *> *DGMergeInboxRows(NSArray *previous,NSArray *incoming,BOOL newestFirst,NSUInteger limit){
 NSMutableArray *order=[NSMutableArray array];NSMutableDictionary *values=[NSMutableDictionary dictionary];
 NSArray *first=newestFirst?incoming:previous,*second=newestFirst?previous:incoming;
 for(NSArray *rows in @[first?:@[],second?:@[]])for(id value in rows){if(![value isKindOfClass:NSDictionary.class])continue;NSString *identifier=Text(String(value[@"id"]));if(!identifier.length)continue;if(!values[identifier]){[order addObject:identifier];values[identifier]=value;}else if(rows==incoming)values[identifier]=value;}
 NSMutableArray *result=[NSMutableArray array];NSUInteger start=!newestFirst&&order.count>limit?order.count-limit:0;
 for(NSUInteger i=start;i<order.count&&result.count<limit;i++)[result addObject:values[order[i]]];return result;
}
void DGReloadInboxRows(UITableView *table,NSArray *previous,NSArray *next){
 if(previous.count!=next.count||[table numberOfRowsInSection:0]!=(NSInteger)previous.count){[table reloadData];return;}
 NSMutableArray *changed=[NSMutableArray array];
 for(NSUInteger i=0;i<next.count;i++){if(![Text(String(previous[i][@"id"]))isEqualToString:Text(String(next[i][@"id"]))]){[table reloadData];return;}if(![previous[i]isEqual:next[i]])[changed addObject:[NSIndexPath indexPathForRow:i inSection:0]];}
 if(changed.count)[UIView performWithoutAnimation:^{[table reloadRowsAtIndexPaths:changed withRowAnimation:UITableViewRowAnimationNone];}];
}
void DGInboxUpdateNoticeCounts(NSArray *counts){
 NSMutableDictionary *state=[DGReadInboxCache(@"notice-badges")mutableCopy],*values=[NSMutableDictionary dictionary];
 for(id raw in counts){if(![raw isKindOfClass:NSDictionary.class])continue;NSInteger group=Number(raw[@"group"]);if(group>0)values[[@(group)stringValue]]=@(MAX(0,Number(raw[@"count"])));}
 state[@"counts"]=values;DGWriteInboxCache(@"notice-badges",state);[NSNotificationCenter.defaultCenter postNotificationName:@"DGInboxUnreadChanged" object:nil];
}
void DGInboxMarkNoticesRead(NSInteger group){
 NSMutableDictionary *state=[DGReadInboxCache(@"notice-badges")mutableCopy];
 NSMutableDictionary *values=[state[@"counts"]isKindOfClass:NSDictionary.class]?[state[@"counts"]mutableCopy]:[NSMutableDictionary dictionary];
 NSMutableDictionary *mask=[state[@"mask"]isKindOfClass:NSDictionary.class]?[state[@"mask"]mutableCopy]:[NSMutableDictionary dictionary];
 NSArray *groups=group==700?@[@700,@2,@3,@6,@401]:@[@(group)];
 for(NSNumber *value in groups){NSString *key=value.stringValue;mask[key]=@(NSDate.date.timeIntervalSince1970+30);values[key]=@0;}
 state[@"counts"]=values;state[@"mask"]=mask;DGWriteInboxCache(@"notice-badges",state);[NSNotificationCenter.defaultCenter postNotificationName:@"DGInboxUnreadChanged" object:nil];
}
BOOL DGInboxCategoryUnread(BOOL followers){
 NSDictionary *state=DGReadInboxCache(@"notice-badges"),*counts=[state[@"counts"]isKindOfClass:NSDictionary.class]?state[@"counts"]:@{},*mask=[state[@"mask"]isKindOfClass:NSDictionary.class]?state[@"mask"]:@{};
 auto count=[&](NSString *key)->long long{return [mask[key]doubleValue]>NSDate.date.timeIntervalSince1970?0:MAX(0,Number(counts[key]));};
 if(followers)return count(@"401")>0;
 if(counts[@"2"]||counts[@"3"]||counts[@"6"])return count(@"2")>0||count(@"3")>0||count(@"6")>0;
 return count(@"700")>count(@"401");
}
void DGInboxMarkConversationRead(NSString *identifier){
 if(!identifier.length)return;NSMutableArray *rows=[Array(DGReadInboxCache(@"conversations")[@"items"])mutableCopy];
 for(NSUInteger i=0;i<rows.count;i++)if([Text(String(rows[i][@"id"]))isEqualToString:identifier]){NSMutableDictionary *row=[rows[i]mutableCopy];row[@"unread"]=@NO;row[@"unreadCount"]=@0;row[@"badge"]=@"";rows[i]=row;break;}
 DGWriteInboxCache(@"conversations",@{@"items":rows});[NSNotificationCenter.defaultCenter postNotificationName:@"DGInboxUnreadChanged" object:nil];
}
