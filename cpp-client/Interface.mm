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
    UIVisualEffectView *_bar;
    UIButton *_settings,*_recommend,*_follow,*_search,*_messages,*_account,*_back;
    DGImage *_accountImage;
    UILabel *_state,*_subtitle;
    UIStackView *_empty;
    UIButton *_retry,*_login;
    UIActivityIndicatorView *_spinner;
    UIRefreshControl *_pull;
    DGComments *_comments;
    UIView *_commentHost;
    NSDictionary *_profile;
    NSString *_operation,*_cursor;
    BOOL _loading,_foreground,_failed,_ownsBridge,_staticFeed,_positioned,_relayout,_visible;
    NSInteger _refreshIndex,_emptyPages,_selected,_current;
    NSUInteger _generation;
}
- (instancetype)init {if((self=[super init])){_ownsBridge=YES;_operation=@"feed";_records=[NSMutableArray array];_cursor=@"0";}return self;}
- (instancetype)initWithRecords:(NSArray *)records selected:(NSInteger)selected bridge:(DGBridge *)bridge {
    if((self=[self init])){_bridge=bridge;_ownsBridge=NO;_staticFeed=YES;_selected=selected;[_records addObjectsFromArray:records];std::vector<Work> works;for(NSDictionary *record in records)works.push_back(ReadWork(record));_feed.append(std::move(works),false,true);_feed.more=false;}return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.blackColor;self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;_foreground=YES;_refreshIndex=1;
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
    for(UIView *view in @[_settings,_follow,_recommend,_search,_messages,_account])[_bar.contentView addSubview:view];
    if(_staticFeed){_bar.hidden=YES;_back=Symbol(@"chevron.left",self,@selector(close));[self.view addSubview:_back];}
    _spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];_state=Label(20,UIFontWeightSemibold);_state.textAlignment=NSTextAlignmentCenter;_subtitle=Label(14,UIFontWeightRegular);_subtitle.numberOfLines=0;_subtitle.textAlignment=NSTextAlignmentCenter;_subtitle.textColor=UIColor.secondaryLabelColor;
    _retry=[UIButton buttonWithType:UIButtonTypeSystem];[_retry setTitle:@"重新加载" forState:UIControlStateNormal];[_retry addTarget:self action:@selector(refreshFeed) forControlEvents:UIControlEventTouchUpInside];_login=[UIButton buttonWithType:UIButtonTypeSystem];[_login setTitle:@"登录 / 网页验证" forState:UIControlStateNormal];[_login addTarget:self action:@selector(openLogin) forControlEvents:UIControlEventTouchUpInside];
    _empty=[[UIStackView alloc] initWithArrangedSubviews:@[_spinner,_state,_subtitle,_retry,_login]];_empty.axis=UILayoutConstraintAxisVertical;_empty.spacing=18;_empty.alignment=UIStackViewAlignmentCenter;[self.view addSubview:_empty];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background) name:UIApplicationWillResignActiveNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground) name:UIApplicationDidBecomeActiveNotification object:nil];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resume) name:@"DGResumePlayback" object:nil];
    if(_staticFeed)[self updateEmpty:nil];else{[self loadFeed:YES];[self loadProfile];}
}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
- (UIStatusBarStyle)preferredStatusBarStyle{return UIStatusBarStyleLightContent;}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];_visible=YES;[self activate];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];_visible=NO;for(DGFeedCell *cell in _collection.visibleCells)[cell active:NO];}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];CGSize size=self.view.bounds.size;CGFloat top=self.view.safeAreaInsets.top;CGFloat panel=_comments?MIN(size.height*.58,size.height-top-170):0;CGFloat h=size.height-panel;
    if(!CGSizeEqualToSize(_collection.bounds.size,CGSizeMake(size.width,h))){_relayout=YES;_collection.frame=CGRectMake(0,0,size.width,h);[_collection.collectionViewLayout invalidateLayout];[_collection layoutIfNeeded];[_collection setContentOffset:CGPointMake(0,MAX(0,_current)*h) animated:NO];_relayout=NO;}
    _commentHost.frame=CGRectMake(8,h,size.width-16,panel-6);_comments.view.frame=_commentHost.bounds;
    CGFloat w=MIN(size.width-28,510),unit=(w-16)/6;_bar.frame=CGRectMake((size.width-w)/2,top+7,w,52);NSArray *buttons=@[_settings,_follow,_recommend,_search,_messages,_account];for(NSUInteger i=0;i<buttons.count;i++)((UIView *)buttons[i]).frame=CGRectMake(8+i*unit,0,unit,52);
    _accountImage.frame=CGRectMake((_account.bounds.size.width-32)/2,10,32,32);_back.frame=CGRectMake(12,top+4,44,44);_empty.frame=CGRectMake(28,h/2-90,size.width-56,230);_subtitle.preferredMaxLayoutWidth=MIN(size.width-56,420);
    _follow.tintColor=[_operation isEqualToString:@"followFeed"]?UIColor.whiteColor:UIColor.secondaryLabelColor;_recommend.tintColor=[_operation isEqualToString:@"feed"]?UIColor.whiteColor:UIColor.secondaryLabelColor;
    if(_staticFeed&&!_positioned&&!_feed.works.empty()){_positioned=YES;_current=MAX(0,MIN(_selected,(NSInteger)_feed.works.size()-1));[_collection setContentOffset:CGPointMake(0,_current*h) animated:NO];}
    for(DGFeedCell *cell in _collection.visibleCells)[cell compact:_comments!=nil];
}
- (void)background{_foreground=NO;[self activate];}
- (void)foreground{_foreground=YES;[self activate];}
- (void)resume{dispatch_async(dispatch_get_main_queue(),^{[self activate];});}
- (void)close{[self dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];}
- (void)updateEmpty:(NSString *)message {_empty.hidden=!_feed.works.empty();_state.text=_loading?@"让喜欢的内容，流进来":@"暂时没有新内容";_subtitle.text=message?:@"视频与图文推荐 · 登录后使用你的抖音账号";_retry.hidden=_loading;_login.hidden=_loading;if(_loading)[_spinner startAnimating];else[_spinner stopAnimating];}
- (void)recommend{if(![_operation isEqualToString:@"feed"]){_operation=@"feed";[self resetChannel];}else[self refreshFeed];}
- (void)followFeed{if(![_operation isEqualToString:@"followFeed"]){_operation=@"followFeed";[self resetChannel];}else[self refreshFeed];}
- (void)resetChannel{++_generation;_loading=NO;[self closeComments];for(DGFeedCell *cell in _collection.visibleCells)[cell active:NO];_feed.clear();[_records removeAllObjects];[_collection reloadData];_current=0;_cursor=@"0";_refreshIndex=1;_emptyPages=0;[self loadFeed:YES];[self.view setNeedsLayout];}
- (void)refreshFeed{if(_staticFeed||_loading){[_pull endRefreshing];return;}[self closeComments];if(_failed)[_bridge reload];_refreshIndex=1;_cursor=@"0";_emptyPages=0;[self loadFeed:YES];}
- (void)loadFeed:(BOOL)replace {
    if(_staticFeed||_loading||(!replace&&!_feed.more))return;_loading=YES;_failed=NO;[self updateEmpty:nil];NSUInteger generation=_generation;__weak DGFeed *weakSelf=self;
    [_bridge request:_operation parameters:@{@"refresh":@(_refreshIndex++),@"cursor":_cursor?:@"0"} completion:^(NSDictionary *result,NSString *error){DGFeed *self=weakSelf;if(!self||generation!=self->_generation)return;self->_loading=NO;[self->_pull endRefreshing];
        if(error){self->_failed=YES;[self updateEmpty:error];if(!self->_feed.works.empty())DGToast(self,error);return;}
        std::vector<Work> works;NSMutableArray *fresh=[NSMutableArray array];std::unordered_set<std::string> ids;if(!replace)for(const Work &work:self->_feed.works)ids.insert(work.id);
        for(NSDictionary *record in Array(result[@"items"])){Work work=ReadWork(record);if(work.playable()&&ids.insert(work.id).second){works.push_back(work);[fresh addObject:record];}}
        NSUInteger before=self->_feed.works.size();std::size_t added=self->_feed.append(std::move(works),[result[@"more"] boolValue],replace);if(replace){[self->_records removeAllObjects];self->_current=0;}[self->_records addObjectsFromArray:fresh];self->_cursor=[result[@"cursor"] description]?:@"0";self->_emptyPages=added?0:self->_emptyPages+1;if(self->_emptyPages>=3)self->_feed.more=false;
        if(replace){[self->_collection reloadData];[self->_collection setContentOffset:CGPointZero animated:NO];}else if(added){NSMutableArray *paths=[NSMutableArray array];for(NSUInteger i=before;i<before+added;i++)[paths addObject:[NSIndexPath indexPathForItem:i inSection:0]];[self->_collection insertItemsAtIndexPaths:paths];}
        [self updateEmpty:nil];DGWarmWorks(self->_feed.works,self->_current);dispatch_async(dispatch_get_main_queue(),^{[self activate];});if(self->_feed.works.empty()&&self->_feed.more)[self loadFeed:NO];
    }];
}
- (void)loadProfile{NSUInteger generation=_generation;__weak DGFeed *weakSelf=self;[_bridge request:@"profile" parameters:@{} completion:^(NSDictionary *result,NSString *error){DGFeed *self=weakSelf;if(!self||generation!=self->_generation)return;self->_profile=error?nil:result;NSString *avatar=[result[@"avatar"] isKindOfClass:NSString.class]?result[@"avatar"]:@"";self->_accountImage.hidden=![result[@"loggedIn"] boolValue]||!avatar.length;[self->_accountImage remote:avatar];[self->_account setImage:self->_accountImage.hidden?[UIImage systemImageNamed:@"person.crop.circle"]:nil forState:UIControlStateNormal];}];}
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section{return _feed.works.size();}
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path{return collectionView.bounds.size;}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)path {
    DGFeedCell *cell=[collectionView dequeueReusableCellWithReuseIdentifier:@"work" forIndexPath:path];cell.bridge=_bridge;cell.presenter=self;const Work &work=_feed.works[path.item];[cell display:work];[cell compact:_comments!=nil];NSString *workID=Text(work.id),*sec=Text(work.authorID),*name=Text(work.author);NSDictionary *record=path.item<(NSInteger)_records.count?_records[path.item]:@{};__weak DGFeed *weakSelf=self;
    cell.commentsAction=^{[weakSelf showComments:workID];};cell.profileAction=^{DGFeed *self=weakSelf;if(self)[self presentPage:DGMakeProfile(self->_bridge,sec,name,workID)];};
    cell.musicAction=^{DGFeed *self=weakSelf;if(self)[self presentPage:DGMakeMusic(self->_bridge,@{@"id":record[@"musicID"]?:@"",@"url":record[@"music"]?:@"",@"title":record[@"musicTitle"]?:@"作品原声",@"author":record[@"musicAuthor"]?:@"",@"cover":record[@"avatar"]?:@""})];};return cell;
}
- (void)activate{if(_relayout)return;CGFloat h=_collection.bounds.size.height;if(h<=0)return;_current=MAX(0,(NSInteger)llround(_collection.contentOffset.y/h));BOOL allowed=_foreground&&_visible&&self.view.window&&self.presentedViewController==nil;for(DGFeedCell *cell in _collection.visibleCells)[cell active:allowed&&[_collection indexPathForCell:cell].item==_current];if(!_failed&&!_loading&&_feed.more&&!_feed.works.empty()&&_current+5>=(NSInteger)_feed.works.size())[self loadFeed:NO];if(!_collection.dragging&&!_collection.decelerating)DGWarmWorks(_feed.works,_current);}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView{[self activate];}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView{DGWarmWorks(_feed.works,_current);[self activate];}
- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)path{[(DGFeedCell *)cell active:NO];}
- (void)showComments:(NSString *)workID {
    if(_comments){[self closeComments];return;}_comments=[[DGComments alloc] initWithBridge:_bridge work:workID parent:nil];__weak DGFeed *weakSelf=self;_comments.closeAction=^{[weakSelf closeComments];};_comments.profileAction=^(NSString *sec,NSString *name){DGFeed *self=weakSelf;if(self)[self presentPage:DGMakeProfile(self->_bridge,sec,name,@"")];};
    [self addChildViewController:_comments];_commentHost=[UIView new];_commentHost.layer.cornerRadius=30;_commentHost.clipsToBounds=YES;[self.view addSubview:_commentHost];[_commentHost addSubview:_comments.view];[_comments didMoveToParentViewController:self];_collection.scrollEnabled=NO;_commentHost.alpha=0;[self.view setNeedsLayout];[UIView animateWithDuration:.34 delay:0 usingSpringWithDamping:.88 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{[self.view layoutIfNeeded];self->_commentHost.alpha=1;} completion:^(BOOL done){[self activate];}];
}
- (void)closeComments{if(!_comments)return;[_comments willMoveToParentViewController:nil];[_comments.view removeFromSuperview];[_comments removeFromParentViewController];_comments=nil;[_commentHost removeFromSuperview];_commentHost=nil;_collection.scrollEnabled=YES;[self.view setNeedsLayout];[UIView animateWithDuration:.28 animations:^{[self.view layoutIfNeeded];} completion:^(BOOL done){[self activate];}];}
- (void)presentPage:(UIViewController *)page{if(!page||self.presentedViewController)return;for(DGFeedCell *cell in _collection.visibleCells)[cell active:NO];UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:page];nav.modalPresentationStyle=UIModalPresentationFullScreen;nav.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;[self presentViewController:nav animated:YES completion:nil];}
- (void)search{[self presentPage:DGMakeSearch(_bridge)];}
- (void)messages{[self presentPage:DGMakeMessages(_bridge)];}
- (void)account{if(![_profile[@"loggedIn"] boolValue]){[self openLogin];return;}[self presentPage:DGMakeProfile(_bridge,@"",_profile[@"nickname"]?:@"我的",@"")];}
- (void)followList:(UILongPressGestureRecognizer *)gesture{if(gesture.state!=UIGestureRecognizerStateBegan)return;extern UIViewController *DGMakeFollowing(DGBridge *,NSString *,NSString *);[self presentPage:DGMakeFollowing(_bridge,_profile[@"sec"]?:@"",_profile[@"uid"]?:@"")];}
- (void)settings {
    UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"澄流 · 设置" message:@"长按两侧 1.5×，向上滑最高 3×\n长按关注可查看关注列表" preferredStyle:UIAlertControllerStyleActionSheet];BOOL enabled=[NSUserDefaults.standardUserDefaults objectForKey:@"douglass.danmaku"]?[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.danmaku"]:YES;
    [menu addAction:[UIAlertAction actionWithTitle:enabled?@"关闭视频弹幕":@"开启视频弹幕" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[NSUserDefaults.standardUserDefaults setBool:!enabled forKey:@"douglass.danmaku"];[NSNotificationCenter.defaultCenter postNotificationName:@"DouGlassSettingsChanged" object:nil];}]];
    [menu addAction:[UIAlertAction actionWithTitle:@"登录 / 安全验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self openLogin];}]];[menu addAction:[UIAlertAction actionWithTitle:@"退出当前账号" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){[self->_bridge signOut:^{[self sessionChanged:NO];}];}]];[menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];menu.popoverPresentationController.sourceView=_settings;menu.popoverPresentationController.sourceRect=_settings.bounds;[self presentViewController:menu animated:YES completion:nil];
}
- (void)openLogin{if(self.presentedViewController)return;for(DGFeedCell *cell in _collection.visibleCells)[cell active:NO];DGLogin *login=[DGLogin new];__weak DGFeed *weakSelf=self;login.finished=^{[weakSelf sessionChanged:YES];};UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:login];nav.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:nav animated:YES completion:nil];}
- (void)sessionChanged:(BOOL)reload{++_generation;_loading=NO;_failed=NO;_profile=nil;[self closeComments];DGClearPlayers();_feed.clear();[_records removeAllObjects];[_collection reloadData];_refreshIndex=1;_cursor=@"0";_emptyPages=0;_current=0;if(reload)[_bridge reload];[self loadFeed:YES];[self loadProfile];}
@end
UIViewController *DGMakeFeedController(void){return [DGFeed new];}
UIViewController *DGMakeWorkPlayer(NSArray<NSDictionary *> *works,NSInteger selected,DGBridge *bridge){return [[DGFeed alloc] initWithRecords:works selected:selected bridge:bridge];}

