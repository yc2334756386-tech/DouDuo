#import "DGSession.h"
#import "DGInboxCache.h"
#import "DGDiagnostics.h"
#import <Security/Security.h>
static NSDictionary *DGKey(void){return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"io.github.yc2334756386.douglass.session",(__bridge id)kSecAttrAccount:@"website"};}
static BOOL DGDomain(NSString *domain){return [domain isEqualToString:@"douyin.com"]||[domain hasSuffix:@".douyin.com"];}
static BOOL DGHasSession(NSArray<NSHTTPCookie *> *cookies){for(NSHTTPCookie *cookie in cookies)if(DGDomain(cookie.domain)&&[cookie.name isEqualToString:@"sessionid"]&&cookie.value.length&&(!cookie.expiresDate||cookie.expiresDate.timeIntervalSinceNow>0))return YES;return NO;}
static BOOL DGRestoreInFlight=NO,DGRestoreComplete=NO,DGMayHaveSession=YES;
static NSUInteger DGSessionEpoch=0;
static NSMutableArray *DGRestoreWaiters(void){static NSMutableArray *callbacks;static dispatch_once_t once;dispatch_once(&once,^{callbacks=[NSMutableArray array];});return callbacks;}
static void DGFinishRestore(NSUInteger epoch,BOOL complete){
 if(epoch!=DGSessionEpoch)return;DGRestoreInFlight=NO;DGRestoreComplete=complete;NSArray *callbacks=DGRestoreWaiters().copy;[DGRestoreWaiters()removeAllObjects];
 DGDiagnostic(@"session.restore",[NSString stringWithFormat:@"complete=%d has_session_hint=%d",complete,DGMayHaveSession]);
 for(void (^callback)(void) in callbacks)callback();
}
BOOL DGSessionMayBeSignedIn(void){return DGMayHaveSession;}
BOOL DGBackgroundAudioEnabled(void){return [NSUserDefaults.standardUserDefaults boolForKey:@"douglass.backgroundAudio"];}
void DGSessionConfigure(WKWebViewConfiguration *configuration){
 configuration.websiteDataStore=WKWebsiteDataStore.defaultDataStore;
 NSString *trust=@"(()=>{if(window.__dgTrust)return;window.__dgTrust=1;const tick=()=>{const b=document.querySelector('.trust-login-dialog-button-confirm')||[...document.querySelectorAll('[class*=trust-login-menu] button,[class*=trust-login-menu] [class*=confirm]')].find(e=>(e.innerText||'').trim()==='保存');if(b&&!b.__dgSaved){b.__dgSaved=1;b.click();window.__dgTrustSaved=Date.now()}};const start=()=>{tick();let pending=false;new MutationObserver(()=>{if(pending)return;pending=true;setTimeout(()=>{pending=false;tick()},200)}).observe(document.documentElement,{childList:true,subtree:true})};if(document.documentElement)start();else document.addEventListener('DOMContentLoaded',start)})();";
 [configuration.userContentController addUserScript:[[WKUserScript alloc]initWithSource:trust injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
}
void DGSessionPrepare(WKWebView *web,BOOL blockMedia,void (^completion)(void)){
 NSString *identifier=blockMedia?@"douglass-session-media-v3":@"douglass-session-v3";
 NSString *rules=blockMedia?@"[{\"trigger\":{\"url-filter\":\"douyin[.]com/passport/web/logout\"},\"action\":{\"type\":\"block\"}},{\"trigger\":{\"url-filter\":\".*\",\"resource-type\":[\"media\"]},\"action\":{\"type\":\"block\"}}]":@"[{\"trigger\":{\"url-filter\":\"douyin[.]com/passport/web/logout\"},\"action\":{\"type\":\"block\"}}]";
 DGSessionRestore(^{[WKContentRuleListStore.defaultStore compileContentRuleListForIdentifier:identifier encodedContentRuleList:rules completionHandler:^(WKContentRuleList *list,NSError *error){if(list)[web.configuration.userContentController addContentRuleList:list];if(completion)completion();}];});
}
void DGSessionCapture(void (^completion)(void)){
 if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{DGSessionCapture(completion);});return;}NSUInteger epoch=DGSessionEpoch;
 [WKWebsiteDataStore.defaultDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies){
  if(epoch!=DGSessionEpoch){if(completion)completion();return;}
  if(DGHasSession(cookies)){
   DGMayHaveSession=YES;
   NSMutableArray *records=[NSMutableArray array];for(NSHTTPCookie *cookie in cookies){if(!DGDomain(cookie.domain))continue;NSMutableDictionary *record=[@{@"name":cookie.name,@"value":cookie.value,@"domain":cookie.domain,@"path":cookie.path?:@"/",@"secure":@(cookie.secure),@"httpOnly":@(cookie.HTTPOnly)} mutableCopy];if(cookie.properties[@"SameSite"])record[@"sameSite"]=cookie.properties[@"SameSite"];if(cookie.expiresDate)record[@"expires"]=@(cookie.expiresDate.timeIntervalSince1970);[records addObject:record];}
   NSData *data=[NSJSONSerialization dataWithJSONObject:records options:0 error:nil];if(data){NSDictionary *attributes=@{(__bridge id)kSecValueData:data,(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};OSStatus status=SecItemUpdate((__bridge CFDictionaryRef)DGKey(),(__bridge CFDictionaryRef)attributes);if(status==errSecItemNotFound){NSMutableDictionary *add=[DGKey() mutableCopy];[add addEntriesFromDictionary:attributes];status=SecItemAdd((__bridge CFDictionaryRef)add,NULL);}DGDiagnostic(@"session.capture",[NSString stringWithFormat:@"status=%d cookies=%lu",(int)status,(unsigned long)records.count]);}
  }
  if(completion)completion();
 }];
}
void DGSessionRestore(void (^completion)(void)){
 if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{DGSessionRestore(completion);});return;}
 if(DGRestoreComplete){if(completion)completion();return;}
 if(completion)[DGRestoreWaiters()addObject:[completion copy]];if(DGRestoreInFlight)return;DGRestoreInFlight=YES;NSUInteger epoch=DGSessionEpoch;
 [WKWebsiteDataStore.defaultDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies){
  if(epoch!=DGSessionEpoch)return;
  if(DGHasSession(cookies)){DGMayHaveSession=YES;DGFinishRestore(epoch,YES);return;}
  NSMutableDictionary *query=[DGKey() mutableCopy];query[(__bridge id)kSecReturnData]=@YES;query[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;CFTypeRef value=NULL;OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&value);NSData *data=status==errSecSuccess?CFBridgingRelease(value):nil;
  if(status!=errSecSuccess&&status!=errSecItemNotFound){DGMayHaveSession=YES;DGDiagnostic(@"session.keychain_pending",[NSString stringWithFormat:@"status=%d",(int)status]);DGFinishRestore(epoch,NO);return;}
  NSArray *records=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;if(![records isKindOfClass:NSArray.class]){DGMayHaveSession=NO;DGFinishRestore(epoch,YES);return;}
  NSMutableArray<NSHTTPCookie *> *restored=[NSMutableArray array];
  for(id value in records){if(![value isKindOfClass:NSDictionary.class])continue;NSDictionary *record=value;NSString *domain=[record[@"domain"]isKindOfClass:NSString.class]?record[@"domain"]:@"";if(!DGDomain(domain))continue;NSNumber *expires=record[@"expires"];if(expires&&expires.doubleValue<NSDate.date.timeIntervalSince1970)continue;NSMutableDictionary *properties=[@{NSHTTPCookieName:record[@"name"]?:@"",NSHTTPCookieValue:record[@"value"]?:@"",NSHTTPCookieDomain:domain,NSHTTPCookiePath:record[@"path"]?:@"/"} mutableCopy];if([record[@"secure"]boolValue])properties[NSHTTPCookieSecure]=@"TRUE";if([record[@"httpOnly"]boolValue])properties[@"HttpOnly"]=@"TRUE";if(record[@"sameSite"])properties[@"SameSite"]=record[@"sameSite"];if(expires)properties[NSHTTPCookieExpires]=[NSDate dateWithTimeIntervalSince1970:expires.doubleValue];NSHTTPCookie *cookie=[NSHTTPCookie cookieWithProperties:properties];if(cookie)[restored addObject:cookie];}
  DGMayHaveSession=DGHasSession(restored);if(!DGMayHaveSession){DGFinishRestore(epoch,YES);return;}
  dispatch_group_t group=dispatch_group_create();for(NSHTTPCookie *cookie in restored){dispatch_group_enter(group);[WKWebsiteDataStore.defaultDataStore.httpCookieStore setCookie:cookie completionHandler:^{dispatch_group_leave(group);}];}
  dispatch_group_notify(group,dispatch_get_main_queue(),^{if(epoch!=DGSessionEpoch)return;[WKWebsiteDataStore.defaultDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *stored){if(epoch!=DGSessionEpoch)return;DGFinishRestore(epoch,DGHasSession(stored));}];});
 }];
}
void DGSessionForget(void){++DGSessionEpoch;DGRestoreInFlight=NO;DGRestoreComplete=YES;DGMayHaveSession=NO;NSArray *callbacks=DGRestoreWaiters().copy;[DGRestoreWaiters()removeAllObjects];dispatch_async(dispatch_get_main_queue(),^{for(void (^callback)(void) in callbacks)callback();});DGClearInboxCache();SecItemDelete((__bridge CFDictionaryRef)DGKey());}

