#import "DGComments.h"
#include <unordered_map>
static NSCache *DGEmojiCache(void){static NSCache *cache;static dispatch_once_t once;dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=250;});return cache;}

@interface DGCommentImage : DGImage
@property(nonatomic, copy) NSString *sourceURL;
@end
@implementation DGCommentImage
@end

@interface DGCommentCell : UITableViewCell
@property(nonatomic,copy) void (^replyAction)(void);
@property(nonatomic,copy) void (^profileAction)(void);
@property(nonatomic,copy) void (^openImageAction)(NSString *,UIImageView *);
@property(nonatomic,copy) void (^saveImageAction)(NSString *);
@property(nonatomic,copy) void (^copyAction)(NSString *);
- (void)display:(const Comment &)comment nested:(BOOL)nested expanded:(BOOL)expanded loading:(BOOL)loading recipient:(NSString *)recipient;
@end
@implementation DGCommentCell {
    DGImage *_avatar;
    UILabel *_name,*_recipient,*_body,*_meta;
    UIButton *_reply;
    UIStackView *_stack,*_media;
    NSLayoutConstraint *_leading,*_avatarWidth,*_avatarHeight;
    NSString *_plainText;
    NSArray<NSDictionary *> *_inlineEmoji;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if((self=[super initWithStyle:style reuseIdentifier:identifier])) {
        self.backgroundColor=UIColor.clearColor; self.selectionStyle=UITableViewCellSelectionStyleNone;
        _avatar=[DGImage new]; _avatar.contentMode=UIViewContentModeScaleAspectFill; _avatar.clipsToBounds=YES;
        _avatar.backgroundColor=[UIColor colorWithWhite:1 alpha:.08]; _avatar.userInteractionEnabled=YES;
        [_avatar addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(profile)]];
        _avatar.isAccessibilityElement=YES; _avatar.accessibilityTraits=UIAccessibilityTraitButton;
        _name=Label(12,UIFontWeightSemibold); _name.textColor=UIColor.secondaryLabelColor;
        _name.userInteractionEnabled=YES; [_name addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(profile)]];
        _recipient=Label(12,UIFontWeightMedium);_recipient.textColor=UIColor.secondaryLabelColor;_recipient.numberOfLines=0;_recipient.hidden=YES;
        _body=Label(15,UIFontWeightRegular); _body.numberOfLines=0; _body.userInteractionEnabled=YES;
        [_body addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(copyText:)]];
        _meta=Label(11,UIFontWeightRegular); _meta.textColor=UIColor.secondaryLabelColor;
        _media=[UIStackView new]; _media.axis=UILayoutConstraintAxisVertical; _media.alignment=UIStackViewAlignmentLeading; _media.spacing=8;
        _reply=[UIButton buttonWithType:UIButtonTypeSystem]; _reply.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
        _reply.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        _reply.tintColor=[UIColor colorWithRed:.70 green:.91 blue:.94 alpha:1];
        [_reply addTarget:self action:@selector(replies) forControlEvents:UIControlEventTouchUpInside];
        _stack=[[UIStackView alloc] initWithArrangedSubviews:@[_name,_recipient,_body,_media,_meta,_reply]];
        _stack.axis=UILayoutConstraintAxisVertical; _stack.spacing=7;
        _avatar.translatesAutoresizingMaskIntoConstraints=NO; _stack.translatesAutoresizingMaskIntoConstraints=NO;
        [self.contentView addSubview:_avatar]; [self.contentView addSubview:_stack];
        _leading=[_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18];
        _avatarWidth=[_avatar.widthAnchor constraintEqualToConstant:36]; _avatarHeight=[_avatar.heightAnchor constraintEqualToConstant:36];
        [NSLayoutConstraint activateConstraints:@[_leading,_avatarWidth,_avatarHeight,
            [_avatar.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14],
            [_stack.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:11],
            [_stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
            [_stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:14],
            [_stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-13]]];
    } return self;
}
- (void)clearMedia {
    for(UIView *view in _media.arrangedSubviews.copy) { [_media removeArrangedSubview:view]; [view removeFromSuperview]; }
}
- (void)addImage:(NSString *)url sticker:(BOOL)sticker nested:(BOOL)nested {
    if(!url.length)return;
    DGCommentImage *image=[DGCommentImage new]; image.sourceURL=url;
    image.contentMode=UIViewContentModeScaleAspectFit; image.clipsToBounds=YES; image.layer.cornerRadius=sticker?0:12;
    image.userInteractionEnabled=YES; image.isAccessibilityElement=YES;
    image.accessibilityTraits=UIAccessibilityTraitButton|UIAccessibilityTraitImage;
    image.accessibilityLabel=sticker?@"表情包，轻点查看，长按保存":@"评论图片，轻点查看，长按保存";
    [image addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openImage:)]];
    [image addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(saveImage:)]];
    [_media addArrangedSubview:image];
    NSLayoutConstraint *width=[image.widthAnchor constraintEqualToConstant:sticker?132:(nested?170:202)]; width.priority=UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[width,[image.widthAnchor constraintLessThanOrEqualToAnchor:_media.widthAnchor],
        [image.heightAnchor constraintEqualToConstant:sticker?132:(nested?150:176)]]];
    [image remote:url];
}
- (void)display:(const Comment &)comment nested:(BOOL)nested expanded:(BOOL)expanded loading:(BOOL)loading recipient:(NSString *)recipient {
    [_avatar remote:Text(comment.avatar)]; _leading.constant=nested?66:18;
    _avatarWidth.constant=nested?28:36; _avatarHeight.constant=nested?28:36; _avatar.layer.cornerRadius=nested?14:18;
    _avatar.accessibilityLabel=[Text(comment.author) stringByAppendingString:@"的主页"];
    _recipient.hidden=!nested;_recipient.text=nested?(recipient.length?[NSString stringWithFormat:@"回复 @%@",recipient]:@"回复对象暂不可见"):nil;
    _name.text=Text(comment.author); _plainText=Text(comment.text); _body.hidden=comment.text.empty();
    NSMutableArray *emojis=[NSMutableArray array];for(const auto &emoji:comment.emoticons)[emojis addObject:@{@"name":Text(emoji.first),@"url":Text(emoji.second)}];_inlineEmoji=emojis;[self renderEmoji];
    for(NSDictionary *emoji in _inlineEmoji){NSString *url=emoji[@"url"];if([DGEmojiCache() objectForKey:url]||!url.length)continue;
        NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];[request setValue:DGUserAgent() forHTTPHeaderField:@"User-Agent"];[request setValue:@"https://www.douyin.com/" forHTTPHeaderField:@"Referer"];__weak DGCommentCell *weakSelf=self;NSString *source=_plainText;
        [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){UIImage *image=data?[UIImage imageWithData:data]:nil;if(!image)return;[DGEmojiCache() setObject:image forKey:url];dispatch_async(dispatch_get_main_queue(),^{DGCommentCell *cell=weakSelf;if(cell&&[cell->_plainText isEqualToString:source])[cell renderEmoji];});}] resume];}
    [self clearMedia];
    for(const auto &url:comment.images) [self addImage:Text(url) sticker:NO nested:nested];
    if(!comment.sticker.empty() && std::find(comment.images.begin(),comment.images.end(),comment.sticker)==comment.images.end())
        [self addImage:Text(comment.sticker) sticker:YES nested:nested];
    _media.hidden=_media.arrangedSubviews.count==0;
    NSDateFormatter *format=[NSDateFormatter new]; format.dateFormat=@"MM-dd HH:mm";
    NSString *date=comment.timestamp>0?[format stringFromDate:[NSDate dateWithTimeIntervalSince1970:comment.timestamp]]:@"";
    NSMutableArray *parts=[NSMutableArray array]; if(date.length)[parts addObject:date];
    NSString *location=Text(comment.location); if(location.length)[parts addObject:location];
     _meta.text=[parts componentsJoinedByString:@"   "];
    _reply.hidden=nested||comment.replies<=0;
    NSString *replyText=expanded?@"收起回复 ︿":[NSString stringWithFormat:@"展开 %@ 条回复 ﹀",Text(douglass::compact(comment.replies))];
    if(loading&&expanded)replyText=@"正在读取回复…";
    _reply.enabled=!(loading&&expanded);
    [_reply setTitle:replyText forState:UIControlStateNormal];
}
- (void)renderEmoji {
    NSMutableAttributedString *text=[[NSMutableAttributedString alloc] initWithString:_plainText?:@"" attributes:@{NSFontAttributeName:_body.font,NSForegroundColorAttributeName:_body.textColor}];
    for(NSDictionary *emoji in _inlineEmoji){UIImage *image=[DGEmojiCache() objectForKey:emoji[@"url"]];NSString *name=emoji[@"name"];if(!image||!name.length)continue;NSUInteger start=0;while(start<text.length){NSRange range=[text.string rangeOfString:name options:0 range:NSMakeRange(start,text.length-start)];if(range.location==NSNotFound)break;NSTextAttachment *attachment=[NSTextAttachment new];attachment.image=image;attachment.bounds=CGRectMake(0,-4,21,21);[text replaceCharactersInRange:range withAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];start=range.location+1;}}_body.attributedText=text;
}
- (void)profile { if(self.profileAction)self.profileAction(); }
- (void)replies { if(self.replyAction)self.replyAction(); }
- (void)openImage:(UITapGestureRecognizer *)gesture {
    DGCommentImage *image=(DGCommentImage *)gesture.view; if(self.openImageAction)self.openImageAction(image.sourceURL,image);
}
- (void)saveImage:(UILongPressGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateBegan)return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    DGCommentImage *image=(DGCommentImage *)gesture.view; if(self.saveImageAction)self.saveImageAction(image.sourceURL);
}
- (void)copyText:(UILongPressGestureRecognizer *)gesture {
    if(gesture.state!=UIGestureRecognizerStateBegan||!_body.text.length)return;
    if(self.copyAction)self.copyAction(_plainText);
}
- (void)prepareForReuse {
    [super prepareForReuse];self.copyAction=nil;self.replyAction=nil; self.profileAction=nil; self.openImageAction=nil; self.saveImageAction=nil; [self clearMedia];
}
@end

@interface DGReplyFooterCell : UITableViewCell
@property(nonatomic,copy) void (^loadAction)(void);
@property(nonatomic,copy) void (^collapseAction)(void);
- (void)loading:(BOOL)loading more:(BOOL)more error:(BOOL)error count:(NSUInteger)count;
@end
@implementation DGReplyFooterCell {
    UIButton *_load,*_collapse;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if((self=[super initWithStyle:style reuseIdentifier:identifier])) {
        self.backgroundColor=UIColor.clearColor; self.selectionStyle=UITableViewCellSelectionStyleNone;
        _load=[UIButton buttonWithType:UIButtonTypeSystem]; _load.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
        _load.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium]; _load.tintColor=[UIColor colorWithRed:.70 green:.91 blue:.94 alpha:1];
        [_load addTarget:self action:@selector(load) forControlEvents:UIControlEventTouchUpInside];
        _collapse=[UIButton buttonWithType:UIButtonTypeSystem]; [_collapse setTitle:@"收起 ︿" forState:UIControlStateNormal];
        _collapse.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium]; _collapse.tintColor=UIColor.secondaryLabelColor;
        [_collapse addTarget:self action:@selector(collapse) forControlEvents:UIControlEventTouchUpInside];
        _load.translatesAutoresizingMaskIntoConstraints=NO; _collapse.translatesAutoresizingMaskIntoConstraints=NO;
        [self.contentView addSubview:_load]; [self.contentView addSubview:_collapse];
        [NSLayoutConstraint activateConstraints:@[
            [_load.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:105],
            [_load.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:2],
            [_load.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-11],
            [_load.heightAnchor constraintGreaterThanOrEqualToConstant:30],
            [_load.trailingAnchor constraintLessThanOrEqualToAnchor:_collapse.leadingAnchor constant:-8],
            [_collapse.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
            [_collapse.centerYAnchor constraintEqualToAnchor:_load.centerYAnchor],[_collapse.widthAnchor constraintEqualToConstant:56]]];
    } return self;
}
- (void)loading:(BOOL)loading more:(BOOL)more error:(BOOL)error count:(NSUInteger)count {
    NSString *title=loading?@"正在读取回复…":error?@"加载失败，轻点重试":more?@"继续展开回复 ﹀":count?@"已显示全部回复":@"暂无可显示的回复";
    [_load setTitle:title forState:UIControlStateNormal]; _load.enabled=!loading&&(more||error);
}
- (void)load { if(self.loadAction)self.loadAction(); }
- (void)collapse { if(self.collapseAction)self.collapseAction(); }
- (void)prepareForReuse { [super prepareForReuse]; self.loadAction=nil; self.collapseAction=nil; }
@end

namespace { struct DGReplyState {
    std::vector<Comment> items;
    std::unordered_set<std::string> ids;
    std::unordered_map<std::string,std::string> authors;
    std::string cursor="0";
    bool expanded=false,loading=false,more=true,loaded=false,failed=false;
}; }

@interface DGComments () <UITableViewDataSource,UITableViewDelegate,UIGestureRecognizerDelegate>
@end
@implementation DGComments {
    DGBridge *_bridge;
    DGImage *_backdrop;UIVisualEffectView *_backdropBlur;UIView *_backdropShade;
    NSString *_workID,*_parent,*_cursor,*_focusID,*_focusParent,*_highlightID;
    NSUInteger _focusPages;
    UIVisualEffectView *_glass,*_closeGlass;
    UIView *_handle,*_separator,*_handleHit;
    UILabel *_titleLabel,*_modeLabel,*_empty,*_sortHint;UISegmentedControl *_sort;
    UIButton *_close,*_footer;
    UITableView *_table;
    BOOL _loading,_more,_failed,_remembered;CGPoint _savedOffset;
    std::vector<Comment> _comments;
    std::unordered_set<std::string> _ids;
    std::unordered_map<std::string,DGReplyState> _replyStates;
}
- (instancetype)initWithBridge:(DGBridge *)bridge work:(NSString *)work parent:(NSString *)parent {
    if((self=[super init])) { _bridge=bridge; _workID=work.copy; _parent=parent.copy; _cursor=@"0"; _more=YES; } return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    _backdrop=[DGImage new];_backdrop.contentMode=UIViewContentModeScaleAspectFill;_backdrop.clipsToBounds=YES;[_backdrop remote:self.coverURL?:@""];[self.view addSubview:_backdrop];
    _backdropBlur=[[UIVisualEffectView alloc]initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];[self.view addSubview:_backdropBlur];_backdropShade=[UIView new];_backdropShade.backgroundColor=[UIColor.systemBackgroundColor colorWithAlphaComponent:.28];[self.view addSubview:_backdropShade];
    self.view.backgroundColor=UIColor.clearColor; self.view.clipsToBounds=YES;
    self.view.layer.cornerRadius=30; self.view.layer.cornerCurve=kCACornerCurveContinuous;
    self.view.layer.borderWidth=.5; self.view.layer.borderColor=[UIColor colorWithWhite:1 alpha:.22].CGColor;
    _glass=Glass(30); [self.view addSubview:_glass];
    _handle=[UIView new]; _handle.backgroundColor=UIColor.tertiaryLabelColor; _handle.layer.cornerRadius=2.5; [_glass.contentView addSubview:_handle];
    _handleHit=[UIView new];[_glass.contentView addSubview:_handleHit];UIPanGestureRecognizer *drag=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(dragHandle:)];drag.delegate=self;[_handleHit addGestureRecognizer:drag];_handleHit.isAccessibilityElement=YES;_handleHit.accessibilityLabel=@"向下拖动关闭评论";
    _titleLabel=Label(18,UIFontWeightSemibold); _titleLabel.text=_parent.length?@"回复":@"评论"; _titleLabel.textAlignment=NSTextAlignmentCenter; [_glass.contentView addSubview:_titleLabel];
    _modeLabel=Label(10,UIFontWeightRegular); _modeLabel.text=@"";_modeLabel.hidden=YES; _modeLabel.textColor=[UIColor colorWithWhite:1 alpha:.5]; [_glass.contentView addSubview:_modeLabel];
    _sort=[[UISegmentedControl alloc]initWithItems:@[@"最热",@"最新"]];_sort.selectedSegmentIndex=0;[_sort addTarget:self action:@selector(sortChanged) forControlEvents:UIControlEventValueChanged];[_glass.contentView addSubview:_sort];_sort.hidden=_parent.length>0;
    _sortHint=Label(10,UIFontWeightRegular);_sortHint.text=@"按已加载评论排序";_sortHint.textColor=UIColor.secondaryLabelColor;[_glass.contentView addSubview:_sortHint];_sortHint.hidden=_sort.hidden;
    _closeGlass=Glass(20); _close=Symbol(@"xmark",self,@selector(close)); _close.accessibilityLabel=@"关闭评论，继续浏览当前作品";
    [_closeGlass.contentView addSubview:_close]; [_glass.contentView addSubview:_closeGlass];
    _separator=[UIView new]; _separator.backgroundColor=[UIColor colorWithWhite:1 alpha:.10]; [_glass.contentView addSubview:_separator];
    _table=[[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; _table.backgroundColor=UIColor.clearColor;
    _table.separatorStyle=UITableViewCellSeparatorStyleNone; _table.rowHeight=UITableViewAutomaticDimension; _table.estimatedRowHeight=112;
    _table.estimatedSectionHeaderHeight=0; _table.estimatedSectionFooterHeight=0; _table.sectionHeaderHeight=0; _table.sectionFooterHeight=0;
    _table.sectionHeaderTopPadding=0;
    _table.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever; _table.alwaysBounceVertical=YES; _table.showsVerticalScrollIndicator=NO;
    _table.dataSource=self; _table.delegate=self;
    [_table registerClass:DGCommentCell.class forCellReuseIdentifier:@"comment"]; [_table registerClass:DGReplyFooterCell.class forCellReuseIdentifier:@"reply-footer"];
    [_glass.contentView addSubview:_table];
    _footer=[UIButton buttonWithType:UIButtonTypeSystem]; _footer.frame=CGRectMake(0,0,320,58);
    _footer.tintColor=UIColor.secondaryLabelColor; _footer.titleLabel.font=[UIFont systemFontOfSize:12];
    [_footer addTarget:self action:@selector(loadMore) forControlEvents:UIControlEventTouchUpInside]; _table.tableFooterView=_footer;
    _empty=Label(14,UIFontWeightRegular); _empty.textColor=UIColor.secondaryLabelColor; _empty.textAlignment=NSTextAlignmentCenter; _empty.numberOfLines=0;
    _table.backgroundView=_empty; [self loadMore];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; CGRect b=self.view.bounds; CGFloat width=b.size.width; _backdrop.frame=b;_backdropBlur.frame=b;_backdropShade.frame=b;_glass.frame=b;
    _handle.frame=CGRectMake((width-50)/2,8,50,5); _titleLabel.frame=CGRectMake(68,24,MAX(0,width-136),30);
    _handleHit.frame=CGRectMake((width-140)/2,0,140,26);
    _modeLabel.frame=CGRectMake(20,35,40,18); _closeGlass.frame=CGRectMake(MAX(0,width-58),22,40,40); _close.frame=_closeGlass.bounds;
    CGFloat header=_parent.length?77:111;_sort.frame=CGRectMake(18,68,130,30);_sortHint.frame=CGRectMake(160,73,MAX(0,width-178),20);
    _separator.frame=CGRectMake(20,header-4,MAX(0,width-40),.5);
    _table.frame=CGRectMake(0,header,width,MAX(0,b.size.height-header));
    _table.contentInset=UIEdgeInsetsMake(0,0,MAX(12,self.view.safeAreaInsets.bottom),0);
}
- (void)close { if(self.closeAction)self.closeAction(); }
- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gesture{CGPoint velocity=[gesture velocityInView:self.view];return velocity.y>0&&velocity.y>fabs(velocity.x)&&self.view.superview.layer.animationKeys.count==0;}
- (void)dragHandle:(UIPanGestureRecognizer *)gesture{CGFloat y=MAX(0,[gesture translationInView:self.view.superview.superview].y);if(gesture.state==UIGestureRecognizerStateChanged&&self.dragAction)self.dragAction(y,0);if(gesture.state==UIGestureRecognizerStateEnded&&self.dragAction)self.dragAction(y,(y>70||[gesture velocityInView:self.view].y>650)?1:2);if((gesture.state==UIGestureRecognizerStateCancelled||gesture.state==UIGestureRecognizerStateFailed)&&self.dragAction)self.dragAction(y,2);}
- (void)rememberPosition{_savedOffset=_table.contentOffset;_remembered=YES;[_table setContentOffset:_savedOffset animated:NO];}
- (void)restorePosition{if(!_remembered)return;[_table layoutIfNeeded];CGFloat maxY=MAX(-_table.adjustedContentInset.top,_table.contentSize.height-_table.bounds.size.height+_table.adjustedContentInset.bottom);[_table setContentOffset:CGPointMake(0,MAX(-_table.adjustedContentInset.top,MIN(maxY,_savedOffset.y))) animated:NO];}
- (void)sortLoaded{
    BOOL latest=_sort.selectedSegmentIndex==1;
    std::stable_sort(_comments.begin(),_comments.end(),[latest](const Comment &a,const Comment &b){if(latest)return a.timestamp>b.timestamp;return a.likes==b.likes?a.timestamp>b.timestamp:a.likes>b.likes;});
}
- (void)sortChanged{[self sortLoaded];[_table reloadData];[_table setContentOffset:CGPointZero animated:NO];_savedOffset=CGPointZero;}
- (void)focusComment:(NSString *)identifier parent:(NSString *)parent {
 _focusID=identifier.copy;_focusParent=parent.copy;_focusPages=0;
 if(self.isViewLoaded)[self advanceFocus];
}
- (void)finishFocus:(NSIndexPath *)path {
 if(!path){_focusID=nil;_focusParent=nil;DGToast(self,@"作品已打开，暂未定位到这条评论");return;}
 _highlightID=_focusID;_focusID=nil;_focusParent=nil;
 [_table reloadData];[_table layoutIfNeeded];
 if(path.section<[_table numberOfSections]&&path.row<[_table numberOfRowsInSection:path.section])[_table scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
}
- (void)advanceFocus {
 if(!_focusID.length||_loading)return;
 NSInteger section=[self indexOfComment:_focusID];
 if(section!=NSNotFound){[self finishFocus:[NSIndexPath indexPathForRow:0 inSection:section]];return;}
 if(_focusParent.length){
  section=[self indexOfComment:_focusParent];
  if(section!=NSNotFound){
   DGReplyState &state=_replyStates[String(_focusParent)];state.expanded=true;
   for(NSUInteger i=0;i<state.items.size();i++)if(state.items[i].id==String(_focusID)){[self finishFocus:[NSIndexPath indexPathForRow:i+1 inSection:section]];return;}
   if(state.loading)return;
   if(state.more&&!state.failed&&_focusPages<16){++_focusPages;[self loadReplies:_focusParent];return;}
   [self finishFocus:nil];return;
  }
 }
 if(_more&&!_failed&&_focusPages<16){++_focusPages;[self loadMore];return;}
 [self finishFocus:nil];
}
- (void)loadMore {
    if(_loading||!_more)return; _loading=YES; _failed=NO;
    [_footer setTitle:@"正在读取评论…" forState:UIControlStateNormal]; _footer.enabled=NO;
    if(_comments.empty())_empty.text=@"正在读取评论"; NSString *oldCursor=_cursor.copy;
    __weak DGComments *weakSelf=self;
    [_bridge request:_parent.length?@"replies":@"comments" parameters:@{@"id":_workID,@"parent":_parent?:@"",@"cursor":_cursor} completion:^(NSDictionary *result,NSString *error) {
        DGComments *self=weakSelf; if(!self)return; self->_loading=NO;
        if(error) { self->_failed=YES; if(self->_comments.empty())self->_empty.text=error;
            [self->_footer setTitle:@"加载失败，轻点重试" forState:UIControlStateNormal]; self->_footer.enabled=YES;[self advanceFocus];return; }
        NSIndexPath *anchor=self->_table.indexPathsForVisibleRows.firstObject;NSString *anchorID=anchor&&anchor.section<(NSInteger)self->_comments.size()?Text(self->_comments[anchor.section].id):@"";CGFloat anchorOffset=anchor?self->_table.contentOffset.y-CGRectGetMinY([self->_table rectForRowAtIndexPath:anchor]):0;
        for(id value in Array(result[@"items"])) { if(![value isKindOfClass:NSDictionary.class])continue;
            Comment comment=ReadComment(value); if(!comment.id.empty()&&self->_ids.insert(comment.id).second)self->_comments.emplace_back(std::move(comment)); }
        self->_cursor=[result[@"cursor"] description]?:@"0"; self->_more=[result[@"more"] boolValue]&&![oldCursor isEqualToString:self->_cursor];
        self->_empty.text=self->_comments.empty()?@"还没有评论":@"";
        long long total=Number(result[@"total"]); self->_titleLabel.text=total>0?[NSString stringWithFormat:@"评论 %@",Text(douglass::compact(total))]:(self->_parent.length?@"回复":@"评论");
        [self->_footer setTitle:self->_more?@"继续加载评论":@"已显示全部评论" forState:UIControlStateNormal]; self->_footer.enabled=self->_more;[self sortLoaded]; [self->_table reloadData];[self->_table layoutIfNeeded];
        NSInteger section=[self indexOfComment:anchorID];if(section!=NSNotFound&&anchor.row<[self->_table numberOfRowsInSection:section]){NSIndexPath *path=[NSIndexPath indexPathForRow:anchor.row inSection:section];CGFloat y=CGRectGetMinY([self->_table rectForRowAtIndexPath:path])+anchorOffset;[self->_table setContentOffset:CGPointMake(0,y) animated:NO];if(self->_remembered)self->_savedOffset=self->_table.contentOffset;}
        [self advanceFocus];
    }];
}
- (NSInteger)indexOfComment:(NSString *)identifier {
    std::string key=String(identifier); for(std::size_t i=0;i<_comments.size();++i)if(_comments[i].id==key)return(NSInteger)i; return NSNotFound;
}
- (void)reloadThread:(NSString *)identifier {
    NSInteger section=[self indexOfComment:identifier]; if(section==NSNotFound||section>=[_table numberOfSections])return;
    [UIView performWithoutAnimation:^{[self->_table reloadSections:[NSIndexSet indexSetWithIndex:section] withRowAnimation:UITableViewRowAnimationNone];}];
}
- (void)toggleReplies:(NSString *)identifier {
    DGReplyState &state=_replyStates[String(identifier)]; state.expanded=!state.expanded;
    if(state.expanded&&!state.loaded&&!state.loading)[self loadReplies:identifier];else [self reloadThread:identifier];
}
- (void)collapseReplies:(NSString *)identifier {
    auto found=_replyStates.find(String(identifier)); if(found==_replyStates.end())return; found->second.expanded=false; [self reloadThread:identifier];
}
- (void)loadReplies:(NSString *)identifier {
    std::string key=String(identifier); DGReplyState &state=_replyStates[key]; if(state.loading||(!state.more&&!state.failed))return;
    state.loading=true; state.failed=false; state.expanded=true; NSString *cursor=Text(state.cursor); [self reloadThread:identifier];
    __weak DGComments *weakSelf=self;
    [_bridge request:@"replies" parameters:@{@"id":_workID,@"parent":identifier,@"cursor":cursor} completion:^(NSDictionary *result,NSString *error) {
        DGComments *self=weakSelf; if(!self)return; DGReplyState &state=self->_replyStates[key]; state.loading=false;
        if(error) {state.failed=true;[self reloadThread:identifier];DGToast(self,error);[self advanceFocus];return;}
        state.loaded=true;
        for(id value in Array(result[@"items"])) {if(![value isKindOfClass:NSDictionary.class])continue;
            Comment reply=ReadComment(value); if(!reply.id.empty()&&state.ids.insert(reply.id).second){state.authors[reply.id]=reply.author;state.items.emplace_back(std::move(reply));}}
        state.cursor=String(result[@"cursor"]?:@"0"); state.more=[result[@"more"] boolValue]&&state.cursor!=String(cursor); [self reloadThread:identifier];[self advanceFocus];
    }];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {return(NSInteger)_comments.size();}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if(section<0||(std::size_t)section>=_comments.size())return 0; auto found=_replyStates.find(_comments[section].id);
    return found!=_replyStates.end()&&found->second.expanded&&(!found->second.loading||found->second.loaded)?(NSInteger)found->second.items.size()+2:1;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    const Comment &parent=_comments[indexPath.section]; NSString *parentID=Text(parent.id);
    auto found=_replyStates.find(parent.id); DGReplyState *state=found==_replyStates.end()?nullptr:&found->second;
    __weak DGComments *weakSelf=self;
    if(indexPath.row>0&&state&&(std::size_t)indexPath.row>state->items.size()) {
        DGReplyFooterCell *cell=[tableView dequeueReusableCellWithIdentifier:@"reply-footer" forIndexPath:indexPath];
        [cell loading:state->loading more:state->more error:state->failed count:state->items.size()];
        cell.loadAction=^{[weakSelf loadReplies:parentID];}; cell.collapseAction=^{[weakSelf collapseReplies:parentID];}; return cell;
    }
    const Comment &comment=indexPath.row==0?parent:state->items[indexPath.row-1];
    DGCommentCell *cell=[tableView dequeueReusableCellWithIdentifier:@"comment" forIndexPath:indexPath];
    NSString *recipient=nil;
    if(indexPath.row>0){
        if(comment.replyToID.empty()||comment.replyToID==parent.id)recipient=Text(parent.author);
        else if(auto target=state->authors.find(comment.replyToID);target!=state->authors.end())recipient=Text(target->second);
        if(!recipient.length)recipient=Text(comment.replyToAuthor);
    }
    [cell display:comment nested:indexPath.row>0 expanded:state&&state->expanded loading:state&&state->loading&&!state->loaded recipient:recipient];
    cell.contentView.backgroundColor=[_highlightID isEqualToString:Text(comment.id)]?[UIColor.systemTealColor colorWithAlphaComponent:.16]:UIColor.clearColor;
    NSString *sec=Text(comment.authorID),*name=Text(comment.author);
    cell.profileAction=^{DGComments *self=weakSelf;if(!self)return;if(!sec.length){DGToast(self,@"平台未提供该用户的主页标识");return;}if(self.profileAction)self.profileAction(sec,name);};
    cell.replyAction=^{[weakSelf toggleReplies:parentID];};
    cell.openImageAction=^(NSString *url,UIImageView *source){DGComments *self=weakSelf;if(self)DGShowImage(self,url,source);};
    cell.saveImageAction=^(NSString *url){DGComments *self=weakSelf;if(self)DGConfirmImageSave(self,url);};
    cell.copyAction=^(NSString *text){DGComments *self=weakSelf;if(self)DGConfirmTextCopy(self,text,@"复制这条评论？",@"评论已复制");};
    return cell;
}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if(self.view.window&&!_failed&&_more&&!_loading&&(std::size_t)(indexPath.section+3)>=_comments.size())[self loadMore];
}
- (void)dealloc{[NSNotificationCenter.defaultCenter removeObserver:self];}
@end

