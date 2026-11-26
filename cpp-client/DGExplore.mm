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
    self.accessoryType=music?UITableViewCellAccessoryDetailButton:UITableViewCellAccessoryNone;_chevron.hidden=music;_image.layer.cornerRadius=music?12:28;[_image remote:DGValue(record[music?@"cover":@"avatar"])];
    _name.text=DGValue(record[music?@"title":@"nickname"]);_name.textColor=music&&DGMusicMatches(DGValue(record[@"id"]))?UIColor.systemTealColor:UIColor.labelColor;
    if(music){NSInteger seconds=Number(record[@"duration"]);_subtitle.text=[NSString stringWithFormat:@"%@%@",DGValue(record[@"author"]),seconds>0?[NSString stringWithFormat:@" · %ld:%02ld",(long)seconds/60,(long)seconds%60]:@""];}
    else {NSString *signature=DGValue(record[@"signature"]);_subtitle.text=signature.length?signature:[NSString stringWithFormat:@"%@ 作品 · %@ 粉丝",DGCount(record[@"works"]),DGCount(record[@"followers"])];}
}
@end

@interface DGGridTile:UIControl
- (void)record:(NSDictionary *)record recent:(BOOL)recent;
@end
@implementation DGGridTile{DGImage *_poster;UILabel *_caption,*_date,*_badge,*_recent;}
- (instancetype)initWithFrame:(CGRect)frame{if((self=[super initWithFrame:frame])){_poster=[DGImage new];_poster.contentMode=UIViewContentModeScaleAspectFill;_poster.clipsToBounds=YES;_poster.layer.cornerRadius=8;_poster.backgroundColor=[UIColor colorWithWhite:1 alpha:.06];[self addSubview:_poster];_caption=Label(11,UIFontWeightMedium);_caption.numberOfLines=2;_caption.backgroundColor=[UIColor colorWithWhite:0 alpha:.34];[_poster addSubview:_caption];_date=Label(10,UIFontWeightRegular);_date.textColor=UIColor.secondaryLabelColor;[self addSubview:_date];_badge=Label(10,UIFontWeightSemibold);_badge.textAlignment=NSTextAlignmentCenter;_badge.backgroundColor=[UIColor colorWithWhite:0 alpha:.4];_badge.layer.cornerRadius=5;_badge.clipsToBounds=YES;[_poster addSubview:_badge];_recent=Label(10,UIFontWeightSemibold);_recent.text=@"刚刚看过";_recent.backgroundColor=[UIColor colorWithRed:.08 green:.36 blue:.38 alpha:.94];[_poster addSubview:_recent];}return self;}
- (void)layoutSubviews{[super layoutSubviews];CGFloat w=self.bounds.size.width,h=self.bounds.size.height;_poster.frame=CGRectMake(0,0,w,h-22);_caption.frame=CGRectMake(4,_poster.bounds.size.height-35,w-8,32);_date.frame=CGRectMake(0,h-19,w,16);_badge.frame=CGRectMake(w-39,5,34,18);_recent.frame=CGRectMake(4,5,58,19);}
- (void)record:(NSDictionary *)record recent:(BOOL)recent{[_poster remote:DGValue(record[@"cover"])];_caption.text=DGValue(record[@"caption"]);long long time=Number(record[@"publishedAt"]);NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"yyyy-MM-dd";_date.text=time>0?[f stringFromDate:[NSDate dateWithTimeIntervalSince1970:time]]:@"日期未知";NSUInteger count=Array(record[@"images"]).count;_badge.hidden=!count;_badge.text=[NSString stringWithFormat:@"%lu图",(unsigned long)count];_recent.hidden=!recent;_poster.layer.borderWidth=recent?2:0;_poster.layer.borderColor=[UIColor colorWithRed:.4 green:.9 blue:.85 alpha:1].CGColor;}
@end
@interface DGExploreGridRow:UITableViewCell
@property(nonatomic,copy) void (^selectWork)(NSInteger index);
- (void)records:(NSArray *)records base:(NSInteger)base recent:(NSString *)recent;
@end
@implementation DGExploreGridRow{NSArray<DGGridTile *> *_tiles;}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier{if((self=[super initWithStyle:style reuseIdentifier:identifier])){self.backgroundColor=UIColor.clearColor;self.selectionStyle=UITableViewCellSelectionStyleNone;NSMutableArray *tiles=[NSMutableArray array];for(NSInteger i=0;i<3;i++){DGGridTile *tile=[[DGGridTile alloc]initWithFrame:CGRectZero];[tile addTarget:self action:@selector(select:) forControlEvents:UIControlEventTouchUpInside];[self.contentView addSubview:tile];[tiles addObject:tile];}_tiles=tiles;}return self;}
- (void)layoutSubviews{[super layoutSubviews];CGFloat w=(self.contentView.bounds.size.width-24)/3;for(NSUInteger i=0;i<3;i++)_tiles[i].frame=CGRectMake(8+i*(w+4),4,w,self.contentView.bounds.size.height-7);}
- (void)records:(NSArray *)records base:(NSInteger)base recent:(NSString *)recent{for(NSUInteger i=0;i<3;i++){DGGridTile *tile=_tiles[i];tile.hidden=i>=records.count;if(tile.hidden)continue;tile.tag=base+i;NSDictionary *record=records[i];[tile record:record recent:recent.length&&[DGValue(record[@"id"])isEqualToString:recent]];}}
- (void)select:(DGGridTile *)tile{if(self.selectWork)self.selectWork(tile.tag);}
- (void)prepareForReuse{[super prepareForReuse];self.selectWork=nil;}
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
    DGImage *_avatar;UILabel *_name,*_signature,*_stats,*_context;UISegmentedControl *_tabs;UIButton *_followingButton,*_play,*_save,*_collectMusic;BOOL _musicCollectBusy;
    UIVisualEffectView *_musicControls;UISearchBar *_search;UIRefreshControl *_refresh;
    UISegmentedControl *_searchTabs;UIButton *_webSearch,*_followUser,*_blockUser;UILabel *_searchHint;UIViewController *_searchPage;
    NSInteger _searchKind;BOOL _relationshipBusy,_webImportMode;
    NSMutableArray<NSDictionary *> *_records;NSMutableSet<NSString *> *_ids;
    NSDictionary *_person;NSString *_cursor,*_query;BOOL _own,_loading,_more,_failed,_locateFound,_profileLoading;
    NSString *_lastQueueID;BOOL _lastQueuePlaying;NSUInteger _generation,_seekPages;NSInteger _selectedTab;AVPlayer *_audio;id _audioEnd;
}
- (instancetype)initWithBridge:(DGBridge *)bridge mode:(DGExploreMode)mode {
    if((self=[super init])){_bridge=bridge;_mode=mode;_records=[NSMutableArray array];_ids=[NSMutableSet set];_cursor=@"0";_more=YES;_query=@"";}return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;self.view.backgroundColor=[UIColor colorWithWhite:.035 alpha:1];
    _own=_mode==DGExploreProfile&&!self.sec.length;
    self.title=_mode==DGExploreSearch?@"搜索":_mode==DGExploreMusic?@"原声":_mode==DGExploreFollowing?@"关注列表":_own?@"我的":self.displayName;
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    if(_mode==DGExploreSearch)self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"globe"] style:UIBarButtonItemStylePlain target:self action:@selector(openSearchPage)];
    _table=[[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];_table.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    _table.backgroundColor=UIColor.clearColor;_table.dataSource=self;_table.delegate=self;_table.separatorStyle=UITableViewCellSeparatorStyleNone;
    _table.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;_table.showsVerticalScrollIndicator=NO;_table.sectionHeaderTopPadding=0;
    if(@available(iOS 26.0,*))_table.topEdgeEffect.hidden=YES;
    [_table registerClass:DGExploreGridRow.class forCellReuseIdentifier:@"work"];[_table registerClass:DGExplorePersonCell.class forCellReuseIdentifier:@"person"];
    [self.view addSubview:_table];
    _empty=Label(14,UIFontWeightRegular);_empty.textColor=UIColor.secondaryLabelColor;_empty.textAlignment=NSTextAlignmentCenter;_empty.numberOfLines=0;_table.backgroundView=_empty;
    _footer=[UIButton buttonWithType:UIButtonTypeSystem];_footer.frame=CGRectMake(0,0,320,64);_footer.titleLabel.font=[UIFont systemFontOfSize:12];_footer.tintColor=UIColor.secondaryLabelColor;
    [_footer addTarget:self action:@selector(loadPage) forControlEvents:UIControlEventTouchUpInside];_table.tableFooterView=_footer;
    _refresh=[UIRefreshControl new];_refresh.tintColor=UIColor.whiteColor;[_refresh addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];_table.refreshControl=_refresh;
    [self buildHeader];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateMusicPlayback) name:@"DGMusicStateChanged" object:nil];
    if(_mode==DGExploreProfile)[self loadProfile];
    else if(_mode==DGExploreSearch){_more=NO;_empty.text=@"搜索视频与图文作品";[_footer setTitle:@"输入关键词并搜索" forState:UIControlStateNormal];}
    else if(_mode==DGExploreFollowing&&!self.sec.length)[self loadFollowingIdentity];
    else if(_mode==DGExploreMusic){[self updateMusicHeader];[self loadMusicDetail];[self loadPage];}
    else [self loadPage];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];if(_mode==DGExploreMusic)[self updateMusicPlayback];
    if(self.navigationController.viewControllers.firstObject==self)self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];if(_audioEnd)[NSNotificationCenter.defaultCenter removeObserver:_audioEnd];}
- (UIStatusBarStyle)preferredStatusBarStyle{return UIStatusBarStyleLightContent;}
- (void)close{[self dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];}
- (void)buildHeader {
    _header=[UIView new];_header.backgroundColor=UIColor.clearColor;
    if(_mode==DGExploreSearch){
        _search=[UISearchBar new];_search.searchBarStyle=UISearchBarStyleMinimal;_search.placeholder=@"搜索视频与图文";_search.delegate=self;_search.returnKeyType=UIReturnKeySearch;[_header addSubview:_search];
        _searchTabs=[[UISegmentedControl alloc]initWithItems:@[@"视频",@"用户"]];_searchTabs.selectedSegmentIndex=0;[_searchTabs addTarget:self action:@selector(searchKindChanged) forControlEvents:UIControlEventValueChanged];[_header addSubview:_searchTabs];
        _webSearch=[UIButton buttonWithType:UIButtonTypeSystem];[_webSearch setTitle:@"网页翻页并导回 ↗" forState:UIControlStateNormal];_webSearch.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];[_webSearch addTarget:self action:@selector(openSearchPage) forControlEvents:UIControlEventTouchUpInside];[_header addSubview:_webSearch];
        _searchHint=Label(11,UIFontWeightRegular);_searchHint.textColor=UIColor.secondaryLabelColor;_searchHint.numberOfLines=2;_searchHint.text=@"结果只有一页时，可在官网手动翻页，再把已加载结果追加回这里。";[_header addSubview:_searchHint];
    }
    else {
        _avatar=[DGImage new];_avatar.contentMode=UIViewContentModeScaleAspectFill;_avatar.clipsToBounds=YES;_avatar.backgroundColor=[UIColor colorWithWhite:1 alpha:.07];_avatar.userInteractionEnabled=YES;
        UITapGestureRecognizer *avatarTap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openAvatar)];[_avatar addGestureRecognizer:avatarTap];
        if(_mode==DGExploreProfile){UILongPressGestureRecognizer *save=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(saveAvatar:)];[_avatar addGestureRecognizer:save];[avatarTap requireGestureRecognizerToFail:save];_avatar.accessibilityLabel=@"用户头像，轻点查看，长按保存";}
        [_header addSubview:_avatar];_name=Label(24,UIFontWeightBold);_name.numberOfLines=2;[_header addSubview:_name];
        _signature=Label(13,UIFontWeightRegular);_signature.textColor=UIColor.secondaryLabelColor;_signature.numberOfLines=2;[_header addSubview:_signature];
        _stats=Label(13,UIFontWeightMedium);_stats.textColor=[UIColor colorWithWhite:1 alpha:.8];[_header addSubview:_stats];
        _context=Label(11,UIFontWeightRegular);_context.textColor=[UIColor colorWithWhite:1 alpha:.48];_context.numberOfLines=2;[_header addSubview:_context];
        if(_mode==DGExploreProfile){
            _tabs=[[UISegmentedControl alloc] initWithItems:_own?@[@"作品",@"喜欢",@"收藏",@"收藏音乐"]:@[@"作品",@"喜欢"]];_tabs.selectedSegmentIndex=0;
            [_tabs addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];[_header addSubview:_tabs];
            _followingButton=[UIButton buttonWithType:UIButtonTypeSystem];[_followingButton setTitle:@"关注列表 ›" forState:UIControlStateNormal];_followingButton.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
            [_followingButton addTarget:self action:@selector(showFollowing) forControlEvents:UIControlEventTouchUpInside];[_header addSubview:_followingButton];
            if(!_own){_followUser=[UIButton buttonWithType:UIButtonTypeSystem];_blockUser=[UIButton buttonWithType:UIButtonTypeSystem];[_followUser setTitle:@"关注" forState:UIControlStateNormal];[_blockUser setTitle:@"拉黑" forState:UIControlStateNormal];for(UIButton *button in @[_followUser,_blockUser]){button.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];button.layer.cornerRadius=15;button.backgroundColor=[UIColor colorWithWhite:1 alpha:.08];button.enabled=NO;[_header addSubview:button];}[_followUser addTarget:self action:@selector(toggleFollow) forControlEvents:UIControlEventTouchUpInside];[_blockUser addTarget:self action:@selector(confirmBlock) forControlEvents:UIControlEventTouchUpInside];}
            _name.text=self.displayName.length?self.displayName:(_own?@"我的":@"用户主页");_signature.text=@"正在读取个人资料…";
            _context.text=self.locate.length?@"正在定位刚刚看过的作品":@"作品按平台返回顺序展示";
        }else if(_mode==DGExploreMusic){
            _musicControls=Glass(20);[_header addSubview:_musicControls];_play=Symbol(@"play.fill",self,@selector(toggleAudio));_play.accessibilityLabel=@"播放或暂停原声";[_musicControls.contentView addSubview:_play];
            _save=Symbol(@"square.and.arrow.down",self,@selector(saveAudio));_save.accessibilityLabel=@"保存原声";[_musicControls.contentView addSubview:_save];_collectMusic=Symbol(@"star",self,@selector(collectMusic));_collectMusic.accessibilityLabel=@"收藏原声";[_musicControls.contentView addSubview:_collectMusic];
            
            _context.text=@"使用这首原声的作品";
        }else{_avatar.hidden=YES;_name.text=@"关注的人";_signature.text=@"点开头像查看主页与作品";}
    }
    [self layoutHeader];_table.tableHeaderView=_header;
}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];[self layoutHeader];}
- (void)layoutHeader {
    CGFloat width=self.view.bounds.size.width,height=_mode==DGExploreProfile?268:_mode==DGExploreSearch?148:_mode==DGExploreMusic?211:108;
    if(_header.bounds.size.width!=width||_header.bounds.size.height!=height){_header.frame=CGRectMake(0,0,width,height);if(_table.tableHeaderView)_table.tableHeaderView=_header;}
    if(_mode==DGExploreSearch){_search.frame=CGRectMake(10,2,width-20,56);_searchTabs.frame=CGRectMake(18,64,132,32);_webSearch.frame=CGRectMake(158,62,MAX(40,width-176),36);_searchHint.frame=CGRectMake(18,104,width-36,36);return;}
    if(_mode==DGExploreFollowing){_name.frame=CGRectMake(20,10,width-40,36);_signature.frame=CGRectMake(20,52,width-40,32);return;}
    _avatar.frame=CGRectMake(20,16,78,78);_avatar.layer.cornerRadius=_mode==DGExploreMusic?18:39;
    _name.frame=CGRectMake(115,15,MAX(30,width-135),60);_signature.frame=CGRectMake(20,111,width-40,38);
    _stats.frame=CGRectMake(115,80,MAX(30,width-135),20);_context.frame=CGRectMake(20,_mode==DGExploreProfile?190:160,width-40,33);
    if(_mode==DGExploreProfile){_followingButton.frame=CGRectMake(20,154,104,30);CGFloat available=MAX(72,(width-152)/2);_followUser.frame=CGRectMake(132,154,available,30);_blockUser.frame=CGRectMake(140+available,154,available,30);_tabs.frame=CGRectMake(18,232,width-36,32);}
    if(_mode==DGExploreMusic){_musicControls.frame=CGRectMake(width-158,112,138,40);_play.frame=CGRectMake(2,0,44,40);_save.frame=CGRectMake(46,0,44,40);_collectMusic.frame=CGRectMake(92,0,44,40);_signature.frame=CGRectMake(20,112,MAX(40,width-194),36);}
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
        [self updateRelationship];
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
    _play.enabled=DGValue(self.music[@"url"]).length>0;_save.enabled=_play.enabled;_collectMusic.enabled=DGValue(self.music[@"id"]).length>0;[_collectMusic setImage:[UIImage systemImageNamed:[self.music[@"collected"]boolValue]?@"star.fill":@"star"] forState:UIControlStateNormal];[self updateMusicPlayback];
}
- (BOOL)musicRows{return _mode==DGExploreProfile&&_own&&_selectedTab==3;}
- (BOOL)peopleRows{return _mode==DGExploreFollowing||(_mode==DGExploreSearch&&_searchKind==1);}
- (void)tabChanged{_selectedTab=_tabs.selectedSegmentIndex;[self pauseAudio];[self resetList];}
- (void)refresh {
    if(_mode==DGExploreProfile&&!_person){[self loadProfile];[_refresh endRefreshing];return;}
    if(_mode==DGExploreSearch&&(!_query.length||_webImportMode)){[_refresh endRefreshing];if(_webImportMode)DGToast(self,@"可使用右上角网页按钮继续翻页；重新搜索可重置结果");return;}[self resetList];
}
- (void)resetList {
    ++_generation;_loading=NO;_more=YES;_failed=NO;_webImportMode=NO;_cursor=@"0";_seekPages=0;_locateFound=NO;_searchHint.text=@"结果只有一页时，可在官网手动翻页，再把已加载结果追加回这里。";[_records removeAllObjects];[_ids removeAllObjects];[_table reloadData];[self loadPage];
}
- (NSString *)operation {
    if(_mode==DGExploreSearch)return _searchKind==1?@"searchUsers":@"search";if(_mode==DGExploreFollowing)return @"following";if(_mode==DGExploreMusic)return @"musicWorks";
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
        BOOL people=[self peopleRows],music=[self musicRows];
        for(id raw in Array(result[@"items"])){
            if(![raw isKindOfClass:NSDictionary.class])continue;NSDictionary *record=raw;NSString *identifier=DGValue(record[people?@"sec":@"id"]);
            if(!identifier.length||[self->_ids containsObject:identifier])continue;
            if(!people&&!music&&!ReadWork(record).playable())continue;
            [self->_ids addObject:identifier];[self->_records addObject:record];
        }
        ++self->_seekPages;self->_cursor=DGValue(result[@"cursor"]);if(!self->_cursor.length)self->_cursor=@"0";
        self->_more=[result[@"more"] boolValue]&&![oldCursor isEqualToString:self->_cursor];
        self->_empty.text=self->_records.count?@"":people?@"暂无可查看的用户":music?@"还没有收藏音乐":@"暂无可查看的作品，内容也可能被账号隐私设置限制";
        [self->_footer setTitle:self->_more?@"继续加载":@"已显示全部可查看内容" forState:UIControlStateNormal];self->_footer.enabled=self->_more;
        [self->_table reloadData];[self locateIfNeeded];
    }];
}
- (void)locateIfNeeded {
    if(_mode!=DGExploreProfile||_selectedTab!=0||!self.locate.length||_locateFound)return;
    NSInteger found=NSNotFound;for(NSUInteger index=0;index<_records.count;++index)if([DGValue(_records[index][@"id"]) isEqualToString:self.locate]){found=index;break;}
    if(found!=NSNotFound){_locateFound=YES;_context.text=@"已定位到刚刚看过的作品";[_table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:found/3 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
        dispatch_async(dispatch_get_main_queue(),^{if(found/3<[self->_table numberOfRowsInSection:0])[self->_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:found/3 inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:YES];});return;}
    if(_more&&_seekPages<15){_context.text=[NSString stringWithFormat:@"正在定位刚刚看过的作品 · 已读取 %lu 页",(unsigned long)_seekPages];dispatch_async(dispatch_get_main_queue(),^{[self loadPage];});}
    else _context.text=_more?@"前 15 页未找到刚刚看过的作品，可继续下滑加载":@"该作品未出现在此主页可查看的作品列表中";
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    NSString *query=[searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!query.length)return;
    [searchBar resignFirstResponder];_query=query;_searchPage=nil;[self resetList];
}
- (void)searchKindChanged{
    _searchKind=_searchTabs.selectedSegmentIndex;_searchPage=nil;_search.placeholder=_searchKind?@"搜索用户昵称或抖音号":@"搜索视频与图文";_query=[_search.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]?:@"";
    [self resetList];if(!_query.length){_more=NO;_empty.text=_searchKind?@"搜索用户昵称或抖音号":@"搜索视频与图文作品";[_footer setTitle:@"输入关键词并搜索" forState:UIControlStateNormal];}
}
- (void)openSearchPage{
    NSString *query=[_search.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!query.length){DGToast(self,@"请先输入搜索词");return;}[_search resignFirstResponder];if(![query isEqualToString:_query]){_query=query;_searchPage=nil;[self resetList];}
    if(!_searchPage){__weak DGExplore *weak=self;NSString *keyword=_query.copy;NSInteger kind=_searchKind;_searchPage=DGMakeSearchPage(keyword,kind==1,^(NSArray<NSDictionary *> *items){DGExplore *self=weak;if(!self||![self->_query isEqualToString:keyword]||self->_searchKind!=kind)return;[self importSearchItems:items];});}
    [self.navigationController pushViewController:_searchPage animated:YES];
}
- (void)importSearchItems:(NSArray<NSDictionary *> *)items{
    ++_generation;_loading=NO;_failed=NO;_more=NO;_webImportMode=YES;[_refresh endRefreshing];NSUInteger added=0;
    for(NSDictionary *record in items){if(![record isKindOfClass:NSDictionary.class])continue;NSString *identifier=DGValue(record[_searchKind?@"sec":@"id"]);if(!identifier.length||[_ids containsObject:identifier]||(!_searchKind&&!ReadWork(record).playable()))continue;[_ids addObject:identifier];[_records addObject:record];++added;}
    _empty.text=_records.count?@"":@"网页还没有可导入的结果";_searchHint.text=[NSString stringWithFormat:@"本次新增 %lu 条，共 %lu 条。可再次进入网页，继续翻页并导回。",(unsigned long)added,(unsigned long)_records.count];[_footer setTitle:@"使用上方网页按钮继续翻页" forState:UIControlStateNormal];_footer.enabled=NO;[_table reloadData];
}
- (void)showFollowing {
    UIViewController *following=DGMakeFollowing(_bridge,self.sec?:@"",self.uid?:@"");[self.navigationController pushViewController:following animated:YES];
}
- (void)openAvatar {
    NSString *url=DGValue(_mode==DGExploreMusic?self.music[@"cover"]:_person[@"avatar"]);if(url.length)DGShowImage(self,url,_avatar);
}
- (void)saveAvatar:(UILongPressGestureRecognizer *)gesture{
    if(gesture.state!=UIGestureRecognizerStateBegan)return;NSString *url=DGValue(_person[@"avatar"]);if(!url.length){DGToast(self,@"头像尚未加载完成");return;}[[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight]impactOccurred];DGConfirmAvatarSave(self,url);
}
- (void)updateRelationship{
    BOOL me=_own||[_person[@"isMe"]boolValue],blocked=[_person[@"blocked"]boolValue];NSInteger status=Number(_person[@"followStatus"]);
    _followUser.hidden=me;_blockUser.hidden=me;_followUser.enabled=!me&&!_relationshipBusy&&!blocked&&self.uid.length>0;_blockUser.enabled=!me&&!_relationshipBusy&&self.uid.length>0;
    [_followUser setTitle:status==2?@"互相关注":status==4?@"已申请":status==1?@"已关注":@"关注" forState:UIControlStateNormal];_followUser.tintColor=status?UIColor.secondaryLabelColor:UIColor.systemPinkColor;
    [_blockUser setTitle:blocked?@"解除拉黑":@"拉黑" forState:UIControlStateNormal];_blockUser.tintColor=blocked?UIColor.systemOrangeColor:UIColor.secondaryLabelColor;
}
- (void)toggleFollow{
    if(_relationshipBusy||!_followUser.enabled)return;BOOL add=Number(_person[@"followStatus"])==0;[self writeRelationship:@"follow" add:add];
}
- (void)confirmBlock{
    if(_relationshipBusy||!_blockUser.enabled||self.presentedViewController)return;BOOL add=![_person[@"blocked"]boolValue];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:add?@"拉黑这个用户？":@"解除拉黑？" message:self.displayName preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:add?@"确认拉黑":@"解除拉黑" style:add?UIAlertActionStyleDestructive:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self writeRelationship:@"block" add:add];}]];[self presentViewController:alert animated:YES completion:nil];
}
- (void)writeRelationship:(NSString *)operation add:(BOOL)add{
    if(_relationshipBusy)return;_relationshipBusy=YES;[self updateRelationship];__weak DGExplore *weak=self;
    [_bridge request:operation parameters:@{@"uid":self.uid?:@"",@"sec":self.sec?:@"",@"add":@(add)} completion:^(NSDictionary *result,NSString *error){DGExplore *self=weak;if(!self)return;self->_relationshipBusy=NO;if(error||![result[@"ok"]boolValue]){[self updateRelationship];DGToast(self,error?:@"平台未确认操作结果，请稍后重试");return;}
        NSMutableDictionary *person=[self->_person mutableCopy];if([operation isEqualToString:@"follow"])person[@"followStatus"]=result[@"followStatus"]?:@(add?1:0);else person[@"blocked"]=@(add);self->_person=person;[self updateRelationship];[[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight]impactOccurred];DGToast(self,[operation isEqualToString:@"follow"]?(add?@"已提交关注":@"已取消关注"):(add?@"已拉黑":@"已解除拉黑"));
    }];
}
- (void)toggleAudio{if(DGMusicMatches(DGValue(self.music[@"id"]))&&DGMusicPlayer().rate>0)DGMusicPause();else DGMusicPlay(self.music);[self updateMusicPlayback];}
- (void)updateMusicPlayback{if([self musicRows]){NSString *identifier=DGCurrentMusicID();BOOL playing=DGMusicPlayer().rate>0;if(![_lastQueueID isEqualToString:identifier]||_lastQueuePlaying!=playing){_lastQueueID=identifier;_lastQueuePlaying=playing;[_table reloadData];}}[_play setImage:[UIImage systemImageNamed:DGMusicMatches(DGValue(self.music[@"id"]))&&DGMusicPlayer().rate>0?@"pause.fill":@"play.fill"] forState:UIControlStateNormal];}
- (void)pauseAudio{if(DGMusicMatches(DGValue(self.music[@"id"])))DGMusicPause();}
- (void)collectMusic{
 if(_musicCollectBusy)return;NSString *identifier=DGValue(self.music[@"id"]);if(!identifier.length)return;_musicCollectBusy=YES;BOOL add=![self.music[@"collected"]boolValue];__weak DGExplore *weak=self;
 [_bridge request:@"musicCollect" parameters:@{@"id":identifier,@"add":@(add)} completion:^(NSDictionary *result,NSString *error){DGExplore *self=weak;if(!self)return;self->_musicCollectBusy=NO;if(error||![result[@"ok"]boolValue]){DGToast(self,error?:@"平台未确认原声收藏结果");return;}NSMutableDictionary *music=[self.music mutableCopy];music[@"collected"]=@(add);self.music=music;[self updateMusicHeader];[[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight]impactOccurred];DGToast(self,add?@"原声已收藏":@"已取消原声收藏");}];
}
- (void)saveAudio{NSString *url=DGValue(self.music[@"url"]);if(!url.length){DGToast(self,@"平台未提供可保存的原声地址");return;}DGSaveAudio(self,url,DGValue(self.music[@"title"]));}
- (void)longSave:(UILongPressGestureRecognizer *)gesture{if(gesture.state==UIGestureRecognizerStateBegan){[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];[self saveAudio];}}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return [self peopleRows]||[self musicRows]?_records.count:(_records.count+2)/3;}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{return [self peopleRows]||[self musicRows]?86:(tableView.bounds.size.width-24)/3*1.42+29;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
 if([self peopleRows]||[self musicRows]){DGExplorePersonCell *cell=[tableView dequeueReusableCellWithIdentifier:@"person" forIndexPath:indexPath];[cell record:_records[indexPath.row] music:[self musicRows]];return cell;}
 DGExploreGridRow *cell=[tableView dequeueReusableCellWithIdentifier:@"work" forIndexPath:indexPath];NSUInteger base=indexPath.row*3;NSArray *records=[_records subarrayWithRange:NSMakeRange(base,MIN((NSUInteger)3,_records.count-base))];[cell records:records base:base recent:_selectedTab==0?self.locate:@""];__weak DGExplore *weak=self;cell.selectWork=^(NSInteger index){[weak openWork:index];};return cell;
}
- (void)openWork:(NSInteger)index{if(index<0||index>=(NSInteger)_records.count)return;DGMusicStop();UIViewController *player=DGMakeWorkPlayer(_records.copy,index,_bridge);player.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:player animated:YES completion:nil];}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{if(![self peopleRows]&&![self musicRows])return;NSDictionary *record=_records[indexPath.row];if([self peopleRows])[self.navigationController pushViewController:DGMakeProfile(_bridge,DGValue(record[@"sec"]),DGValue(record[@"nickname"]),@"") animated:YES];else{if(!DGValue(record[@"url"]).length){DGToast(self,@"平台未提供该曲目的播放地址");return;}if(DGMusicMatches(DGValue(record[@"id"]))&&DGMusicPlayer().rate>0)DGMusicPause();else DGMusicPlayQueue(_records.copy,indexPath.row,_bridge,_cursor,_more);[_table reloadData];}}
- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)path{if([self musicRows]&&path.row<(NSInteger)_records.count)[self.navigationController pushViewController:DGMakeMusic(_bridge,_records[path.row]) animated:YES];}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath{NSInteger scale=[self peopleRows]||[self musicRows]?1:3;if(!_failed&&_more&&!_loading&&(indexPath.row+4)*scale>=(NSInteger)_records.count)[self loadPage];}

@end

UIViewController *DGMakeProfile(DGBridge *bridge,NSString *sec,NSString *name,NSString *locate){DGExplore *view=[[DGExplore alloc] initWithBridge:bridge mode:DGExploreProfile];view.sec=sec?:@"";view.displayName=name?:@"";view.locate=locate?:@"";return view;}
UIViewController *DGMakeSearch(DGBridge *bridge){return [[DGExplore alloc] initWithBridge:bridge mode:DGExploreSearch];}
UIViewController *DGMakeMusic(DGBridge *bridge,NSDictionary *music){DGExplore *view=[[DGExplore alloc] initWithBridge:bridge mode:DGExploreMusic];view.music=music?:@{};return view;}
UIViewController *DGMakeFollowing(DGBridge *bridge,NSString *sec,NSString *uid){DGExplore *view=[[DGExplore alloc] initWithBridge:bridge mode:DGExploreFollowing];view.sec=sec?:@"";view.uid=uid?:@"";return view;}

