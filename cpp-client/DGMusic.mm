#import "DGCommon.h"
#import <MediaPlayer/MediaPlayer.h>
@interface DGMusicSession:NSObject
@property(nonatomic,strong) AVPlayer *player;
@property(nonatomic,strong) NSDictionary *music;
@property(nonatomic,strong) UIImage *artwork;
@property(nonatomic,strong) id clock,endToken;
- (void)play:(NSDictionary *)music;
- (void)publish;
- (void)pause;
@end
static DGMusicSession *DGMusicShared(void){static DGMusicSession *session;static dispatch_once_t once;dispatch_once(&once,^{session=[DGMusicSession new];});return session;}
@implementation DGMusicSession
- (instancetype)init{if((self=[super init])){
 MPRemoteCommandCenter *commands=MPRemoteCommandCenter.sharedCommandCenter;__weak DGMusicSession *weak=self;
 [commands.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event){dispatch_async(dispatch_get_main_queue(),^{DGMusicSession *s=weak;[s.player play];[s publish];});return MPRemoteCommandHandlerStatusSuccess;}];
 [commands.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event){dispatch_async(dispatch_get_main_queue(),^{[weak pause];});return MPRemoteCommandHandlerStatusSuccess;}];
 [commands.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event){dispatch_async(dispatch_get_main_queue(),^{DGMusicSession *s=weak;if(s.player.rate>0)[s pause];else{[s.player play];[s publish];}});return MPRemoteCommandHandlerStatusSuccess;}];
 [commands.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event){NSTimeInterval position=((MPChangePlaybackPositionCommandEvent *)event).positionTime;dispatch_async(dispatch_get_main_queue(),^{DGMusicSession *s=weak;[s.player seekToTime:CMTimeMakeWithSeconds(position,600) completionHandler:^(BOOL ok){[s publish];}];});return MPRemoteCommandHandlerStatusSuccess;}];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interruption:) name:AVAudioSessionInterruptionNotification object:nil];
 [UIApplication.sharedApplication beginReceivingRemoteControlEvents];
 }return self;}
- (void)play:(NSDictionary *)music{
 MPRemoteCommandCenter *commands=MPRemoteCommandCenter.sharedCommandCenter;commands.playCommand.enabled=YES;commands.pauseCommand.enabled=YES;commands.togglePlayPauseCommand.enabled=YES;commands.changePlaybackPositionCommand.enabled=YES;
 NSString *url=Text(String(music[@"url"]));if(!url.length)return;
 [[AVAudioSession sharedInstance]setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:nil];[[AVAudioSession sharedInstance]setActive:YES error:nil];
 BOOL same=[Text(String(self.music[@"id"]))isEqualToString:Text(String(music[@"id"]))]&&[Text(String(self.music[@"url"]))isEqualToString:url];
 if(!same||!_player){if(_clock&&_player)[_player removeTimeObserver:_clock];if(_endToken)[NSNotificationCenter.defaultCenter removeObserver:_endToken];[_player pause];_music=music.copy;_artwork=nil;_player=[AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:Asset(url)]];__weak DGMusicSession *weak=self;
  _clock=[_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(1,600) queue:dispatch_get_main_queue() usingBlock:^(CMTime time){[weak publish];}];
  _endToken=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:_player.currentItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){DGMusicSession *s=weak;[s.player seekToTime:kCMTimeZero];[s pause];}];
  NSString *cover=Text(String(music[@"cover"]));NSURL *address=[NSURL URLWithString:cover];if(address){NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:address];[request setValue:DGUserAgent() forHTTPHeaderField:@"User-Agent"];[request setValue:@"https://www.douyin.com/" forHTTPHeaderField:@"Referer"];NSString *identifier=Text(String(music[@"id"]));[[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){UIImage *image=data?[UIImage imageWithData:data]:nil;if(!image)return;dispatch_async(dispatch_get_main_queue(),^{DGMusicSession *s=weak;if([Text(String(s.music[@"id"]))isEqualToString:identifier]){s.artwork=image;[s publish];}});}]resume];}
 }
 [_player play];[self publish];
}
- (void)publish{
 if(!_player)return;double elapsed=CMTimeGetSeconds(_player.currentTime),duration=CMTimeGetSeconds(_player.currentItem.duration);if(!std::isfinite(duration)||duration<=0)duration=[_music[@"duration"]doubleValue];
 NSMutableDictionary *info=[@{MPMediaItemPropertyTitle:Text(String(_music[@"title"])).length?Text(String(_music[@"title"])):@"作品原声",MPMediaItemPropertyArtist:Text(String(_music[@"author"])),MPNowPlayingInfoPropertyPlaybackRate:@(_player.rate),MPNowPlayingInfoPropertyDefaultPlaybackRate:@1,MPNowPlayingInfoPropertyElapsedPlaybackTime:@(std::isfinite(elapsed)?MAX(0,elapsed):0),MPNowPlayingInfoPropertyMediaType:@(MPNowPlayingInfoMediaTypeAudio)}mutableCopy];
 if(duration>0&&std::isfinite(duration))info[MPMediaItemPropertyPlaybackDuration]=@(duration);if(_artwork){UIImage *image=_artwork;info[MPMediaItemPropertyArtwork]=[[MPMediaItemArtwork alloc]initWithBoundsSize:image.size requestHandler:^UIImage *(CGSize size){return image;}];}
 MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo=info;[NSNotificationCenter.defaultCenter postNotificationName:@"DGMusicStateChanged" object:nil];
}
- (void)pause{[_player pause];[self publish];}
- (void)interruption:(NSNotification *)note{if([note.userInfo[AVAudioSessionInterruptionTypeKey]integerValue]==AVAudioSessionInterruptionTypeBegan)[self pause];}
@end
void DGMusicPlay(NSDictionary *music){[DGMusicShared()play:music];}
void DGMusicPause(void){[DGMusicShared()pause];}
void DGMusicStop(void){DGMusicSession *session=DGMusicShared();[session.player pause];if(session.clock&&session.player)[session.player removeTimeObserver:session.clock];session.clock=nil;if(session.endToken)[NSNotificationCenter.defaultCenter removeObserver:session.endToken];session.endToken=nil;session.player=nil;session.music=nil;MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo=nil;MPRemoteCommandCenter *commands=MPRemoteCommandCenter.sharedCommandCenter;commands.playCommand.enabled=NO;commands.pauseCommand.enabled=NO;commands.togglePlayPauseCommand.enabled=NO;commands.changePlaybackPositionCommand.enabled=NO;}
AVPlayer *DGMusicPlayer(void){return DGMusicShared().player;}
BOOL DGMusicMatches(NSString *identifier){return identifier.length&&[Text(String(DGMusicShared().music[@"id"]))isEqualToString:identifier];}

