#import "DGCommon.h"
#import "DGMedia.h"
#import "DGFeedCache.h"
#import "DGDiagnostics.h"
#import "DGPlaybackResume.h"
#import "DGComments.h"
#import "DGAnimation.h"
#import "DGNavigationResume.h"
#import "DGWorkDetails.h"
#import "DGMusicIndex.h"
#include "ChannelState.hpp"
static NSDictionary *DGWithRelationship(NSDictionary *record,const std::string &sec,const std::string &uid,long long status){
 if(!douglass::matchesAuthor(String(record[@"authorID"]),String(record[@"authorUID"]),sec,uid))return record;
 NSMutableDictionary *updated=[record mutableCopy];updated[@"authorFollowStatus"]=@(status);updated[@"authorFollowStatusKnown"]=@YES;return updated;
}
@interface DGSwipeClock:NSObject
@property(nonatomic,copy) void (^sample)(CADisplayLink *);
- (void)tick:(CADisplayLink *)link;
@end
@implementation DGSwipeClock
- (void)tick:(CADisplayLink *)link{if(self.sample)self.sample(link);else [link invalidate];}
@end
@interface DGFeed : UIViewController <UICollectionViewDataSource,UICollectionViewDelegateFlowLayout,UIGestureRecognizerDelegate,DGPageResume>
- (instancetype)initWithRecords:(NSArray *)records selected:(NSInteger)selected bridge:(DGBridge *)bridge;
- (void)prepareNoticeFocus:(NSString *)comment parent:(NSString *)parent;
- (void)prepareResumeState:(NSDictionary *)state;
- (NSString *)currentWorkIdentifier;
@end
@implementation DGFeed {
    douglass::Feed _feed;
    NSMutableArray *_records;
    DGBridge *_bridge;
    UICollectionView *_collection;
    UIVisualEffectView *_bar;UISegmentedControl *_navigationTabs;NSMutableSet *_locationRequested;
    UIButton *_settings,*_recommend,*_follow,*_search,*_messages,*_account,*_back;
    DGImage *_accountImage;UIActivityIndicatorView *_accountSpinner;
    UILabel *_state,*_subtitle;
    UIStackView *_empty;
    UIButton *_retry,*_login;
    UIActivityIndicatorView *_spinner,*_recommendRefreshSpinner;
    UIVisualEffectView *_recommendRefreshGlass;
    UIRefreshControl *_pull;
    DGComments *_comments,*_retainedComments;NSString *_retainedCommentWorkID;
    UIView *_commentHost;CGFloat _commentDragOffset;
    UIVisualEffectView *_cleanKnob;UIButton *_cleanKnobButton;BOOL _cleanScreen;UIViewController *_messageChannel;BOOL _showingMessages;UIVisualEffectView *_messageRefreshGlass;
    NSDictionary *_profile;NSString *_messageScope;
    BOOL _profileLoading;NSUInteger _accountGeneration,_profileFailures;CFTimeInterval _profileCheckedAt;
    NSString *_operation,*_cursor;
    BOOL _loading,_foreground,_inactive,_failed,_ownsBridge,_staticFeed,_positioned,_relayout,_visible,_commentTransition,_closingComments;
    NSInteger _refreshIndex,_emptyPages,_selected,_current;
    NSUInteger _generation,_warmGeneration,_feedRequest,_refreshFeedback;
    BOOL _pagingMotion,_cachedBootstrap,_manualRecommendationRefresh;
    NSHashTable<DGFeedCell *> *_departingCells;
    CADisplayLink *_pagingClock;
    CFTimeInterval _pagingStarted,_pagingPrevious,_pagingMaxGap,_pagingRelease;
    NSInteger _pagingStartIndex;
    NSUInteger _pagingSamples,_pagingLongFrames;
    NSString *_noticeComment,*_noticeParent,*_restoredWork,*_checkpointWork,*_checkpointScope;
    double _restoredPosition;BOOL _restoredPaused,_restoredApplied;
    CFTimeInterval _checkpointSavedAt,_checkpointAttemptAt,_lastBecameActive;
    std::vector<Work> _beforeProfileViews;
    void (^_deferredFeedUpdate)(void);
    NSMutableSet<NSString *> *_detailRequested;
    NSMutableDictionary<NSString *,NSDictionary *> *_resolvedDetails;
    NSMutableDictionary<NSString *,NSDictionary *> *_channelStates;douglass::ChannelSessions _channelSessions;
    NSMutableSet<NSString *> *_musicCoverRequests;BOOL _musicCoverPending;
}
- (instancetype)init {if((self=[super init])){_ownsBridge=YES;_operation=@"feed";_records=[NSMutableArray array];_cursor=@"0";}return self;}
- (instancetype)initWithRecords:(NSArray *)records selected:(NSInteger)selected bridge:(DGBridge *)bridge {
    if((self=[self init])){_bridge=bridge;_ownsBridge=NO;_staticFeed=YES;_selected=selected;[_records addObjectsFromArray:records];std::vector<Work> works;for(NSDictionary *record in records)works.push_back(ReadWork(record));_feed.append(std::move(works),false,true);_feed.more=false;}return self;
}
- (void)prepareNoticeFocus:(NSString *)comment parent:(NSString *)parent{_noticeComment=comment.copy;_noticeParent=parent.copy;}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.blackColor;_foreground=YES;_refreshIndex=1;_locationRequested=[NSMutableSet set];
    UICollectionViewFlowLayout *layout=[UICollectionViewFlowLayout new];layout.minimumLineSpacing=0;layout.minimumInteritemSpacing=0;
    _collection=[[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];_collection.backgroundColor=UIColor.blackColor;_collection.pagingEnabled=YES;_collection.showsVerticalScrollIndicator=NO;_collection.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;_collection.dataSource=self;_collection.delegate=self;_collection.alwaysBounceVertical=YES;
    _departingCells=[NSHashTable weakObjectsHashTable];[_collection registerClass:DGFeedCell.class forCellWithReuseIdentifier:@"work"];[self.view addSubview:_collection];
    if(!_staticFeed){_pull=[UIRefreshControl new];_pull.tintColor=UIColor.whiteColor;[_pull addTarget:self action:@selector(refreshFeed) forControlEvents:UIControlEventValueChanged];_collection.refreshControl=_pull;}
    if(_ownsBridge){_bridge=[DGBridge new];[_bridge mount:self.view];}
    _bar=Glass(27);_bar.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[self.view addSubview:_bar];_settings=Symbol(@"gearshape",self,@selector(settings));
    _follow=[UIButton buttonWithType:UIButtonTypeSystem];[_follow setTitle:@"关注" forState:UIControlStateNormal];_follow.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];[_follow addTarget:self action:@selector(followFeed) forControlEvents:UIControlEventTouchUpInside];[_follow addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(followList:)]];
    _recommend=[UIButton buttonWithType:UIButtonTypeSystem];[_recommend setTitle:@"推荐" forState:UIControlStateNormal];_recommend.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];[_recommend addTarget:self action:@selector(recommend) forControlEvents:UIControlEventTouchUpInside];
    _search=Symbol(@"magnifyingglass",self,@selector(search));_messages=Symbol(@"bubble.left.and.bubble.right",self,@selector(messages));_account=Symbol(@"person.crop.circle",self,@selector(account));_account.tintColor=UIColor.whiteColor;_search.tintColor=UIColor.whiteColor;
    _accountImage=[DGImage new];_accountImage.contentMode=UIViewContentModeScaleAspectFill;_accountImage.layer.cornerRadius=16;_accountImage.clipsToBounds=YES;_accountImage.userInteractionEnabled=NO;[_account addSubview:_accountImage];
    _accountSpinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];_accountSpinner.color=UIColor.whiteColor;_accountSpinner.hidesWhenStopped=YES;_accountSpinner.userInteractionEnabled=NO;[_account addSubview:_accountSpinner];
    _settings.hidden=YES;_navigationTabs=[[UISegmentedControl alloc]initWithItems:@[@"关注",@"推荐",@"信息"]];_navigationTabs.selectedSegmentIndex=1;_navigationTabs.backgroundColor=UIColor.clearColor;[_navigationTabs addTarget:self action:@selector(navigationChanged:) forControlEvents:UIControlEventValueChanged];[_navigationTabs addGestureRecognizer:[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(navigationHold:)]];UITapGestureRecognizer *navigationTap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(navigationTap:)];navigationTap.cancelsTouchesInView=NO;navigationTap.delegate=self;[_navigationTabs addGestureRecognizer:navigationTap];[_bar.contentView addSubview:_navigationTabs];[self.view addSubview:_account];[self.view addSubview:_search];
    if(_staticFeed){_bar.hidden=YES;_account.hidden=YES;_search.hidden=YES;_back=Symbol(@"chevron.left",self,@selector(close));_back.tintColor=UIColor.whiteColor;[self.view addSubview:_back];}
    if(!_staticFeed){
      _recommendRefreshGlass=Glass(17);_recommendRefreshGlass.hidden=YES;_recommendRefreshGlass.userInteractionEnabled=NO;
      _recommendRefreshSpinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
      _recommendRefreshSpinner.color=UIColor.whiteColor;_recommendRefreshSpinner.hidesWhenStopped=YES;
      [_recommendRefreshGlass.contentView addSubview:_recommendRefreshSpinner];[self.view addSubview:_recommendRefreshGlass];
    }
    _spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];_spinner.color=UIColor.secondaryLabelColor;_state=Label(20,UIFontWeightSemibold);_state.textAlignment=NSTextAlignmentCenter;_state.textColor=UIColor.whiteColor;_subtitle=Label(14,UIFontWeightRegular);_subtitle.numberOfLines=0;_subtitle.textAlignment=NSTextAlignmentCenter;_subtitle.textColor=[UIColor colorWithWhite:1 alpha:.65];
    _retry=[UIButton buttonWithType:UIButtonTypeSystem];[_retry setTitle:@"重新加载" forState:UIControlStateNormal];[_retry addTarget:self action:@selector(refreshFeed) forControlEvents:UIControlEventTouchUpInside];_login=[UIButton buttonWithType:UIButtonTypeSystem];[_login setTitle:@"登录 / 网页验证" forState:UIControlStateNormal];[_login addTarget:self action:@selector(openLogin) forControlEvents:UIControlEventTouchUpInside];
    UIButton *moreSettings=[UIButton buttonWithType:UIButtonTypeSystem];[moreSettings setTitle:@"更多设置" forState:UIControlStateNormal];[moreSettings addTarget:self action:@selector(emptySettings) forControlEvents:UIControlEventTouchUpInside];
    _empty=[[UIStackView alloc] initWithArrangedSubviews:@[_spinner,_state,_subtitle,_retry,_login,moreSettings]];_empty.axis=UILayoutConstraintAxisVertical;_empty.spacing=18;_empty.alignment=UIStackViewAlignmentCenter;[self.view addSubview:_empty];
    _cleanKnob=Glass(23);_cleanKnob.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;_cleanKnob.bounds=CGRectMake(0,0,46,46);
    _cleanKnobButton=Symbol(@"circle.dotted.circle",self,@selector(toggleCleanScreen));
    _cleanKnobButton.accessibilityLabel=@"一键清屏";_cleanKnobButton.accessibilityHint=@"轻点清屏或恢复，拖动可调整位置";
    _cleanKnobButton.frame=_cleanKnob.bounds;[_cleanKnob.contentView addSubview:_cleanKnobButton];
    UIPanGestureRecognizer *knobPan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(moveCleanKnob:)];
    knobPan.maximumNumberOfTouches=1;[_cleanKnob addGestureRecognizer:knobPan];
    [self.view addSubview:_cleanKnob];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(syncCleanScreen) name:@"DouGlassSettingsChanged" object:nil];
    [self syncCleanScreen];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(willResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background) name:UIApplicationDidEnterBackgroundNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground) name:UIApplicationDidBecomeActiveNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resume) name:@"DGResumePlayback" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(workStateChanged:) name:@"DouGlassWorkStateChanged" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(relationshipChanged:) name:@"DGRelationshipChanged" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(musicArtworkChanged:) name:@"DGMusicArtworkChanged" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playbackPreferencesChanged) name:@"DGPlaybackQualityChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(filtersChanged) name:@"DGFiltersChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accountChanged) name:@"DGAccountChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resume) name:@"DGMusicStateChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(verificationCompleted:) name:@"DGVerificationCompleted" object:nil];if(_staticFeed)[self updateEmpty:nil];else{[self restoreInterruptedPlayback];[self startWithCachedRecommendation];[self loadFeed:YES];[self loadProfile];}
}
- (void)dealloc{[_pagingClock invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (UIStatusBarStyle)preferredStatusBarStyle{return _showingMessages?UIStatusBarStyleDefault:UIStatusBarStyleLightContent;}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];if(_staticFeed)[self.navigationController setNavigationBarHidden:YES animated:animated];}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];if(!self.presentedViewController)DGMusicStop();_visible=YES;if(_showingMessages)DGSetEmbeddedMessagesVisible(_messageChannel,YES);_navigationTabs.selectedSegmentIndex=_showingMessages?2:[_operation isEqualToString:@"followFeed"]?0:1;[self activate];if(_ownsBridge&&DGRestoreNavigationResume(self,_bridge))return;DGSaveNavigationResume(self.view.window);if(_noticeComment.length&&_current<(NSInteger)_feed.works.size()&&!_comments)[self showComments:Text(_feed.works[_current].id)];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];if(!_staticFeed)DGCacheSetIdle(NO);if(DGOptionsKeepsPlayback(self.presentedViewController))return;if(_staticFeed)[self.navigationController setNavigationBarHidden:NO animated:animated];_visible=NO;[self finishPaging];for(DGFeedCell *cell in _collection.visibleCells)[cell active:NO];}
- (void)viewDidLayoutSubviews {
 [super viewDidLayoutSubviews];CGSize size=self.view.bounds.size;CGFloat top=self.view.safeAreaInsets.top;
 if(!CGSizeEqualToSize(_collection.bounds.size,size)){_relayout=YES;_collection.frame=self.view.bounds;[_collection.collectionViewLayout invalidateLayout];[_collection layoutIfNeeded];[_collection setContentOffset:CGPointMake(0,MAX(0,_current)*size.height) animated:NO];_relayout=NO;}
 _messageChannel.view.frame=CGRectMake(0,top+62,size.width,MAX(0,size.height-top-62));_messageRefreshGlass.frame=CGRectMake(size.width-54,top+12,40,40);
 CGFloat panel=_comments?MIN(size.height*.64,size.height-top-150):0;CGFloat media=size.height-panel;
 _commentHost.bounds=CGRectMake(0,0,size.width,MAX(0,panel));_commentHost.center=CGPointMake(size.width/2,media+MAX(0,panel)/2);_comments.view.frame=_commentHost.bounds;
 CGFloat w=MIN(size.width-136,330);_bar.frame=CGRectMake((size.width-w)/2,top+7,w,48);_account.frame=CGRectMake(14,top+7,44,48);_navigationTabs.frame=CGRectMake(5,6,w-10,36);CGFloat refreshX=CGRectGetMinX(_bar.frame)+5+(MAX(0,MIN(1,_navigationTabs.selectedSegmentIndex))+.5)*(w-10)/3;_recommendRefreshGlass.frame=CGRectMake(refreshX-17,top+61,34,34);_recommendRefreshSpinner.center=CGPointMake(17,17);_search.frame=CGRectMake(size.width-58,top+7,44,48);
 _accountImage.frame=CGRectMake((_account.bounds.size.width-32)/2,8,32,32);_accountSpinner.center=CGPointMake(_account.bounds.size.width/2,_account.bounds.size.height/2);_back.frame=CGRectMake(12,top+4,44,44);_empty.frame=CGRectMake(28,media/2-90,size.width-56,260);_subtitle.preferredMaxLayoutWidth=MIN(size.width-56,420);[self layoutCleanKnob];
 _follow.tintColor=[_operation isEqualToString:@"followFeed"]?UIColor.whiteColor:UIColor.secondaryLabelColor;_recommend.tintColor=[_operation isEqualToString:@"feed"]?UIColor.whiteColor:UIColor.secondaryLabelColor;
 if(_staticFeed&&!_positioned&&!_feed.works.empty()){_positioned=YES;_current=MAX(0,MIN(_selected,(NSInteger)_feed.works.size()-1));[_collection setContentOffset:CGPointMake(0,_current*size.height) animated:NO];}
 __weak DGFeed *weak=self;for(DGFeedCell *cell in self->_collection.visibleCells){BOOL compact=self->_comments&&!self->_closingComments;if(compact)cell.dismissCommentsAction=^{[weak closeComments];};else cell.dismissCommentsAction=nil;[cell compact:compact];[cell mediaHeight:compact?media+_commentDragOffset:0];[cell layoutIfNeeded];}
}
- (CGRect)cleanKnobBounds {
 CGRect area=UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets);
 return CGRectInset(area,MIN(26,CGRectGetWidth(area)/2),MIN(26,CGRectGetHeight(area)/2));
}
- (void)layoutCleanKnob {
 CGRect area=[self cleanKnobBounds];NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
 double x=[prefs objectForKey:@"douglass.clean.x"]?[prefs doubleForKey:@"douglass.clean.x"]:0;
 double y=[prefs objectForKey:@"douglass.clean.y"]?[prefs doubleForKey:@"douglass.clean.y"]:.58;
 _cleanKnob.center=CGPointMake(CGRectGetMinX(area)+std::clamp(x,0.,1.)*CGRectGetWidth(area),CGRectGetMinY(area)+std::clamp(y,0.,1.)*CGRectGetHeight(area));
}
- (void)moveCleanKnob:(UIPanGestureRecognizer *)gesture {
 if(gesture.state==UIGestureRecognizerStateBegan||gesture.state==UIGestureRecognizerStateChanged){
  CGPoint shift=[gesture translationInView:self.view];[gesture setTranslation:CGPointZero inView:self.view];
  CGRect area=[self cleanKnobBounds];CGPoint last=_cleanKnob.center;
  _cleanKnob.center=CGPointMake(std::clamp(last.x+shift.x,CGRectGetMinX(area),CGRectGetMaxX(area)),std::clamp(last.y+shift.y,CGRectGetMinY(area),CGRectGetMaxY(area)));
 }else if(gesture.state==UIGestureRecognizerStateEnded||gesture.state==UIGestureRecognizerStateCancelled){
  CGRect area=[self cleanKnobBounds];NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
  [prefs setDouble:(_cleanKnob.center.x-CGRectGetMinX(area))/MAX(1,CGRectGetWidth(area)) forKey:@"douglass.clean.x"];
  [prefs setDouble:(_cleanKnob.center.y-CGRectGetMinY(area))/MAX(1,CGRectGetHeight(area)) forKey:@"douglass.clean.y"];
 }
}
- (void)toggleCleanScreen{_cleanScreen=!_cleanScreen;DGHaptic();[self syncCleanScreen];}
- (void)syncCleanScreen {
 BOOL enabled=[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.clean.knob"];
 if(!enabled)_cleanScreen=NO;
 _cleanKnob.hidden=!enabled||_showingMessages||_comments||_feed.works.empty();
 _recommendRefreshGlass.hidden=!_manualRecommendationRefresh||_cleanScreen||_showingMessages;
 _bar.hidden=_staticFeed||_cleanScreen;_back.hidden=_cleanScreen;
 _account.hidden=_staticFeed||_showingMessages||_cleanScreen;_search.hidden=_account.hidden;
 [_cleanKnobButton setImage:[UIImage systemImageNamed:_cleanScreen?@"rectangle.expand.vertical":@"circle.dotted.circle"] forState:UIControlStateNormal];
 _cleanKnobButton.accessibilityLabel=_cleanScreen?@"恢复界面":@"一键清屏";
 for(DGFeedCell *cell in _collection.visibleCells)[cell cleanScreen:_cleanScreen];
}
- (void)savePlaybackCheckpoint {
 if(!_ownsBridge||!_visible||_showingMessages||_current<0||_current>=(NSInteger)_records.count||_current>=(NSInteger)_feed.works.size())return;
 const Work &work=_feed.works[_current];if(!work.playable()||work.isLive)return;
 _checkpointAttemptAt=CACurrentMediaTime();
 DGFeedCell *cell=(DGFeedCell *)[_collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:_current inSection:0]];
 if(!cell){DGDiagnostic(@"playback.checkpoint.deferred",@"reason=no_current_cell");return;}
 if(DGPlaybackResumeSave(_records[_current],_operation,[cell currentPlaybackPosition],[cell isPlaybackPaused])){
  _checkpointWork=Text(work.id);_checkpointScope=DGCurrentFeedScope();_checkpointSavedAt=CACurrentMediaTime();
 }
}
- (NSDictionary *)dgResumeState {
 if(!_staticFeed||!_records.count)return nil;
 NSInteger selected=MAX(0,MIN((NSInteger)_records.count-1,_positioned?_current:_selected));
 NSUInteger start=selected>30?selected-30:0,count=MIN((NSUInteger)61,_records.count-start);
 DGFeedCell *cell=(DGFeedCell *)[_collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:selected inSection:0]];
 double seconds=cell?[cell currentPlaybackPosition]:_restoredPosition;
 NSString *identifier=Text(String(_records[selected][@"id"]));
 return @{@"kind":@"player",@"records":[_records subarrayWithRange:NSMakeRange(start,count)],@"selected":@(selected-start),@"workID":identifier,@"position":@(std::isfinite(seconds)?seconds:0),@"paused":@(cell?[cell isPlaybackPaused]:_restoredPaused),@"comment":_noticeComment?:@"",@"parent":_noticeParent?:@""};
}
- (NSString *)currentWorkIdentifier{
 NSInteger index=_positioned?_current:_selected;
 if(_collection.bounds.size.height>0&&(!_staticFeed||_positioned))index=MAX(0,(NSInteger)llround(_collection.contentOffset.y/_collection.bounds.size.height));
 return index>=0&&index<(NSInteger)_feed.works.size()?Text(_feed.works[index].id):nil;
}
- (void)prepareResumeState:(NSDictionary *)state {
 _restoredWork=Text(String(state[@"workID"]));double seconds=[state[@"position"]doubleValue];_restoredPosition=std::isfinite(seconds)?MAX(0.,seconds):0;
 _restoredPaused=[state[@"paused"]boolValue];_noticeComment=Text(String(state[@"comment"]));_noticeParent=Text(String(state[@"parent"]));
}
- (void)willResignActive {
 _inactive=YES;++_warmGeneration;DGSuspendPrerolls();
 if(_ownsBridge){DGDiagnosticMemory(@"app.inactive");[self savePlaybackCheckpoint];DGCacheCancelPrefetch();DGRefreshRateSuspend();DGFlushSeen();}
 for(DGFeedCell *cell in _collection.visibleCells)[cell suspendForegroundWork];
}
- (void)restoreInterruptedPlayback {
 NSDictionary *saved=DGPlaybackResumeLoad();if(!saved)return;
 NSDictionary *record=saved[@"record"];Work work=ReadWork(record);
 if(!work.playable())return;
 _restoredWork=Text(work.id);_restoredPosition=[saved[@"position"]doubleValue];_restoredPaused=[saved[@"paused"]boolValue];
 _checkpointWork=_restoredWork;_checkpointScope=DGCurrentFeedScope();_checkpointSavedAt=_checkpointAttemptAt=CACurrentMediaTime();
 if([saved[@"channel"]isEqual:@"followFeed"])_operation=@"followFeed";
 [_records addObject:record];_feed.append({std::move(work)},true,true);_cachedBootstrap=YES;
 [_collection reloadData];[self updateEmpty:nil];
}
- (void)background {
 if(!_foreground)return;
 _foreground=NO;_inactive=YES;++_warmGeneration;DGSuspendPrerolls();
 if(_ownsBridge){if([_profile[@"loggedIn"]boolValue])DGSessionCapture(nil);if(CACurrentMediaTime()-_checkpointSavedAt>.25)[self savePlaybackCheckpoint];DGCacheCancelPrefetch();DGFlushSeen();DGDiagnosticMemory(@"app.background");}
 [self finishPaging];DGRefreshRateSuspend();
 BOOL ownsPlayback=_visible&&!_showingMessages&&self.view.window&&(!self.presentedViewController||DGOptionsKeepsPlayback(self.presentedViewController))&&!DGMusicPlayer();
 BOOL audio=DGBackgroundAudioEnabled(),pip=DGAutomaticPiPAvailable();
 for(DGFeedCell *cell in _collection.visibleCells){
  BOOL keep=ownsPlayback&&(audio||pip)&&[_collection indexPathForCell:cell].item==_current;
  [cell enterBackgroundKeepingPlayback:keep audioOnly:audio&&!pip];
 }
 DGTrimPlayers();[DGImage purgeCache];
 if(_ownsBridge)DGDiagnosticMemory(@"app.background.trimmed");
}
- (void)trimPlayback{for(DGFeedCell *cell in _collection.visibleCells)[cell releaseUnusedResources];DGTrimPlayers();[DGImage purgeCache];}
- (void)didReceiveMemoryWarning{[super didReceiveMemoryWarning];DGDiagnosticMemory(@"memory.warning");[self trimPlayback];}
- (void)foreground {
 _foreground=YES;_inactive=NO;_lastBecameActive=CACurrentMediaTime();[self finishPaging];DGRefreshRateApply();
 if(_ownsBridge)DGDiagnosticMemory(@"app.foreground");
 for(DGFeedCell *cell in _collection.visibleCells)[cell leaveBackground];
 [self activate];
 if(_ownsBridge&&(!_profile||CACurrentMediaTime()-_profileCheckedAt>120))[self loadProfile];
}
- (void)resume{dispatch_async(dispatch_get_main_queue(),^{[self activate];});}
- (void)workStateChanged:(NSNotification *)notification {
    NSDictionary *state=notification.userInfo;std::string identifier=String(state[@"id"]);if(identifier.empty())return;
    for(Work &work:_feed.works)if(work.id==identifier){work.liked=[state[@"liked"] boolValue];work.collected=[state[@"collected"] boolValue];work.likes=Number(state[@"likes"]);work.collects=Number(state[@"collects"]);}
    for(NSUInteger index=0;index<_records.count;index++){NSDictionary *record=_records[index];if(String(record[@"id"])!=identifier)continue;NSMutableDictionary *updated=[record mutableCopy];for(NSString *key in @[@"liked",@"collected",@"likes",@"collects"])if(state[key])updated[key]=state[key];_records[index]=updated;}
    for(NSString *channel in _channelStates.allKeys){NSDictionary *saved=_channelStates[channel];NSArray *records=Array(saved[@"records"]);NSMutableArray *updates=nil;
        for(NSUInteger index=0;index<records.count;index++){if(String(records[index][@"id"])!=identifier)continue;if(!updates)updates=[records mutableCopy];NSMutableDictionary *record=[records[index]mutableCopy];for(NSString *key in @[@"liked",@"collected",@"likes",@"collects"])if(state[key])record[key]=state[key];updates[index]=record;}
        if(updates){NSMutableDictionary *copy=[saved mutableCopy];copy[@"records"]=updates;_channelStates[channel]=copy;}
    }
}
- (void)relationshipChanged:(NSNotification *)notification{
 const std::string sec=String(notification.userInfo[@"sec"]),uid=String(notification.userInfo[@"uid"]);long long status=Number(notification.userInfo[@"followStatus"]);
 for(Work &work:_feed.works)if(douglass::matchesAuthor(work.authorID,work.authorUID,sec,uid)){work.followStatus=status;work.followStatusKnown=true;}
 for(NSUInteger i=0;i<_records.count;i++)_records[i]=DGWithRelationship(_records[i],sec,uid,status);
 for(NSString *channel in _channelStates.allKeys){NSDictionary *state=_channelStates[channel];NSMutableArray *records=[Array(state[@"records"])mutableCopy];for(NSUInteger i=0;i<records.count;i++)records[i]=DGWithRelationship(records[i],sec,uid,status);NSMutableDictionary *updated=[state mutableCopy];updated[@"records"]=records;_channelStates[channel]=updated;}
 for(DGFeedCell *cell in _collection.visibleCells){NSIndexPath *path=[_collection indexPathForCell:cell];if(path&&path.item<(NSInteger)_feed.works.size())[cell display:_feed.works[path.item]];}
}
- (void)musicArtworkChanged:(NSNotification *)notification{
 NSString *identifier=Text(String(notification.userInfo[@"id"])),*cover=Text(String(notification.userInfo[@"cover"]));if(!identifier.length||!cover.length)return;DGRememberMusicArtwork(identifier,cover);NSMutableArray *changed=[NSMutableArray array];
 for(NSUInteger i=0;i<_feed.works.size()&&i<_records.count;i++){Work &work=_feed.works[i];if(work.musicID!=String(identifier)||work.musicCover==String(cover))continue;work.musicCover=String(cover);NSMutableDictionary *record=[_records[i]mutableCopy];record[@"musicCover"]=cover;_records[i]=record;[changed addObject:record];DGFeedCell *cell=(DGFeedCell *)[_collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]];if(cell)[cell display:work];}
 for(NSString *channel in _channelStates.allKeys){NSDictionary *state=_channelStates[channel];NSMutableArray *records=[Array(state[@"records"])mutableCopy];BOOL updated=NO;for(NSUInteger i=0;i<records.count;i++){if(String(records[i][@"musicID"])!=String(identifier))continue;NSMutableDictionary *record=[records[i]mutableCopy];record[@"musicCover"]=cover;records[i]=record;[changed addObject:record];updated=YES;}if(updated){NSMutableDictionary *next=[state mutableCopy];next[@"records"]=records;_channelStates[channel]=next;}}
 DGIndexMusicWorks(changed);
}
- (void)requestCurrentMusicArtwork{
 if(_musicCoverPending||!_foreground||_inactive||!_visible||_pagingMotion||_showingMessages||_current<0||_current>=(NSInteger)_feed.works.size())return;
 const Work &work=_feed.works[_current];if(!work.musicCover.empty()||work.musicID.empty())return;DGFeedCell *cell=(DGFeedCell *)[_collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:_current inSection:0]];if(!work.photo()&&![cell hasRenderedMedia])return;
 NSString *identifier=Text(work.musicID),*cached=DGKnownMusicArtwork(identifier);if(cached.length){[NSNotificationCenter.defaultCenter postNotificationName:@"DGMusicArtworkChanged" object:nil userInfo:@{@"id":identifier,@"cover":cached}];return;}
 if(!_musicCoverRequests)_musicCoverRequests=[NSMutableSet set];if([_musicCoverRequests containsObject:identifier])return;if(_musicCoverRequests.count>=240)[_musicCoverRequests removeAllObjects];[_musicCoverRequests addObject:identifier];_musicCoverPending=YES;NSString *scope=DGCurrentFeedScope();__weak DGFeed *weak=self;
 [_bridge request:@"musicDetail" parameters:@{@"id":identifier} completion:^(NSDictionary *result,NSString *error){DGFeed *self=weak;if(!self)return;self->_musicCoverPending=NO;NSString *cover=Text(String(result[@"cover"]));
  if(!error&&cover.length&&[scope isEqualToString:DGCurrentFeedScope()]){DGRememberMusicArtwork(identifier,cover);[NSNotificationCenter.defaultCenter postNotificationName:@"DGMusicArtworkChanged" object:nil userInfo:@{@"id":identifier,@"cover":cover}];}
  else dispatch_after(dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),dispatch_get_main_queue(),^{DGFeed *self=weak;if(self)[self->_musicCoverRequests removeObject:identifier];});
  [self requestCurrentMusicArtwork];
 }];
}
- (void)close{if(self.navigationController&&self.navigationController.viewControllers.firstObject!=self){[self.navigationController popViewControllerAnimated:YES];return;}[self dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];}
- (void)updateEmpty:(NSString *)message {[self syncCleanScreen];_empty.hidden=_showingMessages||!_feed.works.empty();_state.text=_loading?@"让喜欢的内容，流进来":@"暂时没有新内容";_subtitle.text=message?:@"视频与图文推荐 · 登录后使用你的抖音账号";_state.hidden=_loading;_subtitle.hidden=_loading;_retry.hidden=_loading;_login.hidden=_loading;if(_loading)[_spinner startAnimating];else[_spinner stopAnimating];}
- (void)navigationChanged:(UISegmentedControl *)tabs{if(tabs.selectedSegmentIndex==0)[self followFeed];else if(tabs.selectedSegmentIndex==1)[self recommend];else [self messages];}
- (void)navigationHold:(UILongPressGestureRecognizer *)gesture{if([gesture locationInView:_navigationTabs].x<_navigationTabs.bounds.size.width/3)[self followList:gesture];}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
 if(gesture.view!=_navigationTabs)return YES;
 if(_showingMessages)return NO;
 CGFloat width=_navigationTabs.bounds.size.width,x=[touch locationInView:_navigationTabs].x;
 if(_navigationTabs.selectedSegmentIndex==0&&[_operation isEqualToString:@"followFeed"])return x>=0&&x<width/3;
 return _navigationTabs.selectedSegmentIndex==1&&[_operation isEqualToString:@"feed"]&&x>=width/3&&x<width*2/3;
}
- (void)navigationTap:(UITapGestureRecognizer *)gesture {
 BOOL selected=(_navigationTabs.selectedSegmentIndex==0&&[_operation isEqualToString:@"followFeed"])||(_navigationTabs.selectedSegmentIndex==1&&[_operation isEqualToString:@"feed"]);
 if(_staticFeed||!_foreground||_inactive||_showingMessages||_manualRecommendationRefresh||!selected)return;
 DGHaptic();_manualRecommendationRefresh=YES;++_refreshFeedback;
 [_recommendRefreshSpinner startAnimating];[self syncCleanScreen];[self.view setNeedsLayout];
 ++_feedRequest;_deferredFeedUpdate=nil;_loading=NO;
 [self refreshFeed];
}
- (void)endRecommendationFeedback {
 if(!_manualRecommendationRefresh)return;
 NSUInteger feedback=_refreshFeedback;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,320*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
  if(feedback!=self->_refreshFeedback)return;
  [self cancelRecommendationFeedback];
 });
}
- (void)cancelRecommendationFeedback {
 ++_refreshFeedback;_manualRecommendationRefresh=NO;
 [_recommendRefreshSpinner stopAnimating];_recommendRefreshGlass.hidden=YES;
}
- (void)resolveIP{
 if(!_foreground||!_visible||_current<0||_current>=(NSInteger)_feed.works.size())return;const Work &work=_feed.works[_current];if(work.authorID.empty()||(work.locationKind=="IP属地"&&work.location.find("·")!=std::string::npos&&work.followStatusKnown))return;NSString *sec=Text(work.authorID),*identifier=Text(work.id);if([_locationRequested containsObject:sec])return;[_locationRequested addObject:sec];NSUInteger generation=_generation;__weak DGFeed *weak=self;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{DGFeed *self=weak;if(!self||generation!=self->_generation||self->_current>=(NSInteger)self->_feed.works.size()||Text(self->_feed.works[self->_current].id).length==0||self->_feed.works[self->_current].id!=String(identifier)){if(self)[self->_locationRequested removeObject:sec];return;}
 [self->_bridge request:@"userLocation" parameters:@{@"sec":sec} completion:^(NSDictionary *result,NSString *error){DGFeed *self=weak;if(!self||generation!=self->_generation||error)return;if([result[@"followStatusKnown"]boolValue])[NSNotificationCenter.defaultCenter postNotificationName:@"DGRelationshipChanged" object:nil userInfo:@{@"sec":sec,@"followStatus":result[@"followStatus"]?:@0}];NSString *location=Text(String(result[@"location"]));if(!location.length)return;for(NSUInteger i=0;i<self->_feed.works.size();i++){Work &work=self->_feed.works[i];if(work.authorID!=String(sec))continue;work.location=String(location);work.locationKind="IP属地";if(i<self->_records.count){NSMutableDictionary *record=[self->_records[i]mutableCopy];record[@"location"]=location;record[@"locationKind"]=@"IP属地";self->_records[i]=record;}DGFeedCell *cell=(DGFeedCell *)[self->_collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]];if(cell)[cell display:work];}}];
 });
}
- (void)saveChannel{
 if(_channelSessions.setScope(String(DGCurrentFeedScope())))[_channelStates removeAllObjects];
 if(!_channelStates)_channelStates=[NSMutableDictionary dictionary];if(!_records.count)return;
 CGFloat height=_collection.bounds.size.height;NSInteger selected=height>0?(NSInteger)llround(_collection.contentOffset.y/height):_current;selected=MAX(0,MIN(selected,(NSInteger)_records.count-1));
 DGFeedCell *cell=(DGFeedCell *)[_collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:selected inSection:0]];
 _channelStates[_operation]=@{@"records":_records.copy};douglass::ChannelState state;state.cursor=String(_cursor);state.selected=selected;state.position=cell?[cell currentPlaybackPosition]:0;state.paused=cell?[cell isPlaybackPaused]:NO;state.more=_feed.more;state.refreshIndex=(int)_refreshIndex;state.emptyPages=(int)_emptyPages;_channelSessions.save(String(_operation),std::move(state),_records.count);
}
- (void)switchToChannel:(NSString *)operation{
 if([_operation isEqualToString:operation]){[self activate];return;}[self finishPaging];[self saveChannel];
 [self cancelRecommendationFeedback];[self closeComments];DGCacheSetIdle(NO);DGSuspendPrerolls();
 for(DGFeedCell *cell in _collection.visibleCells)[cell active:NO];
 ++_generation;++_warmGeneration;++_feedRequest;_deferredFeedUpdate=nil;_loading=NO;_failed=NO;_cachedBootstrap=NO;[_pull endRefreshing];
 [_detailRequested removeAllObjects];[_resolvedDetails removeAllObjects];_retainedComments=nil;_retainedCommentWorkID=nil;_operation=operation.copy;
 _restoredWork=nil;_restoredApplied=NO;_checkpointWork=nil;_current=0;_cursor=@"0";_refreshIndex=1;_emptyPages=0;_feed.clear();[_records removeAllObjects];
 NSDictionary *state=_channelStates[operation];[_channelStates removeObjectForKey:operation];auto snapshot=_channelSessions.take(String(operation));NSArray *records=snapshot?Array(state[@"records"]):@[];
 if(records.count){
  [_records addObjectsFromArray:records];std::vector<Work> works;works.reserve(records.count);for(NSDictionary *record in records)works.push_back(ReadWork(record));_feed.append(std::move(works),snapshot->more,true);
  _current=MAX(0,MIN((NSInteger)_records.count-1,(NSInteger)snapshot->selected));_cursor=Text(snapshot->cursor);_refreshIndex=snapshot->refreshIndex;_emptyPages=snapshot->emptyPages;
  _restoredWork=Text(String(_records[_current][@"id"]));_restoredPosition=snapshot->position;_restoredPaused=snapshot->paused;
 }
 [_collection reloadData];[_collection setContentOffset:CGPointZero animated:NO];[_collection layoutIfNeeded];
 if(records.count){[_collection setContentOffset:CGPointMake(0,_current*_collection.bounds.size.height) animated:NO];[self updateEmpty:nil];[self activate];}
 else {if([operation isEqualToString:@"feed"])[self startWithCachedRecommendation];[self loadFeed:YES];}
 [self.view setNeedsLayout];
}
- (void)recommend{[self hideMessages];_navigationTabs.selectedSegmentIndex=1;[self switchToChannel:@"feed"];}
- (void)followFeed{[self hideMessages];_navigationTabs.selectedSegmentIndex=0;[self switchToChannel:@"followFeed"];}
- (void)resetChannel{[_channelStates removeAllObjects];_channelSessions.clear();_channelSessions.setScope(String(DGCurrentFeedScope()));_restoredWork=nil;_checkpointWork=nil;DGPlaybackResumeClearCheckpoint();[self cancelRecommendationFeedback];[self finishPaging];DGCacheSetIdle(NO);_cachedBootstrap=NO;[_detailRequested removeAllObjects];[_resolvedDetails removeAllObjects];_retainedComments=nil;_retainedCommentWorkID=nil;++_generation;_loading=NO;[self closeComments];for(DGFeedCell *cell in _collection.visibleCells)[cell active:NO];_feed.clear();[_records removeAllObjects];[_collection reloadData];_current=0;_cursor=@"0";_refreshIndex=1;_emptyPages=0;if([_operation isEqualToString:@"feed"])[self startWithCachedRecommendation];[self loadFeed:YES];[self.view setNeedsLayout];}
- (void)refreshFeed{if(_staticFeed||_loading){[_pull endRefreshing];return;}_retainedComments=nil;_retainedCommentWorkID=nil;[self closeComments];if(_failed)[_bridge reload];_refreshIndex=1;_cursor=@"0";_emptyPages=0;[self loadFeed:YES];}
- (void)startWithCachedRecommendation {
 if(_staticFeed||![_operation isEqualToString:@"feed"]||(!_feed.works.empty()&&!_restoredWork.length))return;
 NSMutableSet *identities=[NSMutableSet set];std::vector<Work> works;
 for(const Work &existing:_feed.works)[identities addObject:DGWorkIdentity(existing)];
 for(NSDictionary *row in DGCacheReadyItems()){
  Work work=ReadWork(row);NSString *identity=DGWorkIdentity(work);
  if(!work.playable()||!DGContentAllowed(work)||[identities containsObject:identity])continue;
  [identities addObject:identity];works.push_back(work);[_records addObject:row];
 }
 if(works.empty())return;_cachedBootstrap=YES;
 _feed.append(std::move(works),true,false);[_collection reloadData];[self updateEmpty:nil];
 DGDiagnostic(@"feed.cached_start",[NSString stringWithFormat:@"items=%lu",(unsigned long)_records.count]);
}
- (void)loadFeed:(BOOL)replace {
 if(_staticFeed||_loading||!_foreground||_inactive||(!replace&&!_feed.more))return;
 _loading=YES;_failed=NO;[self updateEmpty:nil];
 NSUInteger generation=_generation,request=++_feedRequest;BOOL preserve=replace&&_cachedBootstrap;__weak DGFeed *weakSelf=self;
 [_bridge request:_operation parameters:@{@"refresh":@(_refreshIndex++),@"cursor":_cursor?:@"0"} completion:^(NSDictionary *result,NSString *error){
  DGFeed *self=weakSelf;if(!self||generation!=self->_generation||request!=self->_feedRequest)return;
  void (^apply)(void)=^{DGFeed *self=weakSelf;if(!self||generation!=self->_generation||request!=self->_feedRequest)return;
  self->_loading=NO;[self->_pull endRefreshing];[self endRecommendationFeedback];
  if(error){self->_failed=YES;[self updateEmpty:error];if(!self->_feed.works.empty())DGDiagnostic(@"feed.refresh_error_cached",nil);return;}
  self->_cachedBootstrap=NO;
  BOOL reset=replace&&!preserve;NSMutableSet *identities=[NSMutableSet set];std::unordered_set<std::string> ids;
  if(!reset)for(const Work &work:self->_feed.works){[identities addObject:DGWorkIdentity(work)];ids.insert(work.id);}
  std::vector<Work> works;NSMutableArray *fresh=[NSMutableArray array];
  for(NSDictionary *record in Array(result[@"items"])){
   Work work=ReadWork(record);NSString *identity=DGWorkIdentity(work);
   if(!work.playable()||!DGContentAllowed(work)||[identities containsObject:identity]||!ids.insert(work.id).second)continue;
   [identities addObject:identity];works.push_back(work);[fresh addObject:record];
  }
  if(reset&&self->_manualRecommendationRefresh&&!fresh.count&&!self->_feed.works.empty())reset=NO;
  NSUInteger before=self->_feed.works.size();
  std::size_t added=self->_feed.append(std::move(works),[result[@"more"] boolValue],reset);
  if(reset){[self->_records removeAllObjects];self->_current=0;}
  [self->_records addObjectsFromArray:fresh];
  if([self->_operation isEqualToString:@"feed"])DGCacheIngest(fresh);
  self->_cursor=[result[@"cursor"] description]?:@"0";
  self->_emptyPages=added?0:self->_emptyPages+1;if(self->_emptyPages>=5)self->_feed.more=false;
  if(reset){[self->_collection reloadData];[self->_collection setContentOffset:CGPointZero animated:NO];}
  else if(added){NSMutableArray *paths=[NSMutableArray array];for(NSUInteger i=before;i<before+added;i++)[paths addObject:[NSIndexPath indexPathForItem:i inSection:0]];[self->_collection insertItemsAtIndexPaths:paths];}
  DGDiagnostic(@"feed.batch",[NSString stringWithFormat:@"added=%lu skipped=%lu",(unsigned long)added,(unsigned long)(Array(result[@"items"]).count-fresh.count)]);
  [self updateEmpty:nil];dispatch_async(dispatch_get_main_queue(),^{[self activate];});
  if(self->_feed.works.empty()&&self->_feed.more)[self loadFeed:NO];
  };
  if(self->_pagingMotion||!self->_foreground||self->_inactive)self->_deferredFeedUpdate=apply;else apply();
 }];
}
- (void)updateAccountAppearance{
 BOOL loggedIn=[_profile[@"loggedIn"]boolValue];NSString *avatar=loggedIn?Text(String(_profile[@"avatar"])):@"";
 _accountImage.hidden=!avatar.length;[_accountImage remote:avatar];
 BOOL pending=!_profile&&_profileLoading;if(pending)[_accountSpinner startAnimating];else[_accountSpinner stopAnimating];
 [_account setImage:pending||!_accountImage.hidden?nil:[UIImage systemImageNamed:!_profile?@"arrow.clockwise":@"person.crop.circle"] forState:UIControlStateNormal];
 _account.accessibilityLabel=pending?@"正在确认抖音账号":!_profile?@"账号状态暂未确认，轻点重试":loggedIn?@"我的主页":@"登录抖音账号";
}
- (void)loadProfile {
 if(_profileLoading)return;_profileLoading=YES;[self updateAccountAppearance];NSUInteger generation=_accountGeneration;__weak DGFeed *weakSelf=self;
 [_bridge request:@"profile" parameters:@{} completion:^(NSDictionary *result,NSString *error){
  DGFeed *self=weakSelf;if(!self||generation!=self->_accountGeneration)return;self->_profileLoading=NO;
  if(error){[self updateAccountAppearance];NSUInteger failures=++self->_profileFailures;if(failures<=2){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((failures==1?2:6)*NSEC_PER_SEC)),dispatch_get_main_queue(),^{DGFeed *self=weakSelf;if(self&&generation==self->_accountGeneration&&self->_profileFailures==failures&&self->_foreground&&!self->_inactive&&self->_visible)[self loadProfile];});}return;}
  self->_profileFailures=0;self->_profileCheckedAt=CACurrentMediaTime();
  self->_profile=result;NSString *old=DGCurrentFeedScope();NSString *uid=[result[@"loggedIn"]boolValue]?Text(String(result[@"uid"])):@"";
  if(uid.length||[old isEqualToString:@"anonymous"]||[result[@"authConfirmed"]boolValue])DGSeenScope(uid);
  if(uid.length){for(const Work &viewed:self->_beforeProfileViews)DGRecordViewed(viewed);self->_beforeProfileViews.clear();}
  if(![old isEqualToString:DGCurrentFeedScope()]){[self->_channelStates removeAllObjects];self->_channelSessions.clear();self->_channelSessions.setScope(String(DGCurrentFeedScope()));
   if(![old isEqualToString:@"anonymous"]){[self resetChannel];}
   else if([self->_operation isEqualToString:@"feed"]){DGCacheIngest(self->_records);[self filtersChanged];}
  }
  [self activate];[self updateAccountAppearance];
 }];
}
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section{return _feed.works.size();}
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path{return collectionView.bounds.size;}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)path {
    DGFeedCell *cell=[collectionView dequeueReusableCellWithReuseIdentifier:@"work" forIndexPath:path];[self configureCell:cell atIndexPath:path];return cell;
}
- (void)configureCell:(DGFeedCell *)cell atIndexPath:(NSIndexPath *)path{
    cell.bridge=_bridge;cell.presenter=self;const Work &work=_feed.works[path.item];[cell pagingInMotion:_pagingMotion];[cell display:work];NSString *workID=Text(work.id);if(!_restoredApplied&&[_restoredWork isEqualToString:workID]){_restoredApplied=YES;[cell restorePlaybackPosition:_restoredPosition paused:_restoredPaused];}[cell compact:_comments!=nil];[cell cleanScreen:_cleanScreen];NSString *sec=Text(work.authorID),*name=Text(work.author);NSDictionary *record=path.item<(NSInteger)_records.count?_records[path.item]:@{};__weak DGFeed *weakSelf=self;
    __weak DGFeedCell *weakCell=cell;cell.moreAction=^{DGFeed *self=weakSelf;if(!self||self.presentedViewController)return;NSMutableDictionary *options=[record mutableCopy];options[@"selectedImage"]=[weakCell selectedImageURL]?:@"";[self presentViewController:DGMakeOptions(self->_bridge,options) animated:YES completion:nil];};cell.actionMenuAction=^(CGPoint point){DGFeed *self=weakSelf;if(!self||self.presentedViewController)return;NSMutableDictionary *options=[record mutableCopy];options[@"selectedImage"]=[weakCell selectedImageURL]?:@"";options[@"menuOrigin"]=[NSValue valueWithCGPoint:[weakCell.contentView convertPoint:point toView:self.view]];[self presentViewController:DGMakeActions(self->_bridge,options) animated:YES completion:nil];};cell.viewedAction=^{DGFeed *self=weakSelf;DGFeedCell *view=weakCell;if(!self||!view||self->_pagingMotion)return;
  NSIndexPath *visible=[self->_collection indexPathForCell:view];if(!visible||visible.item!=self->_current||visible.item>=(NSInteger)self->_feed.works.size())return;
  const Work &current=self->_feed.works[visible.item];if(current.id!=String(workID))return;
  if(!self->_staticFeed&&!self->_profile&&[DGCurrentFeedScope()isEqualToString:@"anonymous"]&&self->_beforeProfileViews.size()<50)self->_beforeProfileViews.push_back(current);
  DGRecordViewed(current);[self warmAfterSettling];
 };if(_ownsBridge)cell.checkpointAction=^{DGFeed *self=weakSelf;if(self&&!self->_inactive&&CACurrentMediaTime()-self->_checkpointAttemptAt>=15)[self savePlaybackCheckpoint];};
 cell.advanceAction=^BOOL{return [weakSelf advanceWork];};cell.commentsAction=^{[weakSelf showComments:workID];};cell.profileAction=^{DGFeed *self=weakSelf;if(self)[self presentPage:DGMakeProfile(self->_bridge,sec,name,workID)];};
    cell.musicAction=^{DGFeed *self=weakSelf;if(self)[self presentPage:DGMakeMusic(self->_bridge,@{@"id":record[@"musicID"]?:@"",@"url":record[@"music"]?:@"",@"title":record[@"musicTitle"]?:@"作品原声",@"author":record[@"musicAuthor"]?:@"",@"cover":DGMusicArtworkForRecord(record),@"collected":record[@"musicCollected"]?:@NO,@"shareURL":record[@"musicShareURL"]?:@"",@"contextWork":record})];};
}
- (void)resolveBriefWorkAtIndex:(NSInteger)index{
 if(index<0||index>=(NSInteger)_records.count)return;NSDictionary *record=_records[index];if(!DGWorkNeedsDetails(record))return;
 if(!_detailRequested)_detailRequested=[NSMutableSet set];NSString *identifier=Text(String(record[@"id"]));if([_detailRequested containsObject:identifier])return;[_detailRequested addObject:identifier];
 NSUInteger generation=_generation;__weak DGFeed *weak=self;
 DGResolveWorkDetails(_bridge,record,index==_current,^(NSDictionary *result,NSString *error){DGFeed *self=weak;if(!self||generation!=self->_generation)return;NSDictionary *detail=Array(result[@"items"]).firstObject;if(error||!detail)return;
  if(!self->_resolvedDetails)self->_resolvedDetails=[NSMutableDictionary dictionary];self->_resolvedDetails[identifier]=detail;
  if(self->_foreground&&!self->_inactive&&!self->_pagingMotion)[self activate];
 });
}
- (void)applyResolvedDetails{
 if(!_resolvedDetails.count)return;
 NSDictionary *updates=_resolvedDetails.copy;[_resolvedDetails removeAllObjects];
 for(NSUInteger i=0;i<_records.count&&i<_feed.works.size();i++){NSString *identifier=Text(String(_records[i][@"id"]));NSDictionary *detail=updates[identifier];if(!detail)continue;
  _records[i]=detail;_feed.works[i]=ReadWork(detail);NSIndexPath *path=[NSIndexPath indexPathForItem:i inSection:0];DGFeedCell *cell=(DGFeedCell *)[_collection cellForItemAtIndexPath:path];if(cell)[self configureCell:cell atIndexPath:path];
 }
}
- (void)activate {
 if(_relayout||!_foreground||_inactive||_pagingMotion)return;
 [self applyResolvedDetails];
 CGFloat height=_collection.bounds.size.height;if(height<=0)return;
 _current=MAX(0,(NSInteger)llround(_collection.contentOffset.y/height));
 if(_retainedCommentWorkID.length&&(_current>=(NSInteger)_feed.works.size()||![_retainedCommentWorkID isEqualToString:Text(_feed.works[_current].id)])){_retainedComments=nil;_retainedCommentWorkID=nil;}
 BOOL allowed=!_showingMessages&&_visible&&self.view.window&&(self.presentedViewController==nil||DGOptionsKeepsPlayback(self.presentedViewController))&&DGMusicPlayer()==nil;
 DGFeedCell *selected=nil;
 for(DGFeedCell *cell in _collection.visibleCells){
  [cell leaveBackground];[cell pagingInMotion:NO];NSIndexPath *path=[_collection indexPathForCell:cell];
  if(allowed&&path&&path.item==_current)selected=cell;else [cell active:NO];
 }
 if(selected&&_current<(NSInteger)_feed.works.size()&&_ownsBridge){
  NSString *selectedID=Text(_feed.works[_current].id);DGCacheSelectWork(selectedID);
  if(_restoredWork.length&&![_restoredWork isEqualToString:selectedID])_restoredWork=nil;
  if(!_feed.works[_current].isLive&&(![_checkpointWork isEqualToString:selectedID]||![_checkpointScope isEqualToString:DGCurrentFeedScope()])){
   NSUInteger generation=_generation;__weak DGFeed *weak=self;
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW,160*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
    DGFeed *self=weak;if(!self||self->_generation!=generation||self->_pagingMotion||self->_inactive||self->_current<0||self->_current>=(NSInteger)self->_feed.works.size())return;
    if(self->_feed.works[self->_current].id==String(selectedID)&&(![self->_checkpointWork isEqualToString:selectedID]||![self->_checkpointScope isEqualToString:DGCurrentFeedScope()]))[self savePlaybackCheckpoint];
   });
  }
 }
 [selected active:YES];
 if(selected)[self resolveBriefWorkAtIndex:_current];
 if(allowed){[self warmAfterSettling];[self resolveIP];}
}
- (void)beginPaging {
 if(_pagingMotion)return;
 _pagingMotion=YES;++_warmGeneration;DGSuspendPrerolls();
 if(DGDiagnosticEnabled()){
  _pagingStarted=CACurrentMediaTime();_pagingPrevious=_pagingStarted;_pagingRelease=0;_pagingMaxGap=0;_pagingSamples=0;_pagingLongFrames=0;_pagingStartIndex=_current;
  DGSwipeClock *clock=[DGSwipeClock new];__weak DGFeed *weak=self;
  clock.sample=^(CADisplayLink *link){DGFeed *self=weak;if(self)[self samplePagingFrame:link];else [link invalidate];};
  _pagingClock=[CADisplayLink displayLinkWithTarget:clock selector:@selector(tick:)];
  [_pagingClock addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
  DGDiagnostic(@"swipe.begin",[NSString stringWithFormat:@"page=%ld",(long)_current]);
 }
 DGCacheSetIdle(NO);
 for(DGFeedCell *cell in _collection.visibleCells)[cell pagingInMotion:YES];
}
- (void)samplePagingFrame:(CADisplayLink *)link {
 if(!_pagingMotion||!DGDiagnosticEnabled()){[_pagingClock invalidate];_pagingClock=nil;return;}
 CFTimeInterval gap=link.timestamp-_pagingPrevious;
 if(gap>0){
  ++_pagingSamples;_pagingMaxGap=MAX(_pagingMaxGap,gap);
  CFTimeInterval nominal=link.targetTimestamp-link.timestamp;
  if(nominal>0&&gap>nominal*1.65)++_pagingLongFrames;
 }
 _pagingPrevious=link.timestamp;
}
- (void)finishPaging {
 if(_pagingMotion&&_pagingStarted>0){
  CFTimeInterval end=CACurrentMediaTime();CGFloat height=_collection.bounds.size.height;
  NSInteger target=height>0?MAX(0,(NSInteger)llround(_collection.contentOffset.y/height)):_current;
  DGDiagnostic(@"swipe.settled",[NSString stringWithFormat:@"from=%ld to=%ld total_ms=%.0f coast_ms=%.0f frames=%lu long_gaps=%lu max_gap_ms=%.1f",(long)_pagingStartIndex,(long)target,(end-_pagingStarted)*1000,_pagingRelease>0?(end-_pagingRelease)*1000:0,(unsigned long)_pagingSamples,(unsigned long)_pagingLongFrames,_pagingMaxGap*1000]);
 }
 if(_pagingMotion&&_foreground&&[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.autoScroll"]&&_current>=0&&_current<(NSInteger)_feed.works.size()){
  CGFloat height=_collection.bounds.size.height;
  NSInteger target=height>0?MAX(0,(NSInteger)llround(_collection.contentOffset.y/height)):_current;
  const Work &previous=_feed.works[_current];
  if(target!=_current&&!previous.photo()&&!previous.isLive)DGResetWorkPlayback(Text(previous.id));
 }
 _pagingStarted=0;[_pagingClock invalidate];_pagingClock=nil;_pagingMotion=NO;
 NSArray *visible=_collection.visibleCells;
 for(DGFeedCell *cell in _departingCells.allObjects)if(![visible containsObject:cell])[cell active:NO];
 [_departingCells removeAllObjects];
 for(DGFeedCell *cell in visible)[cell pagingInMotion:NO];
 if(_foreground&&!_inactive){void (^apply)(void)=_deferredFeedUpdate;_deferredFeedUpdate=nil;if(apply)dispatch_async(dispatch_get_main_queue(),^{if(self->_inactive||!self->_foreground||self->_pagingMotion){if(!self->_deferredFeedUpdate)self->_deferredFeedUpdate=apply;}else apply();});}
}
- (BOOL)advanceWork {
 if(_comments||_commentTransition||self.presentedViewController||_pagingMotion)return NO;
 NSInteger next=_current+1;if(next>=(NSInteger)_feed.works.size()){if(_feed.more)[self loadFeed:NO];return NO;}
 [self beginPaging];[_collection scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:next inSection:0] atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:YES];return YES;
}
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView{[self beginPaging];}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView{[self finishPaging];[self activate];}
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
 if(_pagingStarted>0){_pagingRelease=CACurrentMediaTime();DGDiagnostic(@"swipe.release",[NSString stringWithFormat:@"decelerates=%d",decelerate]);}
 if(!decelerate){[self finishPaging];[self activate];}
}
- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView{[self finishPaging];[self activate];}
- (void)warmAfterSettling {
 if(_inactive||!_foreground)return;
 NSUInteger request=++_warmGeneration,generation=_generation;__weak DGFeed *weak=self;
 CFTimeInterval delay=MAX(.12,.8-(CACurrentMediaTime()-_lastBecameActive));
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  DGFeed *self=weak;if(!self||request!=self->_warmGeneration||generation!=self->_generation||!self->_foreground||self->_inactive||!self->_visible||self->_showingMessages||self->_pagingMotion)return;
  DGFeedCell *active=(DGFeedCell *)[self->_collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:self->_current inSection:0]];
  BOOL photo=self->_current>=0&&self->_current<(NSInteger)self->_feed.works.size()&&self->_feed.works[self->_current].photo();
  if(!photo&&![active hasRenderedMedia])return;
  [self requestCurrentMusicArtwork];[self resolveBriefWorkAtIndex:self->_current+1];
  if(self->_current<(NSInteger)self->_feed.works.size())DGWarmWorks(self->_feed.works,self->_current);
  BOOL recommends=!self->_staticFeed&&[self->_operation isEqualToString:@"feed"];
  if(recommends){
   NSMutableArray *upcoming=[NSMutableArray array];for(NSUInteger i=MAX(0,self->_current+1);i<self->_records.count&&upcoming.count<50;i++)[upcoming addObject:self->_records[i]];
   DGCacheIngest(upcoming);DGCacheSetIdle([active hasRenderedMedia]||(self->_current<(NSInteger)self->_feed.works.size()&&self->_feed.works[self->_current].photo()));
  }
  if(!self->_staticFeed&&self->_feed.more&&!self->_failed&&!self->_loading){
   NSInteger ahead=(NSInteger)self->_records.count-self->_current-1;
   if(ahead<=6||(recommends&&DGCachePendingCount()<50&&ahead<58))[self loadFeed:NO];
  }
 });
}
- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)path {
 if(_foreground&&!_inactive)[(DGFeedCell *)cell stagePreparedVideo];
 if(path.item==_current&&!_pagingMotion){__weak DGFeed *weak=self;dispatch_async(dispatch_get_main_queue(),^{[weak activate];});}
}
- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)path{if(_pagingMotion)[_departingCells addObject:(DGFeedCell *)cell];else [(DGFeedCell *)cell active:NO];}
- (void)showComments:(NSString *)workID {
 if(_commentTransition)return;_closingComments=NO;if(_comments){[self closeComments];return;}_commentTransition=YES;
 _comments=[_retainedCommentWorkID isEqualToString:workID]?_retainedComments:nil;if(!_comments)_comments=[[DGComments alloc]initWithBridge:_bridge work:workID parent:nil];_retainedComments=_comments;_retainedCommentWorkID=workID.copy;if(_noticeComment.length){[_comments focusComment:_noticeComment parent:_noticeParent];_noticeComment=nil;_noticeParent=nil;}if(_current<(NSInteger)_records.count){NSDictionary *record=_records[_current];_comments.coverURL=Text(String(record[@"cover"]));if(!_comments.coverURL.length)_comments.coverURL=Text(String(Array(record[@"images"]).firstObject));}__weak DGFeed *weak=self;_comments.closeAction=^{[weak closeComments];};_comments.dragAction=^(CGFloat offset,NSInteger phase){[weak commentDragged:offset phase:phase];};_comments.profileAction=^(NSString *sec,NSString *name){DGFeed *self=weak;if(self)[self presentPage:DGMakeProfile(self->_bridge,sec,name,@"")];};
 [self addChildViewController:_comments];_commentHost=[UIView new];_commentHost.layer.cornerRadius=30;_commentHost.clipsToBounds=YES;[self.view addSubview:_commentHost];[_commentHost addSubview:_comments.view];[_comments didMoveToParentViewController:self];_collection.scrollEnabled=NO;
 [UIView performWithoutAnimation:^{[self.view setNeedsLayout];[self.view layoutIfNeeded];[self->_comments restorePosition];}];_commentHost.transform=CGAffineTransformMakeTranslation(0,_commentHost.bounds.size.height+10);
 DGAnimate(.3,^{self->_commentHost.transform=CGAffineTransformIdentity;},^(BOOL done){self->_commentTransition=NO;[self syncCleanScreen];[self activate];});
}
- (void)commentDragged:(CGFloat)offset phase:(NSInteger)phase{if(_commentTransition||!_comments)return;_commentDragOffset=MIN(offset,_commentHost.bounds.size.height);if(phase==0){_commentHost.transform=CGAffineTransformMakeTranslation(0,_commentDragOffset);CGFloat media=self.view.bounds.size.height-_commentHost.bounds.size.height+_commentDragOffset;for(DGFeedCell *cell in _collection.visibleCells)[cell interactiveMediaHeight:media];}else if(phase==1){[self closeComments];}else{_commentDragOffset=0;CGFloat media=self.view.bounds.size.height-_commentHost.bounds.size.height;for(DGFeedCell *cell in _collection.visibleCells)[cell mediaHeight:media];DGAnimate(.25,^{self->_commentHost.transform=CGAffineTransformIdentity;},nil);}}
- (void)closeComments {
 if(!_comments||_commentTransition)return;[_comments rememberPosition];_commentTransition=YES;_closingComments=YES;_commentDragOffset=0;[self.view setNeedsLayout];[self.view layoutIfNeeded];UIView *panel=_commentHost;
 DGAnimate(.3,^{panel.transform=CGAffineTransformMakeTranslation(0,panel.bounds.size.height+10);},^(BOOL done){[self->_comments willMoveToParentViewController:nil];[self->_comments.view removeFromSuperview];[self->_comments removeFromParentViewController];self->_comments=nil;[panel removeFromSuperview];self->_commentHost=nil;self->_collection.scrollEnabled=YES;self->_commentTransition=NO;self->_closingComments=NO;[self syncCleanScreen];[UIView performWithoutAnimation:^{[self.view setNeedsLayout];[self.view layoutIfNeeded];}];[self activate];});
}
- (void)verificationCompleted:(NSNotification *)note{if(!_ownsBridge)return;_failed=NO;[self loadProfile];if([note.userInfo[@"operation"]isEqualToString:_operation]&&!_loading)[self loadFeed:YES];}
- (void)accountChanged{[self sessionChanged:NO];}
- (void)playbackPreferencesChanged{DGClearPlayers();for(NSUInteger index=0;index<_records.count&&index<_feed.works.size();index++){Work work=ReadWork(_records[index]);_feed.works[index]=work;DGFeedCell *cell=(DGFeedCell *)[_collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0]];if(cell)[cell display:work];}DGWarmWorks(_feed.works,_current);}
- (void)filtersChanged{
 [_channelStates removeAllObjects];_channelSessions.clear();
 if(_staticFeed||_feed.works.empty())return;std::vector<Work> kept;NSMutableArray *records=[NSMutableArray array],*deleted=[NSMutableArray array];
 for(NSUInteger index=0;index<_feed.works.size();index++){const Work &work=_feed.works[index];if((NSInteger)index<=_current||DGContentAllowed(work)){kept.push_back(work);if(index<_records.count)[records addObject:_records[index]];}else [deleted addObject:[NSIndexPath indexPathForItem:index inSection:0]];}
 if(!deleted.count)return;BOOL more=_feed.more;_feed.append(std::move(kept),more,true);_records=records;[_collection deleteItemsAtIndexPaths:deleted];[self activate];
}
- (void)presentPage:(UIViewController *)page{if(!page||self.presentedViewController)return;if(_showingMessages){DGSetEmbeddedMessagesVisible(_messageChannel,NO);page.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeMessageDetail)];}for(DGFeedCell *cell in _collection.visibleCells)[cell active:NO];UINavigationController *nav=[[DGNavigationController alloc] initWithRootViewController:page];DGConfigurePageTransition(nav);[self presentViewController:nav animated:YES completion:nil];}
- (void)closeMessageDetail{[self dismissViewControllerAnimated:YES completion:^{DGSetEmbeddedMessagesVisible(self->_messageChannel,self->_showingMessages);[self activate];}];}
- (void)search{[self presentPage:DGMakeSearch(_bridge)];}
- (void)messages{
 if(_showingMessages)return;DGCacheSetIdle(NO);[self closeComments];_showingMessages=YES;_bar.overrideUserInterfaceStyle=UIUserInterfaceStyleUnspecified;[self setNeedsStatusBarAppearanceUpdate];
 for(DGFeedCell *cell in _collection.visibleCells)[cell active:NO];
 _collection.hidden=YES;_empty.hidden=YES;_account.hidden=YES;_search.hidden=YES;
 __weak DGFeed *weak=self;
 if(!_messageChannel||![_messageScope isEqualToString:DGCurrentFeedScope()]){_messageChannel=DGMakeEmbeddedMessages(_bridge,^(UIViewController *page){[weak presentPage:page];});_messageScope=DGCurrentFeedScope();}
 [self addChildViewController:_messageChannel];[self.view insertSubview:_messageChannel.view belowSubview:_bar];[_messageChannel didMoveToParentViewController:self];DGSetEmbeddedMessagesVisible(_messageChannel,YES);
 _messageRefreshGlass=Glass(20);UIButton *refresh=Symbol(@"arrow.clockwise",self,@selector(refreshMessages));refresh.accessibilityLabel=@"刷新信息";refresh.frame=CGRectMake(0,0,40,40);[_messageRefreshGlass.contentView addSubview:refresh];[self.view addSubview:_messageRefreshGlass];[self syncCleanScreen];
 [self.view setNeedsLayout];
}
- (void)refreshMessages{DGRefreshEmbeddedMessages(_messageChannel);}
- (void)hideMessages{
 if(!_showingMessages)return;_showingMessages=NO;_bar.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[self setNeedsStatusBarAppearanceUpdate];
 DGSetEmbeddedMessagesVisible(_messageChannel,NO);[_messageChannel willMoveToParentViewController:nil];[_messageChannel.view removeFromSuperview];[_messageChannel removeFromParentViewController];
 [_messageRefreshGlass removeFromSuperview];_messageRefreshGlass=nil;
 _collection.hidden=NO;_empty.hidden=!_feed.works.empty();_account.hidden=NO;_search.hidden=NO;
 _navigationTabs.selectedSegmentIndex=[_operation isEqualToString:@"followFeed"]?0:1;[self syncCleanScreen];[self activate];
}
- (void)account{if(!_profile){[self loadProfile];DGToast(self,@"正在确认账号，请稍候");return;}if(![_profile[@"loggedIn"] boolValue]){[self openLogin];return;}[self presentPage:DGMakeProfile(_bridge,@"",_profile[@"nickname"]?:@"我的",@"")];}
- (void)followList:(UILongPressGestureRecognizer *)gesture{if(gesture.state!=UIGestureRecognizerStateBegan)return;extern UIViewController *DGMakeFollowing(DGBridge *,NSString *,NSString *);[self presentPage:DGMakeFollowing(_bridge,_profile[@"sec"]?:@"",_profile[@"uid"]?:@"")];}
- (void)emptySettings{if(!self.presentedViewController)[self presentViewController:DGMakeOptions(_bridge,@{}) animated:YES completion:nil];}
- (void)settings {
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"澄流 · 设置" message:@"长按视频固定 2×，松手恢复 1×\n长按关注可查看关注列表" preferredStyle:UIAlertControllerStyleActionSheet];BOOL enabled=[NSUserDefaults.standardUserDefaults objectForKey:@"douglass.danmaku"]?[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.danmaku"]:YES;
    [menu addAction:[UIAlertAction actionWithTitle:enabled?@"关闭视频弹幕":@"开启视频弹幕" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[NSUserDefaults.standardUserDefaults setBool:!enabled forKey:@"douglass.danmaku"];[NSNotificationCenter.defaultCenter postNotificationName:@"DouGlassSettingsChanged" object:nil];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"登录 / 安全验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self openLogin];}]];[menu addAction:[UIAlertAction actionWithTitle:@"退出当前账号" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){[self->_bridge signOut:^{[self sessionChanged:NO];}];}]];[menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];menu.popoverPresentationController.sourceView=_settings;menu.popoverPresentationController.sourceRect=_settings.bounds;[self presentViewController:menu animated:YES completion:nil];
}
- (void)openLogin{if(self.presentedViewController)return;for(DGFeedCell *cell in _collection.visibleCells)[cell active:NO];DGLogin *login=[DGLogin new];__weak DGFeed *weakSelf=self;login.finished=^{[weakSelf sessionChanged:YES];};UINavigationController *nav=[[DGNavigationController alloc] initWithRootViewController:login];DGConfigurePageTransition(nav);[self presentViewController:nav animated:YES completion:nil];}
- (void)sessionChanged:(BOOL)reload{[_musicCoverRequests removeAllObjects];[_channelStates removeAllObjects];_channelSessions.clear();++_accountGeneration;_profileLoading=NO;_profileFailures=0;_profileCheckedAt=0;DGClearNavigationResume();[_detailRequested removeAllObjects];[_resolvedDetails removeAllObjects];_restoredWork=nil;_checkpointWork=nil;DGPlaybackResumeClearCheckpoint();_beforeProfileViews.clear();[self cancelRecommendationFeedback];[self finishPaging];_cachedBootstrap=NO;DGCacheSetIdle(NO);_retainedComments=nil;_retainedCommentWorkID=nil;++_generation;[_locationRequested removeAllObjects];_loading=NO;_failed=NO;_profile=nil;[self closeComments];DGClearPlayers();DGMusicStop();DGResetInteractions();DGResetMusicPages();[self hideMessages];_messageChannel=nil;_messageScope=nil;_feed.clear();[_records removeAllObjects];[_collection reloadData];_refreshIndex=1;_cursor=@"0";_emptyPages=0;_current=0;if(reload)[_bridge reload];if(!reload)DGSeenScope(@"");[self loadFeed:YES];[self loadProfile];}
@end
UIViewController *DGMakeFeedController(void){return [DGFeed new];}
UIViewController *DGMakeWorkPlayer(NSArray<NSDictionary *> *works,NSInteger selected,DGBridge *bridge){return [[DGFeed alloc] initWithRecords:works selected:selected bridge:bridge];}
NSString *DGCurrentWorkID(UIViewController *player){return [player isKindOfClass:DGFeed.class]?[(DGFeed *)player currentWorkIdentifier]:nil;}
UIViewController *DGMakeResumedWorkPlayer(DGBridge *bridge,NSDictionary *state){
 NSMutableArray *records=[NSMutableArray array];NSString *identifier=Text(String(state[@"workID"]));NSInteger selected=NSNotFound;
 for(id value in Array(state[@"records"])){if(![value isKindOfClass:NSDictionary.class]||!ReadWork(value).playable())continue;if([Text(String(value[@"id"]))isEqualToString:identifier])selected=records.count;[records addObject:value];if(records.count==61)break;}
 if(!records.count||selected==NSNotFound)return nil;
 DGFeed *view=[[DGFeed alloc]initWithRecords:records selected:selected bridge:bridge];[view prepareResumeState:state];return view;
}


UIViewController *DGMakeNoticePlayer(NSArray<NSDictionary *> *works,DGBridge *bridge,NSString *commentID,NSString *parentID){DGFeed *player=[[DGFeed alloc]initWithRecords:works selected:0 bridge:bridge];[player prepareNoticeFocus:commentID parent:parentID];return player;}
