#import "DGCommon.h"
static NSMutableOrderedSet<NSString *> *DGSeen;
static NSString *DGScope=@"anonymous";
static NSString *DGSeenKey(void){return [@"douglass.seen." stringByAppendingString:DGScope];}
static void DGReadSeen(void){if(!DGSeen){NSArray *saved=[NSUserDefaults.standardUserDefaults arrayForKey:DGSeenKey()];DGSeen=[[NSMutableOrderedSet alloc]initWithArray:saved?:@[]];}}
void DGSeenScope(NSString *uid){NSString *scope=uid.length?uid:@"anonymous";if([DGScope isEqualToString:scope])return;DGScope=scope.copy;DGSeen=nil;DGReadSeen();}
BOOL DGContentAllowed(const Work &work){NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;if([prefs boolForKey:@"douglass.filter.ads"]&&work.isAd)return NO;BOOL live=[prefs objectForKey:@"douglass.filter.live"]?[prefs boolForKey:@"douglass.filter.live"]:YES;if(live&&work.isLive)return NO;if([prefs boolForKey:@"douglass.filter.seen"]){DGReadSeen();if([DGSeen containsObject:Text(work.id)])return NO;}return YES;}
void DGMarkSeen(NSString *identifier){if(!identifier.length)return;DGReadSeen();if([DGSeen containsObject:identifier])return;[DGSeen addObject:identifier];while(DGSeen.count>4000)[DGSeen removeObjectAtIndex:0];[NSUserDefaults.standardUserDefaults setObject:DGSeen.array forKey:DGSeenKey()];}


static NSMutableOrderedSet<NSString *> *OwnDanmakuIDs;
static NSString *DanmakuLoadedScope;
static NSString *DanmakuKey(NSString *scope){return [@"douglass.ownDanmaku." stringByAppendingString:scope];}
static void LoadOwnDanmaku(void){
 if([DanmakuLoadedScope isEqualToString:DGScope])return;
 DanmakuLoadedScope=DGScope.copy;
 OwnDanmakuIDs=[[NSMutableOrderedSet alloc]initWithArray:[NSUserDefaults.standardUserDefaults arrayForKey:DanmakuKey(DGScope)]?:@[]];
}
BOOL DGIsOwnDanmaku(NSString *identifier){if(!identifier.length||[DGScope isEqualToString:@"anonymous"])return NO;LoadOwnDanmaku();return [OwnDanmakuIDs containsObject:identifier];}
void DGRememberOwnDanmaku(NSString *identifier,NSString *uid){
 if(!identifier.length)return;
 NSString *scope=uid.length?uid:DGScope;if([scope isEqualToString:@"anonymous"])return;
 LoadOwnDanmaku();
 NSMutableOrderedSet *ids=[scope isEqualToString:DGScope]?OwnDanmakuIDs:[[NSMutableOrderedSet alloc]initWithArray:[NSUserDefaults.standardUserDefaults arrayForKey:DanmakuKey(scope)]?:@[]];
 [ids addObject:identifier];while(ids.count>600)[ids removeObjectAtIndex:0];
 [NSUserDefaults.standardUserDefaults setObject:ids.array forKey:DanmakuKey(scope)];
}
