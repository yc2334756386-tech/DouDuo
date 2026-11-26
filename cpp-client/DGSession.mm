#import "DGSession.h"
#import <Security/Security.h>
static NSDictionary *DGKey(void){return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"io.github.yc2334756386.douglass.session",(__bridge id)kSecAttrAccount:@"website"};}
static BOOL DGDomain(NSString *domain){return [domain isEqualToString:@"douyin.com"]||[domain hasSuffix:@".douyin.com"];}
static BOOL DGHasSession(NSArray<NSHTTPCookie *> *cookies){for(NSHTTPCookie *cookie in cookies)if(DGDomain(cookie.domain)&&[cookie.name isEqualToString:@"sessionid"]&&cookie.value.length)return YES;return NO;}
BOOL DGBackgroundAudioEnabled(void){return [NSUserDefaults.standardUserDefaults boolForKey:@"douglass.backgroundAudio"];}
void DGSessionConfigure(WKWebViewConfiguration *configuration){
 configuration.websiteDataStore=WKWebsiteDataStore.defaultDataStore;
 NSString *trust=@"(()=>{if(window.__dgTrust)return;window.__dgTrust=1;const tick=()=>{const b=document.querySelector('.trust-login-dialog-button-confirm')||[...document.querySelectorAll('[class*=trust-login-menu] button,[class*=trust-login-menu] [class*=confirm]')].find(e=>(e.innerText||'').trim()==='保存');if(b&&!b.__dgSaved){b.__dgSaved=1;b.click();window.__dgTrustSaved=Date.now()}};const start=()=>{tick();let pending=false;new MutationObserver(()=>{if(pending)return;pending=true;setTimeout(()=>{pending=false;tick()},200)}).observe(document.documentElement,{childList:true,subtree:true})};if(document.documentElement)start();else document.addEventListener('DOMContentLoaded',start)})();";
 [configuration.userContentController addUserScript:[[WKUserScript alloc]initWithSource:trust injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
}
void DGSessionPrepare(WKWebView *web,BOOL blockMedia,void (^completion)(void)){
 NSString *identifier=blockMedia?@"douglass-session-media-v3":@"douglass-session-v3";
 NSString *rules=blockMedia?@"[{\"trigger\":{\"url-filter\":\"douyin[.]com/passport/web/logout\"},\"action\":{\"type\":\"block\"}},{\"trigger\":{\"url-filter\":\".*\",\"resource-type\":[\"media\"]},\"action\":{\"type\":\"block\"}}]":@"[{\"trigger\":{\"url-filter\":\"douyin[.]com/passport/web/logout\"},\"action\":{\"type\":\"block\"}}]";
 [WKContentRuleListStore.defaultStore compileContentRuleListForIdentifier:identifier encodedContentRuleList:rules completionHandler:^(WKContentRuleList *list,NSError *error){if(list)[web.configuration.userContentController addContentRuleList:list];if(completion)completion();}];
}
void DGSessionCapture(void (^completion)(void)){
 [WKWebsiteDataStore.defaultDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies){
  if(DGHasSession(cookies)){
   NSMutableArray *records=[NSMutableArray array];for(NSHTTPCookie *cookie in cookies){if(!DGDomain(cookie.domain))continue;NSMutableDictionary *record=[@{@"name":cookie.name,@"value":cookie.value,@"domain":cookie.domain,@"path":cookie.path?:@"/",@"secure":@(cookie.secure),@"httpOnly":@(cookie.HTTPOnly)} mutableCopy];if(cookie.properties[@"SameSite"])record[@"sameSite"]=cookie.properties[@"SameSite"];if(cookie.expiresDate)record[@"expires"]=@(cookie.expiresDate.timeIntervalSince1970);[records addObject:record];}
   NSData *data=[NSJSONSerialization dataWithJSONObject:records options:0 error:nil];if(data){NSDictionary *attributes=@{(__bridge id)kSecValueData:data,(__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};OSStatus status=SecItemUpdate((__bridge CFDictionaryRef)DGKey(),(__bridge CFDictionaryRef)attributes);if(status==errSecItemNotFound){NSMutableDictionary *add=[DGKey() mutableCopy];[add addEntriesFromDictionary:attributes];SecItemAdd((__bridge CFDictionaryRef)add,NULL);}}
  }
  if(completion)completion();
 }];
}
void DGSessionRestore(void (^completion)(void)){
 static BOOL attempted=NO;if(attempted){if(completion)completion();return;}attempted=YES;
 [WKWebsiteDataStore.defaultDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies){
  if(DGHasSession(cookies)){if(completion)completion();return;}
  NSMutableDictionary *query=[DGKey() mutableCopy];query[(__bridge id)kSecReturnData]=@YES;query[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;CFTypeRef value=NULL;OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&value);NSData *data=status==errSecSuccess?CFBridgingRelease(value):nil;
  NSArray *records=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;if(![records isKindOfClass:NSArray.class]){if(completion)completion();return;}
  dispatch_group_t group=dispatch_group_create();for(NSDictionary *record in records){if(!DGDomain(record[@"domain"]))continue;NSNumber *expires=record[@"expires"];if(expires&&expires.doubleValue<NSDate.date.timeIntervalSince1970)continue;NSMutableDictionary *properties=[@{NSHTTPCookieName:record[@"name"]?:@"",NSHTTPCookieValue:record[@"value"]?:@"",NSHTTPCookieDomain:record[@"domain"],NSHTTPCookiePath:record[@"path"]?:@"/"} mutableCopy];if([record[@"secure"]boolValue])properties[NSHTTPCookieSecure]=@"TRUE";if([record[@"httpOnly"]boolValue])properties[@"HttpOnly"]=@"TRUE";if(record[@"sameSite"])properties[@"SameSite"]=record[@"sameSite"];if(expires)properties[NSHTTPCookieExpires]=[NSDate dateWithTimeIntervalSince1970:expires.doubleValue];NSHTTPCookie *cookie=[NSHTTPCookie cookieWithProperties:properties];if(cookie){dispatch_group_enter(group);[WKWebsiteDataStore.defaultDataStore.httpCookieStore setCookie:cookie completionHandler:^{dispatch_group_leave(group);}];}}
  dispatch_group_notify(group,dispatch_get_main_queue(),^{if(completion)completion();});
 }];
}
void DGSessionForget(void){SecItemDelete((__bridge CFDictionaryRef)DGKey());}

