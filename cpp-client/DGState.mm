#import "DGCommon.h"
static NSMutableOrderedSet<NSString *> *DGSeen;
static NSString *DGScope=@"anonymous";
static NSString *DGSeenKey(void){return [@"douglass.seen." stringByAppendingString:DGScope];}
static void DGReadSeen(void){if(!DGSeen){NSArray *saved=[NSUserDefaults.standardUserDefaults arrayForKey:DGSeenKey()];DGSeen=[[NSMutableOrderedSet alloc]initWithArray:saved?:@[]];}}
void DGSeenScope(NSString *uid){NSString *scope=uid.length?uid:@"anonymous";if([DGScope isEqualToString:scope])return;DGScope=scope.copy;DGSeen=nil;DGReadSeen();}
BOOL DGContentAllowed(const Work &work){NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;if([prefs boolForKey:@"douglass.filter.ads"]&&work.isAd)return NO;BOOL live=[prefs objectForKey:@"douglass.filter.live"]?[prefs boolForKey:@"douglass.filter.live"]:YES;if(live&&work.isLive)return NO;if([prefs boolForKey:@"douglass.filter.seen"]){DGReadSeen();if([DGSeen containsObject:Text(work.id)])return NO;}return YES;}
void DGMarkSeen(NSString *identifier){if(!identifier.length)return;DGReadSeen();if([DGSeen containsObject:identifier])return;[DGSeen addObject:identifier];while(DGSeen.count>4000)[DGSeen removeObjectAtIndex:0];[NSUserDefaults.standardUserDefaults setObject:DGSeen.array forKey:DGSeenKey()];}
