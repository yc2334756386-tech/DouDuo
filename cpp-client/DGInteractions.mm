#import "DGCommon.h"
@interface DGInteraction:NSObject
@property(nonatomic,strong) DGBridge *bridge;
@property(nonatomic,weak) UIViewController *presenter;
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic) BOOL initialLike,initialCollect,confirmedLike,confirmedCollect,desiredLike,desiredCollect,busyLike,busyCollect;
@property(nonatomic) long long initialLikes,initialCollects;
- (void)publish;
- (void)send:(NSString *)kind;
@end
static NSMutableDictionary<NSString *,DGInteraction *> *DGInteractionEntries(void){static NSMutableDictionary *entries;static dispatch_once_t once;dispatch_once(&once,^{entries=[NSMutableDictionary dictionary];});return entries;}
@implementation DGInteraction
- (void)publish{long long likes=MAX(0,self.initialLikes+(self.desiredLike?1:0)-(self.initialLike?1:0)),collects=MAX(0,self.initialCollects+(self.desiredCollect?1:0)-(self.initialCollect?1:0));[NSNotificationCenter.defaultCenter postNotificationName:@"DouGlassWorkStateChanged" object:nil userInfo:@{@"id":self.identifier,@"liked":@(self.desiredLike),@"collected":@(self.desiredCollect),@"likes":@(likes),@"collects":@(collects),@"pendingLike":@(self.busyLike),@"pendingCollect":@(self.busyCollect)}];}
- (void)send:(NSString *)kind{
 BOOL like=[kind isEqualToString:@"digg"];if(like?self.busyLike:self.busyCollect)return;BOOL target=like?self.desiredLike:self.desiredCollect;BOOL confirmed=like?self.confirmedLike:self.confirmedCollect;if(target==confirmed){[self publish];return;}if(like)self.busyLike=YES;else self.busyCollect=YES;[self publish];
 [self.bridge request:kind parameters:@{@"id":self.identifier,@"add":@(target)} completion:^(NSDictionary *result,NSString *error){
  if(DGInteractionEntries()[self.identifier]!=self)return;
  if(like)self.busyLike=NO;else self.busyCollect=NO;
  BOOL ok=!error&&[result[@"ok"]boolValue];if(ok){if(like)self.confirmedLike=target;else self.confirmedCollect=target;}
  else{if(like)self.desiredLike=self.confirmedLike;else self.desiredCollect=self.confirmedCollect;DGToast(self.presenter,error?:@"平台未确认操作，已恢复显示；请稍后核对");}
  [self publish];if(ok)[self send:kind];
 }];
}
@end
void DGOptimisticAction(DGBridge *bridge,UIViewController *presenter,NSDictionary *snapshot,NSString *kind,BOOL add){
 NSString *identifier=Text(String(snapshot[@"id"]));if(!identifier.length)return;DGInteraction *state=DGInteractionEntries()[identifier];if(!state){state=[DGInteraction new];state.identifier=identifier;state.initialLike=state.confirmedLike=state.desiredLike=[snapshot[@"liked"]boolValue];state.initialCollect=state.confirmedCollect=state.desiredCollect=[snapshot[@"collected"]boolValue];state.initialLikes=Number(snapshot[@"likes"]);state.initialCollects=Number(snapshot[@"collects"]);DGInteractionEntries()[identifier]=state;}state.bridge=bridge;state.presenter=presenter;if([kind isEqualToString:@"digg"])state.desiredLike=add;else state.desiredCollect=add;[[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight]impactOccurred];[state publish];dispatch_async(dispatch_get_main_queue(),^{[state send:kind];});
}
void DGResetInteractions(void){[DGInteractionEntries()removeAllObjects];}

