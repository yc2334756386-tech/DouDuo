#import "DGMobileMusic.h"
#import "DGDiagnostics.h"
#import "DGFeedCache.h"

namespace {
BOOL ValidID(NSString *value){return [value isKindOfClass:NSString.class]&&value.length&&value.length<=24&&[value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location==NSNotFound;}
NSURLSession *Session(){static NSURLSession *session;static dispatch_once_t once;dispatch_once(&once,^{NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;config.URLCache=nil;config.HTTPCookieStorage=nil;config.HTTPShouldSetCookies=NO;config.HTTPMaximumConnectionsPerHost=2;config.timeoutIntervalForRequest=12;config.timeoutIntervalForResource=16;session=[NSURLSession sessionWithConfiguration:config];});return session;}
}
void DGReadMobileMusic(DGBridge *bridge,NSString *operation,NSDictionary *parameters,DGResult completion){
 NSString *identifier=Text(String(parameters[@"id"]));BOOL detail=[operation isEqualToString:@"musicDetail"];
 if(!ValidID(identifier)){completion(nil,@"平台未提供有效原声标识");return;}
 NSString *cursor=Text(String(parameters[@"cursor"]));if(!ValidID(cursor))cursor=@"0";
 NSURLComponents *url=[NSURLComponents componentsWithString:detail?@"https://www.iesdouyin.com/web/api/v2/music/info/":@"https://www.iesdouyin.com/web/api/v2/music/list/aweme/"];
 NSMutableArray *query=[NSMutableArray arrayWithObject:[NSURLQueryItem queryItemWithName:@"music_id" value:identifier]];
 if(!detail)for(NSArray *pair in @[@[@"count",@"15"],@[@"cursor",cursor],@[@"aid",@"1128"],@[@"screen_limit",@"3"],@[@"download_click_limit",@"0"]])[query addObject:[NSURLQueryItem queryItemWithName:pair[0] value:pair[1]]];
 url.queryItems=query;NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url.URL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:12];
 [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1" forHTTPHeaderField:@"User-Agent"];
 [request setValue:[NSString stringWithFormat:@"https://www.iesdouyin.com/share/music/%@/",identifier] forHTTPHeaderField:@"Referer"];
 [request setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];
 NSString *scope=DGCurrentFeedScope();
 DGDiagnostic(@"music.mobile_request",[NSString stringWithFormat:@"operation=%@ music_id=%@ cursor=%@",operation,identifier,cursor]);
 [[Session()dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
  NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
  NSString *raw=data.length&&data.length<=4*1024*1024?[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]:nil;
  dispatch_async(dispatch_get_main_queue(),^{
   if(![scope isEqualToString:DGCurrentFeedScope()]){completion(nil,@"账号状态已变化，请重新打开原声页");return;}
   DGDiagnostic(@"music.mobile_response",[NSString stringWithFormat:@"operation=%@ status=%ld bytes=%lu code=%ld",operation,(long)status,(unsigned long)data.length,(long)error.code]);
   if(error||status<200||status>=300||!raw.length){completion(nil,@"原声移动网页接口未返回内容，可稍后重试；已识别作品会保留");return;}
   [bridge request:@"normalizeMusicResponse" parameters:@{@"id":identifier,@"detail":@(detail),@"json":raw} completion:completion];
  });
 }]resume];
}
