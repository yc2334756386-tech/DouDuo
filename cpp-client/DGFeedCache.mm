#import "DGFeedCache.h"
#import "DGDiagnostics.h"
#include <cstring>

namespace {
constexpr NSUInteger QueueLimit=50;
constexpr unsigned long long FileLimit=45ULL*1024*1024,DiskLimit=384ULL*1024*1024;
NSString *SafeKey(NSString *key){
 if(!key.length||key.length>100)return nil;
 NSCharacterSet *safe=[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-"];
 return [key rangeOfCharacterFromSet:safe.invertedSet].location==NSNotFound?key:nil;
}
NSURL *Root(){return [[NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"Unwatched" isDirectory:YES];}
dispatch_queue_t Disk(){static dispatch_queue_t queue;static dispatch_once_t once;dispatch_once(&once,^{queue=dispatch_queue_create("com.douglass.feed-cache",DISPATCH_QUEUE_SERIAL);});return queue;}
dispatch_queue_t Transfers(){
 static dispatch_queue_t queue;static dispatch_once_t once;
 dispatch_once(&once,^{queue=dispatch_queue_create("com.douglass.feed-cache-transfers",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0));});
 return queue;
}
void Remove(NSURL *file){if(file)dispatch_async(Disk(),^{[NSFileManager.defaultManager removeItemAtURL:file error:nil];});}
BOOL LooksLikeVideo(NSURL *file){
 NSFileHandle *handle=[NSFileHandle fileHandleForReadingFromURL:file error:nil];if(!handle)return NO;
 NSData *head=[handle readDataUpToLength:64 error:nil];[handle closeAndReturnError:nil];
 if(head.length<12)return NO;
 const unsigned char *b=(const unsigned char *)head.bytes;
 for(NSUInteger i=4;i+4<=head.length;i+=4)if(memcmp(b+i,"ftyp",4)==0)return YES;
 return NO;
}
}
@interface DGUnwatchedCache:NSObject<NSURLSessionDownloadDelegate>
- (void)setScope:(NSString *)scope;
- (NSArray<NSDictionary *> *)ready;
- (NSUInteger)pendingCount;
- (void)ingest:(NSArray<NSDictionary *> *)records;
- (void)select:(NSString *)identifier;
- (void)consume:(NSString *)identifier;
- (NSURL *)urlFor:(NSString *)identifier;
- (void)setIdle:(BOOL)idle;
- (void)cancelPrefetch;
@end
@implementation DGUnwatchedCache {
 NSString *_scope,*_current,*_downloading;
 NSURL *_folder,*_currentFile;
 NSMutableArray<NSDictionary *> *_queue;
 NSMutableDictionary<NSString *,NSNumber *> *_mediaSizes;
 NSMutableSet<NSString *> *_failed,*_staging;
 NSURLSession *_session;
 NSURLSessionDownloadTask *_task;
 BOOL _idle,_suspended,_persistQueued;
 NSUInteger _generation;
}
- (instancetype)init {
 if((self=[super init])){
  NSURLSessionConfiguration *config=NSURLSessionConfiguration.ephemeralSessionConfiguration;
  config.URLCache=nil;config.HTTPCookieStorage=nil;config.HTTPShouldSetCookies=NO;
  config.timeoutIntervalForRequest=25;config.timeoutIntervalForResource=60;config.HTTPMaximumConnectionsPerHost=1;
  config.allowsConstrainedNetworkAccess=NO;config.allowsExpensiveNetworkAccess=NO;
  NSOperationQueue *delegate=[NSOperationQueue new];delegate.qualityOfService=NSQualityOfServiceUtility;delegate.maxConcurrentOperationCount=1;
  _session=[NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:delegate];
 }
 return self;
}
- (NSURL *)file:(NSString *)identifier {
 NSString *safe=SafeKey(identifier);return safe?[_folder URLByAppendingPathComponent:[safe stringByAppendingPathExtension:@"mp4"]]:nil;
}
- (void)setScope:(NSString *)scope {
 scope=SafeKey(scope)?:@"anonymous";
 if([_scope isEqualToString:scope])return;
 ++_generation;NSURL *oldFolder=_folder;[_task cancel];_task=nil;_downloading=nil;_suspended=NO;_persistQueued=NO;_current=nil;_currentFile=nil;
 _scope=scope.copy;_folder=[Root() URLByAppendingPathComponent:scope isDirectory:YES];
 _queue=[NSMutableArray array];_mediaSizes=[NSMutableDictionary dictionary];_failed=[NSMutableSet set];_staging=[NSMutableSet set];
 NSData *manifest=[NSData dataWithContentsOfURL:[_folder URLByAppendingPathComponent:@"unwatched.json"]];
 NSDictionary *saved=manifest.length?[NSJSONSerialization JSONObjectWithData:manifest options:0 error:nil]:nil;
 if([saved isKindOfClass:NSDictionary.class])for(NSDictionary *row in Array(saved[@"records"])){
  if(![row isKindOfClass:NSDictionary.class])continue;
  NSString *identifier=SafeKey(Text(String(row[@"id"])));if(!identifier.length||DGIsSeenWork(ReadWork(row)))continue;
  [_queue addObject:row];NSURL *file=[self file:identifier];
  NSNumber *bytes=nil;[file getResourceValue:&bytes forKey:NSURLFileSizeKey error:nil];if(bytes.unsignedLongLongValue>0)_mediaSizes[identifier]=bytes;
  if(_queue.count==QueueLimit)break;
 }
 NSURL *folder=_folder;NSSet *files=[NSSet setWithArray:_mediaSizes.allKeys];
 dispatch_async(Disk(),^{
  NSFileManager *manager=NSFileManager.defaultManager;
  if(oldFolder&&![oldFolder isEqual:folder])[manager removeItemAtURL:oldFolder error:nil];
  [manager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
  for(NSURL *file in [manager contentsOfDirectoryAtURL:folder includingPropertiesForKeys:nil options:0 error:nil])
   if([file.pathExtension isEqualToString:@"mp4"]&&![files containsObject:file.lastPathComponent.stringByDeletingPathExtension])[manager removeItemAtURL:file error:nil];
 });
}
- (NSArray<NSDictionary *> *)ready {
 NSMutableArray *items=[NSMutableArray array];
 for(NSDictionary *row in _queue){NSString *identifier=Text(String(row[@"id"]));Work work=ReadWork(row);if(_mediaSizes[identifier]&&DGContentAllowed(work))[items addObject:row];}
 return items;
}
- (NSUInteger)pendingCount {
 NSUInteger count=0;for(NSDictionary *row in _queue)if(![_failed containsObject:row[@"id"]]||_mediaSizes[row[@"id"]])++count;return count;
}
- (void)persist {
 if(_persistQueued||!_folder)return;_persistQueued=YES;NSUInteger generation=_generation;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,120*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
  if(generation!=self->_generation)return;self->_persistQueued=NO;
  NSArray *snapshot=self->_queue.copy;NSURL *folder=self->_folder;
  dispatch_async(Disk(),^{
   NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"records":snapshot} options:0 error:nil];if(data)[data writeToURL:[folder URLByAppendingPathComponent:@"unwatched.json"] options:NSDataWritingAtomic error:nil];
  });
 });
}
- (void)ingest:(NSArray<NSDictionary *> *)records {
 NSIndexSet *failed=[_queue indexesOfObjectsPassingTest:^BOOL(NSDictionary *row,NSUInteger i,BOOL *stop){NSString *key=row[@"id"];return [_failed containsObject:key]&&!_mediaSizes[key]&&![_downloading isEqualToString:key];}];
 if(failed.count)[_queue removeObjectsAtIndexes:failed];
 NSMutableSet *keys=[NSMutableSet set];for(NSDictionary *row in _queue)[keys addObject:DGWorkIdentity(ReadWork(row))];
 BOOL added=failed.count>0;
 for(NSDictionary *row in records){
  if(_queue.count>=QueueLimit)break;
  Work work=ReadWork(row);NSString *identifier=SafeKey(Text(work.id)),*identity=DGWorkIdentity(work);
  NSString *url=Text(work.play);
  if(!identifier.length||[_failed containsObject:identifier]||work.photo()||work.isLive||!url.length||[url.lowercaseString containsString:@".m3u8"]||!DGContentAllowed(work)||[keys containsObject:identity])continue;
  [keys addObject:identity];[_queue addObject:row];added=YES;
 }
 if(added)[self persist];[self pump];
}
- (void)select:(NSString *)identifier {
 if([_current isEqualToString:identifier])return;
 Remove(_currentFile);_currentFile=nil;_current=identifier.copy;
}
- (void)consume:(NSString *)identifier {
 if(!identifier.length)return;
 NSUInteger where=[_queue indexOfObjectPassingTest:^BOOL(NSDictionary *row,NSUInteger i,BOOL *stop){return [row[@"id"] isEqual:identifier];}];
 if(where==NSNotFound)return;
 [_queue removeObjectAtIndex:where];
 if(_mediaSizes[identifier]){NSURL *file=[self file:identifier];if([_current isEqualToString:identifier])_currentFile=file;else Remove(file);}
 [_mediaSizes removeObjectForKey:identifier];
 if([_downloading isEqualToString:identifier]){[_task cancel];_task=nil;_downloading=nil;_suspended=NO;}
 [self persist];DGDiagnostic(@"cache.consume",[NSString stringWithFormat:@"queued=%lu ready=%lu",(unsigned long)_queue.count,(unsigned long)_mediaSizes.count]);[self pump];
}
- (NSURL *)urlFor:(NSString *)identifier {
 if([_current isEqualToString:identifier]&&_currentFile)return _currentFile;
 return _mediaSizes[identifier]?[self file:identifier]:nil;
}
- (void)setIdle:(BOOL)idle {
 _idle=idle;
 NSURLSessionDownloadTask *task=_task;
 if(task&&!idle&&!_suspended){_suspended=YES;dispatch_async(Transfers(),^{[task suspend];});}
 else if(task&&idle&&_suspended){_suspended=NO;dispatch_async(Transfers(),^{[task resume];});}
 if(idle)[self pump];
}
- (void)cancelPrefetch {
 _idle=NO;
 NSURLSessionDownloadTask *task=_task;_task=nil;_downloading=nil;_suspended=NO;dispatch_async(Transfers(),^{[task cancel];});
}
- (void)pump {
 if(!_idle||_task||_staging.count||!_folder||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
 unsigned long long total=0;for(NSNumber *size in _mediaSizes.allValues)total+=size.unsignedLongLongValue;
 if(total>=DiskLimit)return;
 for(NSDictionary *row in _queue){
  Work work=ReadWork(row);NSString *identifier=Text(work.id);
  if(_mediaSizes[identifier]||[_staging containsObject:identifier]||[_failed containsObject:identifier]||DGIsSeenWork(work)||[_current isEqualToString:identifier])continue;
  NSURL *url=[NSURL URLWithString:Text(work.play)];if(![url.scheme.lowercaseString isEqualToString:@"https"]&&![url.scheme.lowercaseString isEqualToString:@"http"])continue;
  NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:25];
  [request setValue:DGUserAgent() forHTTPHeaderField:@"User-Agent"];[request setValue:@"https://www.douyin.com/" forHTTPHeaderField:@"Referer"];
  _downloading=identifier;_task=[_session downloadTaskWithRequest:request];_task.priority=NSURLSessionTaskPriorityLow;_suspended=NO;[_task resume];return;
 }
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)written totalBytesExpectedToWrite:(int64_t)expected {
 if(written>(int64_t)FileLimit||expected>(int64_t)FileLimit)[task cancel];
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location {
 NSInteger status=[task.response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)task.response).statusCode:0;
 NSNumber *size=nil;[location getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
 if(status!=200||size.unsignedLongLongValue==0||size.unsignedLongLongValue>FileLimit||!LooksLikeVideo(location)){
  dispatch_async(dispatch_get_main_queue(),^{if(task==self->_task&&self->_downloading)[self->_failed addObject:self->_downloading];});return;
 }
 NSFileManager *files=NSFileManager.defaultManager;NSURL *stage=[[files temporaryDirectory] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
 if(![files moveItemAtURL:location toURL:stage error:nil]){dispatch_async(dispatch_get_main_queue(),^{if(task==self->_task&&self->_downloading)[self->_failed addObject:self->_downloading];});return;}
 dispatch_async(dispatch_get_main_queue(),^{
  if(task!=self->_task){Remove(stage);return;}
  NSString *identifier=self->_downloading;NSURL *destination=[self file:identifier];NSUInteger generation=self->_generation;
  unsigned long long total=size.unsignedLongLongValue;for(NSNumber *used in self->_mediaSizes.allValues)total+=used.unsignedLongLongValue;
  if(total>DiskLimit||!destination){[self->_failed addObject:identifier];Remove(stage);return;}
  [self->_staging addObject:identifier];
  dispatch_async(Disk(),^{
   BOOL moved=[NSFileManager.defaultManager moveItemAtURL:stage toURL:destination error:nil];if(!moved)Remove(stage);
   dispatch_async(dispatch_get_main_queue(),^{
    if(generation==self->_generation)[self->_staging removeObject:identifier];
    if(!moved){if(generation==self->_generation){[self->_failed addObject:identifier];[self pump];}return;}
    if(generation!=self->_generation||[self->_queue indexOfObjectPassingTest:^BOOL(NSDictionary *row,NSUInteger i,BOOL *stop){return [row[@"id"]isEqual:identifier];}]==NSNotFound){Remove(destination);[self pump];return;}
    self->_mediaSizes[identifier]=size;
    DGDiagnostic(@"cache.ready",[NSString stringWithFormat:@"files=%lu bytes=%llu",(unsigned long)self->_mediaSizes.count,total]);[self pump];
   });
  });
 });
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
 dispatch_async(dispatch_get_main_queue(),^{
  if(task!=self->_task)return;
  if(self->_downloading&&error)[self->_failed addObject:self->_downloading];
  self->_task=nil;self->_downloading=nil;self->_suspended=NO;
  if(error)DGDiagnostic(@"cache.download.error",[NSString stringWithFormat:@"code=%ld",(long)error.code]);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,280*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self pump];});
 });
}
@end

static DGUnwatchedCache *Cache(){static DGUnwatchedCache *cache;static dispatch_once_t once;dispatch_once(&once,^{cache=[DGUnwatchedCache new];});return cache;}
void DGCacheSetScope(NSString *scope){[Cache() setScope:scope];}
NSArray<NSDictionary *> *DGCacheReadyItems(void){return [Cache() ready];}
NSUInteger DGCachePendingCount(void){return [Cache() pendingCount];}
void DGCacheIngest(NSArray<NSDictionary *> *records){[Cache() ingest:records];}
void DGCacheSelectWork(NSString *identifier){[Cache() select:identifier];}
void DGCacheConsume(NSString *identifier){[Cache() consume:identifier];}
NSURL *DGCacheLocalVideo(NSString *identifier){return [Cache() urlFor:identifier];}
void DGCacheSetIdle(BOOL idle){[Cache() setIdle:idle];}

void DGCacheCancelPrefetch(void){[Cache() cancelPrefetch];}
