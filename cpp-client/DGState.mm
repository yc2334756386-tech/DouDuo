#import "DGFeedCache.h"

namespace {
NSString *Scope=@"anonymous";
NSMutableOrderedSet<NSString *> *Seen;
BOOL Dirty=NO,WritePending=NO;
NSString *SeenKey(){return [@"douglass.seen." stringByAppendingString:Scope];}
void ReadSeen(){if(!Seen){NSArray *saved=[NSUserDefaults.standardUserDefaults arrayForKey:SeenKey()];Seen=[[NSMutableOrderedSet alloc]initWithArray:saved?:@[]];}}
}
NSString *DGCurrentFeedScope(void){return Scope;}
void DGFlushSeen(void){if(!Dirty||!Seen)return;Dirty=NO;[NSUserDefaults.standardUserDefaults setObject:Seen.array forKey:SeenKey()];}
void DGSeenScope(NSString *uid){
 NSString *scope=uid.length?uid:@"anonymous";
 if([scope isEqualToString:Scope])return;
 DGFlushSeen();Scope=scope.copy;Seen=nil;
 [NSUserDefaults.standardUserDefaults setObject:Scope forKey:@"douglass.feed.scope"];
 DGCacheSetScope(Scope);ReadSeen();
}
void DGRestoreFeedScope(void){DGSeenScope([NSUserDefaults.standardUserDefaults stringForKey:@"douglass.feed.scope"]?:@"");DGCacheSetScope(Scope);}
NSString *DGWorkIdentity(const Work &work){return work.contentKey.empty()?Text(work.id):[@"asset:" stringByAppendingString:Text(work.contentKey)];}
BOOL DGIsSeenWork(const Work &work){ReadSeen();return [Seen containsObject:Text(work.id)]||[Seen containsObject:DGWorkIdentity(work)];}
BOOL DGContentAllowed(const Work &work){
 NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
 if([prefs boolForKey:@"douglass.filter.ads"]&&work.isAd)return NO;
 BOOL filterLive=[prefs objectForKey:@"douglass.filter.live"]?[prefs boolForKey:@"douglass.filter.live"]:YES;
 return !(filterLive&&work.isLive)&&!DGIsSeenWork(work);
}
void DGRecordViewed(const Work &work){
 if(work.id.empty())return;
 ReadSeen();NSString *idKey=Text(work.id),*identity=DGWorkIdentity(work);
 if(![Seen containsObject:idKey]||![Seen containsObject:identity]){
  [Seen addObject:idKey];[Seen addObject:identity];while(Seen.count>40000)[Seen removeObjectAtIndex:0];Dirty=YES;
 }
 DGCacheConsume(idKey);
 if(!WritePending){WritePending=YES;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{WritePending=NO;DGFlushSeen();});}
}
