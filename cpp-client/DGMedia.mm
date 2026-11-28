#import "DGMedia.h"
#import "DGFeedCache.h"
#import "DGDiagnostics.h"
#import "DGPlaybackResume.h"
#import "DGPreferences.h"
#import "DGAnimation.h"
#import "DGPhotoNavigator.h"
#import <AVKit/AVKit.h>
#import "DGRefreshPiP.h"
#import "DGAmbient.h"
#import "DGVideoEffects.h"
#import "DGRife.h"
#import "DGTimeline.h"
#import "DGDanmaku.h"
#include "InteractionState.hpp"
#import "DGMediaEnhancement.h"
#import "DGAudioEnhancement.h"
#import <QuartzCore/QuartzCore.h>
static void DGFreezeLayer(CALayer *layer,BOOL freeze){
 if(freeze){if(layer.speed==0)return;CFTimeInterval time=[layer convertTime:CACurrentMediaTime() fromLayer:nil];layer.speed=0;layer.timeOffset=time;}
 else if(layer.speed==0){CFTimeInterval time=layer.timeOffset;layer.speed=1;layer.timeOffset=0;layer.beginTime=0;layer.beginTime=[layer convertTime:CACurrentMediaTime() fromLayer:nil]-time;}
}
static void DGSetLayerPlaybackRate(CALayer *layer,double rate){
 if(!std::isfinite(rate)||rate<0||fabs(layer.speed-rate)<.001)return;
 CFTimeInterval now=CACurrentMediaTime(),local=[layer convertTime:now fromLayer:nil];
 CFTimeInterval parent=layer.superlayer?[layer.superlayer convertTime:now fromLayer:nil]:now;
 layer.speed=rate;layer.timeOffset=local;layer.beginTime=parent;
}
static BOOL DGPrewarmAllowed=NO;
@interface DGPrepared:NSObject
@property(nonatomic,strong) AVPlayer *player;
@property(nonatomic,strong) AVPlayerItem *item;
@property(nonatomic) NSUInteger leases;
@property(nonatomic) BOOL warming, warmed, needsBeginning;
@property(nonatomic) BOOL retired;
@property(nonatomic) NSUInteger warmAttempts;
@property(nonatomic) NSUInteger warmGeneration;
@property(nonatomic) BOOL prewarmRequested;
@property(nonatomic) BOOL bound;
@property(nonatomic) NSUInteger configurationRemaining;
@property(nonatomic) CFTimeInterval createdAt;
@property(nonatomic,copy) NSString *sourceKind;
- (instancetype)initWithURL:(NSString *)url;
- (void)warm;
- (void)requestWarm;
- (void)suspendWarm;
- (void)bindPreparedItem;
- (void)configurationReady;
- (void)retire;
@end
@implementation DGPrepared
- (instancetype)initWithURL:(NSString *)url {
 if((self=[super init])){
  _createdAt=CACurrentMediaTime();NSURL *address=[NSURL URLWithString:url];_sourceKind=address.fileURL?@"local":([address.path containsString:@"/aweme/v1/play/"]?@"redirect":@"direct");
  _item=[AVPlayerItem playerItemWithAsset:Asset(url)];_item.preferredForwardBufferDuration=4;_item.audioTimePitchAlgorithm=AVAudioTimePitchAlgorithmTimeDomain;
  _player=[AVPlayer new];_player.automaticallyWaitsToMinimizeStalling=NO;
  [_player addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];[_item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];
  _configurationRemaining=2;__weak DGPrepared *weak=self;DGPrepareMediaEnhancement(_item,^{[weak configurationReady];});DGPrepareAudioEnhancement(_item,^{[weak configurationReady];});
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,650*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weak bindPreparedItem];});
 }return self;
}
- (void)configurationReady{if(_bound||_retired||!_configurationRemaining)return;if(--_configurationRemaining==0)[self bindPreparedItem];}
- (void)bindPreparedItem{
 if(_bound||_retired)return;_bound=YES;_configurationRemaining=0;DGSealAudioEnhancement(_item);DGSealMediaEnhancement(_item);
 DGPrepareVideoFrameOutput(_item);
 [_player replaceCurrentItemWithPlayerItem:_item];
 DGDiagnostic(@"playback.pipeline.bound",[NSString stringWithFormat:@"audio=%d picture=%d ms=%.0f",_item.audioMix!=nil,_item.videoComposition!=nil,(CACurrentMediaTime()-_createdAt)*1000]);[self warm];
}
- (void)warm {
    if(!NSThread.isMainThread){__weak DGPrepared *weak=self;dispatch_async(dispatch_get_main_queue(),^{[weak warm];});return;}
    if(!_prewarmRequested||!DGPrewarmAllowed||_leases||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||_retired||_needsBeginning||_player.rate!=0||_warming||_warmed||_warmAttempts>=2||_item.status!=AVPlayerItemStatusReadyToPlay||_player.status!=AVPlayerStatusReadyToPlay)return;
    _warming=YES;++_warmAttempts;__weak DGPrepared *weak=self;CFTimeInterval started=CACurrentMediaTime();
    NSUInteger generation=++_warmGeneration;
    [_player prerollAtRate:1 completionHandler:^(BOOL ok){dispatch_async(dispatch_get_main_queue(),^{DGPrepared *s=weak;if(!s||generation!=s.warmGeneration)return;s.warming=NO;s.warmed=ok&&!s.retired;if(DGDiagnosticEnabled())DGDiagnostic(@"playback.preroll",[NSString stringWithFormat:@"ms=%.0f result=%d",(CACurrentMediaTime()-started)*1000,s.warmed]);if(s.warmed)[NSNotificationCenter.defaultCenter postNotificationName:@"DGPreparedVideoWarmed" object:s];});}];
}
- (void)requestWarm{_prewarmRequested=YES;[self warm];}
- (void)suspendWarm{_prewarmRequested=NO;++_warmGeneration;BOOL warming=_warming;_warming=NO;_warmAttempts=0;if(warming)[_player cancelPendingPrerolls];}
- (void)retire {
    _retired=YES;_configurationRemaining=0;DGSealAudioEnhancement(_item);DGSealMediaEnhancement(_item);[self suspendWarm];
    if(!_leases){[_item.asset cancelLoading];[_player pause];[_player replaceCurrentItemWithPlayerItem:nil];}
}
- (void)observeValueForKeyPath:(NSString *)key ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
 if(object==_item&&_item.status==AVPlayerItemStatusReadyToPlay)DGDiagnostic(@"playback.asset_ready",[NSString stringWithFormat:@"ms=%.0f source=%@",(CACurrentMediaTime()-_createdAt)*1000,_sourceKind]);
 if(object==_player||object==_item)[self warm];
}
- (void)dealloc {[_player removeObserver:self forKeyPath:@"status"];[_item removeObserver:self forKeyPath:@"status"];[_player pause];}
@end
static NSHashTable<DGFeedCell *> *MediaCells() {
    static NSHashTable<DGFeedCell *> *cells;
    static dispatch_once_t once;
    dispatch_once(&once,^{cells=[NSHashTable weakObjectsHashTable];});
    return cells;
}
@interface DGFeedCell (MediaCleanup)
- (void)discardInactiveMedia;
- (void)resetPlaybackForWork:(NSString *)identifier;
- (BOOL)keepsDisplayAwake;
@end
static void DGUpdateGalleryWake(){
 BOOL awake=NO;for(DGFeedCell *cell in MediaCells().allObjects)if(cell.window&&[cell keepsDisplayAwake]){awake=YES;break;}
 if(UIApplication.sharedApplication.idleTimerDisabled!=awake)UIApplication.sharedApplication.idleTimerDisabled=awake;
}
static NSMutableDictionary<NSString *,DGPrepared *> *Pool(){static NSMutableDictionary *pool;static dispatch_once_t once;dispatch_once(&once,^{pool=[NSMutableDictionary dictionary];});return pool;}
void DGSuspendPrerolls(void){DGPrewarmAllowed=NO;for(DGPrepared *prepared in Pool().allValues)[prepared suspendWarm];}
void DGDeferPrerolls(void){DGPrewarmAllowed=NO;}
void DGInvalidateAudioPreloads(void){for(NSString *key in Pool().allKeys){DGPrepared *prepared=Pool()[key];if(!prepared.leases){[prepared retire];[Pool() removeObjectForKey:key];}}}
static NSString *PlayerURL(const Work &work){NSString *identifier=Text(work.id);NSURL *file=DGCacheLocalVideo(identifier)?:DGPlaybackResumeLocalVideo(identifier);return file.absoluteString?:Text(work.play);}
static NSString *PoolKey(const Work &work){return [NSString stringWithFormat:@"%@|%@",Text(work.id),PlayerURL(work)];}
static DGPrepared *PreparedForWork(const Work &work){
 DGPrepared *prepared=Pool()[PoolKey(work)];if(prepared&&!prepared.retired&&prepared.item.status!=AVPlayerItemStatusFailed)return prepared;
 // A disk download may finish after this URL was already prepared. Retain the
 // decoded stream instead of discarding its preroll to open the new local file.
 NSString *streamKey=[NSString stringWithFormat:@"%@|%@",Text(work.id),Text(work.play)];prepared=Pool()[streamKey];
 return prepared&&!prepared.retired&&prepared.item.status!=AVPlayerItemStatusFailed&&(prepared.warmed||prepared.warming||prepared.item.status==AVPlayerItemStatusReadyToPlay)?prepared:nil;
}
static DGPrepared *Obtain(const Work &w){if(w.play.empty())return nil;NSString *key=PoolKey(w);DGPrepared *p=PreparedForWork(w);BOOL reused=p!=nil;if(!p){p=[[DGPrepared alloc]initWithURL:PlayerURL(w)];Pool()[key]=p;}if(Pool().count>3)for(NSString *old in Pool().allKeys){DGPrepared *v=Pool()[old];if(v!=p&&!v.leases){[v retire];[Pool() removeObjectForKey:old];if(Pool().count<=3)break;}}if(DGDiagnosticEnabled())DGDiagnostic(@"playback.prepare",[NSString stringWithFormat:@"reuse=%d source=%@ ready=%d warmed=%d pool=%lu",reused,p.sourceKind,p.item.status==AVPlayerItemStatusReadyToPlay,p.warmed,(unsigned long)Pool().count]);return p;}
void DGWarmWorks(const std::vector<Work>&works,NSInteger index){
 if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||index<0||index>=(NSInteger)works.size())return;
 DGPrewarmAllowed=YES;
 NSMutableSet *keys=[NSMutableSet set];
 // Retain the previous prepared item without starting another download behind the user.
 for(NSInteger i=MAX(0,index-1);i<=MIN((NSInteger)works.size()-1,index+1);++i){NSString *prefix=[Text(works[i].id) stringByAppendingString:@"|"];for(NSString *key in Pool())if([key hasPrefix:prefix])[keys addObject:key];}
 NSInteger next=index+1;
 if(next<(NSInteger)works.size()&&!works[next].photo()&&!works[next].play.empty()){[keys addObject:PoolKey(works[next])];[Obtain(works[next]) requestWarm];}
 for(NSString *key in Pool().allKeys){DGPrepared *p=Pool()[key];if(![keys containsObject:key]&&!p.leases){[p retire];[Pool() removeObjectForKey:key];}}
}
void DGResetWorkPlayback(NSString *identifier) {
 if(!identifier.length)return;
 NSString *prefix=[identifier stringByAppendingString:@"|"];
 for(NSString *key in Pool())if([key hasPrefix:prefix])Pool()[key].needsBeginning=YES;
 for(DGFeedCell *cell in MediaCells().allObjects)[cell resetPlaybackForWork:identifier];
}
BOOL DGAutomaticPiPAvailable(){return [NSUserDefaults.standardUserDefaults boolForKey:@"douglass.pip"]&&[AVPictureInPictureController isPictureInPictureSupported];}
void DGTrimPlayers(){DGSuspendPrerolls();for(DGFeedCell *cell in MediaCells().allObjects)[cell discardInactiveMedia];for(NSString *key in Pool().allKeys){DGPrepared *p=Pool()[key];if(!p.leases){[p retire];[Pool() removeObjectForKey:key];}}}
void DGClearPlayers(){DGSuspendPrerolls();for(DGPrepared *p in Pool().allValues)[p retire];[Pool() removeAllObjects];}
static NSString *TimeLabel(double value){if(!std::isfinite(value)||value<0)value=0;return [NSString stringWithFormat:@"%02ld:%02ld",(long)value/60,(long)value%60];}
@interface DGFeedCell()<UIScrollViewDelegate,UIGestureRecognizerDelegate,AVPictureInPictureControllerDelegate>
@end
@implementation DGFeedCell {
 DGVideoEffects *_videoEffects;
 DGAmbient *_ambient;UIPanGestureRecognizer *_railShield,*_moreShield;NSCache *_frameCache;BOOL _previewBusy;double _desiredPreview;NSMutableArray<NSNumber *> *_cachedTimes;
 UIActivityIndicatorView *_loadingSpinner;UILabel *_elapsed,*_totalTime;UIButton *_expandCaption;BOOL _captionExpanded;BOOL _backgroundSoundState;UITapGestureRecognizer *_danmakuTap,*_commentCloseTap;NSString *_tappedDanmaku;
 DGPhotoNavigator *_photoNavigator;Work _work;DGImage *_cover,*_avatar,*_musicAvatar;UIImageView *_photoBrowse;UIScrollView *_photos;NSMutableArray<DGImage*> *_images;
 UIView *_shade;DGDanmakuOverlay *_danmaku;CAGradientLayer *_gradient;UILabel *_author,*_following,*_caption,*_metadata,*_photoCount,*_likeCount,*_commentCount,*_collectCount,*_pause,*_message,*_speedText,*_previewTime;
 UIVisualEffectView *_rail,*_moreGlass,*_photoGlass,*_speedGlass,*_previewGlass;UIButton *_avatarButton,*_likeButton,*_commentButton,*_collectButton,*_fillButton,*_moreButton,*_musicButton;UIImageView *_previewImage;
 AVPlayer *_player,*_musicPlayer;AVPlayerLayer *_playerLayer;DGPrepared *_prepared;AVPlayerItem *_observedItem;AVAssetImageGenerator *_generator,*_frameExport;id _loopToken,_musicLoopToken,_clock,_stallToken,_accessToken,_failureToken;DGTimeline *_slider;
 NSMutableArray<UIScrollView*> *_locked;BOOL _active,_paused,_alternateUsed,_dragging,_seeking,_compact,_fill,_boosting,_busy,_danmakuLoading;double _rate,_boostRate,_holdY,_progressAt,_progress;NSInteger _recoveries,_photoIndex,_danmakuWindow,_lane;NSUInteger _generation,_previewGeneration;NSArray<NSDictionary*> *_danmakuItems;NSMutableSet<NSString*> *_emitted;
 AVPictureInPictureController *_pip;BOOL _backgroundMode,_appInactive,_cleanScreen,_foregroundRebind,_pagingMotion,_reportedView;double _lastPlaybackTime;CGFloat _mediaHeight;BOOL _watchdogScheduled,_watchdogExhausted;NSUInteger _watchdogToken,_spinnerToken,_restartToken;BOOL _spinnerPending,_receivedFirstFrame;double _firstFrameStarted;
}
- (instancetype)initWithFrame:(CGRect)frame {
 if((self=[super initWithFrame:frame])){
 [MediaCells()addObject:self];
 self.contentView.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;self.contentView.backgroundColor=UIColor.blackColor;_loadingSpinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];_loadingSpinner.color=UIColor.whiteColor;_loadingSpinner.hidesWhenStopped=YES;_ambient=[DGAmbient new];[self.contentView addSubview:_ambient];_cachedTimes=[NSMutableArray array];_frameCache=[NSCache new];_frameCache.countLimit=32;_frameCache.totalCostLimit=4*1024*1024;_rate=1;_danmakuWindow=-1;_images=[NSMutableArray array];_locked=[NSMutableArray array];_emitted=[NSMutableSet set];
 _cover=[DGImage new];_cover.contentMode=UIViewContentModeScaleAspectFit;_cover.clipsToBounds=YES;[self.contentView addSubview:_cover];_playerLayer=[AVPlayerLayer playerLayerWithPlayer:nil];_playerLayer.videoGravity=AVLayerVideoGravityResizeAspect;_playerLayer.masksToBounds=YES;[self.contentView.layer addSublayer:_playerLayer];[_playerLayer addObserver:self forKeyPath:@"readyForDisplay" options:NSKeyValueObservingOptionNew context:NULL];
 _photos=[UIScrollView new];_photos.pagingEnabled=YES;_photos.scrollsToTop=NO;_photos.clipsToBounds=YES;_photos.directionalLockEnabled=YES;_photos.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;_photos.alwaysBounceVertical=NO;_photos.showsHorizontalScrollIndicator=NO;_photos.delegate=self;[self.contentView addSubview:_photos];_photoBrowse=[UIImageView new];_photoBrowse.contentMode=UIViewContentModeScaleAspectFit;_photoBrowse.clipsToBounds=YES;_photoBrowse.hidden=YES;[self.contentView addSubview:_photoBrowse];_photoNavigator=[DGPhotoNavigator new];__weak DGFeedCell *photoCell=self;_photoNavigator.onThumbnailReady=^(UIImage *image){DGFeedCell *cell=photoCell;if(cell&&cell->_photoNavigator.browsing&&cell->_photoIndex>=0&&cell->_photoIndex<(NSInteger)cell->_images.count&&!cell->_images[cell->_photoIndex].image)cell->_photoBrowse.image=image;};_photoNavigator.onSelect=^(NSInteger index){DGFeedCell *self=photoCell;if(!self)return;[UIView performWithoutAnimation:^{[self->_photos.layer removeAnimationForKey:@"bounds"];[self->_photos setContentOffset:CGPointMake(index*self->_photos.bounds.size.width,0) animated:NO];[self loadPhotos];}];if(self->_photoNavigator.browsing)[self refreshPhotoBrowse];};_photoNavigator.onBrowsingChanged=^(BOOL browsing){DGFeedCell *self=photoCell;if(!self)return;if(browsing)[self refreshPhotoBrowse];self->_photoBrowse.hidden=!browsing;self->_photos.hidden=browsing||!self->_work.photo();if(!browsing)self->_photoBrowse.image=nil;[self setNeedsLayout];DGAnimate(.18,^{[self layoutIfNeeded];},nil);};[self.contentView addSubview:_photoNavigator];
 _danmaku=[DGDanmakuOverlay new];__weak DGDanmakuOverlay *contrastOverlay=_danmaku;__weak DGAmbient *contrastAmbient=_ambient;_danmaku.samplingChanged=^(BOOL enabled){[contrastAmbient adaptive:enabled];};_ambient.contrastReady=^(UIImage *white,UIImage *black){[contrastOverlay whiteMask:white blackMask:black];};_danmaku.clipsToBounds=YES;_danmakuTap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(copyDanmaku:)];_danmakuTap.delegate=self;[_danmaku addGestureRecognizer:_danmakuTap];[self.contentView addSubview:_danmaku];_shade=[UIView new];_shade.userInteractionEnabled=NO;_gradient=[CAGradientLayer layer];_gradient.colors=@[(id)UIColor.clearColor.CGColor,(id)[UIColor colorWithWhite:0 alpha:.75].CGColor];[_shade.layer addSublayer:_gradient];[self.contentView addSubview:_shade];
 _author=Label(17,UIFontWeightSemibold);_author.userInteractionEnabled=NO;_following=Label(11,UIFontWeightMedium);_following.text=@"正在关注";_following.textColor=[UIColor colorWithWhite:1 alpha:.78];_following.hidden=YES;[self.contentView addSubview:_following];
 _caption=Label(14,UIFontWeightRegular);_caption.numberOfLines=3;_caption.userInteractionEnabled=YES;[_caption addGestureRecognizer:[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(copyCaption:)]];
 _expandCaption=[UIButton buttonWithType:UIButtonTypeSystem];_expandCaption.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];_expandCaption.tintColor=UIColor.whiteColor;[_expandCaption setTitle:@"展开 ﹀" forState:UIControlStateNormal];[_expandCaption addTarget:self action:@selector(expandCaption) forControlEvents:UIControlEventTouchUpInside];[self.contentView addSubview:_expandCaption];_elapsed=Label(10,UIFontWeightRegular);_totalTime=Label(10,UIFontWeightRegular);_totalTime.textAlignment=NSTextAlignmentRight;[self.contentView addSubview:_elapsed];[self.contentView addSubview:_totalTime];_metadata=Label(11,UIFontWeightRegular);_metadata.textColor=[UIColor colorWithWhite:1 alpha:.64];for(UIView *v in @[_author,_caption,_metadata])[self.contentView addSubview:v];
 _musicButton=[UIButton buttonWithType:UIButtonTypeSystem];_musicButton.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;_musicButton.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];_musicButton.tintColor=[UIColor colorWithWhite:1 alpha:.78];_musicButton.titleLabel.lineBreakMode=NSLineBreakByTruncatingTail;[_musicButton addTarget:self action:@selector(music) forControlEvents:UIControlEventTouchUpInside];[self.contentView addSubview:_musicButton];
 _musicAvatar=[DGImage new];_musicAvatar.maximumPixelSize=128;_musicAvatar.placeholderImage=[UIImage systemImageNamed:@"opticaldisc"];_musicAvatar.tintColor=[UIColor colorWithWhite:1 alpha:.75];_musicAvatar.contentMode=UIViewContentModeScaleAspectFill;_musicAvatar.layer.cornerRadius=11;_musicAvatar.clipsToBounds=YES;_musicAvatar.userInteractionEnabled=YES;[_musicAvatar addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(music)]];[self.contentView addSubview:_musicAvatar];
 _rail=Glass(27);[self.contentView addSubview:_rail];_avatarButton=[UIButton buttonWithType:UIButtonTypeCustom];[_avatarButton addTarget:self action:@selector(profile) forControlEvents:UIControlEventTouchUpInside];_avatar=[DGImage new];_avatar.contentMode=UIViewContentModeScaleAspectFill;_avatar.layer.cornerRadius=20;_avatar.clipsToBounds=YES;[_avatarButton addSubview:_avatar];[_rail.contentView addSubview:_avatarButton];
 _likeButton=Symbol(@"heart",self,@selector(like));_commentButton=Symbol(@"text.bubble",self,@selector(comments));_collectButton=Symbol(@"star",self,@selector(collect));_fillButton=Symbol(@"headphones",self,@selector(fill));_likeButton.accessibilityLabel=@"点赞";_commentButton.accessibilityLabel=@"评论";_collectButton.accessibilityLabel=@"收藏";_fillButton.accessibilityLabel=@"后台音频播放";
 UIImageSymbolConfiguration *railSymbols=[UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightMedium];for(UIButton *button in @[_likeButton,_commentButton,_collectButton])[button setPreferredSymbolConfiguration:railSymbols forImageInState:UIControlStateNormal];_likeCount=Label(11,UIFontWeightMedium);_commentCount=Label(11,UIFontWeightMedium);_collectCount=Label(11,UIFontWeightMedium);for(UILabel *l in @[_likeCount,_commentCount,_collectCount])l.textAlignment=NSTextAlignmentCenter;for(UIView *v in @[_likeButton,_likeCount,_commentButton,_commentCount,_collectButton,_collectCount,_fillButton])[_rail.contentView addSubview:v];
 _moreGlass=Glass(25);_moreButton=Symbol(@"ellipsis",self,@selector(more));_moreButton.accessibilityLabel=@"更多选项";[_moreGlass.contentView addSubview:_moreButton];[self.contentView addSubview:_moreGlass];_photoGlass=Glass(16);_photoCount=Label(11,UIFontWeightMedium);_photoCount.textAlignment=NSTextAlignmentCenter;[_photoGlass.contentView addSubview:_photoCount];[self.contentView addSubview:_photoGlass];
 _pause=Label(52,UIFontWeightLight);_pause.text=@"▶";_pause.textAlignment=NSTextAlignmentCenter;_pause.hidden=YES;_pause.layer.shadowColor=UIColor.blackColor.CGColor;_pause.layer.shadowOpacity=.35;_pause.layer.shadowRadius=7;[self.contentView addSubview:_pause];_message=Label(13,UIFontWeightRegular);_message.textAlignment=NSTextAlignmentCenter;_message.numberOfLines=2;[self.contentView addSubview:_message];
 _slider=[DGTimeline new];_slider.minimumValue=0;_slider.maximumValue=1;_slider.tintColor=[UIColor colorWithRed:.76 green:.96 blue:.96 alpha:1];_slider.maximumTrackTintColor=[UIColor colorWithWhite:1 alpha:.18];_slider.tintColor=UIColor.whiteColor;__weak DGFeedCell *timelineCell=self;((DGTimeline *)_slider).trackingBegan=^{[timelineCell seekStart];};((DGTimeline *)_slider).trackingChanged=^{[timelineCell seekChange];};((DGTimeline *)_slider).trackingEnded=^(BOOL cancelled){if(cancelled)[timelineCell seekCancel];else[timelineCell seekEnd];};[self.contentView addSubview:_slider];
 _previewGlass=Glass(14);_previewGlass.hidden=YES;_previewGlass.userInteractionEnabled=NO;_previewImage=[UIImageView new];_previewImage.contentMode=UIViewContentModeScaleAspectFit;_previewTime=Label(11,UIFontWeightMedium);_previewTime.textAlignment=NSTextAlignmentCenter;[_previewGlass.contentView addSubview:_previewImage];[_previewGlass.contentView addSubview:_previewTime];[self.contentView addSubview:_previewGlass];_speedGlass=Glass(19);_speedGlass.hidden=YES;_speedGlass.userInteractionEnabled=NO;_speedText=Label(13,UIFontWeightSemibold);_speedText.textAlignment=NSTextAlignmentCenter;[_speedGlass.contentView addSubview:_speedText];[self.contentView addSubview:_speedGlass];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(videoEffectsChanged) name:@"DGVideoEffectsChanged" object:nil];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(pictureEnhancementChanged) name:@"DGMediaEnhancementChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(audioEnhancementChanged) name:@"DGAudioEnhancementChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(preparedVideoWarmed) name:@"DGPreparedVideoWarmed" object:nil];
 _commentCloseTap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(closeCommentsFromVideo)];_commentCloseTap.delegate=self;_commentCloseTap.delaysTouchesBegan=NO;_commentCloseTap.delaysTouchesEnded=NO;[self.contentView addGestureRecognizer:_commentCloseTap];
 UITapGestureRecognizer *single=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(toggle)];single.delegate=self;single.cancelsTouchesInView=NO;[self.contentView addSubview:_loadingSpinner];UITapGestureRecognizer *doubleTap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(doubleLike:)];doubleTap.numberOfTapsRequired=2;doubleTap.delegate=self;[single requireGestureRecognizerToFail:doubleTap];[self.contentView addGestureRecognizer:single];[self.contentView addGestureRecognizer:doubleTap];UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(hold:)];hold.minimumPressDuration=.32;hold.allowableMovement=22;hold.delegate=self;[self.contentView addGestureRecognizer:hold];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged) name:@"DouGlassSettingsChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(startPiP) name:@"DGPiPStart" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(emojiReady) name:@"DGEmojiAssetsReady" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interactionChanged:) name:@"DouGlassWorkStateChanged" object:nil];
 }return self;
}
- (void)layoutSubviews {
 [super layoutSubviews];CGRect b=self.contentView.bounds;if(_mediaHeight>0)b.size.height=_mediaHeight;CGFloat w=b.size.width,h=b.size.height,bottom=_compact?4:MAX(self.safeAreaInsets.bottom,14),top=MAX(self.safeAreaInsets.top,18)+65;
 [CATransaction begin];[CATransaction setDisableActions:YES];CGRect media=b;if(_compact){media.origin.y=MAX(self.safeAreaInsets.top,18)+45;media.size.height=MAX(80,b.size.height-media.origin.y-6);}_playerLayer.frame=media;[self applyVideoGravity];[_videoEffects layout];[CATransaction commit];_loadingSpinner.center=CGPointMake(CGRectGetMidX(media),CGRectGetMidY(media));_ambient.frame=b;_cover.frame=media;_photoBrowse.frame=media;_photos.frame=media;_photos.contentSize=CGSizeMake(w*_images.count,_photos.bounds.size.height);for(NSUInteger i=0;i<_images.count;++i)_images[i].frame=CGRectMake(i*w,0,w,_photos.bounds.size.height);if(_work.photo()&&w>0&&!_photoNavigator.browsing&&!_photos.tracking&&!_photos.dragging&&!_photos.decelerating&&fabs(_photos.contentOffset.x-_photoIndex*w)>.5)_photos.contentOffset=CGPointMake(_photoIndex*w,0);
 _shade.frame=CGRectMake(0,MAX(0,h-260),w,260);_gradient.frame=_shade.bounds;CGFloat tw=MAX(80,MIN(w-103,680));CGFloat line=_caption.font.lineHeight;CGFloat full=ceil([Text(_work.caption)boundingRectWithSize:CGSizeMake(tw,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:_caption.font} context:nil].size.height);BOOL expandable=full>line*3+1;CGFloat ch=_captionExpanded?full:MIN(full,line*3);_caption.numberOfLines=_captionExpanded?0:3;CGFloat expansion=expandable?22:0;_expandCaption.hidden=!expandable||_compact||_cleanScreen;[_expandCaption setTitle:_captionExpanded?@"收起 ︿":@"展开 ﹀" forState:UIControlStateNormal];
 _musicAvatar.frame=CGRectMake(20,h-bottom-56,22,22);_musicButton.frame=CGRectMake(49,h-bottom-60,tw-29,30);_metadata.frame=CGRectMake(20,CGRectGetMinY(_musicAvatar.frame)-23,tw,18);_expandCaption.frame=CGRectMake(20,CGRectGetMinY(_metadata.frame)-expansion-4,64,expansion);_caption.frame=CGRectMake(20,CGRectGetMinY(_metadata.frame)-ch-expansion-7,tw,ch);_author.frame=CGRectMake(20,CGRectGetMinY(_caption.frame)-30,tw,26);_following.frame=CGRectMake(20,MAX(0,CGRectGetMinY(_author.frame)-21),tw,17);_following.hidden=_compact||_cleanScreen||!douglass::isFollowing(_work.followStatus);
 CGFloat font=[NSUserDefaults.standardUserDefaults doubleForKey:@"douglass.danmaku.size"];if(font<12||font>28)font=14;CGFloat laneHeight=font+12,limit=MIN(CGRectGetMinY(_author.frame)-18,h*.36);CGSize videoSize=_player.currentItem.presentationSize;CGRect videoRect=_playerLayer.videoRect;if(videoSize.width>videoSize.height&&videoSize.height>0&&!CGRectIsEmpty(videoRect)){CGRect visible=[_playerLayer convertRect:videoRect toLayer:self.contentView.layer];limit=MIN(limit,CGRectGetMinY(visible)-12);}CGFloat available=MAX(laneHeight,limit-top);NSInteger scope=MIN(2,MAX(0,[NSUserDefaults.standardUserDefaults integerForKey:@"douglass.danmaku.range"]));CGFloat range=scope==0?MIN(available,3*laneHeight):scope==1?MIN(available,MAX(3*laneHeight,available*.68)):available;_danmaku.frame=CGRectMake(0,top,w,range);[_ambient contrastInRect:_danmaku.frame playerLayer:_playerLayer];
 _rail.frame=CGRectMake(w-73,MAX(top+42,h-bottom-436),53,310);_avatarButton.frame=CGRectMake(4,8,45,45);_avatar.frame=CGRectMake(2.5,2.5,40,40);NSArray<UIButton*> *buttons=@[_likeButton,_commentButton,_collectButton];NSArray<UILabel*> *counts=@[_likeCount,_commentCount,_collectCount];for(NSUInteger i=0;i<3;++i){buttons[i].frame=CGRectMake(1,59+i*65,51,40);counts[i].frame=CGRectMake(0,98+i*65,53,17);}_fillButton.frame=CGRectMake(1,257,51,45);_moreGlass.frame=CGRectMake(w-73,CGRectGetMaxY(_rail.frame)+12,53,49);_moreButton.frame=_moreGlass.bounds;
 _photoGlass.frame=CGRectMake(w-110,top+5,90,30);_photoCount.frame=_photoGlass.bounds;_pause.frame=CGRectMake((w-80)/2,(h-80)/2,80,80);_message.frame=CGRectMake(25,h/2+48,w-50,50);_slider.frame=CGRectMake(20,h-bottom-27,w-40,24);_elapsed.frame=CGRectMake(20,CGRectGetMaxY(_slider.frame),75,13);_totalTime.frame=CGRectMake(w-95,CGRectGetMaxY(_slider.frame),75,13);_elapsed.hidden=_cleanScreen||_compact||_work.photo();_totalTime.hidden=_cleanScreen||_compact||_work.photo();
 CGSize source=_player.currentItem.presentationSize;if(source.width<1||source.height<1)source=CGSizeMake(9,16);CGFloat ratio=source.width/source.height;CGFloat imageW=MIN(272,w-48),imageH=imageW/ratio,maxH=MIN(330,MAX(100,h*.44));if(imageH>maxH){imageH=maxH;imageW=imageH*ratio;}CGFloat pw=imageW+12,ph=imageH+40;CGFloat px=MAX(12,MIN(w-pw-12,20+_slider.value*(w-40)-pw/2));_previewGlass.frame=CGRectMake(px,MAX(0,CGRectGetMinY(_slider.frame)-ph-12),pw,ph);_previewImage.frame=CGRectMake(6,6,imageW,imageH);_previewTime.frame=CGRectMake(6,imageH+12,imageW,22);_speedGlass.frame=CGRectMake((w-184)/2,top+8,184,38);_speedText.frame=_speedGlass.bounds;
 for(UIView *v in @[_author,_caption,_metadata,_musicAvatar,_musicButton,_rail,_moreGlass,_shade])v.hidden=_compact||_cleanScreen;_photoGlass.hidden=_cleanScreen||!_work.photo();_slider.hidden=_cleanScreen||_compact||_work.photo();_photoNavigator.hidden=_cleanScreen||_compact||!_work.photo();_photoNavigator.frame=CGRectMake(24,MAX(top+16,CGRectGetMinY(_author.frame)-40),MAX(80,w-48),30);CGFloat browsingAlpha=_photoNavigator.browsing?0:1;for(UIView *chrome in @[_author,_following,_caption,_metadata,_musicAvatar,_musicButton,_rail,_moreGlass,_expandCaption,_photoGlass,_pause,_danmaku])chrome.alpha=browsingAlpha;[self.contentView bringSubviewToFront:_photoNavigator];if(_compact)_previewGlass.hidden=YES;if(_work.photo())[self loadPhotos];
}
- (void)mediaHeight:(CGFloat)value {
 if(fabs(_mediaHeight-value)<.1)return;CALayer *visible=_playerLayer.presentationLayer;CGRect previous=visible?visible.frame:_playerLayer.frame;_mediaHeight=value;[self setNeedsLayout];DGAnimate(.3,^{[self layoutIfNeeded];},nil);CGRect target=_playerLayer.frame;
 CABasicAnimation *position=[CABasicAnimation animationWithKeyPath:@"position"];position.fromValue=[NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(previous),CGRectGetMidY(previous))];position.toValue=[NSValue valueWithCGPoint:_playerLayer.position];position.duration=DGDuration(.3);position.timingFunction=DGTiming();CABasicAnimation *bounds=[CABasicAnimation animationWithKeyPath:@"bounds"];bounds.fromValue=[NSValue valueWithCGRect:CGRectMake(0,0,previous.size.width,previous.size.height)];bounds.toValue=[NSValue valueWithCGRect:CGRectMake(0,0,target.size.width,target.size.height)];bounds.duration=DGDuration(.3);bounds.timingFunction=position.timingFunction;[_playerLayer addAnimation:position forKey:@"comment-position"];[_playerLayer addAnimation:bounds forKey:@"comment-bounds"];
}
- (void)interactiveMediaHeight:(CGFloat)value{[_playerLayer removeAnimationForKey:@"comment-position"];[_playerLayer removeAnimationForKey:@"comment-bounds"];_mediaHeight=value;[UIView performWithoutAnimation:^{[self setNeedsLayout];[self layoutIfNeeded];}];}

- (void)enterBackgroundKeepingPlayback:(BOOL)keep audioOnly:(BOOL)audioOnly {
 [_videoEffects stop];
 DGSetMetalFXPlaybackActive(_observedItem,NO);
 if(_backgroundMode)return;
 _backgroundMode=YES;DGUpdateGalleryWake();[self syncDanmakuPlayback];[_slider stopFollowing];
 [self stopWatchdog];[_ambient active:NO];[_ambient item:nil imageView:nil];
 if(!keep)[self active:NO];
 [self releaseUnusedResources];
 if(keep&&audioOnly&&!_pip.pictureInPictureActive&&_playerLayer.player){
  _cover.hidden=NO;_playerLayer.player=nil;
 }
}
- (void)suspendForegroundWork {
 [_videoEffects stop];
 DGSetMetalFXPlaybackActive(_observedItem,NO);
 _appInactive=YES;DGUpdateGalleryWake();[_photoNavigator cancelBrowsing];[_slider stopFollowing];[self stopWatchdog];[self cancelLoadingIndicator];[_ambient active:NO];
 [self syncDanmakuPlayback];
}
- (void)leaveBackground {
 _appInactive=NO;DGUpdateGalleryWake();
 if(!_backgroundMode)return;
 _backgroundMode=NO;_foregroundRebind=YES;DGUpdateGalleryWake();
 _progressAt=CACurrentMediaTime();_firstFrameStarted=_progressAt;
 if(_playerLayer.player!=_player)_playerLayer.player=_player;
}
- (void)discardInactiveMedia {if(!_active)[self releaseUnusedResources];}
- (void)releaseUnusedResources {
 if(_dragging){_dragging=NO;_seeking=NO;[self playCurrentVideo];}
 ++_previewGeneration;_previewBusy=NO;[_generator cancelAllCGImageGeneration];_generator=nil;_previewImage.image=nil;_previewGlass.hidden=YES;[_frameCache removeAllObjects];[_cachedTimes removeAllObjects];
 for(NSUInteger i=0;i<_images.count;i++)if(!_active||labs((long)i-_photoIndex)>(_backgroundMode?0:1))[_images[i] remote:@""];
 if(!_active){_photoBrowse.hidden=YES;_photoBrowse.image=nil;}
 if(!_active&&(_player||_musicPlayer)){_lastPlaybackTime=[self currentPlaybackPosition];[self detach];}
}
- (void)configurePiP{BOOL enabled=[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.pip"]&&[AVPictureInPictureController isPictureInPictureSupported]&&!_work.photo();if(enabled&&_player&&!_pip){_pip=[[AVPictureInPictureController alloc]initWithPlayerLayer:_playerLayer];_pip.delegate=self;_pip.canStartPictureInPictureAutomaticallyFromInline=YES;}if(!enabled&&_pip){[_pip stopPictureInPicture];_pip.delegate=nil;_pip=nil;}}
- (void)startPiP{if(!_active||_work.photo())return;[self configurePiP];if(_pip.pictureInPicturePossible)[_pip startPictureInPicture];else if(self.presenter)DGToast(self.presenter,@"当前视频尚不能进入画中画，请稍后再试");}
- (void)pictureInPictureControllerWillStartPictureInPicture:(AVPictureInPictureController *)controller{if(controller==_pip)DGRefreshPiPPreferVideo(YES);}
- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)controller{if(controller==_pip)DGRefreshPiPPreferVideo(NO);}
- (void)pictureInPictureController:(AVPictureInPictureController *)controller failedToStartPictureInPictureWithError:(NSError *)error{if(controller==_pip)DGRefreshPiPPreferVideo(NO);}
- (void)pictureInPictureController:(AVPictureInPictureController *)controller restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL))completion{completion(self.window!=nil);[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}
- (void)cleanScreen:(BOOL)clean {
 if(_cleanScreen==clean)return;
 _cleanScreen=clean;
 id saved=[NSUserDefaults.standardUserDefaults objectForKey:@"douglass.danmaku"];
 _danmaku.hidden=clean||(saved&&![saved boolValue]);
 if(clean){[_photoNavigator cancelBrowsing];[_danmaku.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];_previewGlass.hidden=YES;_speedGlass.hidden=YES;}
 [self setNeedsLayout];[self layoutIfNeeded];
}
- (void)applyVideoGravity{
 CGSize size=_player.currentItem.presentationSize;BOOL fill=douglass::fillsPortrait(_fill,_compact,_work.photo(),size.width,size.height);
 NSString *gravity=fill?AVLayerVideoGravityResizeAspectFill:AVLayerVideoGravityResizeAspect;if(![_playerLayer.videoGravity isEqualToString:gravity])_playerLayer.videoGravity=gravity;
 _cover.contentMode=fill?UIViewContentModeScaleAspectFill:UIViewContentModeScaleAspectFit;
}
- (void)compact:(BOOL)value {if(_compact==value)return;_compact=value;[self applyVideoGravity];[self setNeedsLayout];}
- (CGFloat)notificationTopInView:(UIView *)view {
 if(!_active||!self.window||!view)return 0;
 double font=[NSUserDefaults.standardUserDefaults doubleForKey:@"douglass.danmaku.size"];if(font<12||font>28)font=14;
 NSInteger lanes=MAX(1,(NSInteger)(_danmaku.bounds.size.height/(font+12)));
 CGRect area=CGRectMake(0,0,_danmaku.bounds.size.width,MIN(_danmaku.bounds.size.height,lanes*(font+12)));
 return CGRectGetMaxY([_danmaku convertRect:area toView:view])+12;
}
- (void)detach {
 [_videoEffects stop];
 DGSetMetalFXPlaybackActive(_observedItem,NO);
 DGUpdateGalleryWake();
 [_frameExport cancelAllCGImageGeneration];_frameExport=nil;
 [_danmaku adaptive:[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.danmaku.adaptive"] playing:NO];
 if(_seeking)[_observedItem cancelPendingSeeks];
 _seeking=NO;++_restartToken;_slider.userInteractionEnabled=YES;[_slider stopFollowing];[self cancelLoadingIndicator];

 [self stopWatchdog];BOOL wasPiP=_pip.pictureInPictureActive;[_pip stopPictureInPicture];_pip.delegate=nil;_pip=nil;if(wasPiP)DGRefreshPiPPreferVideo(NO);[_ambient active:NO];[_ambient item:nil imageView:nil];_previewBusy=NO;
 ++_previewGeneration;[_generator cancelAllCGImageGeneration];_generator=nil;if(_observedItem){[_observedItem removeObserver:self forKeyPath:@"status"];_observedItem=nil;}if(_clock&&_player){[_player removeTimeObserver:_clock];_clock=nil;}if(_loopToken){[NSNotificationCenter.defaultCenter removeObserver:_loopToken];_loopToken=nil;}
 if(_stallToken){[NSNotificationCenter.defaultCenter removeObserver:_stallToken];_stallToken=nil;}
 if(_accessToken){[NSNotificationCenter.defaultCenter removeObserver:_accessToken];_accessToken=nil;}
 if(_failureToken){[NSNotificationCenter.defaultCenter removeObserver:_failureToken];_failureToken=nil;}if(_musicLoopToken){[NSNotificationCenter.defaultCenter removeObserver:_musicLoopToken];_musicLoopToken=nil;}if(_prepared){if(_prepared.leases)--_prepared.leases;if(!_prepared.leases)[_prepared.player pause];_prepared=nil;}else[_player pause];[_musicPlayer pause];_musicPlayer=nil;_player=nil;_playerLayer.player=nil;
}
- (void)prepareForReuse {[super prepareForReuse];[_photoNavigator cancelBrowsing];_active=NO;_appInactive=NO;++_generation;[self unlock];[self detach];_work=Work{};self.commentsAction=nil;self.profileAction=nil;self.musicAction=nil;self.moreAction=nil;self.actionMenuAction=nil;self.dismissCommentsAction=nil;self.advanceAction=nil;self.viewedAction=nil;self.checkpointAction=nil;[_danmaku.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];}
- (void)display:(const Work&)work {
 if(!_work.id.empty()&&work.id==_work.id&&(work.photo()!=_work.photo()||work.images!=_work.images))_work.id.clear();
 if(!_work.id.empty()&&work.id==_work.id){BOOL sourceChanged=work.play!=_work.play;double position=[self currentPlaybackPosition];_work=work;[_avatar remote:Text(work.avatar)];[_musicAvatar remote:Text(work.musicCover)];if(sourceChanged&&!work.photo()&&_player&&!_pagingMotion&&(!_receivedFirstFrame||_observedItem.status==AVPlayerItemStatusFailed||_watchdogExhausted)){_alternateUsed=NO;_recoveries=0;_watchdogExhausted=NO;[_frameCache removeAllObjects];[_cachedTimes removeAllObjects];[self attach:Obtain(work) position:position];if(_active)[self active:YES];}[self labels];return;}++_generation;[self unlock];[self detach];_work=work;_reportedView=NO;_lastPlaybackTime=0;_backgroundMode=NO;_paused=NO;_alternateUsed=NO;_watchdogExhausted=NO;_boosting=NO;_dragging=NO;_seeking=NO;_recoveries=0;_photoIndex=0;_busy=NO;_captionExpanded=NO;_previewBusy=NO;[_frameCache removeAllObjects];[_cachedTimes removeAllObjects];_pause.hidden=YES;_previewGlass.hidden=YES;_speedGlass.hidden=YES;_message.text=@"";_slider.value=0;_progress=-1;_progressAt=CACurrentMediaTime();_danmakuWindow=-1;_danmakuItems=@[];_danmakuLoading=NO;[_emitted removeAllObjects];[_danmaku.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];for(DGImage *i in _images)[i removeFromSuperview];[_images removeAllObjects];_cover.hidden=work.photo();[_cover remote:work.photo()?@"":Text(work.cover)];[_avatar remote:Text(work.avatar)];[_musicAvatar remote:Text(work.musicCover)];NSMutableArray *photoURLs=[NSMutableArray array];for(const auto &url:work.images)[photoURLs addObject:Text(url)];[_photoNavigator images:photoURLs];_photos.contentOffset=CGPointZero;_photos.hidden=!work.photo();_photoGlass.hidden=!work.photo();[self settingsChanged];[self labels];
 if(work.photo()){__weak DGFeedCell *weak=self;NSUInteger generation=_generation,photo=0;for(const auto &url:work.images){DGImage *i=[DGImage new];i.experimentalPicture=YES;i.contentMode=UIViewContentModeScaleAspectFit;NSUInteger index=photo++;i.imageReady=^(UIImage *image){DGFeedCell *cell=weak;if(cell&&generation==cell->_generation&&cell->_photoNavigator.browsing&&cell->_photoIndex==(NSInteger)index)cell->_photoBrowse.image=image;};[_photos addSubview:i];[_images addObject:i];}if(_active)[self attachPhotoSound:0];}
 else if(_active)[self attach:Obtain(work) position:0];[self setNeedsLayout];if(_active)[self active:YES];
}
- (void)attachPhotoSound:(double)position {
 if(_work.music.empty()||_musicPlayer)return;
 AVPlayerItem *item=[AVPlayerItem playerItemWithAsset:Asset(Text(_work.music))];__weak DGFeedCell *weak=self;
 _musicPlayer=DGMakeAudioPlayer(item,^(AVPlayer *player){DGFeedCell *cell=weak;if(!cell||cell->_musicPlayer!=player)return;if(position>.05){[player seekToTime:CMTimeMakeWithSeconds(position,600) completionHandler:^(BOOL ok){dispatch_async(dispatch_get_main_queue(),^{DGFeedCell *current=weak;if(ok&&current&&current->_musicPlayer==player&&current->_active&&!current->_paused)[player playImmediatelyAtRate:current->_rate];});}];}else if(cell->_active&&!cell->_paused&&!cell->_pagingMotion)[player playImmediatelyAtRate:cell->_rate];});
 _musicPlayer.automaticallyWaitsToMinimizeStalling=NO;
 if(position>.05&&_musicPlayer.currentItem)[_musicPlayer seekToTime:CMTimeMakeWithSeconds(position,600)];
 __weak AVPlayer *weakPlayer=_musicPlayer;
 _musicLoopToken=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:item queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification){
  AVPlayer *player=weakPlayer;DGFeedCell *cell=weak;if(!cell||player!=cell->_musicPlayer)return;
  [player seekToTime:kCMTimeZero completionHandler:^(BOOL ok){dispatch_async(dispatch_get_main_queue(),^{DGFeedCell *self=weak;AVPlayer *current=weakPlayer;if(self&&ok&&current&&current==self->_musicPlayer&&self->_active&&!self->_paused)[current playImmediatelyAtRate:self->_rate];});}];
 }];
}
- (void)labels {
 _following.hidden=_compact||_cleanScreen||!douglass::isFollowing(_work.followStatus);_author.text=[@"@" stringByAppendingString:Text(_work.author)];_caption.text=Text(_work.caption);NSMutableArray *meta=[NSMutableArray array];if(_work.publishedAt>0){NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"yyyy-MM-dd HH:mm";[meta addObject:[f stringFromDate:[NSDate dateWithTimeIntervalSince1970:_work.publishedAt]]];}if(_work.location.empty()||(_work.locationKind!="ip"&&_work.locationKind!="IP属地"))[meta addObject:@"IP属地：未提供"];if(!_work.location.empty())[meta addObject:[NSString stringWithFormat:@"%@%@",(_work.locationKind=="ip"||_work.locationKind=="IP属地")?@"IP属地 ":@"作品发布地 ",Text(_work.location)]];_metadata.text=[meta componentsJoinedByString:@" · "];NSString *music=_work.musicTitle.empty()?@"作品原声":Text(_work.musicTitle),*by=_work.musicAuthor.empty()?Text(_work.author):Text(_work.musicAuthor);[_musicButton setTitle:[NSString stringWithFormat:@"♫ %@ · %@",music,by] forState:UIControlStateNormal];_likeCount.text=Text(douglass::compact(_work.likes));_commentCount.text=Text(douglass::compact(_work.comments));_collectCount.text=Text(douglass::compact(_work.collects));[_likeButton setImage:[UIImage systemImageNamed:_work.liked?@"heart.fill":@"heart" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];_likeButton.tintColor=_work.liked?[UIColor colorWithRed:1 green:.25 blue:.38 alpha:1]:UIColor.whiteColor;[_collectButton setImage:[UIImage systemImageNamed:_work.collected?@"star.fill":@"star" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];_collectButton.tintColor=_work.collected?[UIColor colorWithRed:1 green:.83 blue:.32 alpha:1]:UIColor.whiteColor;
}
- (void)attach:(DGPrepared*)prepared position:(double)position {
 [prepared bindPreparedItem];
 [prepared suspendWarm];[self detach];if(!prepared)return;_prepared=prepared;++prepared.leases;_player=prepared.player;_slider.userInteractionEnabled=!prepared.needsBeginning;_receivedFirstFrame=NO;_cover.hidden=NO;_playerLayer.player=_player;[self configurePiP];_observedItem=prepared.item;if(_active&&!_backgroundMode&&!_pagingMotion)[_ambient item:_observedItem imageView:nil];[_observedItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];_progressAt=CACurrentMediaTime();_firstFrameStarted=_progressAt;_progress=-1;__weak DGFeedCell *weak=self;
 if(DGDiagnosticEnabled())DGDiagnostic(@"playback.attach",[NSString stringWithFormat:@"active=%d during_swipe=%d preroll=%d source=%@ item_status=%ld prepared_age_ms=%.0f",_active,_pagingMotion,_prepared.warmed,_prepared.sourceKind,(long)_observedItem.status,(CACurrentMediaTime()-_prepared.createdAt)*1000]);
 NSNotificationCenter *notifications=NSNotificationCenter.defaultCenter;
 _stallToken=[notifications addObserverForName:AVPlayerItemPlaybackStalledNotification object:_observedItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *event){
  DGFeedCell *cell=weak;if(!cell||cell->_observedItem!=event.object||!cell->_active)return;
  DGSuspendPrerolls();DGCacheSetIdle(NO);
  DGDiagnostic(@"playback.stalled",[NSString stringWithFormat:@"position=%.2f source=%@ first_frame=%d empty=%d keepup=%d waiting=%@",[cell currentPlaybackPosition],cell->_prepared.sourceKind,cell->_receivedFirstFrame,cell->_observedItem.playbackBufferEmpty,cell->_observedItem.playbackLikelyToKeepUp,cell->_player.reasonForWaitingToPlay?:@"none"]);
 }];
 _accessToken=[notifications addObserverForName:AVPlayerItemNewAccessLogEntryNotification object:_observedItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *event){
  DGFeedCell *cell=weak;AVPlayerItem *item=event.object;if(!cell||cell->_observedItem!=item||!DGDiagnosticEnabled())return;
  AVPlayerItemAccessLogEvent *stats=item.accessLog.events.lastObject;if(!stats)return;
  DGDiagnostic(@"playback.access",[NSString stringWithFormat:@"startup_ms=%.0f stalls=%ld dropped=%ld observed_kbps=%.0f transferred_bytes=%lld transfer_s=%.2f requests=%ld",stats.startupTime*1000,(long)stats.numberOfStalls,(long)stats.numberOfDroppedVideoFrames,stats.observedBitrate/1000,stats.numberOfBytesTransferred,stats.transferDuration,(long)stats.numberOfMediaRequests]);
 }];
 _failureToken=[notifications addObserverForName:AVPlayerItemFailedToPlayToEndTimeNotification object:_observedItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *event){
  DGFeedCell *cell=weak;if(!cell||cell->_observedItem!=event.object||!DGDiagnosticEnabled())return;
  NSError *error=event.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
  DGDiagnostic(@"playback.failed",[NSString stringWithFormat:@"code=%ld",(long)error.code]);
 }];
 _loopToken=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:_observedItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *event){
  DGFeedCell *cell=weak;if(cell)[cell handlePlaybackEnd:event];
 }];
 __weak AVPlayer *clockPlayer=_player;
 _clock=[_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(.25,600) queue:dispatch_get_main_queue() usingBlock:^(CMTime time){
  DGFeedCell *cell=weak;AVPlayer *player=clockPlayer;if(cell&&player&&player==cell->_player)[cell tick:player.currentTime];
 }];
 if(position>.1&&!prepared.needsBeginning)[_player seekToTime:CMTimeMakeWithSeconds(position,600) toleranceBefore:CMTimeMakeWithSeconds(.2,600) toleranceAfter:CMTimeMakeWithSeconds(.2,600)];
 if(_active&&!_paused&&!_backgroundMode){[_player cancelPendingPrerolls];[self playCurrentVideo];[self queueWatchdogAfter:3];}
}
- (void)resetPlaybackForWork:(NSString *)identifier {
 if(_work.photo()||![identifier isEqualToString:Text(_work.id)])return;
 _prepared.needsBeginning=YES;_lastPlaybackTime=0;_progress=0;_progressAt=CACurrentMediaTime();
 if(_seeking||_dragging){
  ++_restartToken;++_previewGeneration;_seeking=NO;_dragging=NO;_previewBusy=NO;
  [_observedItem cancelPendingSeeks];[_generator cancelAllCGImageGeneration];_previewGlass.hidden=YES;
 }
 [_slider stopFollowing];_slider.userInteractionEnabled=!_prepared.needsBeginning;_slider.value=0;_elapsed.text=TimeLabel(0);
 [_emitted removeAllObjects];[_danmaku.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
}
- (void)handlePlaybackEnd:(NSNotification *)event {
 if(event.object!=_observedItem||!_active||_seeking||_prepared.needsBeginning)return;
 if(_dragging){
  NSUInteger request=++_restartToken;__weak DGFeedCell *weak=self;__weak AVPlayer *weakPlayer=_player;
  [_player seekToTime:kCMTimeZero completionHandler:^(BOOL finished){dispatch_async(dispatch_get_main_queue(),^{DGFeedCell *cell=weak;AVPlayer *player=weakPlayer;if(!cell||!player||player!=cell->_player||request!=cell->_restartToken||!finished)return;[cell->_emitted removeAllObjects];[cell->_danmaku.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];if(cell->_active&&!cell->_paused&&!cell->_pagingMotion)[player playImmediatelyAtRate:cell->_boosting?cell->_boostRate:cell->_rate];});}];return;
 }
 [self resetPlaybackForWork:Text(_work.id)];
 BOOL automatic=!_paused&&!_compact&&!_pagingMotion&&UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.autoScroll"];
 if(automatic&&self.advanceAction&&self.advanceAction())return;
 if(!_paused&&!_pagingMotion)[self playCurrentVideo];
}
- (void)playCurrentVideo {
 if(!_player||!_active||_paused||_dragging||_seeking)return;
 if(!_prepared.needsBeginning){[_player playImmediatelyAtRate:_boosting?_boostRate:_rate];return;}
 if(_observedItem.status!=AVPlayerItemStatusReadyToPlay)return;
 [_videoEffects resetFrames];
 _seeking=YES;[_player pause];NSUInteger request=++_restartToken;
 __weak DGFeedCell *weak=self;__weak AVPlayer *weakPlayer=_player;
 [_player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished){
  dispatch_async(dispatch_get_main_queue(),^{
   DGFeedCell *cell=weak;AVPlayer *player=weakPlayer;
   if(!cell||!player||player!=cell->_player||request!=cell->_restartToken)return;
   cell->_seeking=NO;
   if(!finished){if(cell->_active&&!cell->_paused&&!cell->_pagingMotion)[cell queueWatchdogAfter:1];return;}
   cell->_prepared.needsBeginning=NO;cell->_slider.userInteractionEnabled=YES;cell->_lastPlaybackTime=0;cell->_progressAt=CACurrentMediaTime();
   if(cell->_active&&!cell->_paused){[cell playCurrentVideo];[cell displayFirstFrame];[cell queueWatchdogAfter:3];}
  });
 }];
}
- (void)observeValueForKeyPath:(NSString*)key ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
 if(object==_playerLayer){__weak DGFeedCell *weak=self;dispatch_async(dispatch_get_main_queue(),^{[weak displayFirstFrame];});return;}
 __weak DGFeedCell *weak=self;__weak AVPlayerItem *observed=object;
 dispatch_async(dispatch_get_main_queue(),^{
  DGFeedCell *self=weak;AVPlayerItem *item=observed;
  if(!self||!item||item!=self->_observedItem||self->_backgroundMode)return;
  if(item.status==AVPlayerItemStatusReadyToPlay){[self applyVideoGravity];self->_message.text=@"";if(self->_active&&!self->_paused)[self playCurrentVideo];}
  else if(item.status==AVPlayerItemStatusFailed)[self recover];
 });
}

- (void)displayFirstFrame {
 if(!_player||_prepared.needsBeginning||_playerLayer.player!=_player||!_playerLayer.readyForDisplay)return;
 [self applyVideoGravity];
 if(_active&&!_receivedFirstFrame)[self setNeedsLayout];
 _cover.hidden=YES;if(_spinnerPending||_loadingSpinner.isAnimating)[self cancelLoadingIndicator];
 if(_active&&!_receivedFirstFrame){
  _receivedFirstFrame=YES;
  double seconds=CMTimeGetSeconds(_player.currentTime),ahead=0;for(NSValue *value in _observedItem.loadedTimeRanges){CMTimeRange range=value.CMTimeRangeValue;double start=CMTimeGetSeconds(range.start),end=CMTimeGetSeconds(CMTimeRangeGetEnd(range));if(std::isfinite(seconds)&&start<=seconds+.1&&end>seconds)ahead=MAX(ahead,end-seconds);}
  DGDiagnostic(@"playback.first_frame",[NSString stringWithFormat:@"ms=%.0f preroll=%d source=%@ buffered_s=%.2f",(CACurrentMediaTime()-_firstFrameStarted)*1000,_prepared.warmed,_prepared.sourceKind,ahead]);
 }
}
- (void)cancelLoadingIndicator {++_spinnerToken;_spinnerPending=NO;[_loadingSpinner stopAnimating];}
- (void)showLoadingIndicatorIfNeeded {
 if(_spinnerPending||_loadingSpinner.isAnimating)return;
 if(!_active||_paused||_backgroundMode||_appInactive||_pagingMotion||!_player||_playerLayer.readyForDisplay||_message.text.length)return;
 _spinnerPending=YES;NSUInteger token=++_spinnerToken;__weak DGFeedCell *weak=self;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,480*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
  DGFeedCell *self=weak;if(!self||token!=self->_spinnerToken)return;
  self->_spinnerPending=NO;
  if(self->_active&&!self->_paused&&!self->_backgroundMode&&!self->_pagingMotion&&self->_player&&!self->_playerLayer.readyForDisplay&&!self->_message.text.length)[self->_loadingSpinner startAnimating];
 });
}
- (void)stagePreparedVideo {
 if(_active||_player||_work.photo()||_work.play.empty()||_backgroundMode)return;
 DGPrepared *prepared=PreparedForWork(_work);
 if(!prepared||prepared.leases||prepared.retired||prepared.needsBeginning||!prepared.warmed)return;
 // Attach only a prepared source during the transition.
 [self attach:prepared position:0];
}
- (void)preparedVideoWarmed{if(self.window&&!_active&&!_backgroundMode&&!_appInactive)[self stagePreparedVideo];}
- (void)prepareVisibleVideo {
 if(_active||_player||_work.photo()||_work.isLive||_work.play.empty()||_appInactive||_backgroundMode)return;
 if(!PreparedForWork(_work))Obtain(_work);
}
- (void)recover {
 if(!NSThread.isMainThread){__weak DGFeedCell *weak=self;dispatch_async(dispatch_get_main_queue(),^{[weak recover];});return;}
 if(!_active||_paused||_work.photo()||_backgroundMode||_appInactive||_pagingMotion)return;
 if(_recoveries>=2){DGDiagnostic(@"playback.exhausted",nil);_watchdogExhausted=YES;[_loadingSpinner stopAnimating];[self stopWatchdog];_message.text=@"视频暂未加载成功，点击画面重试";return;}
 ++_recoveries;double pos=[self currentPlaybackPosition];if(!_prepared.needsBeginning&&pos<.05)pos=MAX(0,_lastPlaybackTime);
 NSString *url=Text(_work.play);
 AVAsset *asset=_player.currentItem.asset;BOOL local=[asset isKindOfClass:AVURLAsset.class]&&[((AVURLAsset *)asset).URL isFileURL];
 if(!local&&!_alternateUsed&&!_work.alternate.empty()&&_work.alternate!=_work.play){_alternateUsed=YES;url=Text(_work.alternate);}
 DGDiagnostic(@"playback.retry",[NSString stringWithFormat:@"attempt=%ld local=%d",(long)_recoveries,local]);
 DGPrepared *old=_prepared;DGPrepared *replacement=[[DGPrepared alloc]initWithURL:url];
 [self attach:replacement position:pos];
 // A failed pooled item must never be offered to the next cell or prewarmed again.
 if(old){for(NSString *key in Pool().allKeys)if(Pool()[key]==old)[Pool() removeObjectForKey:key];[old retire];}
 Pool()[PoolKey(_work)]=replacement;
}
- (void)stopWatchdog {++_watchdogToken;_watchdogScheduled=NO;}
- (void)queueWatchdogAfter:(NSTimeInterval)delay {
 if(_backgroundMode||_appInactive||_watchdogScheduled||_pagingMotion||!_active||_paused||_work.photo()||!_player||_watchdogExhausted)return;
 _watchdogScheduled=YES;NSUInteger token=++_watchdogToken,generation=_generation;__weak DGFeedCell *weak=self;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  DGFeedCell *s=weak;if(!s||token!=s->_watchdogToken||generation!=s->_generation)return;
  s->_watchdogScheduled=NO;
  if(s->_backgroundMode||s->_pagingMotion||!s->_active||s->_paused||s->_work.photo()||!s->_player)return;
  double now=CACurrentMediaTime();
  if(s->_prepared.needsBeginning){
   if(now-s->_progressAt>=5||s->_observedItem.status==AVPlayerItemStatusFailed)[s recover];
   else if(!s->_seeking)[s playCurrentVideo];
   [s queueWatchdogAfter:1];return;
  }
  double seconds=CMTimeGetSeconds(s->_player.currentTime),duration=CMTimeGetSeconds(s->_player.currentItem.duration);
  BOOL firstFrame=s->_playerLayer.readyForDisplay;
  if(firstFrame)s->_cover.hidden=YES;
  if(s->_dragging||s->_seeking){s->_progressAt=now;s->_firstFrameStarted=now;}
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
 [self syncDanmakuPlayback];
 if(!_player||_backgroundMode||_appInactive||_pagingMotion||_prepared.needsBeginning)return;double seconds=CMTimeGetSeconds(time),duration=CMTimeGetSeconds(_player.currentItem.duration);
 if(_active&&!_paused&&!_dragging&&!_seeking&&_player.rate>0&&DGRecoverAudioEnhancement(_observedItem))[self playCurrentVideo];
 if(_active&&!_paused&&!_dragging&&!_seeking)[_slider followPlayer:_player duration:duration];
 _elapsed.text=TimeLabel(seconds);_totalTime.text=TimeLabel(duration);[self displayFirstFrame];
 if(std::isfinite(seconds)&&seconds>=0)_lastPlaybackTime=seconds;
 if(_active&&!_paused&&!_seeking&&!_backgroundMode&&std::isfinite(seconds)){
  if(!_reportedView&&seconds>.12&&_playerLayer.readyForDisplay&&self.viewedAction){_reportedView=YES;self.viewedAction();}
  if(_reportedView&&self.checkpointAction)self.checkpointAction();

  if(std::fabs(seconds-_progress)>.08){_progress=seconds;_progressAt=CACurrentMediaTime();}
  [self updateDanmaku:seconds];
 }
}
- (double)currentPlaybackPosition {
    if(_prepared.needsBeginning)return 0;
    double seconds=_player?CMTimeGetSeconds(_player.currentTime):_lastPlaybackTime;
    return std::isfinite(seconds)&&seconds>0?seconds:0;
}
- (BOOL)isPlaybackPaused{return _paused;}
- (BOOL)isPlaybackActive{return _active;}
- (BOOL)keepsDisplayAwake{return douglass::keepGalleryAwake(UIApplication.sharedApplication.applicationState==UIApplicationStateActive,_active,_work.photo(),_backgroundMode||_appInactive);}
- (void)restorePlaybackPosition:(double)seconds paused:(BOOL)paused {
    _lastPlaybackTime=_prepared.needsBeginning?0:std::max(0.,seconds);_paused=paused;_pause.hidden=!paused;
    if(_work.duration>0)_slider.value=_lastPlaybackTime/_work.duration;
    if(_player&&_lastPlaybackTime>0.1)[_player seekToTime:CMTimeMakeWithSeconds(_lastPlaybackTime,600) toleranceBefore:CMTimeMakeWithSeconds(.1,600) toleranceAfter:CMTimeMakeWithSeconds(.1,600)];
}
- (BOOL)hasRenderedMedia {
 if(_work.photo())return _photoIndex>=0&&_photoIndex<(NSInteger)_images.count&&_images[_photoIndex].image!=nil;
 return !_prepared.needsBeginning&&_playerLayer.player&&_playerLayer.readyForDisplay;
}
- (void)pagingInMotion:(BOOL)inMotion {
 if(_pagingMotion==inMotion)return;_pagingMotion=inMotion;
 if(inMotion){[_videoEffects suspendForPaging];DGSetMetalFXPlaybackActive(_observedItem,NO);DGReleaseVideoFrameCache(_observedItem);[self cancelLoadingIndicator];[_slider stopFollowing];[self stopWatchdog];[_ambient active:NO];}
 [self syncDanmakuPlayback];
}
- (void)active:(BOOL)value {
 if(!NSThread.isMainThread){__weak DGFeedCell *weak=self;dispatch_async(dispatch_get_main_queue(),^{[weak active:value];});return;}
 BOOL changed=_active!=value;_active=value;DGUpdateGalleryWake();if(value&&!_backgroundMode){if(!_work.photo()&&!_player&&!_work.id.empty())[self attach:Obtain(_work) position:_lastPlaybackTime];else if(_work.photo()&&!_musicPlayer)[self attachPhotoSound:_lastPlaybackTime];}if(value&&!_paused)[self showLoadingIndicatorIfNeeded];else [self cancelLoadingIndicator];if(!value||_backgroundMode||_pagingMotion)[_ambient item:nil imageView:nil];else if(!_work.photo())[_ambient item:_observedItem imageView:nil];[_ambient active:value&&!_paused&&!_backgroundMode&&!_pagingMotion];if((changed||_foregroundRebind)&&_work.photo()&&value&&!_backgroundMode)[self loadPhotos];if(_work.photo()&&value&&!_backgroundMode)[_ambient item:nil imageView:_images.count?_images[MIN((NSUInteger)MAX(0,_photoIndex),_images.count-1)]:_cover];[self syncDanmakuPlayback];if(![_musicAvatar.layer animationForKey:@"album-spin"]){CABasicAnimation *spin=[CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];spin.fromValue=@0;spin.toValue=@(M_PI*2);spin.duration=9;spin.repeatCount=HUGE_VALF;[_musicAvatar.layer addAnimation:spin forKey:@"album-spin"];}DGFreezeLayer(_musicAvatar.layer,!value||_paused||_backgroundMode);
 if(value&&!_paused){
  if(_backgroundMode)return;
  if(_work.photo()&&!_pagingMotion&&!_reportedView&&self.viewedAction){_reportedView=YES;self.viewedAction();}
  if(changed||_foregroundRebind){_foregroundRebind=NO;if(_prepared.warming)[_player cancelPendingPrerolls];_progressAt=CACurrentMediaTime();_firstFrameStarted=_progressAt;}
  if(!_dragging&&!_seeking&&(_player.rate==0||changed||_prepared.needsBeginning))[self playCurrentVideo];
  if(_musicPlayer.rate==0||changed)[_musicPlayer playImmediatelyAtRate:_rate];
  [self displayFirstFrame];if(!_pagingMotion){[self syncVideoEffects];[self queueWatchdogAfter:3];}
 }else{
  [_videoEffects stop];
  DGSetMetalFXPlaybackActive(_observedItem,NO);
  [_slider stopFollowing];[self stopWatchdog];[_player pause];[_musicPlayer pause];
  if(!value){[_photoNavigator cancelBrowsing];[self unlock];_boosting=NO;_speedGlass.hidden=YES;}
 }

}
- (void)toggle {if(self.dismissCommentsAction){self.dismissCommentsAction();return;}if(DGMusicPlayer()){DGMusicStop();_paused=NO;[self active:YES];return;}if(_observedItem.status==AVPlayerItemStatusFailed||_watchdogExhausted){_recoveries=0;_watchdogExhausted=NO;[self recover];return;}_paused=!_paused;_pause.hidden=!_paused;if(!_paused){_progressAt=CACurrentMediaTime();_firstFrameStarted=_progressAt;}[self active:_active];}
- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gesture shouldReceiveTouch:(UITouch*)touch {
 if(gesture==_commentCloseTap)return self.dismissCommentsAction!=nil;
 if(self.dismissCommentsAction&&[gesture isKindOfClass:UITapGestureRecognizer.class])return NO;
 if([gesture isKindOfClass:UILongPressGestureRecognizer.class]&&[touch locationInView:self.contentView].x<24&&self.presenter.navigationController)return NO;
 if(gesture==_danmakuTap){_tappedDanmaku=[(DGDanmakuOverlay *)_danmaku textAtPoint:[touch locationInView:_danmaku]];return _tappedDanmaku.length>0;}BOOL hold=[gesture isKindOfClass:UILongPressGestureRecognizer.class],shield=[gesture isKindOfClass:UIPanGestureRecognizer.class];if(hold){for(UIView *view=touch.view;view&&view!=self.contentView;view=view.superview)if(view==_caption||view==_author||view==_musicButton||view==_musicAvatar||view==_slider||view==_photoNavigator)return NO;return YES;}if(shield)return YES;
 for(UIView *view=touch.view;view&&view!=self.contentView;view=view.superview)if([view isKindOfClass:UIControl.class]||view==_caption||view==_author||view==_musicAvatar||view==_rail||view==_moreGlass||view==_danmaku)return NO;return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer*)first shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)second{return ([first isKindOfClass:UILongPressGestureRecognizer.class]&&(second==_railShield||second==_moreShield))||([second isKindOfClass:UILongPressGestureRecognizer.class]&&(first==_railShield||first==_moreShield));}
- (void)absorbRail:(UIPanGestureRecognizer*)gesture{}
- (void)closeCommentsFromVideo{if(self.dismissCommentsAction)self.dismissCommentsAction();}
- (void)syncVideoEffects {
 if(!_active||_paused||_backgroundMode||_appInactive||_pagingMotion||_work.photo()||_work.isLive||!_player.currentItem){
  DGSetMetalFXPlaybackActive(_observedItem,NO);
  [_videoEffects stop];return;
 }
 DGSetMetalFXPlaybackActive(_observedItem,YES);
 NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
 if(!_videoEffects&&(DGRifeRequested()||[prefs boolForKey:@"douglass.experimental.frameInterpolation"]||
                     [prefs boolForKey:@"douglass.experimental.vtSuperResolution"]))_videoEffects=[DGVideoEffects new];
 [_videoEffects showForPlayerLayer:_playerLayer];
}
- (void)pictureEnhancementChanged{if(_player.currentItem)DGConfigureMediaEnhancement(_player.currentItem);if(_work.photo())[self loadPhotos];[self syncVideoEffects];}
- (void)videoEffectsChanged{[self syncVideoEffects];}
- (void)audioEnhancementChanged{DGUpdateAudioControls();}


- (void)lock {[_locked removeAllObjects];for(UIView *v=self.superview;v;v=v.superview)if([v isKindOfClass:UIScrollView.class]&&((UIScrollView*)v).scrollEnabled){[_locked addObject:(UIScrollView*)v];((UIScrollView*)v).scrollEnabled=NO;}}
- (void)unlock {for(UIScrollView *v in _locked)v.scrollEnabled=YES;[_locked removeAllObjects];}
- (void)hold:(UILongPressGestureRecognizer*)g {
 if(_cleanScreen)return;
 CGPoint point=[g locationInView:self.contentView];BOOL edge=point.x<56||point.x>self.contentView.bounds.size.width-80;
 if(g.state==UIGestureRecognizerStateBegan){
  if(edge&&!_work.photo()&&_player){
   BOOL wasPaused=_paused;_boosting=YES;_boostRate=1.5;_holdY=point.y;_paused=NO;_pause.hidden=YES;
   if(wasPaused){_progressAt=CACurrentMediaTime();_firstFrameStarted=_progressAt;}
   if(DGMusicPlayer())DGMusicStop();
   [[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleMedium]impactOccurred];[self lock];_speedGlass.hidden=NO;_speedText.text=@"1.5× · 上滑换档，松手恢复";_player.currentItem.preferredForwardBufferDuration=8;
   [self active:_active];if(_active&&!_prepared.needsBeginning&&!_seeking&&!_dragging&&fabs(_player.rate-_boostRate)>.01)_player.rate=_boostRate;
  }else if(self.actionMenuAction)self.actionMenuAction(point);
 }
 else if(g.state==UIGestureRecognizerStateChanged&&_boosting){double upward=MAX(0.,_holdY-point.y),speed=douglass::holdRate(upward,DGHoldSpeed());if(fabs(speed-_boostRate)>.01){_boostRate=speed;DGHaptic();_speedText.text=[NSString stringWithFormat:@"%.1f× · 上滑换档，松手恢复",speed];if(_active&&!_paused&&!_prepared.needsBeginning&&!_seeking)_player.rate=speed;}}
 else if(g.state==UIGestureRecognizerStateEnded||g.state==UIGestureRecognizerStateCancelled||g.state==UIGestureRecognizerStateFailed){[self unlock];_boosting=NO;_speedGlass.hidden=YES;_player.currentItem.preferredForwardBufferDuration=4;if(_active&&!_paused&&!_prepared.needsBeginning)_player.rate=_rate;}
 [self syncDanmakuPlayback];
}
- (void)expandCaption{CGFloat width=MAX(80,MIN(self.contentView.bounds.size.width-103,680));CGFloat full=[Text(_work.caption)boundingRectWithSize:CGSizeMake(width,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:_caption.font} context:nil].size.height;if(!_captionExpanded&&full>self.contentView.bounds.size.height*.45){DGShowFullCaption(self.presenter,Text(_work.caption));return;}_captionExpanded=!_captionExpanded;[self setNeedsLayout];DGAnimate(.2,^{[self layoutIfNeeded];},nil);}
- (void)copyCaption:(UILongPressGestureRecognizer*)g {if(g.state==UIGestureRecognizerStateBegan&&!_work.caption.empty())DGConfirmCopy(self.presenter,Text(_work.caption));}
- (void)saveCurrentFrame{
 UIViewController *host=self.presenter;if(!host)return;DGDiagnostic(@"frame.export.begin",[NSString stringWithFormat:@"photo=%d active=%d attached=%d",_work.photo(),_active,_player.currentItem!=nil]);
 if(_work.photo()){UIImage *image=_photoIndex>=0&&_photoIndex<(NSInteger)_images.count?_images[_photoIndex].image:nil;if(image)DGSaveImage(host,image);else DGSaveURL(host,[self selectedImageURL],NO);return;}
 if(_frameExport){DGToast(host,@"正在保存此帧，请稍候");return;}
 if(!_player.currentItem||!_playerLayer.readyForDisplay){DGToast(host,@"视频画面尚未就绪");return;}
 CMTime time=_player.currentTime;if(!CMTIME_IS_NUMERIC(time)){DGToast(host,@"暂时无法读取当前画面");return;}
 DGHaptic();DGToast(host,@"正在保存此帧画面…");_frameExport=[[AVAssetImageGenerator alloc]initWithAsset:_player.currentItem.asset];_frameExport.appliesPreferredTrackTransform=YES;_frameExport.maximumSize=CGSizeMake(2160,2160);_frameExport.requestedTimeToleranceBefore=kCMTimeZero;_frameExport.requestedTimeToleranceAfter=kCMTimeZero;
 __weak DGFeedCell *weak=self;__weak UIViewController *owner=host;__weak AVAssetImageGenerator *request=_frameExport;
 [_frameExport generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:time]] completionHandler:^(CMTime requested,CGImageRef frame,CMTime actual,AVAssetImageGeneratorResult result,NSError *error){UIImage *image=frame?[UIImage imageWithCGImage:frame]:nil;dispatch_async(dispatch_get_main_queue(),^{DGFeedCell *cell=weak;if(!cell||cell->_frameExport!=request)return;cell->_frameExport=nil;if(image)DGSaveImage(owner,image);else DGToast(owner,@"此帧暂时无法保存，请稍后重试");});}];
}
- (void)saveMusic:(UILongPressGestureRecognizer*)g {if(g.state!=UIGestureRecognizerStateBegan)return;if(_work.music.empty()){DGToast(self.presenter,@"这条作品没有可保存的原声地址");return;}DGSaveAudio(self.presenter,Text(_work.music),_work.musicTitle.empty()?@"作品原声":Text(_work.musicTitle));}
- (void)download:(CGPoint)p {UIViewController *host=self.presenter;if(!host||host.presentedViewController)return;UIAlertController *menu=[UIAlertController alertControllerWithTitle:_work.photo()?@"保存图集":@"保存视频" message:nil preferredStyle:UIAlertControllerStyleActionSheet];if(_work.photo()){NSString *url=Text(_work.images[MIN((std::size_t)MAX(0,_photoIndex),_work.images.size()-1)]);[menu addAction:[UIAlertAction actionWithTitle:@"保存当前图片" style:UIAlertActionStyleDefault handler:^(UIAlertAction*a){DGSaveURL(host,url,NO);}]];NSMutableArray *urls=[NSMutableArray array];for(const auto &u:_work.images)[urls addObject:Text(u)];if(urls.count>1)[menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"保存全部 %lu 张图片",(unsigned long)urls.count] style:UIAlertActionStyleDefault handler:^(UIAlertAction*a){for(NSString *url in urls)DGSaveURL(host,url,NO);}]];}else{NSString *url=Text(_work.play);[menu addAction:[UIAlertAction actionWithTitle:@"保存视频到相册" style:UIAlertActionStyleDefault handler:^(UIAlertAction*a){DGSaveURL(host,url,YES);}]];}[menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];menu.popoverPresentationController.sourceView=self.contentView;menu.popoverPresentationController.sourceRect=CGRectMake(p.x,p.y,1,1);[host presentViewController:menu animated:YES completion:nil];}
- (NSString *)selectedImageURL{return _work.images.empty()?@"":Text(_work.images[MIN((std::size_t)MAX(0,_photoIndex),_work.images.size()-1)]);}
- (void)comments {if(self.commentsAction)self.commentsAction();}
- (void)profile {if(self.profileAction)self.profileAction();}
- (void)music {if(self.musicAction)self.musicAction();}
- (void)fill {DGHaptic();BOOL enabled=!DGBackgroundAudioEnabled();[NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"douglass.backgroundAudio"];[NSNotificationCenter.defaultCenter postNotificationName:@"DouGlassSettingsChanged" object:nil];DGToast(self.presenter,enabled?@"已开启后台音频播放":@"已关闭后台音频播放");}
- (void)more {if(self.moreAction)self.moreAction();else[self download:CGPointMake(self.contentView.bounds.size.width-40,self.contentView.bounds.size.height-140)];}
- (void)like {[self write:@"digg" add:!_work.liked];}
- (void)collect {[self write:@"favorite" add:!_work.collected];}
- (void)doubleLike:(UITapGestureRecognizer*)g {
 if(_cleanScreen)return;
 if(_cleanScreen)return;CGPoint point=[g locationInView:self.contentView];CGFloat angle=(arc4random_uniform(2)?1:-1)*(.16+arc4random_uniform(25)/100.);UIImageView *heart=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"heart.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:106 weight:UIImageSymbolWeightBold]]];heart.tintColor=[UIColor colorWithRed:1 green:.16 blue:.34 alpha:1];heart.bounds=CGRectMake(0,0,116,116);heart.center=point;heart.userInteractionEnabled=NO;heart.layer.shadowColor=UIColor.blackColor.CGColor;heart.layer.shadowOpacity=.15;heart.layer.shadowRadius=8;heart.transform=CGAffineTransformConcat(CGAffineTransformMakeRotation(angle),CGAffineTransformMakeScale(.25,.25));heart.alpha=0;[self.contentView addSubview:heart];
 DGAnimate(.22,^{heart.alpha=1;heart.transform=CGAffineTransformMakeRotation(angle);},^(BOOL done){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(DGDuration(.15)*NSEC_PER_SEC)),dispatch_get_main_queue(),^{DGAnimate(.42,^{heart.alpha=0;heart.center=CGPointMake(point.x,point.y-75);heart.transform=CGAffineTransformConcat(CGAffineTransformMakeRotation(angle*.6),CGAffineTransformMakeScale(1.4,1.4));},^(BOOL done){[heart removeFromSuperview];});});});
 if(!_work.liked)[self write:@"digg" add:YES];else [[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight]impactOccurred];
}
- (void)interactionChanged:(NSNotification *)note {
 NSDictionary *state=note.userInfo;if(String(state[@"id"])!=_work.id)return;_work.liked=[state[@"liked"]boolValue];_work.collected=[state[@"collected"]boolValue];_work.likes=Number(state[@"likes"]);_work.collects=Number(state[@"collects"]);[self labels];_likeButton.alpha=[state[@"pendingLike"]boolValue]?.75:1;_collectButton.alpha=[state[@"pendingCollect"]boolValue]?.75:1;
}
- (void)write:(NSString*)operation add:(BOOL)add {
 if(!self.bridge)return;DGOptimisticAction(self.bridge,self.presenter,@{@"id":Text(_work.id),@"liked":@(_work.liked),@"collected":@(_work.collected),@"likes":@(_work.likes),@"collects":@(_work.collects)},operation,add);
 UIButton *button=[operation isEqualToString:@"digg"]?_likeButton:_collectButton;[UIView animateWithDuration:.1 animations:^{button.transform=CGAffineTransformMakeScale(1.2,1.2);} completion:^(BOOL done){[UIView animateWithDuration:.18 animations:^{button.transform=CGAffineTransformIdentity;}];}];
}
- (void)refreshPhotoBrowse{
 UIImage *ready=_photoIndex>=0&&_photoIndex<(NSInteger)_images.count?_images[_photoIndex].image:nil;
 _photoBrowse.image=ready?:[_photoNavigator selectedThumbnail];
}
- (void)loadPhotos {if(_photos.bounds.size.width<=0||!_images.count)return;NSInteger page=MAX(0,MIN((NSInteger)_images.count-1,(NSInteger)llround(_photos.contentOffset.x/_photos.bounds.size.width)));_photoIndex=page;for(NSUInteger i=0;i<_images.count;i++)if(labs((long)i-page)>1)[_images[i]remote:@""];[_photoNavigator page:page];if(_active&&!_backgroundMode)[_ambient item:nil imageView:_images[page]];for(NSInteger i=MAX(0,page-1);i<=MIN((NSInteger)_images.count-1,page+1);++i)[_images[i] remote:Text(_work.images[i])];_photoCount.text=[NSString stringWithFormat:@"图文 %ld/%lu",(long)page+1,(unsigned long)_images.count];}
- (void)scrollViewDidScroll:(UIScrollView *)scroll {if(scroll==_photos)[self loadPhotos];}
- (void)scrollViewWillEndDragging:(UIScrollView *)scroll withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)target {
 if(scroll!=_photos||!target||!_images.count||scroll.bounds.size.width<=0)return;
 CGFloat width=scroll.bounds.size.width;
 NSInteger index=std::clamp((NSInteger)llround(target->x/width),(NSInteger)0,(NSInteger)_images.count-1);
 *target=CGPointMake(index*width,0);
}
- (void)settlePhotoPage {
 if(!_work.photo()||!_images.count||_photos.bounds.size.width<=0)return;
 CGFloat width=_photos.bounds.size.width;
 NSInteger index=std::clamp((NSInteger)llround(_photos.contentOffset.x/width),(NSInteger)0,(NSInteger)_images.count-1);
 [_photos setContentOffset:CGPointMake(index*width,0) animated:NO];
 [self loadPhotos];
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scroll {if(scroll==_photos)[self settlePhotoPage];}
- (void)scrollViewDidEndDragging:(UIScrollView *)scroll willDecelerate:(BOOL)decelerate {if(scroll==_photos&&!decelerate)[self settlePhotoPage];}
- (void)cacheFrame:(UIImage *)frame key:(NSNumber *)key{if(!frame)return;[_frameCache setObject:frame forKey:key cost:CGImageGetBytesPerRow(frame.CGImage)*CGImageGetHeight(frame.CGImage)];[_cachedTimes removeObject:key];[_cachedTimes addObject:key];while(_cachedTimes.count>48)[_cachedTimes removeObjectAtIndex:0];}
- (UIImage *)closestFrame:(double)seconds{UIImage *frame=nil;double distance=1.01;for(NSNumber *key in _cachedTimes){double delta=fabs(key.doubleValue/2-seconds);if(delta<distance){UIImage *candidate=[_frameCache objectForKey:key];if(candidate){distance=delta;frame=candidate;}}}return frame;}
- (void)seekStart {
 if(!_player||_seeking||_prepared.needsBeginning)return;
 ++_restartToken;++_previewGeneration;[_generator cancelAllCGImageGeneration];_dragging=YES;_previewImage.image=nil;_previewGlass.hidden=YES;_previewBusy=NO;
}
- (void)preparePreview {
 if(!_generator&&_player.currentItem.asset){_generator=[[AVAssetImageGenerator alloc]initWithAsset:_player.currentItem.asset];_generator.appliesPreferredTrackTransform=YES;_generator.maximumSize=CGSizeMake(360,480);_generator.requestedTimeToleranceBefore=CMTimeMakeWithSeconds(.12,600);_generator.requestedTimeToleranceAfter=CMTimeMakeWithSeconds(.12,600);}
}
- (void)seekChange {
 if(!_dragging||_compact||!((DGTimeline *)_slider).scrubbing)return;_previewGlass.hidden=NO;double duration=CMTimeGetSeconds(_player.currentItem.duration);if(!std::isfinite(duration)||duration<=0)duration=_work.duration;if(duration<=0)return;_desiredPreview=_slider.value*duration;_previewTime.text=[NSString stringWithFormat:@"%@ / %@",TimeLabel(_desiredPreview),TimeLabel(duration)];NSNumber *key=@(llround(_desiredPreview*2));UIImage *cached=[_frameCache objectForKey:key];if(cached){_previewImage.image=cached;_previewTime.text=[NSString stringWithFormat:@"%@ / %@",TimeLabel(_desiredPreview),TimeLabel(duration)];}else if([self closestFrame:_desiredPreview])_previewImage.image=[self closestFrame:_desiredPreview];else if(!_previewImage.image)_previewTime.text=[NSString stringWithFormat:@"%@ · 正在取帧",TimeLabel(_desiredPreview)];[self setNeedsLayout];[self requestPreview];
}
- (void)requestPreview {
 if(!_dragging||_previewBusy||!_player.currentItem)return;
 [self preparePreview];if(!_generator)return;_previewBusy=YES;double wanted=_desiredPreview;
 NSUInteger generation=_generation,request=_previewGeneration;__weak DGFeedCell *weak=self;
 // The thumbnail decoder is independent from the player shown on screen.
 [_generator generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:CMTimeMakeWithSeconds(wanted,600)]] completionHandler:^(CMTime requested,CGImageRef image,CMTime actual,AVAssetImageGeneratorResult result,NSError *error){
  UIImage *frame=image?[UIImage imageWithCGImage:image]:nil;
  dispatch_async(dispatch_get_main_queue(),^{DGFeedCell *cell=weak;if(!cell||generation!=cell->_generation||request!=cell->_previewGeneration)return;
   cell->_previewBusy=NO;[cell cacheFrame:frame key:@(llround(wanted*2))];
   if(!cell->_dragging)return;
   if(frame&&fabs(cell->_desiredPreview-wanted)<.3)cell->_previewImage.image=frame;
   if(fabs(cell->_desiredPreview-wanted)>.04)[cell requestPreview];
   else if(!frame&&!cell->_previewImage.image)cell->_previewTime.text=[NSString stringWithFormat:@"%@ · 暂未取得缩略图",TimeLabel(wanted)];
  });
 }];
}
- (void)finishScrubAt:(double)seconds {
 _dragging=NO;_previewGlass.hidden=YES;++_previewGeneration;_previewBusy=NO;[_generator cancelAllCGImageGeneration];
 _progressAt=CACurrentMediaTime();
 if(!_player||!std::isfinite(seconds)){_seeking=NO;[self playCurrentVideo];return;}
 [_videoEffects resetFrames];
 _seeking=YES;NSUInteger request=++_restartToken;
 __weak DGFeedCell *weak=self;__weak AVPlayer *weakPlayer=_player;
 [_player seekToTime:CMTimeMakeWithSeconds(seconds,600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished){
  dispatch_async(dispatch_get_main_queue(),^{DGFeedCell *cell=weak;AVPlayer *player=weakPlayer;
   if(!cell||!player||player!=cell->_player||request!=cell->_restartToken)return;
   cell->_seeking=NO;cell->_progressAt=CACurrentMediaTime();[cell playCurrentVideo];
  });
 }];
}
- (void)seekCancel{
 if(!_dragging)return;
 _dragging=NO;_seeking=NO;_previewGlass.hidden=YES;++_previewGeneration;_previewBusy=NO;[_generator cancelAllCGImageGeneration];
 double duration=CMTimeGetSeconds(_player.currentItem.duration),position=CMTimeGetSeconds(_player.currentTime);if(std::isfinite(duration)&&duration>0&&std::isfinite(position))_slider.value=position/duration;
 _progressAt=CACurrentMediaTime();[self playCurrentVideo];
}
- (void)seekEnd {
 if(!_dragging)return;
 double duration=CMTimeGetSeconds(_player.currentItem.duration);if(!std::isfinite(duration)||duration<=0)duration=_work.duration;
 [_emitted removeAllObjects];[_danmaku.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
 [self finishScrubAt:std::isfinite(duration)&&duration>0?_slider.value*duration:NAN];
}
- (void)settingsChanged {_fill=[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.fillPortrait"];[self applyVideoGravity];[self configurePiP];[self setNeedsLayout];[self emojiReady];_rate=1;BOOL state=DGBackgroundAudioEnabled();if(_backgroundSoundState!=state){_backgroundSoundState=state;[UIView transitionWithView:_fillButton duration:.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{[self->_fillButton setImage:[UIImage systemImageNamed:state?@"headphones.circle.fill":@"headphones"] forState:UIControlStateNormal];} completion:nil];[UIView animateWithDuration:.12 animations:^{self->_fillButton.transform=CGAffineTransformMakeScale(1.15,1.15);} completion:^(BOOL done){[UIView animateWithDuration:.18 animations:^{self->_fillButton.transform=CGAffineTransformIdentity;}];}];}else [_fillButton setImage:[UIImage systemImageNamed:state?@"headphones.circle.fill":@"headphones"] forState:UIControlStateNormal];id enabled=[NSUserDefaults.standardUserDefaults objectForKey:@"douglass.danmaku"];_danmaku.hidden=_cleanScreen||(enabled&&![enabled boolValue]);if(_danmaku.hidden)[_danmaku.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];if(_active&&!_paused&&!_boosting){if(fabs(_player.rate-_rate)>.01&&_player.rate>0)_player.rate=_rate;if(fabs(_musicPlayer.rate-_rate)>.01&&_musicPlayer.rate>0)_musicPlayer.rate=_rate;}}
- (void)copyDanmaku:(UITapGestureRecognizer *)gesture{if(gesture.state!=UIGestureRecognizerStateRecognized)return;NSString *text=_tappedDanmaku;_tappedDanmaku=nil;if(text.length)DGConfirmTextCopy(self.presenter,text,@"复制这条弹幕？",@"弹幕已复制");}
- (void)emojiReady{for(DGDanmakuLabel *label in _danmaku.subviews){DGRenderDanmaku(label,label.plain,label.emoticons);[label refreshAppearance];}[self syncDanmakuPlayback];}
- (void)syncDanmakuPlayback{
 double speed=_active&&!_paused&&!_backgroundMode&&!_appInactive&&!_seeking&&_player.timeControlStatus==AVPlayerTimeControlStatusPlaying?MAX(0.,_player.rate):0;
 DGSetLayerPlaybackRate(_danmaku.layer,speed);
 [_danmaku adaptive:[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.danmaku.adaptive"] playing:speed>0];
}
- (void)updateDanmaku:(double)seconds {
 if(_danmaku.hidden||_work.photo()||!self.bridge)return;NSInteger window=(NSInteger)seconds/30;
 if(window!=_danmakuWindow&&!_danmakuLoading){_danmakuLoading=YES;NSUInteger generation=_generation;__weak DGFeedCell *weak=self;[self.bridge request:@"danmaku" parameters:@{@"id":Text(_work.id),@"from":@(window*30000),@"to":@((window+1)*30000),@"duration":@(MAX(30000.,_work.duration*1000))} completion:^(NSDictionary *result,NSString *error){DGFeedCell *self=weak;if(!self||generation!=self->_generation)return;self->_danmakuLoading=NO;self->_danmakuWindow=window;self->_danmakuItems=error?@[]:Array(result[@"items"]);[self->_emitted removeAllObjects];}];}
 if(window!=_danmakuWindow)return;double font=[NSUserDefaults.standardUserDefaults doubleForKey:@"douglass.danmaku.size"];if(font<12||font>28)font=14;NSInteger lanes=MAX(1,(NSInteger)(_danmaku.bounds.size.height/(font+12)));CGFloat area=_danmaku.bounds.size.width;CFTimeInterval now=[_danmaku.layer convertTime:CACurrentMediaTime() fromLayer:nil];NSUInteger index=0;
 for(NSDictionary *row in _danmakuItems){double offset=[row[@"offset"]doubleValue];NSString *rowID=Text(String(row[@"id"]));NSString *key=rowID.length?[@"id:" stringByAppendingString:rowID]:[NSString stringWithFormat:@"%ld:%lu",(long)window,(unsigned long)index];++index;if(offset>seconds+.2||offset<seconds-1.2||[_emitted containsObject:key])continue;
  NSInteger lane=-1;for(NSInteger step=0;step<lanes;step++){NSInteger candidate=(_lane+step)%lanes;BOOL free=YES;for(DGDanmakuLabel *label in _danmaku.subviews){if(label.tag!=candidate)continue;CALayer *presentation=label.layer.presentationLayer;CGRect frame=presentation?presentation.frame:label.frame;if(now-label.born<.15||CGRectGetMaxX(frame)>area-36){free=NO;break;}}if(free){lane=candidate;break;}}
  if(lane<0)continue;_lane=(lane+1)%lanes;NSString *text=[row[@"text"]isKindOfClass:NSString.class]?row[@"text"]:@"";[_emitted addObject:key];if(!text.length)continue;
  DGDanmakuLabel *label=[DGDanmakuLabel new];label.font=[UIFont systemFontOfSize:font weight:UIFontWeightSemibold];label.textColor=UIColor.whiteColor;label.plain=text;label.emoticons=Array(row[@"emoticons"]);DGRenderDanmaku(label,text,label.emoticons);label.tag=lane;label.born=now;[label sizeToFit];CGFloat width=MIN(900,label.bounds.size.width);label.frame=CGRectMake(area,lane*(font+12),width,font+8);[_danmaku addSubview:label];CGFloat speed=MAX(58,area/5.5);
  [UIView animateWithDuration:(area+width)/speed delay:0 options:UIViewAnimationOptionCurveLinear|UIViewAnimationOptionAllowUserInteraction animations:^{label.frame=CGRectOffset(label.frame,-area-width,0);} completion:^(BOOL done){[label removeFromSuperview];}];
 }
}
- (void)dealloc {_active=NO;DGUpdateGalleryWake();[_playerLayer removeObserver:self forKeyPath:@"readyForDisplay"];[NSNotificationCenter.defaultCenter removeObserver:self];[self unlock];[self detach];}
@end
CGFloat DGFeedNotificationTop(UIViewController *host){
 CGFloat top=0;for(DGFeedCell *cell in MediaCells().allObjects)if(cell.presenter==host)top=MAX(top,[cell notificationTopInView:host.view]);return top;
}


void DGSaveCurrentFrame(UIViewController *host){for(DGFeedCell *cell in MediaCells().allObjects)if((cell.presenter==host||cell.presenter.navigationController==host)&&cell.window&&[cell isPlaybackActive]){[cell saveCurrentFrame];return;}DGToast(host,@"没有正在显示的作品画面");}
