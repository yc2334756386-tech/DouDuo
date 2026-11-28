#import "DGCommon.h"
#import "DGInboxCache.h"
#import "DGFeedCache.h"
#import <QuartzCore/QuartzCore.h>
@interface DGChatService:NSObject<WKNavigationDelegate>
@property(nonatomic,strong) WKWebView *web;
@property(nonatomic,strong) UIView *mount;
@property(nonatomic) BOOL ready,loading;
@property(nonatomic,copy) NSString *failure;
- (void)attach:(UIView *)host;
- (void)reload;
- (void)call:(NSString *)action parameters:(NSDictionary *)parameters completion:(DGResult)completion;
@end
@implementation DGChatService
- (instancetype)init{if((self=[super init])){WKWebViewConfiguration *config=[WKWebViewConfiguration new];DGSessionConfigure(config);config.allowsInlineMediaPlayback=YES;config.mediaTypesRequiringUserActionForPlayback=WKAudiovisualMediaTypeAll;NSString *script=[NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"messages" ofType:@"js"] encoding:NSUTF8StringEncoding error:nil]?:@"";[config.userContentController addUserScript:[[WKUserScript alloc]initWithSource:script injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES]];_web=[[WKWebView alloc]initWithFrame:CGRectMake(0,0,1280,900) configuration:config];_web.customUserAgent=DGUserAgent();_web.navigationDelegate=self;_web.userInteractionEnabled=NO;_mount=[[UIView alloc]initWithFrame:CGRectMake(0,0,1,1)];_mount.clipsToBounds=YES;_mount.alpha=.01;_mount.userInteractionEnabled=NO;_mount.accessibilityElementsHidden=YES;[_mount addSubview:_web];}return self;}
- (void)attach:(UIView *)host{if(_mount.superview!=host){[_mount removeFromSuperview];[host insertSubview:_mount atIndex:0];}if(!_loading&&!_ready)[self reload];}
- (void)reload{_loading=YES;_ready=NO;_failure=nil;DGSessionPrepare(_web,YES,^{[self->_web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.douyin.com/chat"] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:25]];});}
- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation{_ready=YES;_loading=NO;_failure=nil;}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)web{_ready=NO;_loading=NO;_failure=nil;}
- (void)webView:(WKWebView *)web didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error{if(error.code==NSURLErrorCancelled)return;_loading=NO;_failure=@"消息连接失败，请点右上角刷新";}
- (void)webView:(WKWebView *)web didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error{[self webView:web didFailProvisionalNavigation:navigation withError:error];}
- (void)webView:(WKWebView *)web decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decision{decision([@[@"http",@"https",@"about",@"blob",@"data"]containsObject:action.request.URL.scheme.lowercaseString]?WKNavigationActionPolicyAllow:WKNavigationActionPolicyCancel);}
- (void)call:(NSString *)action parameters:(NSDictionary *)parameters completion:(DGResult)completion{
 if(!_ready){completion(nil,_failure?:@"正在连接消息服务…");return;}
 [_web callAsyncJavaScript:@"return window.DGChat ? await window.DGChat.request(action,params) : {error:'消息服务尚未就绪'};" arguments:@{@"action":action,@"params":parameters} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id value,NSError *error){NSDictionary *result=[value isKindOfClass:NSDictionary.class]?value:nil;completion(result,error?@"消息同步暂时失败":result[@"error"]);}];
}
@end
@interface DGConversationCell:UITableViewCell
- (void)record:(NSDictionary *)record;
@end
@implementation DGConversationCell{DGImage *_avatar;UILabel *_name,*_preview,*_time,*_badge;BOOL _dotOnly;}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier{if((self=[super initWithStyle:style reuseIdentifier:identifier])){self.backgroundColor=UIColor.clearColor;_avatar=[DGImage new];_avatar.layer.cornerRadius=25;_avatar.clipsToBounds=YES;_avatar.contentMode=UIViewContentModeScaleAspectFill;_name=Label(16,UIFontWeightSemibold);_preview=Label(13,UIFontWeightRegular);_preview.textColor=UIColor.secondaryLabelColor;_time=Label(11,UIFontWeightRegular);_time.textColor=UIColor.tertiaryLabelColor;_time.textAlignment=NSTextAlignmentRight;_badge=Label(11,UIFontWeightSemibold);_badge.textAlignment=NSTextAlignmentCenter;_badge.textColor=UIColor.whiteColor;_badge.backgroundColor=UIColor.systemRedColor;_badge.layer.cornerRadius=10;_badge.clipsToBounds=YES;for(UIView *view in @[_avatar,_name,_preview,_time,_badge])[self.contentView addSubview:view];}return self;}
- (void)layoutSubviews{[super layoutSubviews];CGFloat w=self.contentView.bounds.size.width;_avatar.frame=CGRectMake(18,16,50,50);_name.frame=CGRectMake(82,15,w-170,24);_preview.frame=CGRectMake(82,45,w-130,22);_time.frame=CGRectMake(w-92,16,74,20);_badge.frame=_dotOnly?CGRectMake(w-30,51,9,9):CGRectMake(w-48,47,30,20);_badge.layer.cornerRadius=_dotOnly?4.5:10;}
- (void)record:(NSDictionary *)record{[_avatar remote:Text(String(record[@"avatar"]))];_name.text=Text(String(record[@"name"]));_preview.text=Text(String(record[@"preview"]));_time.text=Text(String(record[@"time"]));_badge.text=Text(String(record[@"badge"]));BOOL unread=[record[@"unread"]boolValue]||Number(record[@"unreadCount"])>0||(_badge.text.length&&![_badge.text isEqual:@"0"]);_dotOnly=!_badge.text.length;_badge.hidden=!unread;self.accessibilityValue=unread?@"有未读私信":nil;[self setNeedsLayout];}
@end
@interface DGChatBubble:UITableViewCell
- (void)record:(NSDictionary *)record;
@end
@implementation DGChatBubble{UIStackView *_stack;UIView *_bubble;UILabel *_text;DGImage *_image;NSLayoutConstraint *_left,*_right,*_imageHeight;}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier{if((self=[super initWithStyle:style reuseIdentifier:identifier])){self.selectionStyle=UITableViewCellSelectionStyleNone;self.backgroundColor=UIColor.clearColor;_bubble=[UIView new];_bubble.layer.cornerRadius=18;_text=Label(16,UIFontWeightRegular);_text.numberOfLines=0;_image=[DGImage new];_image.contentMode=UIViewContentModeScaleAspectFit;_image.clipsToBounds=YES;_image.layer.cornerRadius=12;_stack=[[UIStackView alloc]initWithArrangedSubviews:@[_text,_image]];_stack.axis=UILayoutConstraintAxisVertical;_stack.spacing=8;_bubble.translatesAutoresizingMaskIntoConstraints=NO;_stack.translatesAutoresizingMaskIntoConstraints=NO;[self.contentView addSubview:_bubble];[_bubble addSubview:_stack];_left=[_bubble.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16];_right=[_bubble.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16];_imageHeight=[_image.heightAnchor constraintEqualToConstant:0];[NSLayoutConstraint activateConstraints:@[[_bubble.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:6],[_bubble.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6],[_bubble.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:.78],[_stack.leadingAnchor constraintEqualToAnchor:_bubble.leadingAnchor constant:13],[_stack.trailingAnchor constraintEqualToAnchor:_bubble.trailingAnchor constant:-13],[_stack.topAnchor constraintEqualToAnchor:_bubble.topAnchor constant:10],[_stack.bottomAnchor constraintEqualToAnchor:_bubble.bottomAnchor constant:-10],_imageHeight]];}return self;}
- (void)record:(NSDictionary *)record{BOOL mine=[record[@"mine"]boolValue];_left.active=!mine;_right.active=mine;_bubble.backgroundColor=mine?[UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits){return traits.userInterfaceStyle==UIUserInterfaceStyleDark?[UIColor colorWithRed:.08 green:.36 blue:.38 alpha:1]:[UIColor colorWithRed:.81 green:.95 blue:.93 alpha:1];}]:UIColor.secondarySystemBackgroundColor;_text.textColor=UIColor.labelColor;_text.text=Text(String(record[@"text"]));_text.hidden=!_text.text.length;NSString *url=Text(String(record[@"image"]));_image.hidden=!url.length;_imageHeight.constant=url.length?170:0;if([url hasPrefix:@"data:image/"]){NSString *base64=[url componentsSeparatedByString:@","].lastObject;_image.image=[UIImage imageWithData:[[NSData alloc]initWithBase64EncodedString:base64 options:0]];}else[_image remote:url];}
@end
@interface DGMessages:UIViewController<UITableViewDataSource,UITableViewDelegate,UITextViewDelegate>
@property(nonatomic,strong) DGChatService *service;
@property(nonatomic,strong) DGBridge *bridge;
@property(nonatomic,strong) NSDictionary *conversation;
@property(nonatomic,copy) NSString *uid;
@property(nonatomic) BOOL embedded;
@property(nonatomic,copy) void (^navigate)(UIViewController *);
@end
@implementation DGMessages{UITableView *_table;NSArray *_rows;NSTimer *_timer;UILabel *_empty;UIRefreshControl *_refresh;UIVisualEffectView *_composer;UITextView *_input;UIButton *_send;BOOL _busy,_sending,_opened,_visible,_positioned,_noticeBusy;CGFloat _keyboard;NSArray<UIView *> *_noticeDots;CFTimeInterval _noticeCheckedAt;}
- (void)viewDidLoad{
 [super viewDidLoad];self.view.backgroundColor=UIColor.systemBackgroundColor;if(!_service)_service=[DGChatService new];_rows=Array(DGReadInboxCache([self cacheKey])[@"items"]);self.title=self.conversation?Text(String(self.conversation[@"name"])):@"信息";
 _table=[[UITableView alloc]initWithFrame:self.view.bounds style:UITableViewStylePlain];_table.backgroundColor=UIColor.clearColor;_table.separatorStyle=UITableViewCellSeparatorStyleNone;_table.rowHeight=self.conversation?UITableViewAutomaticDimension:82;_table.estimatedRowHeight=72;_table.dataSource=self;_table.delegate=self;_table.keyboardDismissMode=UIScrollViewKeyboardDismissModeOnDrag;[_table registerClass:DGConversationCell.class forCellReuseIdentifier:@"conversation"];[_table registerClass:DGChatBubble.class forCellReuseIdentifier:@"message"];[self.view addSubview:_table];
 _empty=Label(14,UIFontWeightRegular);_empty.textColor=UIColor.secondaryLabelColor;_empty.textAlignment=NSTextAlignmentCenter;_empty.numberOfLines=0;_empty.text=@"正在同步消息…";_table.backgroundView=_empty;_refresh=[UIRefreshControl new];[_refresh addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];_table.refreshControl=_refresh;
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
 if(self.conversation){_composer=Glass(22);[self.view addSubview:_composer];_input=[UITextView new];_input.backgroundColor=UIColor.clearColor;_input.textColor=UIColor.labelColor;_input.font=[UIFont systemFontOfSize:16];_input.delegate=self;_input.accessibilityLabel=@"输入消息";[_composer.contentView addSubview:_input];_send=Symbol(@"arrow.up.circle.fill",self,@selector(send));_send.accessibilityLabel=@"发送";[_composer.contentView addSubview:_send];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];}
 else{UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,154)];NSMutableArray *dots=[NSMutableArray array];NSArray *titles=@[@"新的关注",@"互动消息"],*subtitles=@[@"查看新粉丝与关注动态",@"评论、赞与提到我的消息"],*icons=@[@"person.2.fill",@"bubble.left.and.bubble.right.fill"];for(NSInteger index=0;index<2;index++){UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];button.tag=index;button.frame=CGRectMake(0,index*76,self.view.bounds.size.width,76);button.autoresizingMask=UIViewAutoresizingFlexibleWidth;[button addTarget:self action:@selector(noticeCategory:) forControlEvents:UIControlEventTouchUpInside];UIView *circle=[[UIView alloc]initWithFrame:CGRectMake(18,13,50,50)];circle.backgroundColor=index?UIColor.systemPinkColor:UIColor.systemBlueColor;circle.layer.cornerRadius=25;circle.userInteractionEnabled=NO;UIImageView *icon=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:icons[index]]];icon.tintColor=UIColor.whiteColor;icon.contentMode=UIViewContentModeScaleAspectFit;icon.frame=CGRectMake(12,12,26,26);[circle addSubview:icon];[button addSubview:circle];UILabel *title=Label(16,UIFontWeightSemibold);title.frame=CGRectMake(82,13,self.view.bounds.size.width-120,24);title.text=titles[index];[button addSubview:title];UILabel *subtitle=Label(12,UIFontWeightRegular);subtitle.textColor=UIColor.secondaryLabelColor;subtitle.frame=CGRectMake(82,42,self.view.bounds.size.width-120,20);subtitle.text=subtitles[index];[button addSubview:subtitle];UIView *dot=[[UIView alloc]initWithFrame:CGRectMake(self.view.bounds.size.width-30,32,9,9)];dot.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;dot.backgroundColor=UIColor.systemRedColor;dot.layer.cornerRadius=4.5;dot.userInteractionEnabled=NO;dot.hidden=YES;dot.isAccessibilityElement=YES;dot.accessibilityLabel=index?@"有新的互动消息":@"有新的关注";[button addSubview:dot];[dots addObject:dot];[header addSubview:button];}_noticeDots=dots;_table.tableHeaderView=header;self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];__weak DGMessages *weak=self;[_bridge request:@"profile" parameters:@{} completion:^(NSDictionary *result,NSString *error){if(!error)weak.uid=Text(String(result[@"uid"]));}];}
 if(_rows.count)_empty.text=@"";
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateUnreadIndicators) name:@"DGInboxUnreadChanged" object:nil];[self updateUnreadIndicators];
}
- (NSString *)cacheKey{return self.conversation?[@"thread:" stringByAppendingString:Text(String(self.conversation[@"id"]))]:@"conversations";}
- (void)noticeCategory:(UIButton *)button{UIViewController *page=DGMakeNoticesGroup(self.bridge,button.tag?0:4);if(self.navigate)self.navigate(page);else[self.navigationController pushViewController:page animated:YES];}
- (void)setChannelVisible:(BOOL)visible{
 if(_visible==visible)return;
 _visible=visible;[_timer invalidate];_timer=nil;
 if(!visible)return;
 [self updateUnreadIndicators];
 [_service attach:self.view];[self poll];
 __weak DGMessages *weak=self;_timer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){[weak poll];}];
}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];[self setChannelVisible:YES];}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];if(self.conversation&&!_positioned&&_rows.count){_positioned=YES;[_table layoutIfNeeded];[_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:_rows.count-1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];}}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[self setChannelVisible:NO];}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];CGFloat safe=self.view.safeAreaInsets.bottom,bottom=MAX(safe,_keyboard),height=self.view.bounds.size.height;_table.frame=CGRectMake(0,0,self.view.bounds.size.width,MAX(0,height-(self.conversation?64+bottom:0)));_composer.frame=CGRectMake(10,height-bottom-60,self.view.bounds.size.width-20,54);_input.frame=CGRectMake(10,5,_composer.bounds.size.width-66,44);_send.frame=CGRectMake(_composer.bounds.size.width-52,4,48,46);}
- (void)keyboard:(NSNotification *)note{CGRect rect=[self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey]CGRectValue] fromView:nil];_keyboard=MAX(0,self.view.bounds.size.height-rect.origin.y);[self.view setNeedsLayout];[self.view layoutIfNeeded];}
- (void)close{[self dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];}
- (void)refresh{if(self.conversation){[self query:@"older"];}else{_noticeCheckedAt=0;if(_service.failure)[_service reload];[self poll];}}
- (void)updateUnreadIndicators{
 if(self.conversation)return;
 if(_noticeDots.count==2){_noticeDots[0].hidden=!DGInboxCategoryUnread(YES);_noticeDots[1].hidden=!DGInboxCategoryUnread(NO);}
 NSArray *rows=Array(DGReadInboxCache(@"conversations")[@"items"]);if(rows.count&& ![_rows isEqual:rows]){NSArray *old=_rows;_rows=rows;DGReloadInboxRows(_table,old,rows);_empty.text=@"";}
}
- (void)pollNoticeCounts{
 if(self.conversation||_noticeBusy||CACurrentMediaTime()-_noticeCheckedAt<30)return;
 _noticeBusy=YES;_noticeCheckedAt=CACurrentMediaTime();NSString *scope=DGCurrentFeedScope();__weak DGMessages *weak=self;
 [_bridge request:@"noticeCounts" parameters:@{} completion:^(NSDictionary *result,NSString *error){DGMessages *self=weak;if(!self)return;self->_noticeBusy=NO;if(error||![scope isEqual:DGCurrentFeedScope()])return;DGInboxUpdateNoticeCounts(Array(result[@"items"]));}];
}
- (void)poll{if(!_visible||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;[self pollNoticeCounts];if(_busy||_sending)return;if(!_service.ready&&!_service.loading&&!_service.failure)[_service attach:self.view];[self query:self.conversation?(_opened?@"messages":@"open"):@"list"];}
- (void)query:(NSString *)action{
 if(_busy||_sending)return;_busy=YES;NSString *scope=DGCurrentFeedScope();__weak DGMessages *weak=self;
 [_service call:action parameters:@{@"id":self.conversation[@"id"]?:@"",@"uid":self.uid?:@""} completion:^(NSDictionary *result,NSString *error){
  DGMessages *self=weak;if(!self)return;self->_busy=NO;[self->_refresh endRefreshing];if(![scope isEqual:DGCurrentFeedScope()])return;
  if(error){if(self.conversation&&self->_service.ready)self->_opened=NO;if(!self->_rows.count)self->_empty.text=error;return;}
  if([action isEqualToString:@"open"]){self->_opened=YES;DGInboxMarkConversationRead(Text(String(self.conversation[@"id"])));}
  NSArray *previous=self->_rows,*incoming=Array(result[@"items"]);BOOL older=[action isEqualToString:@"older"];
  NSArray *rows=DGMergeInboxRows(previous,incoming,!self.conversation||older,self.conversation?200:100);
  self->_empty.text=rows.count?@"":self.conversation?@"还没有可显示的消息":[result[@"ready"]boolValue]?@"暂时没有会话":@"正在同步会话；若长时间无内容，请返回完成登录后刷新";
  if([previous isEqual:rows])return;
  BOOL nearBottom=self->_table.contentOffset.y+self->_table.bounds.size.height>self->_table.contentSize.height-100;
  self->_rows=rows;DGWriteInboxCache([self cacheKey],@{@"items":rows});DGReloadInboxRows(self->_table,previous,rows);
  if(self.conversation&&rows.count&&nearBottom&&!older)[self->_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:rows.count-1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:NO];
 }];
}
- (void)send{
 NSString *text=[_input.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!text.length||_sending||!_opened)return;_sending=YES;_send.enabled=NO;__weak DGMessages *weak=self;
 [_service call:@"send" parameters:@{@"id":self.conversation[@"id"]?:@"",@"uid":self.uid?:@"",@"text":text} completion:^(NSDictionary *result,NSString *error){DGMessages *self=weak;if(!self)return;self->_sending=NO;self->_send.enabled=YES;if(error){DGToast(self,error);return;}if([result[@"sent"]boolValue])self->_input.text=@"";[self poll];}];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return _rows.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{if(self.conversation){DGChatBubble *cell=[tableView dequeueReusableCellWithIdentifier:@"message" forIndexPath:indexPath];[cell record:_rows[indexPath.row]];return cell;}DGConversationCell *cell=[tableView dequeueReusableCellWithIdentifier:@"conversation" forIndexPath:indexPath];[cell record:_rows[indexPath.row]];return cell;}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{[tableView deselectRowAtIndexPath:indexPath animated:YES];if(self.conversation)return;DGMessages *thread=[DGMessages new];thread.service=_service;thread.bridge=_bridge;thread.conversation=_rows[indexPath.row];thread.uid=self.uid;if(self.navigate)self.navigate(thread);else[self.navigationController pushViewController:thread animated:YES];}
- (void)dealloc{[_timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
UIViewController *DGMakeMessages(DGBridge *bridge){DGMessages *messages=[DGMessages new];messages.bridge=bridge;return messages;}


UIViewController *DGMakeEmbeddedMessages(DGBridge *bridge,void (^navigate)(UIViewController *)){DGMessages *messages=[DGMessages new];messages.bridge=bridge;messages.embedded=YES;messages.navigate=navigate;return messages;}

void DGRefreshEmbeddedMessages(UIViewController *page){if([page isKindOfClass:DGMessages.class])[(DGMessages *)page refresh];}

void DGSetEmbeddedMessagesVisible(UIViewController *page,BOOL visible){if([page isKindOfClass:DGMessages.class])[(DGMessages *)page setChannelVisible:visible];}
