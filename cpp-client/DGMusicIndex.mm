#import "DGMusicIndex.h"
#import "DGFeedCache.h"

namespace {
constexpr NSUInteger Limit=240;
NSString *IndexedScope;
NSMutableArray<NSDictionary *> *Rows;
NSMutableDictionary<NSString *,NSDictionary *> *ByWork;
NSURL *IndexFile(){return [[NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"KnownOriginalSoundWorks.json"];}
dispatch_queue_t IndexIO(){static dispatch_queue_t queue;static dispatch_once_t once;dispatch_once(&once,^{queue=dispatch_queue_create("com.douglass.music-index",DISPATCH_QUEUE_SERIAL);});return queue;}
BOOL Pending=NO;NSUInteger Generation=0;
void Load(){
 NSString *scope=DGCurrentFeedScope();if([IndexedScope isEqualToString:scope])return;
 BOOL first=!IndexedScope;IndexedScope=scope.copy;++Generation;Pending=NO;
 Rows=[NSMutableArray array];ByWork=[NSMutableDictionary dictionary];
 NSData *data=first?[NSData dataWithContentsOfURL:IndexFile()]:nil;
 id saved=data.length&&data.length<=2*1024*1024?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
 if(!first)dispatch_async(IndexIO(),^{[NSFileManager.defaultManager removeItemAtURL:IndexFile() error:nil];});
 if(![saved isKindOfClass:NSDictionary.class]||![saved[@"scope"]isEqual:scope])return;
 double now=NSDate.date.timeIntervalSince1970;
 for(NSDictionary *entry in Array(saved[@"items"])){
  if(![entry isKindOfClass:NSDictionary.class]||now-[entry[@"at"]doubleValue]>7200||now<[entry[@"at"]doubleValue])continue;
  NSDictionary *work=entry[@"work"];if(![work isKindOfClass:NSDictionary.class])continue;
  NSString *key=Text(String(work[@"id"]));if(!key.length||ByWork[key])continue;
  [Rows addObject:entry];ByWork[key]=entry;if(Rows.count==Limit)break;
 }
}
void SaveSoon(){
 if(Pending)return;Pending=YES;NSUInteger generation=Generation;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  if(generation!=Generation)return;Pending=NO;
  NSDictionary *index=@{@"scope":IndexedScope,@"items":Rows.copy};
  dispatch_async(IndexIO(),^{NSData *data=[NSJSONSerialization dataWithJSONObject:index options:0 error:nil];if(data.length&&data.length<2*1024*1024)[data writeToURL:IndexFile() options:NSDataWritingAtomic error:nil];});
 });
}
}
void DGIndexMusicWorks(NSArray<NSDictionary *> *records){
 if(!records.count)return;
 BOOL changed=NO;
 for(NSDictionary *record in records){
  if(![record isKindOfClass:NSDictionary.class])continue;
  NSString *music=Text(String(record[@"musicID"])),*work=Text(String(record[@"id"]));
  if(!music.length||!work.length||(!String(record[@"play"]).size()&&!Array(record[@"images"]).count))continue;
  Load();NSDictionary *previous=ByWork[work];
  if(previous&&[previous[@"work"]isEqual:record])continue;
  if(previous)[Rows removeObjectIdenticalTo:previous];
  NSDictionary *entry=@{@"work":record,@"at":@(NSDate.date.timeIntervalSince1970)};
  [Rows insertObject:entry atIndex:0];ByWork[work]=entry;changed=YES;
 }
 while(Rows.count>Limit){NSString *work=Text(String(Rows.lastObject[@"work"][@"id"]));[ByWork removeObjectForKey:work];[Rows removeLastObject];}
 if(changed)SaveSoon();
}
NSArray<NSDictionary *> *DGIndexedMusicWorks(NSString *musicID){
 if(!musicID.length)return @[];
 Load();NSMutableArray *results=[NSMutableArray array];double now=NSDate.date.timeIntervalSince1970;
 for(NSDictionary *entry in Rows){NSDictionary *work=entry[@"work"];if(now-[entry[@"at"]doubleValue]<=7200&&[Text(String(work[@"musicID"]))isEqualToString:musicID])[results addObject:work];}
 return results;
}
