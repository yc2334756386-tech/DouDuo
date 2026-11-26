#import "DGCommon.h"

UIViewController *DGMakeFollowing(DGBridge *, NSString *, NSString *);

static NSString *DGValue(id value) { return Text(String(value)); }
static NSString *DGPublished(NSDictionary *record) {
    long long timestamp=Number(record[@"publishedAt"]); if(timestamp<=0)return @"发布日期未提供";
    NSDateFormatter *formatter=[NSDateFormatter new]; formatter.dateFormat=@"yyyy-MM-dd";
    return [@"发布于 " stringByAppendingString:[formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]]];
}
static NSString *DGCount(id value) { return Text(douglass::compact(Number(value))); }

@interface DGExploreWorkCell : UITableViewCell
- (void)record:(NSDictionary *)record recent:(BOOL)recent;
@end
@implementation DGExploreWorkCell {
    DGImage *_poster;
    UILabel *_caption,*_date,*_detail,*_badge,*_recent;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if((self=[super initWithStyle:style reuseIdentifier:identifier])) {
        self.backgroundColor=UIColor.clearColor; self.selectionStyle=UITableViewCellSelectionStyleNone;
        _poster=[DGImage new];_poster.contentMode=UIViewContentModeScaleAspectFill;_poster.clipsToBounds=YES;_poster.layer.cornerRadius=14;
        _poster.backgroundColor=[UIColor colorWithWhite:1 alpha:.06];
        _caption=Label(15,UIFontWeightMedium);_caption.numberOfLines=3;
        _date=Label(11,UIFontWeightRegular);_date.textColor=[UIColor colorWithWhite:1 alpha:.5];
        _detail=Label(11,UIFontWeightRegular);_detail.textColor=[UIColor colorWithWhite:1 alpha:.64];
        _badge=Label(10,UIFontWeightSemibold);_badge.textAlignment=NSTextAlignmentCenter;
        _badge.backgroundColor=[UIColor colorWithWhite:0 alpha:.46];_badge.layer.cornerRadius=6;_badge.clipsToBounds=YES;
        _recent=Label(10,UIFontWeightSemibold);_recent.text=@"刚刚看过";_recent.textColor=[UIColor colorWithRed:.7 green:.95 blue:.93 alpha:1];
        for(UIView *view in @[_poster,_caption,_date,_detail,_recent]) [self.contentView addSubview:view];
        [_poster addSubview:_badge];
    }return self;
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat width=self.contentView.bounds.size.width;
    _poster.frame=CGRectMake(18,12,94,128);CGFloat x=126,w=MAX(50,width-144);
    _recent.frame=CGRectMake(x,13,w,15);_caption.frame=CGRectMake(x,_recent.hidden?16:33,w,62);
    _date.frame=CGRectMake(x,104,w,16);_detail.frame=CGRectMake(x,123,w,16);_badge.frame=CGRectMake(7,7,42,20);
}
- (void)record:(NSDictionary *)record recent:(BOOL)recent {
    NSString *cover=DGValue(record[@"cover"]);if(!cover.length)cover=DGValue(Array(record[@"images"]).firstObject);
    [_poster remote:cover];NSString *caption=DGValue(record[@"caption"]);_caption.text=caption.length?caption:@"查看这条作品";
    _date.text=DGPublished(record);_detail.text=[NSString stringWithFormat:@"@%@    ♡ %@",DGValue(record[@"author"]),DGCount(record[@"likes"])];
    NSUInteger photos=Array(record[@"images"]).count;_badge.hidden=!photos;_badge.text=photos?[NSString stringWithFormat:@"%lu 图",(unsigned long)photos]:@"";
    _recent.hidden=!recent;self.contentView.backgroundColor=recent?[UIColor colorWithRed:.12 green:.25 blue:.26 alpha:.42]:UIColor.clearColor;
    [self setNeedsLayout];
}
@end

@interface DGExplorePersonCell : UITableViewCell
- (void)record:(NSDictionary *)record music:(BOOL)music;
@end
@implementation DGExplorePersonCell {
    DGImage *_image;UILabel *_name,*_subtitle,*_chevron;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if((self=[super initWithStyle:style reuseIdentifier:identifier])) {
        self.backgroundColor=UIColor.clearColor;self.selectionStyle=UITableViewCellSelectionStyleNone;
        _image=[DGImage new];_image.contentMode=UIViewContentModeScaleAspectFill;_image.clipsToBounds=YES;_image.backgroundColor=[UIColor colorWithWhite:1 alpha:.07];
        _name=Label(16,UIFontWeightSemibold);_subtitle=Label(12,UIFontWeightRegular);_subtitle.textColor=UIColor.secondaryLabelColor;_subtitle.numberOfLines=2;
        _chevron=Label(20,UIFontWeightRegular);_chevron.text=@"›";_chevron.textColor=UIColor.tertiaryLabelColor;
        for(UIView *view in @[_image,_name,_subtitle,_chevron])[self.contentView addSubview:view];
    }return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];CGFloat width=self.contentView.bounds.size.width;
    _image.frame=CGRectMake(20,15,56,56);_name.frame=CGRectMake(91,17,MAX(0,width-128),23);_subtitle.frame=CGRectMake(91,43,MAX(0,width-128),32);_chevron.frame=CGRectMake(width-32,25,20,30);
}
- (void)record:(NSDictionary *)record music:(BOOL)music {
    _image.layer.cornerRadius=music?12:28;[_image remote:DGValue(record[music?@"cover":@"avatar"])];
    _name.text=DGValue(record[music?@"title":@"nickname"]);
    if(music){NSInteger seconds=Number(record[@"duration"]);_subtitle.text=[NSString stringWithFormat:@"%@%@",DGValue(record[@"author"]),seconds>0?[NSString stringWithFormat:@" · %ld:%02ld",(long)seconds/60,(long)seconds%60]:@""];}
    else {NSString *signature=DGValue(record[@"signature"]);_subtitle.text=signature.length?signature:[NSString stringWithFormat:@"%@ 作品 · %@ 粉丝",DGCount(record[@"works"]),DGCount(record[@"followers"])];}
}
@end

typedef NS_ENUM(NSInteger,DGExploreMode){DGExploreProfile,DGExploreSearch,DGExploreMusic,DGExploreFollowing};
@interface DGExplore : UIViewController <UITableViewDataSource,UITableViewDelegate,UISearchBarDelegate>
- (instancetype)initWithBridge:(DGBridge *)bridge mode:(DGExploreMode)mode;
@property(nonatomic,copy) NSString *sec;
@property(nonatomic,copy) NSString *uid;
@property(nonatomic,copy) NSString *displayName;
@property(nonatomic,copy) NSString *locate;
@property(nonatomic,strong) NSDictionary *music;
@end
@implementation DGExplore {
    DGBridge *_bridge;DGExploreMode _mode;
    UITableView *_table;UIView *_header;UIButton *_footer;UILabel *_empty;
    DGImage *_avatar;UILabel *_name,*_signature,*_stats,*_context;UISegmentedControl *_tabs;UIButton *_followingButton,*_play,*_save;
    UIVisualEffectView *_musicControls;UISearchBar *_search;UIRefreshControl *_refresh;
    NSMutableArray<NSDictionary *> *_records;NSMutableSet<NSString *> *_ids;
    NSDictionary *_person;NSString *_cursor,*_query;BOOL _own,_loading,_more,_failed,_locateFound,_profileLoading;
    NSUInteger _generation,_seekPages;NSInteger _selectedTab;AVPlayer *_audio;id _audioEnd;
}
- (instancetype)initWithBridge:(DGBridge *)bridge mode:(DGExploreMode)mode {
    if((self=[super init])){_bridge=bridge;_mode=mode;_records=[NSMutableArray array];_ids=[NSMutableSet set];_cursor=@"0";_more=YES;_query=@"";}return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;self.view.backgroundColor=[UIColor colorWithWhite:.035 alpha:1];
    _own=_mode==DGExploreProfile&&!self.sec.length;
    self.title=_mode==DGExploreSearch?@"搜索":_mode==DGExploreMusic?@"原声":_mode==DGExploreFollowing?@"关注列表":_own?@"我的":self.displayName;
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    _table=[[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];_table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    _table.backgroundColor=UIColor.clearColor;_table.dataSource=self;_table.delegate=self;_table.separatorStyle=UITableViewCellSeparatorStyleNone;
    _table.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;_table.showsVerticalScrollIndicator=NO;_table.sectionHeaderTopPadding=0;
    [_table registerClass:DGExploreWorkCell.class forCellReuseIdentifier:@"work"];[_table registerClass:DGExplorePersonCell.class forCellReuseIdentifier:@"person"];
    [self.view addSubview:_table];
    _empty=Label(14,UIFontWeightRegular);_empty.textColor=UIColor.secondaryLabelColor;_empty.textAlignment=NSTextAlignmentCenter;_empty.numberOfLines=0;_table.backgroundView=_empty;
    _footer=[UIButton buttonWithType:UIButtonTypeSystem];_footer.frame=CGRectMake(0,0,320,64);_footer.titleLabel.font=[UIFont systemFontOfSize:12];_footer.tintColor=UIColor.secondaryLabelColor;
    [_footer addTarget:self action:@selector(loadPage) forControlEvents:UIControlEventTouchUpInside];_table.tableFooterView=_footer;
    _refresh=[UIRefreshControl new];_refresh.tintColor=UIColor.whiteColor;[_refresh addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];_table.refreshControl=_refresh;
    [self buildHeader];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(pauseAudio) name:UIApplicationWillResignActiveNotification object:nil];
    if(_mode==DGExploreProfile)[self loadProfile];
    else if(_mode==DGExploreSearch){_more=NO;_empty.text=@"搜索视频与图文作品";[_footer setTitle:@"输入关键词并搜索" forState:UIControlStateNormal];}
    else if(_mode==DGExploreFollowing&&!self.sec.length)[self loadFollowingIdentity];
    else if(_mode==DGExploreMusic){[self updateMusicHeader];[self loadMusicDetail];[self loadPage];}
    else [self loadPage];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if(self.navigationController.viewControllers.firstObject==self)self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self pauseAudio];}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];if(_audioEnd)[NSNotificationCenter.defaultCenter removeObserver:_audioEnd];[_audio pause];}
- (UIStatusBarStyle)preferredStatusBarStyle{return UIStatusBarStyleLightContent;}
- (void)close{[self pauseAudio];[self dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];}
- (void)buildHeader {
    _header=[UIView new];_header.backgroundColor=UIColor.clearColor;
    if(_mode==DGExploreSearch){_search=[UISearchBar new];_search.searchBarStyle=UISearchBarStyleMinimal;_search.placeholder=@"搜索视频与图文";_search.delegate=self;_search.returnKeyType=UIReturnKeySearch;[_header addSubview:_search];}
    else {
        _avatar=[DGImage new];_avatar.contentMode=UIViewContentModeScaleAspectFill;_avatar.clipsToBounds=YES;_avatar.backgroundColor=[UIColor colorWithWhite:1 alpha:.07];_avatar.userInteractionEnabled=YES;
        [_avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openAvatar)]];
        [_header addSubview:_avatar];_name=Label(24,UIFontWeightBold);_name.numberOfLines=2;[_header addSubview:_name];
        _signature=Label(13,UIFontWeightRegular);_signature.textColor=UIColor.secondaryLabelColor;_signature.numberOfLines=2;[_header addSubview:_signature];
        _stats=Label(13,UIFontWeightMedium);_stats.textColor=[UIColor colorWithWhite:1 alpha:.8];[_header addSubview:_stats];
        _context=Label(11,UIFontWeightRegular);_context.textColor=[UIColor colorWithWhite:1 alpha:.48];_context.numberOfLines=2;[_header addSubview:_context];
        if(_mode==DGExploreProfile){
            _tabs=[[UISegmentedControl alloc] initWithItems:_own?@[@"作品",@"喜欢",@"收藏",@"收藏音乐"]:@[@"作品",@"喜欢"]];_tabs.selectedSegmentIndex=0;
            [_tabs addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];[_header addSubview:_tabs];
            _followingButton=[UIButton buttonWithType:UIButtonTypeSystem];[_followingButton setTitle:@"关注列表 ›" forState:UIControlStateNormal];_followingButton.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
            [_followingButton addTarget:self action:@selector(showFollowing) forControlEvents:UIControlEventTouchUpInside];[_header addSubview:_followingButton];
            _name.text=self.displayName.length?self.displayName:(_own?@"我的":@"用户主页");_signature.text=@"正在读取个人资料…";
            _context.text=self.locate.length?@"正在定位刚刚看过的作品":@"作品按平台返回顺序展示";
        }else if(_mode==DGExploreMusic){
            _musicControls=Glass(20);[_header addSubview:_musicControls];_play=Symbol(@"play.fill",self,@selector(toggleAudio));_play.accessibilityLabel=@"播放或暂停原声";[_musicControls.contentView addSubview:_play];
            _save=Symbol(@"square.and.arrow.down",self,@selector(saveAudio));_save.accessibilityLabel=@"保存原声";[_musicControls.contentView addSubview:_save];
            [_header addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longSave:)]];
            _context.text=@"使用这首原声的作品 · 长按保存原声";
        }else{_avatar.hidden=YES;_name.text=@"关注的人";_signature.text=@"点开头像查看主页与作品";}
    }
    [self layoutHeader];_table.tableHeaderView=_header;
}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];[self layoutHeader];}
- (void)layoutHeader {
    CGFloat width=self.view.bounds.size.width,height=_mode==DGExploreProfile?268:_mode==DGExploreSearch?62:_mode==DGExploreMusic?211:108;
    if(_header.bounds.size.width!=width||_header.bounds.size.height!=height){_header.frame=CGRectMake(0,0,width,height);if(_table.tableHeaderView)_table.tableHeaderView=_header;}
    if(_mode==DGExploreSearch){_search.frame=CGRectMake(10,2,width-20,56);return;}
    if(_mode==DGExploreFollowing){_name.frame=CGRectMake(20,10,width-40,36);_signature.frame=CGRectMake(20,52,width-40,32);return;}
    _avatar.frame=CGRectMake(20,16,78,78);_avatar.layer.cornerRadius=_mode==DGExploreMusic?18:39;
    _name.frame=CGRectMake(115,15,MAX(30,width-135),60);_signature.frame=CGRectMake(20,111,width-40,38);
    _stats.frame=CGRectMake(115,80,MAX(30,width-135),20);_context.frame=CGRectMake(20,_mode==DGExploreProfile?190:160,width-40,33);
    if(_mode==DGExploreProfile){_followingButton.frame=CGRectMake(20,154,112,30);_tabs.frame=CGRectMake(18,232,width-36,32);}
    if(_mode==DGExploreMusic){_musicControls.frame=CGRectMake(width-112,112,92,40);_play.frame=CGRectMake(2,0,44,40);_save.frame=CGRectMake(46,0,44,40);_signature.frame=CGRectMake(20,112,MAX(40,width-148),36);}
}
- (void)loadProfile {
    if(_profileLoading)return;_profileLoading=YES;__weak DGExplore *weakSelf=self;
    [_bridge request:_own?@"profile":@"userProfile" parameters:@{@"sec":self.sec?:@""} completion:^(NSDictionary *result,NSString *error){
        DGExplore *self=weakSelf;if(!self)return;self->_profileLoading=NO;
        if(error||![result[@"loggedIn"] boolValue]){
            NSString *reason=error?:@"登录已失效，请返回首页重新登录";self->_signature.text=reason;self->_empty.text=reason;self->_failed=YES;
            [self->_footer setTitle:@"重新读取个人资料" forState:UIControlStateNormal];self->_footer.enabled=YES;return;
        }
        self->_person=result;self.sec=DGValue(result[@"sec"]);self.uid=DGValue(result[@"uid"]);self.displayName=DGValue(result[@"nickname"]);
        self.title=self->_own?@"我的":self.displayName;self->_name.text=self.displayName;[self->_avatar remote:DGValue(result[@"avatar"])];
        NSString *signature=DGValue(result[@"signature"]);self->_signature.text=signature.length?signature:@"这个人还没有填写简介";
        self->_stats.text=[NSString stringWithFormat:@"%@ 获赞 · %@ 粉丝",DGCount(result[@"likes"]),DGCount(result[@"followers"])];
        [self->_followingButton setTitle:[NSString stringWithFormat:@"%@ 关注 ›",DGCount(result[@"following"])] forState:UIControlStateNormal];
        NSString *location=DGValue(result[@"location"]);self->_context.text=self.locate.length?@"正在定位刚刚看过的作品":location.length?location:@"作品按平台返回顺序展示";
        [self resetList];
    }];
}
- (void)loadFollowingIdentity {
    __weak DGExplore *weakSelf=self;
    [_bridge request:@"profile" parameters:@{} completion:^(NSDictionary *result,NSString *error){DGExplore *self=weakSelf;if(!self)return;
        if(error||![result[@"loggedIn"] boolValue]){self->_empty.text=error?:@"请先登录以查看关注列表";self->_more=NO;[self->_footer setTitle:@"返回首页登录后重试" forState:UIControlStateNormal];return;}
        self.sec=DGValue(result[@"sec"]);self.uid=DGValue(result[@"uid"]);[self loadPage];
    }];
}
- (void)loadMusicDetail {
    NSString *identifier=DGValue(self.music[@"id"]);if(!identifier.length)return;__weak DGExplore *weakSelf=self;
    [_bridge request:@"musicDetail" parameters:@{@"id":identifier} completion:^(NSDictionary *result,NSString *error){DGExplore *self=weakSelf;if(!self)return;
        if(!error){NSMutableDictionary *music=[self.music mutableCopy]?:[NSMutableDictionary dictionary];for(NSString *key in result)if(DGValue(result[key]).length)music[key]=result[key];self.music=music;[self updateMusicHeader];}
    }];
}
- (void)updateMusicHeader {
    _name.text=DGValue(self.music[@"title"]).length?DGValue(self.music[@"title"]):@"作品原声";_signature.text=DGValue(self.music[@"author"]);
    [_avatar remote:DGValue(self.music[@"cover"])];NSInteger duration=Number(self.music[@"duration"]);_stats.text=duration>0?[NSString stringWithFormat:@"%ld:%02ld",(long)duration/60,(long)duration%60]:@"";
    _play.enabled=DGValue(self.music[@"url"]).length>0;_save.enabled=_play.enabled;
}
- (BOOL)musicRows{return _mode==DGExploreProfile&&_own&&_selectedTab==3;}
- (void)tabChanged{_selectedTab=_tabs.selectedSegmentIndex;[self pauseAudio];[self resetList];}
- (void)refresh {
    if(_mode==DGExploreProfile&&!_person){[self loadProfile];[_refresh endRefreshing];return;}
    if(_mode==DGExploreSearch&&!_query.length){[_refresh endRefreshing];return;}[self resetList];
}
- (void)resetList {
    ++_generation;_loading=NO;_more=YES;_failed=NO;_cursor=@"0";_seekPages=0;_locateFound=NO;[_records removeAllObjects];[_ids removeAllObjects];[_table reloadData];[self loadPage];
}
- (NSString *)operation {
    if(_mode==DGExploreSearch)return @"search";if(_mode==DGExploreFollowing)return @"following";if(_mode==DGExploreMusic)return @"musicWorks";
    return @[@"works",@"likes",@"collections",@"musicList"][_selectedTab];
}
- (void)loadPage {
    if(_mode==DGExploreProfile&&!_person){[self loadProfile];return;}
    if(_loading||!_more)return;if(_mode==DGExploreSearch&&!_query.length)return;
    if(_mode==DGExploreMusic&&!DGValue(self.music[@"id"]).length){_empty.text=@"平台没有提供该原声的作品列表标识";[_footer setTitle:@"仍可播放或保存已提供的原声" forState:UIControlStateNormal];_more=NO;return;}
    _loading=YES;_failed=NO;_footer.enabled=NO;[_footer setTitle:@"正在加载…" forState:UIControlStateNormal];if(!_records.count)_empty.text=@"正在读取内容";
    NSString *operation=[self operation],*oldCursor=_cursor.copy;NSUInteger generation=_generation;
    NSDictionary *parameters=@{@"sec":self.sec?:@"",@"uid":self.uid?:@"",@"id":DGValue(self.music[@"id"]),@"kw":_query?:@"",@"cursor":_cursor};
    __weak DGExplore *weakSelf=self;
    [_bridge request:operation parameters:parameters completion:^(NSDictionary *result,NSString *error){
        DGExplore *self=weakSelf;if(!self||generation!=self->_generation)return;self->_loading=NO;[self->_refresh endRefreshing];
        if(error){self->_failed=YES;if(!self->_records.count)self->_empty.text=error;[self->_footer setTitle:@"加载失败，轻点重试" forState:UIControlStateNormal];self->_footer.enabled=YES;return;}
        BOOL people=self->_mode==DGExploreFollowing,music=[self musicRows];
        for(id raw in Array(result[@"items"])){
            if(![raw isKindOfClass:NSDictionary.class])continue;NSDictionary *record=raw;NSString *identifier=DGValue(record[people?@"sec":@"id"]);
            if(!identifier.length||[self->_ids containsObject:identifier])continue;
            if(!people&&!music&&!ReadWork(record).playable())continue;
            [self->_ids addObject:identifier];[self->_records addObject:record];
        }
        ++self->_seekPages;self->_cursor=DGValue(result[@"cursor"]);if(!self->_cursor.length)self->_cursor=@"0";
        self->_more=[result[@"more"] boolValue]&&![oldCursor isEqualToString:self->_cursor];
        self->_empty.text=self->_records.count?@"":people?@"还没有可显示的关注用户":music?@"还没有收藏音乐":@"暂无可查看的作品，内容也可能被账号隐私设置限制";
        [self->_footer setTitle:self->_more?@"继续加载":@"已显示全部可查看内容" forState:UIControlStateNormal];self->_footer.enabled=self->_more;
        [self->_table reloadData];[self locateIfNeeded];
    }];
}
- (void)locateIfNeeded {
    if(_mode!=DGExploreProfile||_selectedTab!=0||!self.locate.length||_locateFound)return;
    NSInteger found=NSNotFound;for(NSUInteger index=0;index<_records.count;++index)if([DGValue(_records[index][@"id"]) isEqualToString:self.locate]){found=index;break;}
    if(found!=NSNotFound){_locateFound=YES;_context.text=@"已定位到刚刚看过的作品";[_table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:found inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
        dispatch_async(dispatch_get_main_queue(),^{if(found<[self->_table numberOfRowsInSection:0])[self->_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:found inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:YES];});return;}
    if(_more&&_seekPages<15){_context.text=[NSString stringWithFormat:@"正在定位刚刚看过的作品 · 已读取 %lu 页",(unsigned long)_seekPages];dispatch_async(dispatch_get_main_queue(),^{[self loadPage];});}
    else _context.text=_more?@"前 15 页未找到刚刚看过的作品，可继续下滑加载":@"该作品未出现在此主页可查看的作品列表中";
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    NSString *query=[searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!query.length)return;
    [searchBar resignFirstResponder];_query=query;[self resetList];
}
- (void)showFollowing {
    UIViewController *following=DGMakeFollowing(_bridge,self.sec?:@"",self.uid?:@"");[self.navigationController pushViewController:following animated:YES];
}
- (void)openAvatar {
    NSString *url=DGValue(_mode==DGExploreMusic?self.music[@"cover"]:_person[@"avatar"]);if(url.length)DGShowImage(self,url,_avatar);
}
- (void)toggleAudio {
    if(_audio.rate>0){[self pauseAudio];return;}
    NSString *url=DGValue(self.music[@"url"]);if(!url.length){DGToast(self,@"平台未提供可播放的原声地址");return;}
    if(!_audio){_audio=[AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:Asset(url)]];
        __weak DGExplore *weakSelf=self;_audioEnd=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:_audio.currentItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){DGExplore *self=weakSelf;if(!self)return;[self->_audio seekToTime:kCMTimeZero];[self pauseAudio];}];}
    [_audio play];[_play setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal];
}
- (void)pauseAudio{[_audio pause];[_play setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];}
- (void)saveAudio{NSString *url=DGValue(self.music[@"url"]);if(!url.length){DGToast(self,@"平台未提供可保存的原声地址");return;}DGSaveAudio(self,url,DGValue(self.music[@"title"]));}
- (void)longSave:(UILongPressGestureRecognizer *)gesture{if(gesture.state==UIGestureRecognizerStateBegan){[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];[self saveAudio];}}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return _records.count;}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{return _mode==DGExploreFollowing||[self musicRows]?86:152;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *record=_records[indexPath.row];
    if(_mode==DGExploreFollowing||[self musicRows]){DGExplorePersonCell *cell=[tableView dequeueReusableCellWithIdentifier:@"person" forIndexPath:indexPath];[cell record:record music:[self musicRows]];return cell;}
    DGExploreWorkCell *cell=[tableView dequeueReusableCellWithIdentifier:@"work" forIndexPath:indexPath];BOOL recent=_mode==DGExploreProfile&&_selectedTab==0&&self.locate.length&&[DGValue(record[@"id"]) isEqualToString:self.locate];[cell record:record recent:recent];return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self pauseAudio];NSDictionary *record=_records[indexPath.row];
    if(_mode==DGExploreFollowing){[self.navigationController pushViewController:DGMakeProfile(_bridge,DGValue(record[@"sec"]),DGValue(record[@"nickname"]),@"") animated:YES];return;}
    if([self musicRows]){[self.navigationController pushViewController:DGMakeMusic(_bridge,record) animated:YES];return;}
    UIViewController *player=DGMakeWorkPlayer(_records.copy,indexPath.row,_bridge);player.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:player animated:YES completion:nil];
}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if(!_failed&&_more&&!_loading&&indexPath.row+4>=(NSInteger)_records.count)[self loadPage];
}
@end

UIViewController *DGMakeProfile(DGBridge *bridge,NSString *sec,NSString *name,NSString *locate){DGExplore *view=[[DGExplore alloc] initWithBridge:bridge mode:DGExploreProfile];view.sec=sec?:@"";view.displayName=name?:@"";view.locate=locate?:@"";return view;}
UIViewController *DGMakeSearch(DGBridge *bridge){return [[DGExplore alloc] initWithBridge:bridge mode:DGExploreSearch];}
UIViewController *DGMakeMusic(DGBridge *bridge,NSDictionary *music){DGExplore *view=[[DGExplore alloc] initWithBridge:bridge mode:DGExploreMusic];view.music=music?:@{};return view;}
UIViewController *DGMakeFollowing(DGBridge *bridge,NSString *sec,NSString *uid){DGExplore *view=[[DGExplore alloc] initWithBridge:bridge mode:DGExploreFollowing];view.sec=sec?:@"";view.uid=uid?:@"";return view;}

