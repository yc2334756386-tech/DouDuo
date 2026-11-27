#import "DGCommon.h"
#import "DGSearchAssist.h"
#import "DGMusicIndex.h"
#import "DGDiagnostics.h"
#import "DGNavigationResume.h"

UIViewController *DGMakeFollowing(DGBridge *, NSString *, NSString *);

static NSString *DGValue(id value) { return Text(String(value)); }
static NSString *DGPublished(NSDictionary *record) {
    long long timestamp=Number(record[@"publishedAt"]); if(timestamp<=0)return @"发布日期未提供";
    NSDateFormatter *formatter=[NSDateFormatter new]; formatter.dateFormat=@"yyyy-MM-dd HH:mm";
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
    DGImage *_image;UILabel *_name,*_subtitle,*_chevron,*_newBadge;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if((self=[super initWithStyle:style reuseIdentifier:identifier])) {
        self.backgroundColor=UIColor.clearColor;self.selectionStyle=UITableViewCellSelectionStyleNone;
        _image=[DGImage new];_image.contentMode=UIViewContentModeScaleAspectFill;_image.clipsToBounds=YES;_image.backgroundColor=[UIColor colorWithWhite:1 alpha:.07];
        _name=Label(16,UIFontWeightSemibold);_subtitle=Label(12,UIFontWeightRegular);_subtitle.textColor=UIColor.secondaryLabelColor;_subtitle.numberOfLines=2;
        _chevron=Label(20,UIFontWeightRegular);_chevron.text=@"›";_chevron.textColor=UIColor.tertiaryLabelColor;
        _newBadge=Label(10,UIFontWeightBold);_newBadge.text=@"新";_newBadge.textAlignment=NSTextAlignmentCenter;_newBadge.backgroundColor=UIColor.systemPinkColor;_newBadge.layer.cornerRadius=5;_newBadge.clipsToBounds=YES;[self.contentView addSubview:_newBadge];
        for(UIView *view in @[_image,_name,_subtitle,_chevron])[self.contentView addSubview:view];
    }return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];CGFloat width=self.contentView.bounds.size.width;
    _image.frame=CGRectMake(20,15,56,56);_name.frame=CGRectMake(91,17,MAX(0,width-128),23);_subtitle.frame=CGRectMake(91,43,MAX(0,width-128),32);_chevron.frame=CGRectMake(width-32,25,20,30);
        _newBadge.frame=CGRectMake(width-63,19,23,19);if(!_newBadge.hidden)_name.frame=CGRectMake(91,17,MAX(0,width-160),23);
}
- (void)record:(NSDictionary *)record music:(BOOL)music {
    _newBadge.hidden=![record[@"newInBatch"]boolValue];self.accessoryType=music?UITableViewCellAccessoryDetailButton:UITableViewCellAccessoryNone;_chevron.hidden=music;_image.layer.cornerRadius=music?12:28;[_image remote:DGValue(record[music?@"cover":@"avatar"])];
    _name.text=DGValue(record[music?@"title":@"nickname"]);_name.textColor=music&&DGMusicMatches(DGValue(record[@"id"]))?UIColor.systemTealColor:UIColor.labelColor;
    if(music){NSInteger seconds=Number(record[@"duration"]);_subtitle.text=[NSString stringWithFormat:@"%@%@",DGValue(record[@"author"]),seconds>0?[NSString stringWithFormat:@" · %ld:%02ld",(long)seconds/60,(long)seconds%60]:@""];}
    else {NSString *signature=DGValue(record[@"signature"]);_subtitle.text=signature.length?signature:[NSString stringWithFormat:@"%@ 作品 · %@ 粉丝",DGCount(record[@"works"]),DGCount(record[@"followers"])];}
}
@end

@interface DGGridTile:UIControl
- (void)record:(NSDictionary *)record recent:(BOOL)recent;
@end
@implementation DGGridTile{DGImage *_poster;UILabel *_caption,*_date,*_badge,*_recent,*_newBadge,*_pinnedBadge;}
- (instancetype)initWithFrame:(CGRect)frame{if((self=[super initWithFrame:frame])){_poster=[DGImage new];_poster.contentMode=UIViewContentModeScaleAspectFill;_poster.clipsToBounds=YES;_poster.layer.cornerRadius=8;_poster.backgroundColor=[UIColor colorWithWhite:1 alpha:.06];[self addSubview:_poster];_caption=Label(11,UIFontWeightMedium);_caption.numberOfLines=2;_caption.textColor=UIColor.whiteColor;_caption.backgroundColor=[UIColor colorWithWhite:0 alpha:.34];[_poster addSubview:_caption];_date=Label(10,UIFontWeightRegular);_date.textColor=UIColor.secondaryLabelColor;[self addSubview:_date];_badge=Label(10,UIFontWeightSemibold);_badge.textAlignment=NSTextAlignmentCenter;_badge.backgroundColor=[UIColor colorWithWhite:0 alpha:.4];_badge.layer.cornerRadius=5;_badge.clipsToBounds=YES;[_poster addSubview:_badge];_recent=Label(10,UIFontWeightSemibold);_recent.text=@"刚刚看过";_recent.backgroundColor=[UIColor colorWithRed:.08 green:.36 blue:.38 alpha:.94];[_poster addSubview:_recent];_newBadge=Label(11,UIFontWeightBold);_newBadge.text=@"新";_newBadge.textAlignment=NSTextAlignmentCenter;_newBadge.backgroundColor=UIColor.systemPinkColor;_newBadge.layer.cornerRadius=5;_newBadge.clipsToBounds=YES;[_poster addSubview:_newBadge];_pinnedBadge=Label(10,UIFontWeightSemibold);_pinnedBadge.text=@"置顶";_pinnedBadge.textAlignment=NSTextAlignmentCenter;_pinnedBadge.backgroundColor=UIColor.systemPinkColor;_pinnedBadge.layer.cornerRadius=4;_pinnedBadge.clipsToBounds=YES;[_poster addSubview:_pinnedBadge];}return self;}
- (void)layoutSubviews{[super layoutSubviews];CGFloat w=self.bounds.size.width,h=self.bounds.size.height;_poster.frame=CGRectMake(0,0,w,h-22);_caption.frame=CGRectMake(4,_poster.bounds.size.height-35,w-8,32);_date.frame=CGRectMake(0,h-19,w,16);_badge.frame=CGRectMake(_newBadge.hidden?w-39:w-69,5,34,18);_recent.frame=CGRectMake(4,_pinnedBadge.hidden?5:27,58,19);_pinnedBadge.frame=CGRectMake(4,5,34,19);_newBadge.frame=CGRectMake(w-29,5,24,20);}
- (void)record:(NSDictionary *)record recent:(BOOL)recent{_pinnedBadge.hidden=![record[@"pinned"]boolValue];_newBadge.hidden=![record[@"newInBatch"]boolValue];[_poster remote:DGValue(record[@"cover"])];_caption.text=DGValue(record[@"caption"]);long long time=Number(record[@"publishedAt"]);NSDateFormatter *f=[NSDateFormatter new];f.dateFormat=@"yyyy-MM-dd HH:mm";_date.text=time>0?[f stringFromDate:[NSDate dateWithTimeIntervalSince1970:time]]:@"日期未知";NSUInteger count=Array(record[@"images"]).count;_badge.hidden=!count;_badge.text=[NSString stringWithFormat:@"%lu图",(unsigned long)count];_recent.hidden=!recent;_poster.layer.borderWidth=recent?2:0;_poster.layer.borderColor=[UIColor colorWithRed:.4 green:.9 blue:.85 alpha:1].CGColor;[self setNeedsLayout];}
@end
@interface DGExploreGridRow:UITableViewCell
@property(nonatomic,copy) void (^selectWork)(NSInteger index);
- (void)records:(NSArray *)records base:(NSInteger)base recent:(NSString *)recent;
- (UIView *)sourceForWork:(NSInteger)index;
@end
@implementation DGExploreGridRow{NSArray<DGGridTile *> *_tiles;}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier{if((self=[super initWithStyle:style reuseIdentifier:identifier])){self.backgroundColor=UIColor.clearColor;self.selectionStyle=UITableViewCellSelectionStyleNone;NSMutableArray *tiles=[NSMutableArray array];for(NSInteger i=0;i<3;i++){DGGridTile *tile=[[DGGridTile alloc]initWithFrame:CGRectZero];[tile addTarget:self action:@selector(select:) forControlEvents:UIControlEventTouchUpInside];[self.contentView addSubview:tile];[tiles addObject:tile];}_tiles=tiles;}return self;}
- (void)layoutSubviews{[super layoutSubviews];CGFloat w=(self.contentView.bounds.size.width-24)/3;for(NSUInteger i=0;i<3;i++)_tiles[i].frame=CGRectMake(8+i*(w+4),4,w,self.contentView.bounds.size.height-7);}
- (void)records:(NSArray *)records base:(NSInteger)base recent:(NSString *)recent{for(NSUInteger i=0;i<3;i++){DGGridTile *tile=_tiles[i];tile.hidden=i>=records.count;if(tile.hidden)continue;tile.tag=base+i;NSDictionary *record=records[i];[tile record:record recent:recent.length&&[DGValue(record[@"id"])isEqualToString:recent]];}}
- (UIView *)sourceForWork:(NSInteger)index{for(DGGridTile *tile in _tiles)if(!tile.hidden&&tile.tag==index)return tile;return nil;}
- (void)select:(DGGridTile *)tile{if(self.selectWork)self.selectWork(tile.tag);}
- (void)prepareForReuse{[super prepareForReuse];self.selectWork=nil;}
@end


typedef NS_ENUM(NSInteger,DGExploreMode){DGExploreProfile,DGExploreSearch,DGExploreMusic,DGExploreFollowing};
@interface DGExplore : UIViewController <UITableViewDataSource,UITableViewDelegate,UISearchBarDelegate,DGPageResume>
- (instancetype)initWithBridge:(DGBridge *)bridge mode:(DGExploreMode)mode;
@property(nonatomic,copy) NSString *sec;
@property(nonatomic,copy) NSString *uid;
@property(nonatomic,copy) NSString *displayName;
@property(nonatomic,copy) NSString *locate;
@property(nonatomic,strong) NSDictionary *music;
@property(nonatomic,strong) NSDictionary *resumeData;
@end
@implementation DGExplore {
    DGBridge *_bridge;DGExploreMode _mode;
    UITableView *_table;UIView *_header;UIButton *_footer;UILabel *_empty;
    DGImage *_avatar;UILabel *_name,*_signature,*_stats,*_context;UISegmentedControl *_tabs;UIButton *_followingButton,*_play,*_collectMusic;BOOL _musicCollectBusy,_refreshingMusicID;
    UIVisualEffectView *_musicControls;UISearchBar *_search;UIRefreshControl *_refresh;
    UISegmentedControl *_searchTabs;UIButton *_webSearch,*_followUser,*_blockUser;UILabel *_searchHint;UIViewController *_searchPage;
    NSInteger _searchKind;BOOL _relationshipBusy,_webImportMode;
    DGSearchAssist *_assist;CGFloat _keyboardTop;
    UIVisualEffectView *_locateGlass;UIButton *_locateButton;BOOL _locating;
    UISearchBar *_librarySearch;NSString *_libraryQuery;NSInteger _libraryPages;
    BOOL _profileSearchOpen,_locateKeywordResult;NSArray<NSDictionary *> *_filteredWorks;__weak UIViewController *_zoomPlayer;
    NSMutableArray<NSDictionary *> *_records;NSMutableSet<NSString *> *_ids;
    NSDictionary *_person;NSString *_cursor,*_query;BOOL _own,_loading,_more,_failed,_locateFound,_profileLoading;
    NSString *_lastQueueID;BOOL _lastQueuePlaying,_restoreListPosition;NSUInteger _generation,_seekPages;NSInteger _selectedTab;AVPlayer *_audio;id _audioEnd;
}
- (instancetype)initWithBridge:(DGBridge *)bridge mode:(DGExploreMode)mode {
    if((self=[super init])){_bridge=bridge;_mode=mode;_records=[NSMutableArray array];_ids=[NSMutableSet set];_cursor=@"0";_more=YES;_query=@"";}return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.systemBackgroundColor;
    _own=_mode==DGExploreProfile&&(self.resumeData?[self.resumeData[@"own"]boolValue]:!self.sec.length);
    self.title=_mode==DGExploreSearch?@"搜索":_mode==DGExploreMusic?@"原声":_mode==DGExploreFollowing?@"关注列表":_own?@"我的":self.displayName;
    self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    if(_mode==DGExploreProfile){
        UIBarButtonItem *find=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"magnifyingglass"] style:UIBarButtonItemStylePlain target:self action:@selector(toggleProfileSearch)];
        find.accessibilityLabel=@"搜索主页作品";self.navigationItem.rightBarButtonItem=find;
    }
    if(_mode==DGExploreSearch||_mode==DGExploreMusic)self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"globe"] style:UIBarButtonItemStylePlain target:self action:@selector(openSearchPage)];
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
    if(_mode==DGExploreProfile&&self.locate.length){_locateGlass=Glass(23);[self.view addSubview:_locateGlass];_locateButton=[UIButton buttonWithType:UIButtonTypeSystem];[_locateButton setTitle:@"定位刚刚看过" forState:UIControlStateNormal];[_locateButton setImage:[UIImage systemImageNamed:@"scope"] forState:UIControlStateNormal];_locateButton.tintColor=UIColor.labelColor;_locateButton.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];[_locateButton addTarget:self action:@selector(beginLocate) forControlEvents:UIControlEventTouchUpInside];[_locateGlass.contentView addSubview:_locateButton];_table.contentInset=UIEdgeInsetsMake(0,0,76,0);}
    if(_mode==DGExploreSearch){_assist=[[DGSearchAssist alloc]initWithBridge:_bridge];[self.view addSubview:_assist];__weak DGExplore *weak=self;_assist.selected=^(NSString *word){[weak submitSearch:word];};_assist.fill=^(NSString *word){DGExplore *self=weak;if(!self)return;self->_search.text=word;[self->_search becomeFirstResponder];[self->_assist keyword:word];};[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];}
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateMusicPlayback) name:@"DGMusicStateChanged" object:nil];
    if(self.resumeData){[self applyResumeData];}
    else if(_mode==DGExploreProfile)[self loadProfile];
    else if(_mode==DGExploreSearch){_more=NO;_empty.text=@"搜索视频与图文作品";[_footer setTitle:@"输入关键词并搜索" forState:UIControlStateNormal];}
    else if(_mode==DGExploreFollowing&&!self.sec.length)[self loadFollowingIdentity];
    else if(_mode==DGExploreMusic){[self seedKnownMusicWorks];[self updateMusicHeader];[self loadMusicDetail];[self loadPage];}
    else [self loadPage];
}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];DGSaveNavigationResume(self.view.window);}
- (NSDictionary *)dgResumeState {
 if(!_table)return self.resumeData;
 BOOL single=[self peopleRows]||[self musicRows];NSUInteger scale=single?1:3;
 NSIndexPath *first=[[_table.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)]firstObject];
 NSArray *listed=[self listed];NSUInteger anchor=first?MIN((NSUInteger)first.row*scale,listed.count):0;
 NSDictionary *anchorRecord=anchor<listed.count?listed[anchor]:nil;
 NSString *anchorID=DGValue(anchorRecord[single&&[self peopleRows]?@"sec":@"id"]);
 NSUInteger location=anchorRecord?[_records indexOfObject:anchorRecord]:0;if(location==NSNotFound)location=0;
 NSUInteger start=location>90?((location-90)/3)*3:0,count=MIN((NSUInteger)180,_records.count-start);
 NSArray *records=[_records subarrayWithRange:NSMakeRange(start,count)];
 CGFloat inset=first?CGRectGetMinY([_table rectForRowAtIndexPath:first])-_table.contentOffset.y:0;
 return @{@"kind":@"explore",@"mode":@(_mode),@"sec":self.sec?:@"",@"uid":self.uid?:@"",@"name":self.displayName?:@"",@"locate":self.locate?:@"",@"music":self.music?:@{},@"person":_person?:@{},@"own":@(_own),@"tab":@(_selectedTab),@"searchKind":@(_searchKind),@"query":_query?:@"",@"draft":_search.text?:@"",@"libraryQuery":_libraryQuery?:@"",@"profileSearch":@(_profileSearchOpen),@"webImport":@(_webImportMode),@"records":records,@"cursor":_cursor?:@"0",@"more":@(_more&&start+count==_records.count),@"offset":@(_table.contentOffset.y),@"anchorID":anchorID,@"anchorInset":@(inset)};
}
- (void)applyResumeData {
 NSDictionary *state=self.resumeData;
 _selectedTab=MAX(0,MIN(_own?3:1,Number(state[@"tab"])));_tabs.selectedSegmentIndex=_selectedTab;
 _searchKind=MAX(0,MIN(1,Number(state[@"searchKind"])));_searchTabs.selectedSegmentIndex=_searchKind;
 _query=DGValue(state[@"query"]);_search.text=DGValue(state[@"draft"]);_libraryQuery=DGValue(state[@"libraryQuery"]);_librarySearch.text=_libraryQuery;
 _profileSearchOpen=[state[@"profileSearch"]boolValue];_webImportMode=[state[@"webImport"]boolValue];_cursor=DGValue(state[@"cursor"]);if(!_cursor.length)_cursor=@"0";_more=[state[@"more"]boolValue];
 for(id value in Array(state[@"records"])){
  if(![value isKindOfClass:NSDictionary.class])continue;NSDictionary *record=value;NSString *identifier=DGValue(record[[self peopleRows]?@"sec":@"id"]);
  if(!identifier.length||[_ids containsObject:identifier])continue;
  if(![self peopleRows]&&![self musicRows]&&!ReadWork(record).playable())continue;
  [_records addObject:record];[_ids addObject:identifier];if(_records.count==180)break;
 }
 if(_mode==DGExploreProfile&&[state[@"person"]isKindOfClass:NSDictionary.class]&&[state[@"person"]count]){_person=state[@"person"];[self showProfile:_person];}
 if(_mode==DGExploreMusic)[self updateMusicHeader];
 _assist.hidden=YES;_searchHint.text=@"已恢复上次的关键词和结果，可继续搜索或网页翻页。";
 _empty.text=_records.count?@"":@"已恢复上次页面，可下拉刷新";[_footer setTitle:_more?@"继续加载":@"已恢复上次列表，可下拉刷新" forState:UIControlStateNormal];_footer.enabled=_more;
 _restoreListPosition=YES;[_table reloadData];[self.view setNeedsLayout];
 if(_mode==DGExploreProfile&&!_person)[self loadProfile];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    id<UIViewControllerTransitionCoordinator> transition=self.transitionCoordinator;
    if(animated&&_zoomPlayer&&[transition viewControllerForKey:UITransitionContextFromViewControllerKey]==_zoomPlayer){
        [transition animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context){self->_table.transform=CGAffineTransformIdentity;}
                                  completion:^(id<UIViewControllerTransitionCoordinatorContext> context){if(!context.isCancelled)self->_zoomPlayer=nil;}];
    }else _table.transform=CGAffineTransformIdentity;
    if(_mode==DGExploreMusic)[self updateMusicPlayback];
    if(self.navigationController.viewControllers.firstObject==self)self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
}
- (void)viewWillDisappear:(BOOL)animated {
 [super viewWillDisappear:animated];
 id<UIViewControllerTransitionCoordinator> transition=self.transitionCoordinator;
 if(!animated||!_zoomPlayer||[transition viewControllerForKey:UITransitionContextToViewControllerKey]!=_zoomPlayer)return;
 [transition animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context){
  self->_table.transform=CGAffineTransformMakeScale(.975,.975);
 } completion:^(id<UIViewControllerTransitionCoordinatorContext> context){if(context.isCancelled)self->_table.transform=CGAffineTransformIdentity;}];
}
- (void)viewDidDisappear:(BOOL)animated{[super viewDidDisappear:animated];if(UIApplication.sharedApplication.applicationState==UIApplicationStateActive)DGMusicStopOwned(self);}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];if(_audioEnd)[NSNotificationCenter.defaultCenter removeObserver:_audioEnd];}
- (UIStatusBarStyle)preferredStatusBarStyle{return UIStatusBarStyleDefault;}
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
        _stats=Label(13,UIFontWeightMedium);_stats.textColor=UIColor.secondaryLabelColor;[_header addSubview:_stats];
        _context=Label(11,UIFontWeightRegular);_context.textColor=UIColor.secondaryLabelColor;_context.numberOfLines=2;[_header addSubview:_context];
        if(_mode==DGExploreProfile){
            _tabs=[[UISegmentedControl alloc] initWithItems:_own?@[@"作品",@"喜欢",@"收藏",@"收藏音乐"]:@[@"作品",@"喜欢"]];_tabs.selectedSegmentIndex=0;
            [_tabs addTarget:self action:@selector(tabChanged) forControlEvents:UIControlEventValueChanged];[_header addSubview:_tabs];
            {_librarySearch=[UISearchBar new];_librarySearch.searchBarStyle=UISearchBarStyleMinimal;_librarySearch.placeholder=@"搜索作品文案或话题";_librarySearch.returnKeyType=UIReturnKeySearch;_librarySearch.delegate=self;_librarySearch.hidden=YES;[_header addSubview:_librarySearch];}
            _followingButton=[UIButton buttonWithType:UIButtonTypeSystem];[_followingButton setTitle:@"关注列表 ›" forState:UIControlStateNormal];_followingButton.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
            [_followingButton addTarget:self action:@selector(showFollowing) forControlEvents:UIControlEventTouchUpInside];[_header addSubview:_followingButton];
            if(!_own){_followUser=[UIButton buttonWithType:UIButtonTypeSystem];_blockUser=[UIButton buttonWithType:UIButtonTypeSystem];[_followUser setTitle:@"关注" forState:UIControlStateNormal];[_blockUser setTitle:@"拉黑" forState:UIControlStateNormal];for(UIButton *button in @[_followUser,_blockUser]){button.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];button.layer.cornerRadius=15;button.backgroundColor=[UIColor colorWithWhite:1 alpha:.08];button.enabled=NO;[_header addSubview:button];}[_followUser addTarget:self action:@selector(toggleFollow) forControlEvents:UIControlEventTouchUpInside];[_blockUser addTarget:self action:@selector(confirmBlock) forControlEvents:UIControlEventTouchUpInside];}
            _name.text=self.displayName.length?self.displayName:(_own?@"我的":@"用户主页");_signature.text=@"正在读取个人资料…";
            _context.text=self.locate.length?@"可点击下方按钮定位刚刚看过的作品":@"作品按平台返回顺序展示";
        }else if(_mode==DGExploreMusic){
            _musicControls=Glass(20);[_header addSubview:_musicControls];_play=Symbol(@"play.fill",self,@selector(toggleAudio));_play.accessibilityLabel=@"播放或暂停原声";[_musicControls.contentView addSubview:_play];
            _collectMusic=Symbol(@"star",self,@selector(collectMusic));_collectMusic.accessibilityLabel=@"收藏原声";[_musicControls.contentView addSubview:_collectMusic];
            
            _context.text=@"使用这首原声的作品";
            _webSearch=[UIButton buttonWithType:UIButtonTypeSystem];[_webSearch setTitle:@"网页查看原声作品并导回 ↗" forState:UIControlStateNormal];_webSearch.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];[_webSearch addTarget:self action:@selector(openMusicPage) forControlEvents:UIControlEventTouchUpInside];[_header addSubview:_webSearch];
        }else{_avatar.hidden=YES;_name.text=@"关注的人";_signature.text=@"点开头像查看主页与作品";}
    }
    [self layoutHeader];_table.tableHeaderView=_header;
}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];[self layoutHeader];if(_locateGlass){CGFloat width=self.view.bounds.size.width;_locateGlass.frame=CGRectMake(MAX(16,width-188),self.view.bounds.size.height-self.view.safeAreaInsets.bottom-60,172,44);_locateButton.frame=_locateGlass.bounds;}if(_assist){CGFloat top=CGRectGetMaxY([_header convertRect:_header.bounds toView:self.view])+4,bottom=_keyboardTop>0?_keyboardTop:self.view.bounds.size.height-self.view.safeAreaInsets.bottom;_assist.frame=CGRectMake(0,top,self.view.bounds.size.width,MAX(0,bottom-top));}
 if(_restoreListPosition&&_table.bounds.size.width>0){
  _restoreListPosition=NO;[_table layoutIfNeeded];CGFloat offset=[self.resumeData[@"offset"]doubleValue];NSString *anchor=DGValue(self.resumeData[@"anchorID"]);NSArray *records=[self listed];
  BOOL people=[self peopleRows];NSUInteger found=[records indexOfObjectPassingTest:^BOOL(NSDictionary *record,NSUInteger i,BOOL *stop){return anchor.length&&[DGValue(record[people?@"sec":@"id"])isEqualToString:anchor];}];
  if(found!=NSNotFound){NSUInteger row=([self peopleRows]||[self musicRows])?found:found/3;offset=CGRectGetMinY([_table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]])-[self.resumeData[@"anchorInset"]doubleValue];}
  CGFloat minimum=-_table.adjustedContentInset.top,maximum=MAX(minimum,_table.contentSize.height-_table.bounds.size.height+_table.adjustedContentInset.bottom);
  if(std::isfinite(offset))[_table setContentOffset:CGPointMake(0,MAX(minimum,MIN(maximum,offset))) animated:NO];
 }
}
- (void)keyboardChanged:(NSNotification *)note{CGRect frame=[self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey]CGRectValue] fromView:nil];_keyboardTop=CGRectGetMinY(frame)>=self.view.bounds.size.height?0:MAX(0,CGRectGetMinY(frame));[self.view setNeedsLayout];[UIView animateWithDuration:.25 animations:^{[self.view layoutIfNeeded];}];}
- (void)layoutHeader {
    BOOL library=[self showsLibrarySearch];_librarySearch.hidden=!library;CGFloat width=self.view.bounds.size.width,height=_mode==DGExploreProfile?(library?326:268):_mode==DGExploreSearch?148:_mode==DGExploreMusic?250:108;
    if(_header.bounds.size.width!=width||_header.bounds.size.height!=height){_header.frame=CGRectMake(0,0,width,height);if(_table.tableHeaderView)_table.tableHeaderView=_header;}
    if(_mode==DGExploreSearch){_search.frame=CGRectMake(10,2,width-20,56);_searchTabs.frame=CGRectMake(18,64,132,32);_webSearch.frame=CGRectMake(158,62,MAX(40,width-176),36);_searchHint.frame=CGRectMake(18,104,width-36,36);return;}
    if(_mode==DGExploreFollowing){_name.frame=CGRectMake(20,10,width-40,36);_signature.frame=CGRectMake(20,52,width-40,32);return;}
    _avatar.frame=CGRectMake(20,16,78,78);_avatar.layer.cornerRadius=_mode==DGExploreMusic?18:39;
    _name.frame=CGRectMake(115,15,MAX(30,width-135),60);_signature.frame=CGRectMake(20,111,width-40,38);
    _stats.frame=CGRectMake(115,80,MAX(30,width-135),20);_context.frame=CGRectMake(20,_mode==DGExploreProfile?190:160,width-40,33);
    if(_mode==DGExploreProfile){_followingButton.frame=CGRectMake(20,154,104,30);CGFloat available=MAX(72,(width-152)/2);_followUser.frame=CGRectMake(132,154,available,30);_blockUser.frame=CGRectMake(140+available,154,available,30);_tabs.frame=CGRectMake(18,232,width-36,32);}
    if(_mode==DGExploreMusic){_musicControls.frame=CGRectMake(width-114,112,94,40);_play.frame=CGRectMake(3,0,44,40);_collectMusic.frame=CGRectMake(47,0,44,40);_signature.frame=CGRectMake(20,112,MAX(40,width-150),36);}
    if(_mode==DGExploreMusic)_webSearch.frame=CGRectMake(18,202,width-36,36);
    _librarySearch.frame=CGRectMake(10,270,width-20,50);
}
- (void)showProfile:(NSDictionary *)result {
 self.sec=DGValue(result[@"sec"]);self.uid=DGValue(result[@"uid"]);self.displayName=DGValue(result[@"nickname"]);
 self.title=_own?@"我的":self.displayName;_name.text=self.displayName;[_avatar remote:DGValue(result[@"avatar"])];
 NSString *signature=DGValue(result[@"signature"]);_signature.text=signature.length?signature:@"这个人还没有填写简介";
 _stats.text=[NSString stringWithFormat:@"%@ 获赞 · %@ 粉丝",DGCount(result[@"likes"]),DGCount(result[@"followers"])];
 [_followingButton setTitle:[NSString stringWithFormat:@"%@ 关注 ›",DGCount(result[@"following"])] forState:UIControlStateNormal];[self updateRelationship];
 NSString *location=DGValue(result[@"location"]);_context.text=self.locate.length?@"可点击下方按钮定位刚刚看过的作品":location.length?location:@"作品按平台返回顺序展示";
}
- (void)loadProfile {
    if(_profileLoading)return;_profileLoading=YES;__weak DGExplore *weakSelf=self;
    [_bridge request:_own?@"profile":@"userProfile" parameters:@{@"sec":self.sec?:@""} completion:^(NSDictionary *result,NSString *error){
        DGExplore *self=weakSelf;if(!self)return;self->_profileLoading=NO;
        if(error||![result[@"loggedIn"] boolValue]){
            NSString *reason=error?:@"登录已失效，请返回首页重新登录";self->_signature.text=reason;self->_empty.text=reason;self->_failed=YES;
            [self->_footer setTitle:@"重新读取个人资料" forState:UIControlStateNormal];self->_footer.enabled=YES;return;
        }
        self->_person=result;[self showProfile:result];
        if(!self.resumeData||!self->_records.count)[self resetList];
    }];
}
- (void)loadFollowingIdentity {
    __weak DGExplore *weakSelf=self;
    [_bridge request:@"profile" parameters:@{} completion:^(NSDictionary *result,NSString *error){DGExplore *self=weakSelf;if(!self)return;
        if(error||![result[@"loggedIn"] boolValue]){self->_empty.text=error?:@"请先登录以查看关注列表";self->_more=NO;[self->_footer setTitle:@"返回首页登录后重试" forState:UIControlStateNormal];return;}
        self.sec=DGValue(result[@"sec"]);self.uid=DGValue(result[@"uid"]);[self loadPage];
    }];
}
- (void)seedKnownMusicWorks {
 NSString *identifier=DGValue(self.music[@"id"]);if(!identifier.length)return;
 NSDictionary *origin=self.music[@"contextWork"];
 if([origin isKindOfClass:NSDictionary.class])DGIndexMusicWorks(@[origin]);
 for(NSDictionary *record in DGIndexedMusicWorks(identifier)){
  NSString *key=DGValue(record[@"id"]);if(!key.length||[_ids containsObject:key]||!ReadWork(record).playable())continue;
  [_ids addObject:key];[_records addObject:record];
 }
 if(_records.count){_empty.text=@"";_context.text=[NSString stringWithFormat:@"本机已识别 %lu 条 · 正在查找更多",(unsigned long)_records.count];[_table reloadData];}
}
- (void)resolveMusicIdentifier {
 NSDictionary *origin=self.music[@"contextWork"];NSString *work=[origin isKindOfClass:NSDictionary.class]?DGValue(origin[@"id"]):@"";
 if(!work.length){_more=NO;_empty.text=@"平台没有提供这首原声的标识";[_footer setTitle:@"" forState:UIControlStateNormal];return;}
 _refreshingMusicID=YES;_empty.text=@"正在识别原声…";NSUInteger generation=_generation;__weak DGExplore *weak=self;
 [_bridge request:@"detail" parameters:@{@"id":work} completion:^(NSDictionary *result,NSString *error){
  DGExplore *self=weak;if(!self||generation!=self->_generation)return;self->_refreshingMusicID=NO;
  NSDictionary *item=Array(result[@"items"]).firstObject;NSString *musicID=DGValue(item[@"musicID"]);
  if(!musicID.length){self->_more=NO;self->_empty.text=@"这条作品未提供可识别的原声标识";[self->_footer setTitle:@"" forState:UIControlStateNormal];return;}
  NSMutableDictionary *music=[self.music mutableCopy];music[@"id"]=musicID;music[@"contextWork"]=item;self.music=music;
  [self seedKnownMusicWorks];[self updateMusicHeader];[self loadMusicDetail];[self loadPage];
 }];
}
- (void)loadMusicDetail {
    NSString *identifier=DGValue(self.music[@"id"]);if(!identifier.length)return;__weak DGExplore *weakSelf=self;
    [_bridge request:@"musicDetail" parameters:@{@"id":identifier} completion:^(NSDictionary *result,NSString *error){DGExplore *self=weakSelf;if(!self)return;
        if(!error){NSMutableDictionary *music=[self.music mutableCopy]?:[NSMutableDictionary dictionary];for(NSString *key in result)if(![key isEqualToString:@"id"]&&DGValue(result[key]).length)music[key]=result[key];self.music=music;[self updateMusicHeader];}
    }];
}
- (void)updateMusicHeader {
    _name.text=DGValue(self.music[@"title"]).length?DGValue(self.music[@"title"]):@"作品原声";_signature.text=DGValue(self.music[@"author"]);
    [_avatar remote:DGValue(self.music[@"cover"])];NSInteger duration=Number(self.music[@"duration"]);_stats.text=duration>0?[NSString stringWithFormat:@"%ld:%02ld",(long)duration/60,(long)duration%60]:@"";
    _play.enabled=DGValue(self.music[@"url"]).length>0;_collectMusic.enabled=DGValue(self.music[@"id"]).length>0;[_collectMusic setImage:[UIImage systemImageNamed:[self.music[@"collected"]boolValue]?@"star.fill":@"star"] forState:UIControlStateNormal];[self updateMusicPlayback];
}
- (BOOL)musicRows{return _mode==DGExploreProfile&&_own&&_selectedTab==3;}
- (BOOL)peopleRows{return _mode==DGExploreFollowing||(_mode==DGExploreSearch&&_searchKind==1);}
- (BOOL)showsLibrarySearch {
 if(_mode!=DGExploreProfile||[self musicRows])return NO;
 return _profileSearchOpen||(_own&&(_selectedTab==1||_selectedTab==2));
}
- (NSArray<NSDictionary *> *)listed {
 if(!_libraryQuery.length||![self showsLibrarySearch])return _records;
 if(_filteredWorks)return _filteredWorks;
 NSArray *tokens=[_libraryQuery componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 NSMutableArray *matches=[NSMutableArray array];
 for(NSDictionary *record in _records){
  NSString *text=[NSString stringWithFormat:@"%@ %@",DGValue(record[@"caption"]),DGValue(record[@"author"])];
  BOOL match=YES;
  for(NSString *token in tokens)if(token.length&&[text rangeOfString:token options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch|NSWidthInsensitiveSearch].location==NSNotFound){match=NO;break;}
  if(match)[matches addObject:record];
 }
 _filteredWorks=matches.copy;return _filteredWorks;
}
- (void)toggleProfileSearch {
 if(_mode!=DGExploreProfile)return;
 if([self musicRows]){_tabs.selectedSegmentIndex=0;[self tabChanged];}
 _profileSearchOpen=!_profileSearchOpen;
 if(!_profileSearchOpen&&_selectedTab==0){[_librarySearch resignFirstResponder];_librarySearch.text=@"";[self libraryChanged:@"" submit:NO];}
 [self.view setNeedsLayout];[self.view layoutIfNeeded];
 if([self showsLibrarySearch]){[_table setContentOffset:CGPointMake(0,-_table.adjustedContentInset.top) animated:NO];[_librarySearch becomeFirstResponder];}
}
- (void)showKeywordResult {
 if(!_locateKeywordResult||![self listed].count)return;
 _locateKeywordResult=NO;
 if([_table numberOfRowsInSection:0]>0)[_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] atScrollPosition:UITableViewScrollPositionTop animated:YES];
}
- (void)libraryChanged:(NSString *)query submit:(BOOL)submit {
 _libraryQuery=[query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 _filteredWorks=nil;_libraryPages=0;_locateKeywordResult=submit&&_libraryQuery.length>0;
 [self endLocate];[_table reloadData];
 _empty.text=_libraryQuery.length&&![self listed].count?(_more?@"当前已加载的作品没有匹配":@"没有匹配的作品"):@"";
 [self showKeywordResult];
 if(_libraryQuery.length&&_more&&(submit||_selectedTab!=0))[self loadPage];
}
- (void)tabChanged {
 [_librarySearch resignFirstResponder];_libraryQuery=@"";_librarySearch.text=@"";_filteredWorks=nil;_libraryPages=0;_locateKeywordResult=NO;
 [self endLocate];DGMusicStopOwned(self);_selectedTab=_tabs.selectedSegmentIndex;
 [self.view setNeedsLayout];[self pauseAudio];[self resetList];
}
- (void)refresh {
    if(_mode==DGExploreProfile&&!_person){[self loadProfile];[_refresh endRefreshing];return;}
    if(_mode==DGExploreSearch&&(!_query.length||_webImportMode)){[_refresh endRefreshing];if(_webImportMode)DGToast(self,@"可使用右上角网页按钮继续翻页；重新搜索可重置结果");return;}[self resetList];
}
- (void)resetList {
    self.resumeData=nil;_restoreListPosition=NO;
    _refreshingMusicID=NO;++_generation;_loading=NO;_more=YES;_failed=NO;_webImportMode=NO;_cursor=@"0";_seekPages=0;_locateFound=NO;_searchHint.text=@"结果只有一页时，可在官网手动翻页，再把已加载结果追加回这里。";[_records removeAllObjects];_filteredWorks=nil;[_ids removeAllObjects];[_table reloadData];if(_mode==DGExploreMusic)[self seedKnownMusicWorks];[self loadPage];
}
- (NSString *)operation {
    if(_mode==DGExploreSearch)return _searchKind==1?@"searchUsers":@"search";if(_mode==DGExploreFollowing)return @"following";if(_mode==DGExploreMusic)return @"musicWorks";
    return @[@"works",@"likes",@"collections",@"musicList"][_selectedTab];
}
- (void)loadPage {
    if(_mode==DGExploreProfile&&!_person){[self loadProfile];return;}
    if(_loading||!_more||_refreshingMusicID)return;if(_mode==DGExploreSearch&&!_query.length)return;
    if(_mode==DGExploreMusic&&!DGValue(self.music[@"id"]).length){[self resolveMusicIdentifier];return;}
    _loading=YES;_failed=NO;_footer.enabled=NO;[_footer setTitle:@"正在加载…" forState:UIControlStateNormal];if(!_records.count)_empty.text=@"正在读取内容";
    NSString *operation=[self operation],*oldCursor=_cursor.copy;NSUInteger generation=_generation;
    NSDictionary *parameters=@{@"sec":self.sec?:@"",@"uid":self.uid?:@"",@"id":DGValue(self.music[@"id"]),@"title":DGValue(self.music[@"title"]),@"author":DGValue(self.music[@"author"]),@"kw":_query?:@"",@"cursor":_cursor};
    __weak DGExplore *weakSelf=self;
    [_bridge request:operation parameters:parameters completion:^(NSDictionary *result,NSString *error){
        DGExplore *self=weakSelf;if(!self||generation!=self->_generation)return;self->_loading=NO;[self->_refresh endRefreshing];
        if(error){[self endLocate];self->_failed=YES;if(self->_mode==DGExploreMusic&&self->_records.count)self->_context.text=[NSString stringWithFormat:@"平台列表暂不可用 · 已识别 %lu 条",(unsigned long)self->_records.count];if(!self->_records.count)self->_empty.text=error;[self->_footer setTitle:@"加载失败，轻点重试" forState:UIControlStateNormal];self->_footer.enabled=YES;return;}
        BOOL people=[self peopleRows],music=[self musicRows];
        if(self->_mode==DGExploreMusic)DGDiagnostic(@"music.lookup",[NSString stringWithFormat:@"source=%@ returned=%lu scanned=%ld more=%d",[result[@"lookup"]isEqual:@"search"]?@"search":@"official",(unsigned long)Array(result[@"items"]).count,(long)Number(result[@"scanned"]),[result[@"more"]boolValue]]);
        for(id raw in Array(result[@"items"])){
            if(![raw isKindOfClass:NSDictionary.class])continue;NSDictionary *record=raw;NSString *identifier=DGValue(record[people?@"sec":@"id"]);
            if(!identifier.length||[self->_ids containsObject:identifier])continue;
            if(!people&&!music&&!ReadWork(record).playable())continue;
            if(self->_mode==DGExploreMusic&&![DGValue(record[@"musicID"])isEqualToString:DGValue(self.music[@"id"])])continue;
            [self->_ids addObject:identifier];[self->_records addObject:record];
        }
        if(self->_mode==DGExploreProfile&&self->_selectedTab==0)[self->_records sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){BOOL first=[a[@"pinned"]boolValue],second=[b[@"pinned"]boolValue];return first==second?NSOrderedSame:first?NSOrderedAscending:NSOrderedDescending;}];++self->_seekPages;self->_cursor=DGValue(result[@"cursor"]);if(!self->_cursor.length)self->_cursor=@"0";
        self->_more=[result[@"more"] boolValue]&&![oldCursor isEqualToString:self->_cursor];
        if(self->_mode==DGExploreMusic)self->_context.text=[NSString stringWithFormat:[result[@"lookup"]isEqual:@"search"]?@"已按原声 ID 核对 %lu 条 · 搜索结果可能不全":@"使用这首原声的作品 · 已识别 %lu 条",(unsigned long)self->_records.count];
        self->_empty.text=self->_records.count?@"":people?@"暂无可查看的用户":music?@"还没有收藏音乐":@"暂无可查看的作品，内容也可能被账号隐私设置限制";
        [self->_footer setTitle:self->_more?@"继续加载":@"已显示全部可查看内容" forState:UIControlStateNormal];self->_footer.enabled=self->_more;
        if(self->_mode==DGExploreMusic&&[result[@"lookup"]isEqual:@"search"]){
            if(!self->_records.count)self->_empty.text=@"当前搜索页未找到同一原声的作品，可继续查找或打开网页翻页";
            [self->_footer setTitle:self->_more?@"继续查找同原声作品":@"本次搜索结束，可使用网页继续查找" forState:UIControlStateNormal];
        }
        self->_filteredWorks=nil;[self->_table reloadData];[self locateIfNeeded];
        if(self->_libraryQuery.length){
            BOOL found=[self listed].count>0;[self showKeywordResult];
            BOOL scanning=self->_more&&++self->_libraryPages<40&&(!found||self->_selectedTab!=0);
            self->_empty.text=found?@"":scanning?@"正在查找更多作品…":@"暂无匹配作品";
            if(scanning){NSString *query=self->_libraryQuery.copy;dispatch_async(dispatch_get_main_queue(),^{if(generation==self->_generation&&[query isEqualToString:self->_libraryQuery])[self loadPage];});}
            [self->_footer setTitle:self->_more?@"继续查找更多作品":@"已搜索全部可读取作品" forState:UIControlStateNormal];
        }
    }];
}
- (void)locateIfNeeded {
    if(!_locating||_mode!=DGExploreProfile||_selectedTab!=0||!self.locate.length||_locateFound)return;
    NSInteger found=NSNotFound;for(NSUInteger index=0;index<_records.count;++index)if([DGValue(_records[index][@"id"]) isEqualToString:self.locate]){found=index;break;}
    if(found!=NSNotFound){_locateFound=YES;[self endLocate];_context.text=@"已定位到刚刚看过的作品";[_table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:found/3 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
        dispatch_async(dispatch_get_main_queue(),^{if(found/3<[self->_table numberOfRowsInSection:0])[self->_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:found/3 inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:YES];});return;}
    if(_more&&_seekPages<15){_context.text=[NSString stringWithFormat:@"正在定位刚刚看过的作品 · 已读取 %lu 页",(unsigned long)_seekPages];dispatch_async(dispatch_get_main_queue(),^{[self loadPage];});}
    else{_context.text=_more?@"前 15 页未找到刚刚看过的作品，可继续下滑加载":@"该作品未出现在此主页可查看的作品列表中";[self endLocate];}
}
- (void)beginLocate{DGHaptic();if(_libraryQuery.length){[_librarySearch resignFirstResponder];_librarySearch.text=@"";[self libraryChanged:@"" submit:NO];}if(_selectedTab!=0){_selectedTab=0;_tabs.selectedSegmentIndex=0;[self resetList];}_locateFound=NO;_locating=YES;_locateButton.enabled=NO;[_locateButton setTitle:@"正在定位…" forState:UIControlStateNormal];[self locateIfNeeded];}
- (void)endLocate{_locating=NO;_locateButton.enabled=YES;[_locateButton setTitle:@"定位刚刚看过" forState:UIControlStateNormal];}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    if(searchBar==_librarySearch){[searchBar resignFirstResponder];[self libraryChanged:searchBar.text submit:YES];return;}
    [self submitSearch:searchBar.text];
}
- (void)submitSearch:(NSString *)word{NSString *query=[word stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!query.length)return;_search.text=query;[_assist remember:query];[_search resignFirstResponder];_assist.hidden=YES;_table.scrollEnabled=YES;_query=query;_searchPage=nil;[self resetList];}
- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar{if(searchBar==_librarySearch)return;[_table setContentOffset:CGPointMake(0,-_table.adjustedContentInset.top) animated:NO];_assist.hidden=NO;_table.scrollEnabled=NO;[_assist keyword:searchBar.text];[self.view setNeedsLayout];}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText{if(searchBar==_librarySearch){[self libraryChanged:searchText submit:NO];return;}_assist.hidden=NO;[_assist keyword:searchText];[self.view setNeedsLayout];}
- (void)searchKindChanged{
    _searchKind=_searchTabs.selectedSegmentIndex;_searchPage=nil;_search.placeholder=_searchKind?@"搜索用户昵称或抖音号":@"搜索视频与图文";_query=[_search.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]?:@"";
    [self resetList];if(!_query.length){_more=NO;_empty.text=_searchKind?@"搜索用户昵称或抖音号":@"搜索视频与图文作品";[_footer setTitle:@"输入关键词并搜索" forState:UIControlStateNormal];}
}
- (void)openSearchPage{
    if(_mode==DGExploreMusic){[self openMusicPage];return;}
    _assist.hidden=YES;_table.scrollEnabled=YES;
    NSString *query=[_search.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!query.length){DGToast(self,@"请先输入搜索词");return;}[_search resignFirstResponder];[_assist remember:query];if(![query isEqualToString:_query]){_query=query;_searchPage=nil;[self resetList];}
    if(!_searchPage){__weak DGExplore *weak=self;NSString *keyword=_query.copy;NSInteger kind=_searchKind;_searchPage=DGMakeSearchPage(keyword,kind==1,^(NSArray<NSDictionary *> *items){DGExplore *self=weak;if(!self||![self->_query isEqualToString:keyword]||self->_searchKind!=kind)return;[self importSearchItems:items];});}
    [self.navigationController pushViewController:_searchPage animated:YES];
}
- (void)importSearchItems:(NSArray<NSDictionary *> *)items{
    ++_generation;_loading=NO;_failed=NO;_more=NO;_webImportMode=YES;[_refresh endRefreshing];NSUInteger added=0;for(NSUInteger index=0;index<_records.count;index++){NSMutableDictionary *old=[_records[index]mutableCopy];[old removeObjectForKey:@"newInBatch"];_records[index]=old;}
    for(NSDictionary *record in items){if(![record isKindOfClass:NSDictionary.class])continue;NSString *identifier=DGValue(record[_searchKind?@"sec":@"id"]);if(!identifier.length||[_ids containsObject:identifier]||(!_searchKind&&!ReadWork(record).playable()))continue;if(_mode==DGExploreMusic&&![DGValue(record[@"musicID"])isEqualToString:DGValue(self.music[@"id"])])continue;[_ids addObject:identifier];NSMutableDictionary *fresh=[record mutableCopy];fresh[@"newInBatch"]=@YES;[_records addObject:fresh];++added;}
    _empty.text=_records.count?@"":@"网页还没有可导入的结果";NSString *summary=[NSString stringWithFormat:@"本次新增 %lu 条，共 %lu 条。可再次进入网页，继续翻页并导回。",(unsigned long)added,(unsigned long)_records.count];_searchHint.text=summary;if(_mode==DGExploreMusic)_context.text=summary;[_footer setTitle:@"使用上方网页按钮继续翻页" forState:UIControlStateNormal];_footer.enabled=NO;[_table reloadData];
}
- (void)openMusicPage{
    NSString *identifier=DGValue(self.music[@"id"]);if(!identifier.length){DGToast(self,@"平台未提供原声标识");return;}
    if(!_searchPage){NSString *title=DGValue(self.music[@"title"]),*author=DGValue(self.music[@"author"]);NSString *keyword=[title isEqual:@"原声"]||[title isEqual:@"作品原声"]?@"":title;if(keyword.length&&author.length&&[title rangeOfString:author].location==NSNotFound)keyword=[keyword stringByAppendingFormat:@" %@",author];__weak DGExplore *weak=self;_searchPage=DGMakeMusicWebPage(identifier,keyword,^(NSArray<NSDictionary *> *items){[weak importSearchItems:items];});}
    [self.navigationController pushViewController:_searchPage animated:YES];
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
- (void)toggleAudio{if(DGMusicMatches(DGValue(self.music[@"id"]))&&DGMusicPlayer().rate>0)DGMusicPause();else{DGMusicSetOwner(self);DGMusicPlay(self.music);}[self updateMusicPlayback];}
- (void)updateMusicPlayback{if([self musicRows]){NSString *identifier=DGCurrentMusicID();BOOL playing=DGMusicPlayer().rate>0;if(![_lastQueueID isEqualToString:identifier]||_lastQueuePlaying!=playing){_lastQueueID=identifier;_lastQueuePlaying=playing;[_table reloadData];}}[_play setImage:[UIImage systemImageNamed:DGMusicMatches(DGValue(self.music[@"id"]))&&DGMusicPlayer().rate>0?@"pause.fill":@"play.fill"] forState:UIControlStateNormal];}
- (void)pauseAudio{if(DGMusicMatches(DGValue(self.music[@"id"])))DGMusicPause();}
- (void)collectMusic{
 if(_musicCollectBusy)return;NSString *identifier=DGValue(self.music[@"id"]);if(!identifier.length)return;_musicCollectBusy=YES;BOOL add=![self.music[@"collected"]boolValue];__weak DGExplore *weak=self;
 [_bridge request:@"musicCollect" parameters:@{@"id":identifier,@"add":@(add)} completion:^(NSDictionary *result,NSString *error){DGExplore *self=weak;if(!self)return;self->_musicCollectBusy=NO;if(error||![result[@"ok"]boolValue]){DGToast(self,error?:@"平台未确认原声收藏结果");return;}NSMutableDictionary *music=[self.music mutableCopy];music[@"collected"]=@(add);self.music=music;[self updateMusicHeader];[[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight]impactOccurred];DGToast(self,add?@"原声已收藏":@"已取消原声收藏");}];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return [self peopleRows]||[self musicRows]?[self listed].count:([self listed].count+2)/3;}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{return [self peopleRows]||[self musicRows]?86:(tableView.bounds.size.width-24)/3*1.42+29;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
 if([self peopleRows]||[self musicRows]){DGExplorePersonCell *cell=[tableView dequeueReusableCellWithIdentifier:@"person" forIndexPath:indexPath];[cell record:[self listed][indexPath.row] music:[self musicRows]];return cell;}
 DGExploreGridRow *cell=[tableView dequeueReusableCellWithIdentifier:@"work" forIndexPath:indexPath];NSUInteger base=indexPath.row*3;NSArray *records=[[self listed] subarrayWithRange:NSMakeRange(base,MIN((NSUInteger)3,[self listed].count-base))];[cell records:records base:base recent:_selectedTab==0?self.locate:@""];__weak DGExplore *weak=self;cell.selectWork=^(NSInteger index){[weak openWork:index];};return cell;
}
- (void)openWork:(NSInteger)index {
 NSArray *works=[self listed];if(index<0||index>=(NSInteger)works.count)return;
 [_librarySearch resignFirstResponder];DGMusicStop();
 UIViewController *player=DGMakeWorkPlayer(works,index,_bridge);
 if(!self.navigationController){player.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:player animated:YES completion:nil];return;}
 NSString *identifier=DGValue(works[index][@"id"]);__weak DGExplore *weak=self;
 if(!UIAccessibilityIsReduceMotionEnabled()){
  UIZoomTransitionOptions *options=[UIZoomTransitionOptions new];
  options.dimmingVisualEffect=[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
  player.preferredTransition=[UIViewControllerTransition zoomWithOptions:options sourceViewProvider:^UIView *(UIZoomTransitionSourceViewProviderContext *context){
   DGExplore *self=weak;if(!self)return nil;
   NSUInteger current=[[self listed]indexOfObjectPassingTest:^BOOL(NSDictionary *record,NSUInteger offset,BOOL *stop){return [DGValue(record[@"id"])isEqualToString:identifier];}];
   if(current==NSNotFound)return nil;
   NSIndexPath *path=[NSIndexPath indexPathForRow:current/3 inSection:0];
   DGExploreGridRow *row=(DGExploreGridRow *)[self->_table cellForRowAtIndexPath:path];
   return [row isKindOfClass:DGExploreGridRow.class]?[row sourceForWork:current]:nil;
  }];
  _zoomPlayer=player;
 }
 [self.navigationController pushViewController:player animated:YES];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{if(![self peopleRows]&&![self musicRows])return;NSDictionary *record=_records[indexPath.row];if([self peopleRows])[self.navigationController pushViewController:DGMakeProfile(_bridge,DGValue(record[@"sec"]),DGValue(record[@"nickname"]),@"") animated:YES];else{if(!DGValue(record[@"url"]).length){DGToast(self,@"平台未提供该曲目的播放地址");return;}if(DGMusicMatches(DGValue(record[@"id"]))&&DGMusicPlayer().rate>0)DGMusicPause();else{DGMusicSetOwner(self);DGMusicPlayQueue(_records.copy,indexPath.row,_bridge,_cursor,_more);}[_table reloadData];}}
- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)path{if([self musicRows]&&path.row<(NSInteger)[self listed].count)[self.navigationController pushViewController:DGMakeMusic(_bridge,_records[path.row]) animated:YES];}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath{if(_restoreListPosition||(_mode==DGExploreMusic&&[_cursor hasPrefix:@"search:"]))return;NSInteger scale=[self peopleRows]||[self musicRows]?1:3;if(!_failed&&_more&&!_loading&&(indexPath.row+4)*scale>=(NSInteger)[self listed].count)[self loadPage];}

@end

UIViewController *DGMakeProfile(DGBridge *bridge,NSString *sec,NSString *name,NSString *locate){DGExplore *view=[[DGExplore alloc] initWithBridge:bridge mode:DGExploreProfile];view.sec=sec?:@"";view.displayName=name?:@"";view.locate=locate?:@"";return view;}
UIViewController *DGMakeSearch(DGBridge *bridge){return [[DGExplore alloc] initWithBridge:bridge mode:DGExploreSearch];}
UIViewController *DGMakeMusic(DGBridge *bridge,NSDictionary *music){DGExplore *view=[[DGExplore alloc] initWithBridge:bridge mode:DGExploreMusic];view.music=music?:@{};return view;}
UIViewController *DGMakeFollowing(DGBridge *bridge,NSString *sec,NSString *uid){DGExplore *view=[[DGExplore alloc] initWithBridge:bridge mode:DGExploreFollowing];view.sec=sec?:@"";view.uid=uid?:@"";return view;}
UIViewController *DGMakeResumedExplore(DGBridge *bridge,NSDictionary *state){
 NSInteger mode=Number(state[@"mode"]);if(mode<DGExploreProfile||mode>DGExploreFollowing)return nil;
 DGExplore *view=[[DGExplore alloc]initWithBridge:bridge mode:(DGExploreMode)mode];view.sec=DGValue(state[@"sec"]);view.uid=DGValue(state[@"uid"]);view.displayName=DGValue(state[@"name"]);view.locate=DGValue(state[@"locate"]);view.music=[state[@"music"]isKindOfClass:NSDictionary.class]?state[@"music"]:@{};view.resumeData=state;return view;
}

