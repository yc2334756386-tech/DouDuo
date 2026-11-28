#import "DGCommon.h"

@interface DGSearchPage:UIViewController<WKNavigationDelegate,DGInPageBack>
@property(nonatomic,copy) NSString *keyword;
@property(nonatomic,copy) NSString *musicID;
@property(nonatomic,copy) NSString *musicURL;
@property(nonatomic) BOOL users;
@property(nonatomic,copy) void (^imported)(NSArray<NSDictionary *> *items);
@end
@implementation DGSearchPage{
 WKWebView *_web;UIView *_tools;UILabel *_hint;UIButton *_import,*_reload;UIActivityIndicatorView *_spinner;BOOL _reading,_musicFallback;
}
- (void)viewDidLoad{
 [super viewDidLoad];self.title=self.musicID.length?@"原声作品网页":@"网页翻页";self.view.backgroundColor=UIColor.systemBackgroundColor;
 WKWebViewConfiguration *config=[WKWebViewConfiguration new];DGSessionConfigure(config);config.allowsInlineMediaPlayback=YES;config.mediaTypesRequiringUserActionForPlayback=WKAudiovisualMediaTypeAll;config.defaultWebpagePreferences.preferredContentMode=self.musicID.length?WKContentModeMobile:WKContentModeDesktop;
 NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"keyword":self.keyword?:@"",@"users":@(self.users),@"musicID":self.musicID?:@""} options:0 error:nil];NSString *json=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
 NSString *capture=[NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"search-page" ofType:@"js"] encoding:NSUTF8StringEncoding error:nil]?:@"";
 NSString *script=[[NSString stringWithFormat:@"window.DGSearchExpected=%@;\n",json?:@"{}"]stringByAppendingString:capture];
 [config.userContentController addUserScript:[[WKUserScript alloc]initWithSource:script injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
 NSString *adapter=[NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"bridge" ofType:@"js"] encoding:NSUTF8StringEncoding error:nil]?:@"";
 [config.userContentController addUserScript:[[WKUserScript alloc]initWithSource:adapter injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES]];
 _web=[[WKWebView alloc]initWithFrame:CGRectZero configuration:config];_web.customUserAgent=self.musicID.length?@"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1":DGUserAgent();_web.navigationDelegate=self;_web.allowsBackForwardNavigationGestures=YES;[self.view addSubview:_web];
 self.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"magnifyingglass"] style:UIBarButtonItemStylePlain target:self action:@selector(loadSearch)],[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"arrow.uturn.backward"] style:UIBarButtonItemStylePlain target:self action:@selector(webBack)]];
 if(self.musicID.length){UIBarButtonItem *original=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"music.note"] style:UIBarButtonItemStylePlain target:self action:@selector(loadMusicOriginal)];original.accessibilityLabel=@"打开官方原声页";self.navigationItem.rightBarButtonItems=@[original,[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"arrow.uturn.backward"] style:UIBarButtonItemStylePlain target:self action:@selector(webBack)]];}
 _tools=[UIView new];_tools.backgroundColor=UIColor.secondarySystemBackgroundColor;[self.view addSubview:_tools];
 _hint=Label(12,UIFontWeightRegular);_hint.numberOfLines=2;_hint.textColor=UIColor.secondaryLabelColor;_hint.text=self.musicID.length?@"当前打开这首原声的官网页面。作品出现后可导回；官网未返回作品时无法导入。":@"默认打开综合搜索，手动翻页或下滑加载，再导回视频与图文。";[_tools addSubview:_hint];
 _import=[UIButton buttonWithType:UIButtonTypeSystem];[_import setTitle:@"导入已加载结果并返回" forState:UIControlStateNormal];_import.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];[_import addTarget:self action:@selector(importResults) forControlEvents:UIControlEventTouchUpInside];[_tools addSubview:_import];
 _reload=Symbol(@"arrow.clockwise",self,@selector(reload));_reload.accessibilityLabel=@"重新加载官方搜索页";[_tools addSubview:_reload];
 _spinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];_spinner.hidesWhenStopped=YES;[_tools addSubview:_spinner];
 __weak DGSearchPage *weak=self;DGSessionPrepare(_web,NO,^{[weak loadSearch];});
}
- (void)viewDidLayoutSubviews{
 [super viewDidLayoutSubviews];CGRect b=self.view.bounds;CGFloat top=self.view.safeAreaInsets.top,bottom=self.view.safeAreaInsets.bottom,tools=94;
 _web.frame=CGRectMake(0,top,b.size.width,MAX(0,b.size.height-top-bottom-tools));_tools.frame=CGRectMake(0,b.size.height-bottom-tools,b.size.width,tools+bottom);_hint.frame=CGRectMake(16,8,b.size.width-32,36);_import.frame=CGRectMake(44,46,b.size.width-100,42);_reload.frame=CGRectMake(b.size.width-48,46,40,42);_spinner.frame=CGRectMake(10,54,28,28);
}
- (void)loadSearch{
 NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_~"];
 if(self.musicID.length){[self loadMusicOriginal];return;}
 NSString *keyword=[self.keyword stringByAddingPercentEncodingWithAllowedCharacters:allowed];NSURLComponents *url=[NSURLComponents componentsWithString:[@"https://www.douyin.com/search/" stringByAppendingString:keyword?:@""]];url.queryItems=@[[NSURLQueryItem queryItemWithName:@"type" value:self.users?@"user":@"general"]];if(url.URL)[_web loadRequest:[NSURLRequest requestWithURL:url.URL]];
}
- (void)loadMusicOriginal{
 NSURL *url=[NSURL URLWithString:self.musicURL?:@""];NSString *path=url.path;BOOL matching=[path isEqualToString:[@"/music/" stringByAppendingString:self.musicID]]||[path isEqualToString:[@"/share/music/" stringByAppendingString:self.musicID]]||[path isEqualToString:[NSString stringWithFormat:@"/share/music/%@/",self.musicID]];
 if(![url.scheme.lowercaseString isEqual:@"https"]||![url.host.lowercaseString isEqual:@"www.iesdouyin.com"]||!matching)url=[NSURL URLWithString:[NSString stringWithFormat:@"https://www.iesdouyin.com/share/music/%@/",self.musicID]];
 _musicFallback=[url.host.lowercaseString isEqual:@"www.iesdouyin.com"];[_web loadRequest:[NSURLRequest requestWithURL:url]];
}
- (void)reload{if(self.musicID.length){_musicFallback=!_musicFallback;NSString *url=_musicFallback?[NSString stringWithFormat:@"https://www.iesdouyin.com/share/music/%@/",self.musicID]:[@"https://www.douyin.com/music/" stringByAppendingString:self.musicID];[_web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]]];_hint.text=@"已重新打开这首原声的官网页面。作品出现后可导回。";}else[_web reload];}
- (void)webBack{if(_web.canGoBack)[_web goBack];else [self loadSearch];}
- (BOOL)dgHasPreviousPage{return _web.canGoBack;}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[_web evaluateJavaScript:@"document.querySelectorAll('video,audio').forEach(media=>media.pause())" completionHandler:nil];}
- (void)importResults{
 if(_reading)return;_reading=YES;_import.enabled=NO;[_spinner startAnimating];__weak DGSearchPage *weak=self;
 [_web evaluateJavaScript:@"window.DGSearchPage?window.DGSearchPage.read():({error:'网页尚未加载，请等搜索结果出现后再导入'})" completionHandler:^(id value,NSError *error){DGSearchPage *self=weak;if(!self)return;self->_reading=NO;self->_import.enabled=YES;[self->_spinner stopAnimating];NSDictionary *result=[value isKindOfClass:NSDictionary.class]?value:nil;NSString *message=Text(String(result[@"error"]));NSArray *items=DGNormalizeWebItems(result[@"items"]);if(error||message.length||!items.count){DGToast(self,message.length?message:@"还没有读取到结果，请先手动翻页并等待内容出现");return;}DGSessionCapture(nil);if(self.imported)self.imported(items);[self.navigationController popViewControllerAnimated:YES];}];
}
- (void)webView:(WKWebView *)web didStartProvisionalNavigation:(WKNavigation *)navigation{[_spinner startAnimating];}
- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation{if(!_reading)[_spinner stopAnimating];if(self.musicID.length){__weak DGSearchPage *weak=self;[web evaluateJavaScript:@"(document.body?.innerText||'').includes('服务出现异常')" completionHandler:^(id result,NSError *error){DGSearchPage *self=weak;if(!self||![result boolValue])return;self->_hint.text=@"官网原声服务未返回作品，可重新加载；已有作品会保留。";}];}}
- (void)webView:(WKWebView *)web didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error{[_spinner stopAnimating];if(error.code!=NSURLErrorCancelled)DGToast(self,@"网页加载失败，可点击右下角重新加载");}
- (void)webView:(WKWebView *)web decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decision{
 NSString *scheme=action.request.URL.scheme.lowercaseString,*host=action.request.URL.host.lowercaseString;BOOL allowed=[scheme isEqualToString:@"about"]||([@[@"http",@"https"]containsObject:scheme]&&([host isEqualToString:@"douyin.com"]||[host hasSuffix:@".douyin.com"]||[host isEqualToString:@"www.iesdouyin.com"]||[host hasSuffix:@".bytedance.com"]));if(allowed&&!action.targetFrame){decision(WKNavigationActionPolicyCancel);[web loadRequest:action.request];return;}decision(allowed?WKNavigationActionPolicyAllow:WKNavigationActionPolicyCancel);
}
@end
UIViewController *DGMakeSearchPage(NSString *keyword,BOOL users,void (^imported)(NSArray<NSDictionary *> *items)){DGSearchPage *page=[DGSearchPage new];page.keyword=keyword;page.users=users;page.imported=imported;return page;}
UIViewController *DGMakeMusicWebPage(NSString *identifier,NSString *shareURL,void (^imported)(NSArray<NSDictionary *> *items)){DGSearchPage *page=[DGSearchPage new];page.musicID=identifier;page.musicURL=shareURL;page.imported=imported;return page;}
