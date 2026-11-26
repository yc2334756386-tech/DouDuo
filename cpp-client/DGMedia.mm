#import "DGMedia.h"
#import <QuartzCore/QuartzCore.h>
@interface DGPrepared:NSObject
@property(nonatomic,strong) AVPlayer *player;
@property(nonatomic,strong) AVPlayerItem *item;
@property(nonatomic) NSUInteger leases;
@property(nonatomic) BOOL warming, warmed;
@property(nonatomic) BOOL retired;
@property(nonatomic) NSUInteger warmAttempts;
- (instancetype)initWithURL:(NSString *)url;
- (void)warm;
- (void)retire;
@end
@implementation DGPrepared
- (instancetype)initWithURL:(NSString *)url { if((self=[super init])){_item=[AVPlayerItem playerItemWithAsset:Asset(url)];_item.preferredForwardBufferDuration=2;_player=[AVPlayer playerWithPlayerItem:_item];_player.automaticallyWaitsToMinimizeStalling=NO;[_player addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];}return self;}
- (void)warm {
    if(!NSThread.isMainThread){__weak DGPrepared *weak=self;dispatch_async(dispatch_get_main_queue(),^{[weak warm];});return;}
    if(_retired||_leases||_warming||_warmed||_warmAttempts>=2||_item.status!=AVPlayerItemStatusReadyToPlay||_player.status!=AVPlayerStatusReadyToPlay)return;
    _warming=YES;++_warmAttempts;__weak DGPrepared *weak=self;
    [_player prerollAtRate:1 completionHandler:^(BOOL ok){dispatch_async(dispatch_get_main_queue(),^{DGPrepared *s=weak;if(!s)return;s.warming=NO;s.warmed=ok&&!s.retired;});}];
}
- (void)retire {
    _retired=YES;[_player cancelPendingPrerolls];_warming=NO;
    if(!_leases){[_player pause];[_player replaceCurrentItemWithPlayerItem:nil];}
}
- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)object change:(NSDictionary *)change context:(void *)context {if(object==_player)[self warm];}
- (void)dealloc {[_player removeObserver:self forKeyPath:@"status"];[_player pause];}
@end
static NSMutableDictionary<NSString *,DGPrepared *> *Pool(){static NSMutableDictionary *pool;static dispatch_once_t once;dispatch_once(&once,^{pool=[NSMutableDictionary dictionary];});return pool;}
static NSString *PoolKey(const Work &w){return [NSString stringWithFormat:@"%@|%@",Text(w.id),Text(w.play)];}
static DGPrepared *Obtain(const Work &w){if(w.play.empty())return nil;NSString *key=PoolKey(w);DGPrepared *p=Pool()[key];if(!p){p=[[DGPrepared alloc]initWithURL:Text(w.play)];Pool()[key]=p;}if(Pool().count>6)for(NSString *old in Pool().allKeys){DGPrepared *v=Pool()[old];if(![key isEqualToString:old]&&!v.leases){[v retire];[Pool() removeObjectForKey:old];if(Pool().count<=5)break;}}return p;}
void DGWarmWorks(const std::vector<Work>&works,NSInteger index){NSMutableSet *keys=[NSMutableSet set];for(NSInteger i=MAX(0,index-1);i<=MIN((NSInteger)works.size()-1,index+3);++i){const Work &w=works[i];if(w.photo()||w.play.empty())continue;[keys addObject:PoolKey(w)];DGPrepared *p=Obtain(w);if(i!=index)[p warm];}for(NSString *key in Pool().allKeys){DGPrepared *p=Pool()[key];if(![keys containsObject:key]&&!p.leases){[p retire];[Pool() removeObjectForKey:key];}}}
void DGClearPlayers(){for(DGPrepared *p in Pool().allValues)[p retire];[Pool() removeAllObjects];}
static NSString *TimeLabel(double value){if(!std::isfinite(value)||value<0)value=0;return [NSString stringWithFormat:@"%02ld:%02ld",(long)value/60,(long)value%60];}
@interface DGFeedCell()<UIScrollViewDelegate,UIGestureRecognizerDelegate>
@end
@implementation DGFeedCell {
 Work _work;DGImage *_cover,*_avatar,*_musicAvatar;UIScrollView *_photos;NSMutableArray<DGImage*> *_images;
 UIView *_shade,*_danmaku;CAGradientLayer *_gradient;UILabel *_author,*_caption,*_metadata,*_photoCount,*_likeCount,*_commentCount,*_collectCount,*_pause,*_message,*_speedText,*_previewTime;
 UIVisualEffectView *_rail,*_moreGlass,*_photoGlass,*_speedGlass,*_previewGlass;UIButton *_avatarButton,*_likeButton,*_commentButton,*_collectButton,*_fillButton,*_moreButton,*_musicButton;UIImageView *_previewImage;
 AVPlayer *_player,*_musicPlayer;AVPlayerLayer *_playerLayer;DGPrepared *_prepared;AVPlayerItem *_observedItem;AVAssetImageGenerator *_generator;id _loopToken,_musicLoopToken,_clock;UISlider *_slider;
 NSMutableArray<UIScrollView*> *_locked;BOOL _active,_paused,_alternateUsed,_dragging,_compact,_fill,_boosting,_busy,_danmakuLoading;double _rate,_holdY,_progressAt,_progress;NSInteger _recoveries,_photoIndex,_danmakuWindow,_lane;NSUInteger _generation,_previewGeneration;NSArray<NSDictionary*> *_danmakuItems;NSMutableSet<NSString*> *_emitted;
 CGFloat _mediaHeight;BOOL _watchdogScheduled,_watchdogExhausted;NSUInteger _watchdogToken;double _firstFrameStarted;
}
- (instancetype)initWithFrame:(CGRect)frame {
 if((self=[super initWithFrame:frame])){
 self.contentView.backgroundColor=UIColor.blackColor;_rate=1;_danmakuWindow=-1;_images=[NSMutableArray array];_locked=[NSMutableArray array];_emitted=[NSMutableSet set];
 _cover=[DGImage new];_cover.contentMode=UIViewContentModeScaleAspectFit;[self.contentView addSubview:_cover];_playerLayer=[AVPlayerLayer playerLayerWithPlayer:nil];_playerLayer.videoGravity=AVLayerVideoGravityResizeAspect;[self.contentView.layer addSublayer:_playerLayer];
 _photos=[UIScrollView new];_photos.pagingEnabled=YES;_photos.showsHorizontalScrollIndicator=NO;_photos.delegate=self;[self.contentView addSubview:_photos];
 _danmaku=[UIView new];_danmaku.clipsToBounds=YES;_danmaku.userInteractionEnabled=NO;[self.contentView addSubview:_danmaku];_shade=[UIView new];_shade.userInteractionEnabled=NO;_gradient=[CAGradientLayer layer];_gradient.colors=@[(id)UIColor.clearColor.CGColor,(id)[UIColor colorWithWhite:0 alpha:.75].CGColor];[_shade.layer addSublayer:_gradient];[self.contentView addSubview:_shade];
 _author=Label(17,UIFontWeightSemibold);_author.userInteractionEnabled=YES;[_author addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(profile)]];
 _caption=Label(14,UIFontWeightRegular);_caption.numberOfLines=3;_caption.userInteractionEnabled=YES;[_caption addGestureRecognizer:[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(copyCaption:)]];
 _metadata=Label(11,UIFontWeightRegular);_metadata.textColor=[UIColor colorWithWhite:1 alpha:.64];for(UIView *v in @[_author,_caption,_metadata])[self.contentView addSubview:v];
 _musicButton=[UIButton buttonWithType:UIButtonTypeSystem];_musicButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;_musicButton.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];_musicButton.tintColor=[UIColor colorWithWhite:1 alpha:.78];_musicButton.titleLabel.lineBreakMode=NSLineBreakByTruncatingTail;[_musicButton addTarget:self action:@selector(music) forControlEvents:UIControlEventTouchUpInside];[_musicButton addGestureRecognizer:[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(saveMusic:)]];[self.contentView addSubview:_musicButton];
 _musicAvatar=[DGImage new];_musicAvatar.contentMode=UIViewContentModeScaleAspectFill;_musicAvatar.layer.cornerRadius=11;_musicAvatar.clipsToBounds=YES;_musicAvatar.userInteractionEnabled=YES;[_musicAvatar addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(profile)]];[self.contentView addSubview:_musicAvatar];
 _rail=Glass(27);[self.contentView addSubview:_rail];_avatarButton=[UIButton buttonWithType:UIButtonTypeCustom];[_avatarButton addTarget:self action:@selector(profile) forControlEvents:UIControlEventTouchUpInside];_avatar=[DGImage new];_avatar.contentMode=UIViewContentModeScaleAspectFill;_avatar.layer.cornerRadius=20;_avatar.clipsToBounds=YES;[_avatarButton addSubview:_avatar];[_rail.contentView addSubview:_avatarButton];
 _likeButton=Symbol(@"heart",self,@selector(like));_commentButton=Symbol(@"text.bubble",self,@selector(comments));_collectButton=Symbol(@"star",self,@selector(collect));_fillButton=Symbol(@"headphones",self,@selector(fill));_likeButton.accessibilityLabel=@"点赞";_commentButton.accessibilityLabel=@"评论";_collectButton.accessibilityLabel=@"收藏";_fillButton.accessibilityLabel=@"后台音频播放";
 _likeCount=Label(11,UIFontWeightMedium);_commentCount=Label(11,UIFontWeightMedium);_collectCount=Label(11,UIFontWeightMedium);for(UILabel *l in @[_likeCount,_commentCount,_collectCount])l.textAlignment=NSTextAlignmentCenter;for(UIView *v in @[_likeButton,_likeCount,_commentButton,_commentCount,_collectButton,_collectCount,_fillButton])[_rail.contentView addSubview:v];
 _moreGlass=Glass(25);_moreButton=Symbol(@"ellipsis",self,@selector(more));_moreButton.accessibilityLabel=@"更多选项";[_moreGlass.contentView addSubview:_moreButton];[self.contentView addSubview:_moreGlass];_photoGlass=Glass(16);_photoCount=Label(11,UIFontWeightMedium);_photoCount.textAlignment=NSTextAlignmentCenter;[_photoGlass.contentView addSubview:_photoCount];[self.contentView addSubview:_photoGlass];
 _pause=Label(52,UIFontWeightLight);_pause.text=@"▶";_pause.textAlignment=NSTextAlignmentCenter;_pause.hidden=YES;_pause.layer.shadowColor=UIColor.blackColor.CGColor;_pause.layer.shadowOpacity=.35;_pause.layer.shadowRadius=7;[self.contentView addSubview:_pause];_message=Label(13,UIFontWeightRegular);_message.textAlignment=NSTextAlignmentCenter;_message.numberOfLines=2;[self.contentView addSubview:_message];
 _slider=[UISlider new];_slider.minimumValue=0;_slider.maximumValue=1;_slider.tintColor=[UIColor colorWithRed:.76 green:.96 blue:.96 alpha:1];_slider.maximumTrackTintColor=[UIColor colorWithWhite:1 alpha:.18];[_slider setThumbImage:[UIImage systemImageNamed:@"circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:8]] forState:UIControlStateNormal];[_slider addTarget:self action:@selector(seekStart) forControlEvents:UIControlEventTouchDown];[_slider addTarget:self action:@selector(seekChange) forControlEvents:UIControlEventValueChanged];[_slider addTarget:self action:@selector(seekEnd) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];[self.contentView addSubview:_slider];
 _previewGlass=Glass(14);_previewGlass.hidden=YES;_previewGlass.userInteractionEnabled=NO;_previewImage=[UIImageView new];_previewImage.contentMode=UIViewContentModeScaleAspectFit;_previewTime=Label(11,UIFontWeightMedium);_previewTime.textAlignment=NSTextAlignmentCenter;[_previewGlass.contentView addSubview:_previewImage];[_previewGlass.contentView addSubview:_previewTime];[self.contentView addSubview:_previewGlass];_speedGlass=Glass(19);_speedGlass.hidden=YES;_speedGlass.userInteractionEnabled=NO;_speedText=Label(13,UIFontWeightSemibold);_speedText.textAlignment=NSTextAlignmentCenter;[_speedGlass.contentView addSubview:_speedText];[self.contentView addSubview:_speedGlass];
 UITapGestureRecognizer *single=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(toggle)];single.delegate=self;single.cancelsTouchesInView=NO;UITapGestureRecognizer *doubleTap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(doubleLike:)];doubleTap.numberOfTapsRequired=2;doubleTap.delegate=self;[single requireGestureRecognizerToFail:doubleTap];[self.contentView addGestureRecognizer:single];[self.contentView addGestureRecognizer:doubleTap];UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(hold:)];hold.minimumPressDuration=.32;hold.allowableMovement=22;hold.delegate=self;[self.contentView addGestureRecognizer:hold];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged) name:@"DouGlassSettingsChanged" object:nil];
 }return self;
}
- (void)layoutSubviews {
 [super layoutSubviews];CGRect b=self.contentView.bounds;if(_mediaHeight>0)b.size.height=_mediaHeight;CGFloat w=b.size.width,h=b.size.height,bottom=_compact?4:MAX(self.safeAreaInsets.bottom,14),top=_compact?6:MAX(self.safeAreaInsets.top,18)+65;
 [CATransaction begin];[CATransaction setDisableActions:YES];_playerLayer.frame=b;[CATransaction commit];_cover.frame=b;_photos.frame=b;_photos.contentSize=CGSizeMake(w*_images.count,h);for(NSUInteger i=0;i<_images.count;++i)_images[i].frame=CGRectMake(i*w,0,w,h);if(_work.photo()&&w>0&&!_photos.dragging&&!_photos.decelerating)_photos.contentOffset=CGPointMake(_photoIndex*w,0);
 _danmaku.frame=CGRectMake(0,top,w,MIN(160,MAX(60,h-top-80)));_shade.frame=CGRectMake(0,MAX(0,h-260),w,260);_gradient.frame=_shade.bounds;CGFloat tw=MAX(80,MIN(w-103,680));CGFloat ch=MIN([_caption sizeThatFits:CGSizeMake(tw,70)].height,68);
 _musicAvatar.frame=CGRectMake(20,h-bottom-56,22,22);_musicButton.frame=CGRectMake(49,h-bottom-60,tw-29,30);_metadata.frame=CGRectMake(20,CGRectGetMinY(_musicAvatar.frame)-23,tw,18);_caption.frame=CGRectMake(20,CGRectGetMinY(_metadata.frame)-ch-7,tw,ch);_author.frame=CGRectMake(20,CGRectGetMinY(_caption.frame)-30,tw,26);
 _rail.frame=CGRectMake(w-73,MAX(top+42,h-bottom-436),53,310);_avatarButton.frame=CGRectMake(4,8,45,45);_avatar.frame=CGRectMake(2.5,2.5,40,40);NSArray<UIButton*> *buttons=@[_likeButton,_commentButton,_collectButton];NSArray<UILabel*> *counts=@[_likeCount,_commentCount,_collectCount];for(NSUInteger i=0;i<3;++i){buttons[i].frame=CGRectMake(1,59+i*65,51,40);counts[i].frame=CGRectMake(0,98+i*65,53,17);}_fillButton.frame=CGRectMake(1,257,51,45);_moreGlass.frame=CGRectMake(w-73,CGRectGetMaxY(_rail.frame)+12,53,49);_moreButton.frame=_moreGlass.bounds;
 _photoGlass.frame=CGRectMake(w-110,top+5,90,30);_photoCount.frame=_photoGlass.bounds;_pause.frame=CGRectMake((w-80)/2,(h-80)/2,80,80);_message.frame=CGRectMake(25,h/2+48,w-50,50);_slider.frame=CGRectMake(20,h-bottom-29,w-40,24);
 CGFloat px=MAX(12,MIN(w-144,20+_slider.value*(w-40)-66));_previewGlass.frame=CGRectMake(px,MAX(0,CGRectGetMinY(_slider.frame)-114),132,108);_previewImage.frame=CGRectMake(5,5,122,78);_previewTime.frame=CGRectMake(4,84,124,18);_speedGlass.frame=CGRectMake((w-184)/2,top+8,184,38);_speedText.frame=_speedGlass.bounds;
 for(UIView *v in @[_author,_caption,_metadata,_musicAvatar,_musicButton,_rail,_moreGlass,_shade])v.hidden=_compact;_photoGlass.hidden=!_work.photo();_slider.hidden=_work.photo();if(_work.photo())[self loadPhotos];
}
- (void)mediaHeight:(CGFloat)value {if(fabs(_mediaHeight-value)<.1)return;_mediaHeight=value;[self setNeedsLayout];}
- (void)backgroundAudio:(BOOL)value {if(value&&!_work.photo())_playerLayer.player=nil;else _playerLayer.player=_player;}
- (void)compact:(BOOL)value {if(_compact==value)return;_compact=value;_playerLayer.videoGravity=_fill&&!value?AVLayerVideoGravityResizeAspectFill:AVLayerVideoGravityResizeAspect;[self setNeedsLayout];}
- (void)detach {
 [self stopWatchdog];
 ++_previewGeneration;[_generator cancelAllCGImageGeneration];_generator=nil;if(_observedItem){[_observedItem removeObserver:self forKeyPath:@"status"];_observedItem=nil;}if(_clock&&_player){[_player removeTimeObserver:_clock];_clock=nil;}if(_loopToken){[NSNotificationCenter.defaultCenter removeObserver:_loopToken];_loopToken=nil;}if(_musicLoopToken){[NSNotificationCenter.defaultCenter removeObserver:_musicLoopToken];_musicLoopToken=nil;}if(_prepared){if(_prepared.leases)--_prepared.leases;if(!_prepared.leases)[_prepared.player pause];_prepared=nil;}else[_player pause];[_musicPlayer pause];_musicPlayer=nil;_player=nil;_playerLayer.player=nil;
}
- (void)prepareForReuse {[super prepareForReuse];_active=NO;++_generation;[self unlock];[self detach];_work=Work{};self.commentsAction=nil;self.profileAction=nil;self.musicAction=nil;self.moreAction=nil;[_danmaku.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];}
- (void)display:(const Work&)work {
 if(!_work.id.empty()&&work.id==_work.id){_work=work;[self labels];return;}++_generation;[self unlock];[self detach];_work=work;_paused=NO;_alternateUsed=NO;_watchdogExhausted=NO;_boosting=NO;_dragging=NO;_recoveries=0;_photoIndex=0;_busy=NO;_pause.hidden=YES;_previewGlass.hidden=YES;_speedGlass.hidden=YES;_message.text=@"";_slider.value=0;_progress=-1;_progressAt=CACurrentMediaTime();_danmakuWindow=-1;_danmakuItems=@[];_danmakuLoading=NO;[_emitted removeAllObjects];[_danmaku.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];for(DGImage *i in _images)[i removeFromSuperview];[_images removeAllObjects];_cover.hidden=NO;[_cover remote:Text(work.cover)];[_avatar remote:Text(work.avatar)];[_musicAvatar remote:Text(work.avatar)];_photos.contentOffset=CGPointZero;_photos.hidden=!work.photo();_photoGlass.hidden=!work.photo();[self settingsChanged];[self labels];
 if(work.photo()){for(const auto &url:work.images){DGImage *i=[DGImage new];i.contentMode=UIViewContentModeScaleAspectFit;[_photos addSubview:i];[_images addObject:i];}if(!work.music.empty()){_musicPlayer=[AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:Asset(Text(work.music))]];_musicPlayer.automaticallyWaitsToMinimizeStalling=NO;__weak DGFeedCell *weak=self;_musicLoopToken=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:_musicPlayer.currentItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){DGFeedCell *s=weak;if(!s)return;[s->_musicPlayer seekToTime:kCMTimeZero completionHandler:^(BOOL ok){if(s->_active&&!s->_paused)[s->_musicPlayer playImmediatelyAtRate:s->_rate];}];}];}}
 else[self attach:Obtain(work) position:0];[self setNeedsLayout];if(_active)[self active:YES];
}
- (void)labels {
 _author.text=[@"@" stringByAppendingString:Text(_work.author)];_caption.text=Text(_work.caption);NSMutableArray *meta=[NSMutableArray array];if(_work.publishedAt>0){NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"yyyy-MM-dd";[meta addObject:[f stringFromDate:[NSDate dateWithTimeIntervalSince1970:_work.publishedAt]]];}if(!_work.location.empty())[meta addObject:[NSString stringWithFormat:@"%@%@",(_work.locationKind=="ip"||_work.locationKind=="IP属地")?@"IP属地 ":@"作品发布地 ",Text(_work.location)]];_metadata.text=[meta componentsJoinedByString:@" · "];NSString *music=_work.musicTitle.empty()?@"作品原声":Text(_work.musicTitle),*by=_work.musicAuthor.empty()?Text(_work.author):Text(_work.musicAuthor);[_musicButton setTitle:[NSString stringWithFormat:@"♫ %@ · %@",music,by] forState:UIControlStateNormal];_likeCount.text=Text(douglass::compact(_work.likes));_commentCount.text=Text(douglass::compact(_work.comments));_collectCount.text=Text(douglass::compact(_work.collects));[_likeButton setImage:[UIImage systemImageNamed:_work.liked?@"heart.fill":@"heart"] forState:UIControlStateNormal];_likeButton.tintColor=_work.liked?[UIColor colorWithRed:1 green:.25 blue:.38 alpha:1]:UIColor.whiteColor;[_collectButton setImage:[UIImage systemImageNamed:_work.collected?@"star.fill":@"star"] forState:UIControlStateNormal];_collectButton.tintColor=_work.collected?[UIColor colorWithRed:1 green:.83 blue:.32 alpha:1]:UIColor.whiteColor;
}
- (void)attach:(DGPrepared*)prepared position:(double)position {
 [self detach];if(!prepared)return;_prepared=prepared;++prepared.leases;_player=prepared.player;[_player cancelPendingPrerolls];_playerLayer.player=_player;_observedItem=prepared.item;[_observedItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];_progressAt=CACurrentMediaTime();_firstFrameStarted=_progressAt;_progress=-1;__weak DGFeedCell *weak=self;
 _loopToken=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:_observedItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){DGFeedCell *s=weak;if(!s)return;[s->_emitted removeAllObjects];s->_progressAt=CACurrentMediaTime();[s->_player seekToTime:kCMTimeZero completionHandler:^(BOOL ok){if(s->_active&&!s->_paused)[s->_player playImmediatelyAtRate:s->_rate];}];}];_clock=[_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(.25,600) queue:dispatch_get_main_queue() usingBlock:^(CMTime t){[weak tick:t];}];if(position>.1)[_player seekToTime:CMTimeMakeWithSeconds(position,600) toleranceBefore:CMTimeMakeWithSeconds(.2,600) toleranceAfter:CMTimeMakeWithSeconds(.2,600)];if(_active&&!_paused){[_player playImmediatelyAtRate:_rate];[self queueWatchdogAfter:3];}
}
- (void)observeValueForKeyPath:(NSString*)key ofObject:(id)object change:(NSDictionary*)change context:(void*)context {if(object!=_observedItem)return;dispatch_async(dispatch_get_main_queue(),^{if(object!=self->_observedItem)return;if(self->_observedItem.status==AVPlayerItemStatusReadyToPlay){self->_message.text=@"";if(self->_active&&!self->_paused)[self->_player playImmediatelyAtRate:self->_rate];}else if(self->_observedItem.status==AVPlayerItemStatusFailed)[self recover];});}
- (void)recover {
 if(!NSThread.isMainThread){__weak DGFeedCell *weak=self;dispatch_async(dispatch_get_main_queue(),^{[weak recover];});return;}
 if(!_active||_paused||_work.photo())return;
 if(_recoveries>=2){_watchdogExhausted=YES;[self stopWatchdog];_message.text=@"视频暂未加载成功，点击画面重试";return;}
 ++_recoveries;double pos=CMTimeGetSeconds(_player.currentTime);if(!std::isfinite(pos))pos=0;
 NSString *url=Text(_work.play);if(!_alternateUsed&&!_work.alternate.empty()&&_work.alternate!=_work.play){_alternateUsed=YES;url=Text(_work.alternate);}
 DGPrepared *old=_prepared;DGPrepared *replacement=[[DGPrepared alloc]initWithURL:url];
 [self attach:replacement position:pos];
 // A failed pooled item must never be offered to the next cell or prewarmed again.
 if(old){for(NSString *key in Pool().allKeys)if(Pool()[key]==old)[Pool() removeObjectForKey:key];[old retire];}
 Pool()[PoolKey(_work)]=replacement;
}
- (void)stopWatchdog {++_watchdogToken;_watchdogScheduled=NO;}
- (void)queueWatchdogAfter:(NSTimeInterval)delay {
 if(_watchdogScheduled||!_active||_paused||_work.photo()||!_player||_watchdogExhausted)return;
 _watchdogScheduled=YES;NSUInteger token=++_watchdogToken,generation=_generation;__weak DGFeedCell *weak=self;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  DGFeedCell *s=weak;if(!s||token!=s->_watchdogToken||generation!=s->_generation)return;
  s->_watchdogScheduled=NO;
  if(!s->_active||s->_paused||s->_work.photo()||!s->_player)return;
  double now=CACurrentMediaTime(),seconds=CMTimeGetSeconds(s->_player.currentTime),duration=CMTimeGetSeconds(s->_player.currentItem.duration);
  BOOL firstFrame=s->_playerLayer.readyForDisplay;
  if(firstFrame)s->_cover.hidden=YES;
  if(s->_dragging){s->_progressAt=now;s->_firstFrameStarted=now;}
  else {
   if(std::isfinite(seconds)&&std::fabs(seconds-s->_progress)>.08){s->_progress=seconds;s->_progressAt=now;}
   BOOL ended=std::isfinite(duration)&&duration>0&&std::isfinite(seconds)&&seconds>=duration-.35;
   BOOL noFrame=!firstFrame&&!(DGBackgroundAudioEnabled()&&UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)&&now-s->_firstFrameStarted>=3.3;
   BOOL noProgress=!ended&&now-s->_progressAt>=4.5;
   if(noFrame||noProgress||s->_observedItem.status==AVPlayerItemStatusFailed){[s recover];}
  }
  // attach/recover may already have queued a fresh generation; never create a second chain.
  [s queueWatchdogAfter:1];
 });
}
- (void)tick:(CMTime)time {
 if(!_player)return;double seconds=CMTimeGetSeconds(time),duration=CMTimeGetSeconds(_player.currentItem.duration);
 if(std::isfinite(duration)&&duration>0&&std::isfinite(seconds)&&!_dragging)_slider.value=seconds/duration;
 if(_playerLayer.readyForDisplay)_cover.hidden=YES;
 if(_active&&!_paused&&!_dragging&&std::isfinite(seconds)){
  if(std::fabs(seconds-_progress)>.08){_progress=seconds;_progressAt=CACurrentMediaTime();}
  [self updateDanmaku:seconds];
 }
}
- (void)active:(BOOL)value {
 if(!NSThread.isMainThread){__weak DGFeedCell *weak=self;dispatch_async(dispatch_get_main_queue(),^{[weak active:value];});return;}
 BOOL changed=_active!=value;_active=value;
 if(value&&!_paused){
  if(changed){_progressAt=CACurrentMediaTime();_firstFrameStarted=_progressAt;}
  if(_player.rate==0||changed)[_player playImmediatelyAtRate:_boosting?2:_rate];
  if(_musicPlayer.rate==0||changed)[_musicPlayer playImmediatelyAtRate:_rate];
  [self queueWatchdogAfter:3];
 }else{
  [self stopWatchdog];[_player pause];[_musicPlayer pause];
  if(!value){[self unlock];_boosting=NO;_speedGlass.hidden=YES;[_danmaku.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];}
 }
}
- (void)toggle {if(_observedItem.status==AVPlayerItemStatusFailed||_watchdogExhausted){_recoveries=0;_watchdogExhausted=NO;[self recover];return;}_paused=!_paused;_pause.hidden=!_paused;if(!_paused){_progressAt=CACurrentMediaTime();_firstFrameStarted=_progressAt;}[self active:_active];if(_paused)[_danmaku.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];}
- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gesture shouldReceiveTouch:(UITouch*)touch {for(UIView *v=touch.view;v&&v!=self.contentView;v=v.superview)if([v isKindOfClass:UIControl.class]||v==_caption||v==_author||v==_musicAvatar)return NO;return YES;}
- (void)lock {[_locked removeAllObjects];for(UIView *v=self.superview;v;v=v.superview)if([v isKindOfClass:UIScrollView.class]&&((UIScrollView*)v).scrollEnabled){[_locked addObject:(UIScrollView*)v];((UIScrollView*)v).scrollEnabled=NO;}}
- (void)unlock {for(UIScrollView *v in _locked)v.scrollEnabled=YES;[_locked removeAllObjects];}
- (void)hold:(UILongPressGestureRecognizer*)g {
 if(g.state==UIGestureRecognizerStateBegan){if(!_work.photo()&&_player){_boosting=YES;[self lock];_speedGlass.hidden=NO;_speedText.text=@"2× 倍速播放 · 松手恢复";if(_active&&!_paused)[_player playImmediatelyAtRate:2];}else[self download:[g locationInView:self.contentView]];}
 else if(g.state==UIGestureRecognizerStateEnded||g.state==UIGestureRecognizerStateCancelled||g.state==UIGestureRecognizerStateFailed){[self unlock];_boosting=NO;_speedGlass.hidden=YES;if(_active&&!_paused)[_player playImmediatelyAtRate:1];}
}
- (void)copyCaption:(UILongPressGestureRecognizer*)g {if(g.state==UIGestureRecognizerStateBegan&&!_work.caption.empty())DGConfirmCopy(self.presenter,Text(_work.caption));}
- (void)saveMusic:(UILongPressGestureRecognizer*)g {if(g.state!=UIGestureRecognizerStateBegan)return;if(_work.music.empty()){DGToast(self.presenter,@"这条作品没有可保存的原声地址");return;}DGSaveAudio(self.presenter,Text(_work.music),_work.musicTitle.empty()?@"作品原声":Text(_work.musicTitle));}
- (void)download:(CGPoint)p {UIViewController *host=self.presenter;if(!host||host.presentedViewController)return;UIAlertController *menu=[UIAlertController alertControllerWithTitle:_work.photo()?@"保存图集":@"保存视频" message:nil preferredStyle:UIAlertControllerStyleActionSheet];if(_work.photo()){NSString *url=Text(_work.images[MIN((std::size_t)MAX(0,_photoIndex),_work.images.size()-1)]);[menu addAction:[UIAlertAction actionWithTitle:@"保存当前图片" style:UIAlertActionStyleDefault handler:^(UIAlertAction*a){DGSaveURL(host,url,NO);}]];NSMutableArray *urls=[NSMutableArray array];for(const auto &u:_work.images)[urls addObject:Text(u)];if(urls.count>1)[menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"保存全部 %lu 张图片",(unsigned long)urls.count] style:UIAlertActionStyleDefault handler:^(UIAlertAction*a){for(NSString *url in urls)DGSaveURL(host,url,NO);}]];}else{NSString *url=Text(_work.play);[menu addAction:[UIAlertAction actionWithTitle:@"保存视频到相册" style:UIAlertActionStyleDefault handler:^(UIAlertAction*a){DGSaveURL(host,url,YES);}]];}[menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];menu.popoverPresentationController.sourceView=self.contentView;menu.popoverPresentationController.sourceRect=CGRectMake(p.x,p.y,1,1);[host presentViewController:menu animated:YES completion:nil];}
- (void)comments {if(self.commentsAction)self.commentsAction();}
- (void)profile {if(self.profileAction)self.profileAction();}
- (void)music {if(self.musicAction)self.musicAction();}
- (void)fill {BOOL enabled=!DGBackgroundAudioEnabled();[NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"douglass.backgroundAudio"];[NSNotificationCenter.defaultCenter postNotificationName:@"DouGlassSettingsChanged" object:nil];DGToast(self.presenter,enabled?@"已开启后台音频播放":@"已关闭后台音频播放");}
- (void)more {if(self.moreAction)self.moreAction();else[self download:CGPointMake(self.contentView.bounds.size.width-40,self.contentView.bounds.size.height-140)];}
- (void)like {[self write:@"digg" add:!_work.liked];}
- (void)collect {[self write:@"favorite" add:!_work.collected];}
- (void)doubleLike:(UITapGestureRecognizer*)g {if(!_work.liked)[self write:@"digg" add:YES];}
- (void)write:(NSString*)operation add:(BOOL)add {if(_busy||!self.bridge)return;_busy=YES;NSUInteger generation=_generation;NSString *workID=Text(_work.id);__weak DGFeedCell *weak=self;[self.bridge request:operation parameters:@{@"id":workID,@"add":@(add)} completion:^(NSDictionary*r,NSString*error){DGFeedCell *s=weak;if(!s||generation!=s->_generation)return;s->_busy=NO;BOOL ok=[r[@"ok"]boolValue]||[r[@"success"]boolValue];if(error||!ok){DGToast(s.presenter,error?:@"平台未确认操作，请先登录再重试");return;}if([operation isEqualToString:@"digg"]){s->_work.liked=add;s->_work.likes=MAX(0,s->_work.likes+(add?1:-1));}else{s->_work.collected=add;s->_work.collects=MAX(0,s->_work.collects+(add?1:-1));}[s labels];UIImpactFeedbackGenerator *feedback=[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight];[feedback impactOccurred];UIButton *button=[operation isEqualToString:@"digg"]?s->_likeButton:s->_collectButton;[UIView animateWithDuration:.12 animations:^{button.transform=CGAffineTransformMakeScale(1.2,1.2);} completion:^(BOOL ok){[UIView animateWithDuration:.18 animations:^{button.transform=CGAffineTransformIdentity;}];}];[NSNotificationCenter.defaultCenter postNotificationName:@"DouGlassWorkStateChanged" object:nil userInfo:@{@"id":workID,@"liked":@(s->_work.liked),@"collected":@(s->_work.collected),@"likes":@(s->_work.likes),@"collects":@(s->_work.collects)}];}];}
- (void)loadPhotos {if(_photos.bounds.size.width<=0||!_images.count)return;NSInteger page=MAX(0,MIN((NSInteger)_images.count-1,(NSInteger)llround(_photos.contentOffset.x/_photos.bounds.size.width)));_photoIndex=page;for(NSInteger i=MAX(0,page-1);i<=MIN((NSInteger)_images.count-1,page+1);++i)[_images[i] remote:Text(_work.images[i])];_photoCount.text=[NSString stringWithFormat:@"图文 %ld/%lu",(long)page+1,(unsigned long)_images.count];}
- (void)scrollViewDidScroll:(UIScrollView*)scroll {[self loadPhotos];}
- (void)seekStart {_dragging=YES;_previewImage.image=nil;_previewGlass.hidden=NO;if(!_generator&&_player.currentItem.asset){_generator=[[AVAssetImageGenerator alloc]initWithAsset:_player.currentItem.asset];_generator.appliesPreferredTrackTransform=YES;_generator.maximumSize=CGSizeMake(320,240);_generator.requestedTimeToleranceBefore=CMTimeMakeWithSeconds(.15,600);_generator.requestedTimeToleranceAfter=CMTimeMakeWithSeconds(.15,600);}[self seekChange];}
- (void)seekChange {if(!_dragging)return;double duration=CMTimeGetSeconds(_player.currentItem.duration);if(!std::isfinite(duration)||duration<=0)return;double seconds=_slider.value*duration;_previewTime.text=[NSString stringWithFormat:@"%@ / %@",TimeLabel(seconds),TimeLabel(duration)];[self setNeedsLayout];NSUInteger request=++_previewGeneration,generation=_generation;__weak DGFeedCell *weak=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,75*NSEC_PER_MSEC),dispatch_get_main_queue(),^{DGFeedCell *s=weak;if(!s||!s->_dragging||generation!=s->_generation||request!=s->_previewGeneration)return;[s->_generator cancelAllCGImageGeneration];[s->_generator generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:CMTimeMakeWithSeconds(seconds,600)]] completionHandler:^(CMTime requested,CGImageRef image,CMTime actual,AVAssetImageGeneratorResult result,NSError*error){UIImage *frame=image?[UIImage imageWithCGImage:image]:nil;dispatch_async(dispatch_get_main_queue(),^{DGFeedCell *s=weak;if(s&&s->_dragging&&generation==s->_generation&&request==s->_previewGeneration&&frame)s->_previewImage.image=frame;});}];});}
- (void)seekEnd {double duration=CMTimeGetSeconds(_player.currentItem.duration);_dragging=NO;_previewGlass.hidden=YES;++_previewGeneration;[_generator cancelAllCGImageGeneration];[_emitted removeAllObjects];[_danmaku.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];_progressAt=CACurrentMediaTime();if(std::isfinite(duration)&&duration>0){__weak DGFeedCell *weak=self;[_player seekToTime:CMTimeMakeWithSeconds(_slider.value*duration,600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL ok){DGFeedCell *s=weak;if(s&&s->_active&&!s->_paused)[s->_player playImmediatelyAtRate:s->_rate];}];}}
- (void)settingsChanged {_rate=1;[_fillButton setImage:[UIImage systemImageNamed:DGBackgroundAudioEnabled()?@"headphones.circle.fill":@"headphones"] forState:UIControlStateNormal];id enabled=[NSUserDefaults.standardUserDefaults objectForKey:@"douglass.danmaku"];_danmaku.hidden=enabled&&![enabled boolValue];if(_danmaku.hidden)[_danmaku.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];if(_active&&!_paused&&!_boosting){_player.rate=_rate;_musicPlayer.rate=_rate;}}
- (void)updateDanmaku:(double)seconds {if(_danmaku.hidden||_work.photo()||!self.bridge)return;NSInteger window=(NSInteger)seconds/30;if(window!=_danmakuWindow&&!_danmakuLoading){_danmakuLoading=YES;NSUInteger generation=_generation;__weak DGFeedCell *weak=self;[self.bridge request:@"danmaku" parameters:@{@"id":Text(_work.id),@"from":@(window*30000),@"to":@((window+1)*30000),@"duration":@(MAX(30000.,_work.duration*1000))} completion:^(NSDictionary*r,NSString*error){DGFeedCell *s=weak;if(!s||generation!=s->_generation)return;s->_danmakuLoading=NO;s->_danmakuWindow=window;s->_danmakuItems=error?@[]:Array(r[@"items"]);[s->_emitted removeAllObjects];}];}if(window!=_danmakuWindow)return;NSUInteger i=0;for(NSDictionary *row in _danmakuItems){double offset=[row[@"offset"]doubleValue];NSString *key=[NSString stringWithFormat:@"%ld:%lu",(long)window,(unsigned long)i++];if(offset>seconds+.25||offset<seconds-.55||[_emitted containsObject:key])continue;[_emitted addObject:key];NSString *text=[row[@"text"]isKindOfClass:NSString.class]?row[@"text"]:@"";if(!text.length||_danmaku.subviews.count>=10)continue;UILabel *label=Label(14,UIFontWeightSemibold);label.text=text;label.layer.shadowColor=UIColor.blackColor.CGColor;label.layer.shadowOpacity=.85;label.layer.shadowRadius=2;label.layer.shadowOffset=CGSizeMake(0,1);[label sizeToFit];CGFloat width=MIN(label.bounds.size.width,800);label.frame=CGRectMake(_danmaku.bounds.size.width,(_lane++%3)*30,width,25);[_danmaku addSubview:label];[UIView animateWithDuration:6/MAX(.5,_rate) delay:0 options:UIViewAnimationOptionCurveLinear|UIViewAnimationOptionAllowUserInteraction animations:^{label.frame=CGRectOffset(label.frame,-self->_danmaku.bounds.size.width-width,0);} completion:^(BOOL ok){[label removeFromSuperview];}];}}
- (void)dealloc {[NSNotificationCenter.defaultCenter removeObserver:self];[self unlock];[self detach];}
@end

