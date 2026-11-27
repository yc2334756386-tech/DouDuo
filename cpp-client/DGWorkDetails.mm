#import "DGWorkDetails.h"
#import "DGFeedCache.h"
#import "DGDiagnostics.h"

@interface DGDetailJob:NSObject
@property(nonatomic,strong) DGBridge *bridge;
@property(nonatomic,copy) NSString *identifier,*scope,*key;
@property(nonatomic,strong) NSMutableArray *callbacks;
@end
@implementation DGDetailJob
@end
namespace {
void Pump();
NSMutableArray<DGDetailJob *> *Queue(){static NSMutableArray *queue;static dispatch_once_t once;dispatch_once(&once,^{queue=[NSMutableArray array];[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){Pump();}];});return queue;}
NSMutableDictionary<NSString *,DGDetailJob *> *Pending(){static NSMutableDictionary *pending;static dispatch_once_t once;dispatch_once(&once,^{pending=[NSMutableDictionary dictionary];});return pending;}
NSCache *Cache(){static NSCache *cache;static dispatch_once_t once;dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=90;cache.totalCostLimit=3*1024*1024;});return cache;}
NSUInteger Active=0;
void Pump(){
 if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
 while(Active<2&&Queue().count){DGDetailJob *job=Queue().firstObject;[Queue()removeObjectAtIndex:0];++Active;
  if(![job.scope isEqual:DGCurrentFeedScope()]){--Active;[Pending()removeObjectForKey:job.key];for(DGResult callback in job.callbacks)callback(nil,@"账号已变化");continue;}
  [job.bridge request:@"detail" parameters:@{@"id":job.identifier} completion:^(NSDictionary *result,NSString *error){
   if(Active)--Active;[Pending()removeObjectForKey:job.key];NSDictionary *record=nil;
   for(id item in Array(result[@"items"]))if([item isKindOfClass:NSDictionary.class]&&[Text(String(item[@"id"]))isEqualToString:job.identifier]&&ReadWork(item).playable()&&String(item[@"authorID"]).size()&&!DGWorkNeedsDetails(item)){record=item;break;}
   BOOL current=[job.scope isEqual:DGCurrentFeedScope()];
   if(current&&record){NSData *data=[NSJSONSerialization dataWithJSONObject:record options:0 error:nil];[Cache()setObject:@{@"at":@(NSDate.date.timeIntervalSince1970),@"record":record} forKey:job.key cost:data.length];}
   DGDiagnostic(@"music.work_detail",[NSString stringWithFormat:@"resolved=%d",current&&record!=nil]);
   for(DGResult callback in job.callbacks)callback(current&&record?@{@"items":@[record]}:nil,current?(record?nil:(error?:@"平台未返回完整作品资料")):@"账号已变化");
   Pump();
  }];
 }
}
}
BOOL DGWorkNeedsDetails(NSDictionary *record){return [record[@"needsDetail"]boolValue]||(!String(record[@"authorID"]).size()&&[record[@"mobileBrief"]boolValue]);}
void DGResolveWorkDetails(DGBridge *bridge,NSDictionary *record,BOOL priority,DGResult completion){
 NSString *identifier=Text(String(record[@"id"]));if(!identifier.length){if(completion)completion(nil,@"作品标识缺失");return;}
 NSString *scope=DGCurrentFeedScope(),*key=[scope stringByAppendingFormat:@"|%@",identifier];NSDictionary *cached=[Cache()objectForKey:key];
 if(cached&&NSDate.date.timeIntervalSince1970-[cached[@"at"]doubleValue]<180){if(completion)dispatch_async(dispatch_get_main_queue(),^{BOOL current=[scope isEqualToString:DGCurrentFeedScope()];completion(current?@{@"items":@[cached[@"record"]]}:nil,current?nil:@"账号已变化");});return;}
 DGDetailJob *job=Pending()[key];if(!job){job=[DGDetailJob new];job.bridge=bridge;job.identifier=identifier;job.scope=scope;job.key=key;job.callbacks=[NSMutableArray array];Pending()[key]=job;[Queue()addObject:job];}
 if(completion)[job.callbacks addObject:[completion copy]];
 if(priority&&[Queue()containsObject:job]){[Queue()removeObject:job];[Queue()insertObject:job atIndex:0];}
 Pump();
}
