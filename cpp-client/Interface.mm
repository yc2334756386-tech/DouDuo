#import "DGCommon.h"
#import "DGMedia.h"
#import "DGComments.h"
@interface DGFeed : UIViewController <UICollectionViewDataSource,UICollectionViewDelegateFlowLayout>
- (instancetype)initWithRecords:(NSArray *)records selected:(NSInteger)selected bridge:(DGBridge *)bridge;
@end
@implementation DGFeed {
    douglass::Feed _feed;
    NSMutableArray *_records;
    DGBridge *_bridge;
    UICollectionView *_collection;
    UIVisualEffectView *_bar;UISegmentedControl *_navigationTabs;NSMutableSet *_locationRequested;
    UIButton *_settings,*_recommend,*_follow,*_search,*_messages,*_account,*_back;
    DGImage *_accountImage;
    UILabel *_state,*_subtitle;
    UIStackView *_empty;
    UIButton *_retry,*_login;
    UIActivityIndicatorView *_spinner;
    UIRefreshControl *_pull;
    DGComments *_comments,*_retainedComments;NSString *_retainedCommentWorkID;
    UIView *_commentHost;
    NSDictionary *_profile;
    NSString *_operation,*_cursor;
    BOOL _loading,_foreground,_failed,_ownsBridge,_staticFeed,_positioned,_relayout,_visible,_commentTransition,_closingComments;
    NSInteger _refreshIndex,_emptyPages,_selected,_current;
    NSUInteger _generation;
}
- (instancetype)init {if((self=[super init])){_ownsBridge=YES;_operation=@"feed";_records=[NSMutableArray array];_cursor=@"0";}return self;}
- (instancetype)initWithRecords:(NSArray *)records selected:(NSInteger)selected bridge:(DGBridge *)bridge {
    if((self=[self init])){_bridge=bridge;_ownsBridge=NO;_staticFeed=YES;_selected=selected;[_records addObjectsFromArray:records];std::vector<Work> works;for(NSDictionary *record in records)works.push_back(ReadWork(record));_feed.append(std::move(works),false,true);_feed.more=false;}return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.blackColor;self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;_foreground=YES;_refreshIndex=1;_locationRequested=[NSMutableSet set];DGInstallBackGesture(self);
    UICollectionViewFlowLayout *layout=[UICollectionViewFlowLayout new];layout.minimumLineSpacing=0;layout.minimumInteritemSpacing=0;
    _collection=[[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];_collection.backgroundColor=UIColor.blackColor;_collection.pagingEnabled=YES;_collection.showsVerticalScrollIndicator=NO;_collection.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;_collection.dataSource=self;_collection.delegate=self;_collection.alwaysBounceVertical=YES;
    [_collection registerClass:DGFeedCell.class forCellWithReuseIdentifier:@"work"];[self.view addSubview:_collection];
    if(!_staticFeed){_pull=[UIRefreshControl new];_pull.tintColor=UIColor.whiteColor;[_pull addTarget:self action:@selector(refreshFeed) forControlEvents:UIControlEventValueChanged];_collection.refreshControl=_pull;}
    if(_ownsBridge){_bridge=[DGBridge new];[_bridge mount:self.view];}
    _bar=Glass(27);[self.view addSubview:_bar];_settings=Symbol(@"gearshape",self,@selector(settings));
    _follow=[UIButton buttonWithType:UIButtonTypeSystem];[_follow setTitle:@"关注" forState:UIControlStateNormal];_follow.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];[_follow addTarget:self action:@selector(followFeed) forControlEvents:UIControlEventTouchUpInside];[_follow addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(followList:)]];
    _recommend=[UIButton buttonWithType:UIButtonTypeSystem];[_recommend setTitle:@"推荐" forState:UIControlStateNormal];_recommend.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];[_recommend addTarget:self action:@selector(recommend) forControlEvents:UIControlEventTouchUpInside];
    _search=Symbol(@"magnifyingglass",self,@selector(search));_messages=Symbol(@"bubble.left.and.bubble.right",self,@selector(messages));_account=Symbol(@"person.crop.circle",self,@selector(account));
    _accountImage=[DGImage new];_accountImage.contentMode=UIViewContentModeScaleAspectFill;_accountImage.layer.cornerRadius=16;_accountImage.clipsToBounds=YES;_accountImage.userInteractionEnabled=NO;[_account addSubview:_accountImage];
    _settings.hidden=YES;_navigationTabs=[[UISegmentedControl alloc]initWithItems:@[@"关注",@"推荐",@"信息"]];_navigationTabs.selectedSegmentIndex=1;_navigationTabs.backgroundColor=UIColor.clearColor;[_navigationTabs addTarget:self action:@selector(navigationChanged:) forControlEvents:UIControlEventValueChanged];[_navigationTabs addGestureRecognizer:[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(navigationHold:)]];UITapGestureRecognizer *navigationTap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(navigationTap:)];navigationTap.cancelsTouchesInView=NO;[_navigationTabs addGestureRecognizer:navigationTap];[_bar.contentView addSubview:_navigationTabs];[self.view addSubview:_account];[self.view addSubview:_search];
    if(_staticFeed){_bar.hidden=YES;_account.hidden=YES;_search.hidden=YES;_back=Symbol(@"chevron.left",self,@selector(close));[self.view addSubview:_back];}
    _spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];_spinner.color=UIColor.secondaryLabelColor;_state=Label(20,UIFontWeightSemibold);_state.textAlignment=NSTextAlignmentCenter;_subtitle=Label(14,UIFontWeightRegular);_subtitle.numberOfLines=0;_subtitle.textAlignment=NSTextAlignmentCenter;_subtitle.textColor=UIColor.secondaryLabelColor;
    _retry=[UIButton buttonWithType:UIButtonTypeSystem];[_retry setTitle:@"重新加载" forState:UIControlStateNormal];[_retry addTarget:self action:@selector(refreshFeed) forControlEvents:UIControlEventTouchUpInside];_login=[UIButton buttonWithType:UIButtonTypeSystem];[_login setTitle:@"登录 / 网页验证" forState:UIControlStateNormal];[_login addTarget:self action:@selector(openLogin) forControlEvents:UIControlEventTouchUpInside];
    _empty=[[UIStackView alloc] initWithArrangedSubviews:@[_spinner,_state,_subtitle,_retry,_login]];_empty.axis=UILayoutConstraintAxisVertical;_empty.spacing=18;_empty.alignment=UIStackViewAlignmentCenter;[self.view addSubview:_empty];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background) name:UIApplicationDidEnterBackgroundNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground) name:UIApplicationDidBecomeActiveNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resume) name:@"DGResumePlayback" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(workStateChanged:) name:@"DouGlassWorkStateChanged" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(playbackPreferencesChanged) name:@"DGPlaybackQualityChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(filtersChanged) name:@"DGFiltersChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accountChanged) name:@"DGAccountChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resume) name:@"DGMusicStateChanged" object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(verificationCompleted:) name:@"DGVerificationCompleted" object:nil];if(_staticFeed)[self updateEmpty:nil];else{[self loadFeed:YES];[self loadProfile];}
}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (UIStatusBarStyle)preferredStatusBarStyle{return UIStatusBarStyleLightContent;}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];if(!self.presentedViewController)DGMusicStop();_visible=YES;_navigationTabs.selectedSegmentIndex=[_operation isEqualToString:@"followFeed"]?0:1;[self activate];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];if(DGOptionsKeepsPlayback(self.presentedViewController))return;_visible=NO;for(DGFeedCell *cell in _collection.visibleCells)[cell active:NO];}
- (void)viewDidLayoutSubviews {
 [super viewDidLayoutSubviews];CGSize size=self.view.bounds.size;CGFloat top=self.view.safeAreaInsets.top;
 if(!CGSizeEqualToSize(_collection.bounds.size,size)){_relayout=YES;_collection.frame=self.view.bounds;[_collection.collectionViewLayout invalidateLayout];[_collection layoutIfNeeded];[_collection setContentOffset:CGPointMake(0,MAX(0,_current)*size.height) animated:NO];_relayout=NO;}
 CGFloat panel=_comments?MIN(size.height*.64,size.height-top-150):0;CGFloat media=size.height-panel;
 _commentHost.bounds=CGRectMake(0,0,size.width,MAX(0,panel));_commentHost.center=CGPointMake(size.width/2,media+MAX(0,panel)/2);_comments.view.frame=_commentHost.bounds;
 CGFloat w=MIN(size.width-136,330);_bar.frame=CGRectMake((size.width-w)/2,top+7,w,48);_account.frame=CGRectMake(14,top+7,44,48);_navigationTabs.frame=CGRectMake(5,6,w-10,36);_search.frame=CGRectMake(size.width-58,top+7,44,48);
 _accountImage.frame=CGRectMake((_account.bounds.size.width-32)/2,8,32,32);_back.frame=CGRectMake(12,top+4,44,44);_empty.frame=CGRectMake(28,media/2-90,size.width-56,230);_subtitle.preferredMaxLayoutWidth=MIN(size.width-56,420);
 _follow.tintColor=[_operation isEqualToString:@"followFeed"]?UIColor.whiteColor:UIColor.secondaryLabelColor;_recommend.tintColor=[_operation isEqualToString:@"feed"]?UIColor.whiteColor:UIColor.secondaryLabelColor;
 if(_staticFeed&&!_positioned&&!_feed.works.empty()){_positioned=YES;_current=MAX(0,MIN(_selected,(NSInteger)_feed.works.size()-1));[_collection setContentOffset:CGPointMake(0,_current*size.height) animated:NO];}
 __weak DGFeed *weak=self;for(DGFeedCell *cell in self->_collection.visibleCells){BOOL compact=self->_comments&&!self->_closingComments;if(compact)cell.dismissCommentsAction=^{[weak closeComments];};else cell.dismissCommentsAction=nil;[cell compact:compact];[cell mediaHeight:compact?media:0];[cell layoutIfNeeded];}
}
- (void)background{_foreground=NO;DGSessionCapture(nil);[self activate];}
- (void)foreground{_foreground=YES;[self activate];}
- (void)resume{dispatch_async(dispatch_get_main_queue(),^{[self activate];});}
- (void)workStateChanged:(NSNotification *)notification {
    NSDictionary *state=notification.userInfo;std::string identifier=String(state[@"id"]);if(identifier.empty())return;
    for(Work &work:_feed.works)if(work.id==identifier){work.liked=[state[@"liked"] boolValue];work.collected=[state[@"collected"] boolValue];work.likes=Number(state[@"likes"]);work.collects=Number(state[@"collects"]);}
    for(NSUInteger index=0;index<_records.count;index++){NSDictionary *record=_records[index];if(String(record[@"id"])!=identifier)continue;NSMutableDictionary *updated=[record mutableCopy];for(NSString *key in @[@"liked",@"collected",@"likes",@"collects"])if(state[key])updated[key]=state[key];_records[index]=updated;}
}
- (void)close{[self dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];}
- (void)updateEmpty:(NSString *)message {_empty.hidden=!_feed.works.empty();_state.text=_loading?@"让喜欢的内容，流进来":@"暂时没有新内容";_subtitle.text=message?:@"视频与图文推荐 · 登录后使用你的抖音账号";_state.hidden=_loading;_subtitle.hidden=_loading;_retry.hidden=_loading;_login.hidden=_loading;if(_loading)[_spinner startAnimating];else[_spinner stopAnimating];}
- (void)navigationChanged:(UISegmentedControl *)tabs{if(tabs.selectedSegmentIndex==0)[self followFeed];else if(tabs.selectedSegmentIndex==1)[self recommend];else [self messages];}
- (void)navigationHold:(UILongPressGestureRecognizer *)gesture{if([gesture locationInView:_navigationTabs].x<_navigationTabs.bounds.size.width/3)[self followList:gesture];}
- (void)navigationTap:(UITapGestureRecognizer *)gesture{CGFloat x=[gesture locationInView:_navigationTabs].x,w=_navigationTabs.bounds.size.width;if(x>=w/3&&x<w*2/3&&[_operation isEqualToString:@"feed"]&&_navigationTabs.selectedSegmentIndex==1)[self refreshFeed];}
- (void)resolveIP{
 if(!_foreground||!_visible||_current<0||_current>=(NSInteger)_feed.works.size())return;const Work &work=_feed.works[_current];if(work.authorID.empty()||(work.locationKind=="IP属地"&&work.location.find("·")!=std::string::npos))return;NSString *sec=Text(work.authorID),*identifier=Text(work.id);if([_locationRequested containsObject:sec])return;[_locationRequested addObject:sec];NSUInteger generation=_generation;__weak DGFeed *weak=self;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{DGFeed *self=weak;if(!self||generation!=self->_generation||self->_current>=(NSInteger)self->_feed.works.size()||Text(self->_feed.works[self->_current].id).length==0||self->_feed.works[self->_current].id!=String(identifier)){if(self)[self->_locationRequested removeObject:sec];return;}
 [self->_bridge request:@"userLocation" parameters:@{@"sec":sec} completion:^(NSDictionary *result,NSString *error){DGFeed *self=weak;if(!self||generation!=self->_generation||error)return;NSString *location=Text(String(result[@"location"]));if(!location.length)return;for(NSUInteger i=0;i<self->_feed.works.size();i++){Work &work=self->_feed.works[i];if(work.authorID!=String(sec))continue;work.location=String(location);work.locationKind="IP属地";if(i<self->_records.count){NSMutableDictionary *record=[self->_records[i]mutableCopy];record[@"location"]=location;record[@"locationKind"]=@"IP属地";self->_records[i]=record;}DGFeedCell *cell=(DGFeedCell *)[self->_collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:i inSection:0]];if(cell)[cell display:work];}}];
 });
}
- (void)recommend{if(![_operation isEqualToString:@"feed"]){_operation=@"feed";[self resetChannel];}else[self refreshFeed];}
- (void)followFeed{if(![_operation isEqualToString:@"followFeed"]){_operation=@"followFeed";[self resetChannel];}else[self refreshFeed];}
- (void)resetChannel{_retainedComments=nil;_retainedCommentWorkID=nil;++_generation;_loading=NO;[self closeComments];for(DGFeedCell *cell in _collection.visibleCells)[cell active:NO];_feed.clear();[_records removeAllObjects];[_collection reloadData];_current=0;_cursor=@"0";_refreshIndex=1;_emptyPages=0;[self loadFeed:YES];[self.view setNeedsLayout];}
- (void)refreshFeed{if(_staticFeed||_loading){[_pull endRefreshing];return;}_retainedComments=nil;_retainedCommentWorkID=nil;[self closeComments];if(_failed)[_bridge reload];_refreshIndex=1;_cursor=@"0";_emptyPages=0;[self loadFeed:YES];}
- (void)loadFeed:(BOOL)replace {
    if(_staticFeed||_loading||(!replace&&!_feed.more))return;_loading=YES;_failed=NO;[self updateEmpty:nil];NSUInteger generation=_generation;__weak DGFeed *weakSelf=self;
    [_bridge request:_operation parameters:@{@"refresh":@(_refreshIndex++),@"cursor":_cursor?:@"0"} completion:^(NSDictionary *result,NSString *error){DGFeed *self=weakSelf;if(!self||generation!=self->_generation)return;self->_loading=NO;[self->_pull endRefreshing];
        if(error){self->_failed=YES;[self updateEmpty:error];if(!self->_feed.works.empty())DGToast(self,error);return;}
        std::vector<Work> works;NSMutableArray *fresh=[NSMutableArray array];std::unordered_set<std::string> ids;if(!replace)for(const Work &work:self->_feed.works)ids.insert(work.id);
        for(NSDictionary *record in Array(result[@"items"])){Work work=ReadWork(record);if(work.playable()&&DGContentAllowed(work)&&ids.insert(work.id).second){works.push_back(work);[fresh addObject:record];}}
        NSUInteger before=self->_feed.works.size();std::size_t added=self->_feed.append(std::move(works),[result[@"more"] boolValue],replace);if(replace){[self->_records removeAllObjects];self->_current=0;}[self->_records addObjectsFromArray:fresh];self->_cursor=[result[@"cursor"] description]?:@"0";self->_emptyPages=added?0:self->_emptyPages+1;if(self->_emptyPages>=3)self->_feed.more=false;
        if(replace){[self->_collection reloadData];[self->_collection setContentOffset:CGPointZero animated:NO];}else if(added){NSMutableArray *paths=[NSMutableArray array];for(NSUInteger i=before;i<before+added;i++)[paths addObject:[NSIndexPath indexPathForItem:i inSection:0]];[self->_collection insertItemsAtIndexPaths:paths];}
        [self updateEmpty:nil];DGWarmWorks(self->_feed.works,self->_current);dispatch_async(dispatch_get_main_queue(),^{[self activate];});if(self->_feed.works.empty()&&self->_feed.more)[self loadFeed:NO];
    }];
}
- (void)loadProfile{NSUInteger generation=_generation;__weak DGFeed *weakSelf=self;[_bridge request:@"profile" parameters:@{} completion:^(NSDictionary *result,NSString *error){DGFeed *self=weakSelf;if(!self||generation!=self->_generation)return;if(error){return;}self->_profile=result;DGSeenScope(Text(String(result[@"uid"])));[self activate];NSString *avatar=[result[@"avatar"] isKindOfClass:NSString.class]?result[@"avatar"]:@"";self->_accountImage.hidden=![result[@"loggedIn"] boolValue]||!avatar.length;[self->_accountImage remote:avatar];[self->_account setImage:self->_accountImage.hidden?[UIImage systemImageNamed:@"person.crop.circle"]:nil forState:UIControlStateNormal];}];}
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section{return _feed.works.size();}
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path{return collectionView.bounds.size;}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)path {
    DGFeedCell *cell=[collectionView dequeueReusableCellWithReuseIdentifier:@"work" forIndexPath:path];cell.bridge=_bridge;cell.presenter=self;const Work &work=_feed.works[path.item];[cell display:work];[cell compact:_comments!=nil];NSString *workID=Text(work.id),*sec=Text(work.authorID),*name=Text(work.author);NSDictionary *record=path.item<(NSInteger)_records.count?_records[path.item]:@{};__weak DGFeed *weakSelf=self;
    __weak DGFeedCell *weakCell=cell;cell.moreAction=^{DGFeed *self=weakSelf;if(!self||self.presentedViewController)return;NSMutableDictionary *options=[record mutableCopy];options[@"selectedImage"]=[weakCell selectedImageURL]?:@"";[self presentViewController:DGMakeOptions(self->_bridge,options) animated:YES completion:nil];};cell.actionMenuAction=^(CGPoint point){DGFeed *self=weakSelf;if(!self||self.presentedViewController)return;NSMutableDictionary *options=[record mutableCopy];options[@"selectedImage"]=[weakCell selectedImageURL]?:@"";options[@"menuOrigin"]=[NSValue valueWithCGPoint:[weakCell.contentView convertPoint:point toView:self.view]];[self presentViewController:DGMakeActions(self->_bridge,options) animated:YES completion:nil];};cell.advanceAction=^BOOL{return [weakSelf advanceWork];};cell.commentsAction=^{[weakSelf showComments:workID];};cell.profileAction=^{DGFeed *self=weakSelf;if(self)[self presentPage:DGMakeProfile(self->_bridge,sec,name,workID)];};
    cell.musicAction=^{DGFeed *self=weakSelf;if(self)[self presentPage:DGMakeMusic(self->_bridge,@{@"id":record[@"musicID"]?:@"",@"url":record[@"music"]?:@"",@"title":record[@"musicTitle"]?:@"作品原声",@"author":record[@"musicAuthor"]?:@"",@"cover":record[@"avatar"]?:@"",@"collected":record[@"musicCollected"]?:@NO})];};return cell;
}
- (void)activate{if(_relayout)return;CGFloat h=_collection.bounds.size.height;if(h<=0)return;_current=MAX(0,(NSInteger)llround(_collection.contentOffset.y/h));if(_retainedCommentWorkID.length&&(_current>=(NSInteger)_feed.works.size()||![_retainedCommentWorkID isEqualToString:Text(_feed.works[_current].id)])){_retainedComments=nil;_retainedCommentWorkID=nil;}BOOL allowed=(_foreground||DGBackgroundAudioEnabled()||[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.pip"])&&_visible&&self.view.window&&(self.presentedViewController==nil||DGOptionsKeepsPlayback(self.presentedViewController))&&DGMusicPlayer()==nil;for(DGFeedCell *cell in _collection.visibleCells){[cell backgroundAudio:!_foreground&&DGBackgroundAudioEnabled()];[cell active:allowed&&[_collection indexPathForCell:cell].item==_current];}if(allowed&&_foreground&&!_failed&&!_loading&&_feed.more&&!_feed.works.empty()&&_current+5>=(NSInteger)_feed.works.size())[self loadFeed:NO];if(allowed&&_foreground&&!_collection.dragging&&!_collection.decelerating){DGWarmWorks(_feed.works,_current);if(_current<(NSInteger)_feed.works.size())DGMarkSeen(Text(_feed.works[_current].id));[self resolveIP];}}
- (BOOL)advanceWork{if(_comments||_commentTransition||self.presentedViewController)return NO;NSInteger next=_current+1;if(next>=(NSInteger)_feed.works.size()){if(_feed.more)[self loadFeed:NO];return NO;}[_collection scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:next inSection:0] atScrollPosition:UICollectionViewScrollPositionCenteredVertically animated:YES];return YES;}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView{[self activate];}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView{DGWarmWorks(_feed.works,_current);[self activate];}
- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)path{[(DGFeedCell *)cell active:NO];}
- (void)showComments:(NSString *)workID {
 if(_commentTransition)return;_closingComments=NO;if(_comments){[self closeComments];return;}_commentTransition=YES;
 _comments=[_retainedCommentWorkID isEqualToString:workID]?_retainedComments:nil;if(!_comments)_comments=[[DGComments alloc]initWithBridge:_bridge work:workID parent:nil];_retainedComments=_comments;_retainedCommentWorkID=workID.copy;if(_current<(NSInteger)_records.count){NSDictionary *record=_records[_current];_comments.coverURL=Text(String(record[@"cover"]));if(!_comments.coverURL.length)_comments.coverURL=Text(String(Array(record[@"images"]).firstObject));}__weak DGFeed *weak=self;_comments.closeAction=^{[weak closeComments];};_comments.profileAction=^(NSString *sec,NSString *name){DGFeed *self=weak;if(self)[self presentPage:DGMakeProfile(self->_bridge,sec,name,@"")];};
 [self addChildViewController:_comments];_commentHost=[UIView new];_commentHost.layer.cornerRadius=30;_commentHost.clipsToBounds=YES;[self.view addSubview:_commentHost];[_commentHost addSubview:_comments.view];[_comments didMoveToParentViewController:self];_collection.scrollEnabled=NO;
 [UIView performWithoutAnimation:^{[self.view setNeedsLayout];[self.view layoutIfNeeded];[self->_comments restorePosition];}];_commentHost.transform=CGAffineTransformMakeTranslation(0,_commentHost.bounds.size.height+10);
 [UIView animateWithDuration:.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut|UIViewAnimationOptionBeginFromCurrentState animations:^{self->_commentHost.transform=CGAffineTransformIdentity;} completion:^(BOOL done){self->_commentTransition=NO;[self activate];}];
}
- (void)closeComments {
 if(!_comments||_commentTransition)return;[_comments rememberPosition];_commentTransition=YES;_closingComments=YES;[self.view setNeedsLayout];[self.view layoutIfNeeded];UIView *panel=_commentHost;
 [UIView animateWithDuration:.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut|UIViewAnimationOptionBeginFromCurrentState animations:^{panel.transform=CGAffineTransformMakeTranslation(0,panel.bounds.size.height+10);} completion:^(BOOL done){[self->_comments willMoveToParentViewController:nil];[self->_comments.view removeFromSuperview];[self->_comments removeFromParentViewController];self->_comments=nil;[panel removeFromSuperview];self->_commentHost=nil;self->_collection.scrollEnabled=YES;self->_commentTransition=NO;self->_closingComments=NO;[UIView performWithoutAnimation:^{[self.view setNeedsLayout];[self.view layoutIfNeeded];}];[self activate];}];
}
- (void)verificationCompleted:(NSNotification *)note{if(!_ownsBridge)return;_failed=NO;[self loadProfile];if([note.userInfo[@"operation"]isEqualToString:_operation]&&!_loading)[self loadFeed:YES];}
- (void)accountChanged{[self sessionChanged:NO];}
- (void)playbackPreferencesChanged{DGClearPlayers();for(NSUInteger index=0;index<_records.count&&index<_feed.works.size();index++){Work work=ReadWork(_records[index]);_feed.works[index]=work;DGFeedCell *cell=(DGFeedCell *)[_collection cellForItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0]];if(cell)[cell display:work];}DGWarmWorks(_feed.works,_current);}
- (void)filtersChanged{
 if(_staticFeed||_feed.works.empty())return;std::vector<Work> kept;NSMutableArray *records=[NSMutableArray array],*deleted=[NSMutableArray array];
 for(NSUInteger index=0;index<_feed.works.size();index++){const Work &work=_feed.works[index];if((NSInteger)index<=_current||DGContentAllowed(work)){kept.push_back(work);if(index<_records.count)[records addObject:_records[index]];}else [deleted addObject:[NSIndexPath indexPathForItem:index inSection:0]];}
 if(!deleted.count)return;BOOL more=_feed.more;_feed.append(std::move(kept),more,true);_records=records;[_collection deleteItemsAtIndexPaths:deleted];[self activate];
}
- (void)presentPage:(UIViewController *)page{if(!page||self.presentedViewController)return;for(DGFeedCell *cell in _collection.visibleCells)[cell active:NO];UINavigationController *nav=[[DGNavigationController alloc] initWithRootViewController:page];DGConfigurePageTransition(nav);nav.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[self presentViewController:nav animated:YES completion:nil];}
- (void)search{[self presentPage:DGMakeSearch(_bridge)];}
- (void)messages{[self presentPage:DGMakeMessages(_bridge)];}
- (void)account{if(![_profile[@"loggedIn"] boolValue]){[self openLogin];return;}[self presentPage:DGMakeProfile(_bridge,@"",_profile[@"nickname"]?:@"我的",@"")];}
- (void)followList:(UILongPressGestureRecognizer *)gesture{if(gesture.state!=UIGestureRecognizerStateBegan)return;extern UIViewController *DGMakeFollowing(DGBridge *,NSString *,NSString *);[self presentPage:DGMakeFollowing(_bridge,_profile[@"sec"]?:@"",_profile[@"uid"]?:@"")];}
- (void)settings {
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"澄流 · 设置" message:@"长按视频固定 2×，松手恢复 1×\n长按关注可查看关注列表" preferredStyle:UIAlertControllerStyleActionSheet];BOOL enabled=[NSUserDefaults.standardUserDefaults objectForKey:@"douglass.danmaku"]?[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.danmaku"]:YES;
    [menu addAction:[UIAlertAction actionWithTitle:enabled?@"关闭视频弹幕":@"开启视频弹幕" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[NSUserDefaults.standardUserDefaults setBool:!enabled forKey:@"douglass.danmaku"];[NSNotificationCenter.defaultCenter postNotificationName:@"DouGlassSettingsChanged" object:nil];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"登录 / 安全验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self openLogin];}]];[menu addAction:[UIAlertAction actionWithTitle:@"退出当前账号" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){[self->_bridge signOut:^{[self sessionChanged:NO];}];}]];[menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];menu.popoverPresentationController.sourceView=_settings;menu.popoverPresentationController.sourceRect=_settings.bounds;[self presentViewController:menu animated:YES completion:nil];
}
- (void)openLogin{if(self.presentedViewController)return;for(DGFeedCell *cell in _collection.visibleCells)[cell active:NO];DGLogin *login=[DGLogin new];__weak DGFeed *weakSelf=self;login.finished=^{[weakSelf sessionChanged:YES];};UINavigationController *nav=[[DGNavigationController alloc] initWithRootViewController:login];DGConfigurePageTransition(nav);[self presentViewController:nav animated:YES completion:nil];}
- (void)sessionChanged:(BOOL)reload{_retainedComments=nil;_retainedCommentWorkID=nil;++_generation;[_locationRequested removeAllObjects];_loading=NO;_failed=NO;_profile=nil;[self closeComments];DGClearPlayers();DGMusicStop();DGResetInteractions();DGResetMusicPages();_feed.clear();[_records removeAllObjects];[_collection reloadData];_refreshIndex=1;_cursor=@"0";_emptyPages=0;_current=0;if(reload)[_bridge reload];DGSeenScope(@"");[self loadFeed:YES];[self loadProfile];}
@end
UIViewController *DGMakeFeedController(void){return [DGFeed new];}
UIViewController *DGMakeWorkPlayer(NSArray<NSDictionary *> *works,NSInteger selected,DGBridge *bridge){return [[DGFeed alloc] initWithRecords:works selected:selected bridge:bridge];}

