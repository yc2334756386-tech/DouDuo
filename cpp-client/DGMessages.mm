#import "DGCommon.h"
@interface DGMessages : UIViewController <WKNavigationDelegate,WKUIDelegate>
@end
@implementation DGMessages { WKWebView *_web; UIActivityIndicatorView *_spinner; }
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"信息";self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
    WKWebViewConfiguration *config=[WKWebViewConfiguration new];config.websiteDataStore=WKWebsiteDataStore.defaultDataStore;config.allowsInlineMediaPlayback=YES;config.mediaTypesRequiringUserActionForPlayback=WKAudiovisualMediaTypeAll;
    _web=[[WKWebView alloc] initWithFrame:CGRectZero configuration:config];_web.customUserAgent=DGUserAgent();_web.navigationDelegate=self;_web.UIDelegate=self;_web.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:_web];
    [NSLayoutConstraint activateConstraints:@[[_web.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[_web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[_web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[_web.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
    _spinner=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];self.navigationItem.titleView=_spinner;[_spinner startAnimating];[self refresh];
}
- (void)refresh {[_web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.douyin.com/chat"]]];}
- (void)close {[_web evaluateJavaScript:@"document.querySelectorAll('video,audio').forEach(v=>v.pause())" completionHandler:nil];[self dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];}
- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation {[_spinner stopAnimating];self.navigationItem.titleView=nil;}
- (void)webView:(WKWebView *)web didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {[_spinner stopAnimating];self.navigationItem.titleView=nil;if(error.code!=NSURLErrorCancelled)DGToast(self,@"信息加载失败，请点右上角刷新");}
- (void)webView:(WKWebView *)web decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decision {
    decision([@[@"https",@"http",@"about",@"blob",@"data"] containsObject:action.request.URL.scheme.lowercaseString]?WKNavigationActionPolicyAllow:WKNavigationActionPolicyCancel);
}
- (WKWebView *)webView:(WKWebView *)web createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {if(!action.targetFrame)[web loadRequest:action.request];return nil;}
@end
UIViewController *DGMakeMessages(DGBridge *bridge){return [DGMessages new];}

