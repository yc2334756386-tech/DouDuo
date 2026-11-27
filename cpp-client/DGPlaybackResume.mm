#import "DGPlaybackResume.h"
#import "DGFeedCache.h"
#import "DGDiagnostics.h"

namespace {
NSString *LocalWorkID;
NSURL *Folder() {
 return [[NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"InterruptedPlayback" isDirectory:YES];
}
NSURL *Checkpoint(){return [Folder() URLByAppendingPathComponent:@"checkpoint.json"];}
NSURL *Video(){return [Folder() URLByAppendingPathComponent:@"resume.mp4"];}
}
NSDictionary *DGPlaybackResumeTake(void) {
 NSData *data=[NSData dataWithContentsOfURL:Checkpoint()];
 id saved=data.length&&data.length<256*1024?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
 DGPlaybackResumeClearCheckpoint();
 if([saved isKindOfClass:NSDictionary.class]&&[saved[@"scope"]isEqual:DGCurrentFeedScope()]&&[saved[@"record"] isKindOfClass:NSDictionary.class]){
  double age=NSDate.date.timeIntervalSince1970-[saved[@"time"]doubleValue];
  Work work=ReadWork(saved[@"record"]);
  if(age>=0&&age<=90&&work.playable()){
   if([NSFileManager.defaultManager fileExistsAtPath:Video().path])LocalWorkID=Text(work.id);
   DGDiagnostic(@"playback.checkpoint.restore",[NSString stringWithFormat:@"age_seconds=%.1f local=%d",age,LocalWorkID!=nil]);
   return saved;
  }
 }
 [NSFileManager.defaultManager removeItemAtURL:Video() error:nil];return nil;
}
void DGPlaybackResumeSave(NSDictionary *record,NSString *channel,double seconds,BOOL paused) {
 if(!record||!std::isfinite(seconds)||seconds<0)return;
 NSString *identifier=Text(String(record[@"id"]));
 if(!identifier.length)return;
 NSFileManager *files=NSFileManager.defaultManager;
 if(![files createDirectoryAtURL:Folder() withIntermediateDirectories:YES attributes:nil error:nil])return;
 if(![LocalWorkID isEqualToString:identifier]){
  [files removeItemAtURL:Video() error:nil];
  NSURL *source=DGCacheLocalVideo(identifier);
  LocalWorkID=source&&[files linkItemAtURL:source toURL:Video() error:nil]?identifier.copy:nil;
 }
 NSDictionary *save=@{@"scope":DGCurrentFeedScope(),@"channel":channel?:@"feed",@"time":@(NSDate.date.timeIntervalSince1970),@"record":record,@"position":@(seconds),@"paused":@(paused)};
 NSData *data=[NSJSONSerialization dataWithJSONObject:save options:0 error:nil];
 BOOL ok=data.length&&data.length<256*1024&&[data writeToURL:Checkpoint() options:NSDataWritingAtomic error:nil];
 if(ok)DGDiagnostic(@"playback.checkpoint.saved",[NSString stringWithFormat:@"position=%.2f local=%d",seconds,LocalWorkID!=nil]);
}
void DGPlaybackResumeClearCheckpoint(void){[NSFileManager.defaultManager removeItemAtURL:Checkpoint() error:nil];}
void DGPlaybackResumeSelectWork(NSString *identifier) {
 if(!LocalWorkID.length||[LocalWorkID isEqualToString:identifier])return;
 LocalWorkID=nil;[NSFileManager.defaultManager removeItemAtURL:Video() error:nil];
}
NSURL *DGPlaybackResumeLocalVideo(NSString *identifier){return [LocalWorkID isEqualToString:identifier]?Video():nil;}
