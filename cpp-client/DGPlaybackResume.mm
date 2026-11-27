#import "DGPlaybackResume.h"
#import "DGFeedCache.h"
#import "DGDiagnostics.h"

namespace {
constexpr NSUInteger SnapshotLimit=256*1024;
constexpr double ResumeWindow=5*60;
NSString *LocalWorkID,*LocalScope;
NSURL *Folder(NSSearchPathDirectory base) {
 return [[NSFileManager.defaultManager URLsForDirectory:base inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"InterruptedPlayback" isDirectory:YES];
}
NSURL *Checkpoint(){return [Folder(NSApplicationSupportDirectory) URLByAppendingPathComponent:@"checkpoint.json"];}
NSURL *LegacyCheckpoint(){return [Folder(NSCachesDirectory) URLByAppendingPathComponent:@"checkpoint.json"];}
NSURL *LocalVideo(NSString *identifier){
 if(!identifier.length||identifier.length>40||[identifier rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location!=NSNotFound)return nil;
 return [Folder(NSCachesDirectory) URLByAppendingPathComponent:[NSString stringWithFormat:@"resume-%@.mp4",identifier]];
}
void PruneVideos(NSURL *keep){
 NSFileManager *files=NSFileManager.defaultManager;
 for(NSURL *file in [files contentsOfDirectoryAtURL:Folder(NSCachesDirectory) includingPropertiesForKeys:nil options:0 error:nil]){
  NSString *name=file.lastPathComponent;
  if(![file isEqual:keep]&&[file.pathExtension isEqualToString:@"mp4"]&&([name hasPrefix:@"resume-"]||[name isEqualToString:@"resume.mp4"]))[files removeItemAtURL:file error:nil];
 }
}
BOOL PrepareFolder(NSSearchPathDirectory base){
 NSFileManager *files=NSFileManager.defaultManager;NSURL *folder=Folder(base);
 if([files fileExistsAtPath:folder.path])return YES;
 if(![files createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil])return NO;
 [folder setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];return YES;
}
}
NSDictionary *DGPlaybackResumeLoad(void) {
 NSFileManager *files=NSFileManager.defaultManager;
 NSData *data=[NSData dataWithContentsOfURL:Checkpoint()];BOOL legacy=!data;
 if(legacy)data=[NSData dataWithContentsOfURL:LegacyCheckpoint()];
 if(!data.length){DGDiagnostic(@"playback.checkpoint.miss",@"reason=missing");PruneVideos(nil);return nil;}
 id saved=data.length<SnapshotLimit?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
 NSString *reason=@"invalid";
 if([saved isKindOfClass:NSDictionary.class]&&[saved[@"record"] isKindOfClass:NSDictionary.class]&&[saved[@"time"] isKindOfClass:NSNumber.class]&&[saved[@"position"] isKindOfClass:NSNumber.class]&&[saved[@"paused"] isKindOfClass:NSNumber.class]){
  double age=NSDate.date.timeIntervalSince1970-[saved[@"time"]doubleValue],seconds=[saved[@"position"]doubleValue];
  Work work=ReadWork(saved[@"record"]);
  if(![saved[@"scope"] isEqual:DGCurrentFeedScope()])reason=@"account";
  else if(age<0||age>ResumeWindow)reason=@"expired";
  else if(work.playable()&&std::isfinite(seconds)&&seconds>=0){
   NSString *identifier=Text(work.id);NSURL *video=LocalVideo(identifier);
   if(legacy&&video&&![files fileExistsAtPath:video.path]){
    NSURL *old=[Folder(NSCachesDirectory) URLByAppendingPathComponent:@"resume.mp4"];
    [files linkItemAtURL:old toURL:video error:nil];
   }
   BOOL local=video&&[files fileExistsAtPath:video.path];LocalWorkID=local?identifier:nil;LocalScope=local?DGCurrentFeedScope():nil;
   PruneVideos(local?video:nil);
   DGDiagnostic(@"playback.checkpoint.restore",[NSString stringWithFormat:@"age_seconds=%.1f position=%.2f local=%d legacy=%d",age,seconds,local,legacy]);
   return saved;
  }
 }
 DGDiagnostic(@"playback.checkpoint.miss",[NSString stringWithFormat:@"reason=%@",reason]);DGPlaybackResumeClearCheckpoint();return nil;
}
BOOL DGPlaybackResumeSave(NSDictionary *record,NSString *channel,double seconds,BOOL paused) {
 if(!record||!std::isfinite(seconds)||seconds<0)return NO;
 NSString *identifier=Text(String(record[@"id"])),*scope=DGCurrentFeedScope();
 if(!identifier.length||!PrepareFolder(NSApplicationSupportDirectory))return NO;
 NSDictionary *save=@{@"scope":scope,@"channel":channel?:@"feed",@"time":@(NSDate.date.timeIntervalSince1970),@"record":record,@"position":@(seconds),@"paused":@(paused)};
 NSData *data=[NSJSONSerialization dataWithJSONObject:save options:0 error:nil];
 if(!data.length||data.length>=SnapshotLimit){DGDiagnostic(@"playback.checkpoint.failed",@"reason=record");return NO;}
 NSFileManager *files=NSFileManager.defaultManager;NSURL *video=LocalVideo(identifier),*source=DGCacheLocalVideo(identifier);
 BOOL local=video&&[files fileExistsAtPath:video.path],linked=NO;
 if(!local&&video&&source&&PrepareFolder(NSCachesDirectory))local=linked=[files linkItemAtURL:source toURL:video error:nil];
 NSError *error=nil;
 if(![data writeToURL:Checkpoint() options:NSDataWritingAtomic|NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication error:&error]){
  if(linked)[files removeItemAtURL:video error:nil];
  DGDiagnostic(@"playback.checkpoint.failed",[NSString stringWithFormat:@"reason=write code=%ld",(long)error.code]);return NO;
 }
 BOOL prune=linked||(LocalWorkID&&(![LocalWorkID isEqualToString:identifier]||![LocalScope isEqualToString:scope]));
 LocalWorkID=local?identifier:nil;LocalScope=local?scope:nil;
 if(prune)PruneVideos(local?video:nil);
 if([files fileExistsAtPath:LegacyCheckpoint().path])[files removeItemAtURL:LegacyCheckpoint() error:nil];
 DGDiagnostic(@"playback.checkpoint.saved",[NSString stringWithFormat:@"position=%.2f local=%d",seconds,local]);return YES;
}
void DGPlaybackResumeClearCheckpoint(void){
 NSFileManager *files=NSFileManager.defaultManager;[files removeItemAtURL:Checkpoint() error:nil];[files removeItemAtURL:LegacyCheckpoint() error:nil];
 LocalWorkID=nil;LocalScope=nil;PruneVideos(nil);
}
NSURL *DGPlaybackResumeLocalVideo(NSString *identifier){return [LocalWorkID isEqualToString:identifier]&&[LocalScope isEqualToString:DGCurrentFeedScope()]?LocalVideo(identifier):nil;}
