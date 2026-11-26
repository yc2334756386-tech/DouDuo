#import "DGBridge.h"

NSString *DGUserAgent(void) {
    return @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";
}
@implementation DGBridge {
    WKWebView *_web;
    BOOL _ready, _started;
    NSUInteger _generation;
    NSMutableArray *_waiters;
    NSString *_script;
}
- (instancetype)init {
    if ((self = [super init])) {
        _waiters = [NSMutableArray array];
        NSString *path = [NSBundle.mainBundle pathForResource:@"bridge" ofType:@"js"];
        _script = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
        WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
        configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
        configuration.allowsInlineMediaPlayback = YES;
        configuration.allowsPictureInPictureMediaPlayback = NO;
        configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
        NSString *quiet = @"(()=>{HTMLMediaElement.prototype.play=function(){this.muted=true;return Promise.resolve()};new MutationObserver(()=>document.querySelectorAll('video,audio').forEach(v=>{v.muted=true;v.pause()})).observe(document,{childList:true,subtree:true})})();";
        [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:quiet injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
        _web = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 1280, 900) configuration:configuration];
        _web.customUserAgent = DGUserAgent();
        _web.navigationDelegate = self;
        _web.userInteractionEnabled = NO;
    }
    return self;
}
- (WKWebView *)web { return _web; }
- (void)mount:(UIView *)host {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
    container.clipsToBounds = YES;
    container.alpha = 0.01;
    container.userInteractionEnabled = NO;
    container.accessibilityElementsHidden = YES;
    [host insertSubview:container atIndex:0];
    [container addSubview:_web];
    if (!_started) { _started = YES; [self reload]; }
}
- (void)flush:(NSString *)error {
    NSArray *blocks = _waiters.copy;
    [_waiters removeAllObjects];
    for (void (^block)(NSString *) in blocks) block(error);
}
- (void)reload {
    [self flush:@"登录状态已更新，请刷新重试"];
    _ready = NO;
    NSUInteger generation = ++_generation;
    [_web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.douyin.com/jingxuan"]]];
    __weak DGBridge *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 35 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        DGBridge *self = weakSelf;
        if (self && generation == self->_generation && !self->_ready) [self flush:@"官网连接超时，请打开登录网页或重新刷新"];
    });
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSUInteger generation = _generation;
    __weak DGBridge *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        DGBridge *self = weakSelf;
        if (!self || generation != self->_generation) return;
        [webView evaluateJavaScript:self->_script completionHandler:^(id result, NSError *error) {
            if (generation != self->_generation) return;
            if (error) { [self flush:@"网页初始化失败，请刷新重试"]; return; }
            self->_ready = YES;
            [self flush:nil];
        }];
    });
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (error.code != NSURLErrorCancelled) [self flush:@"官网暂时无法连接，请检查网络后刷新"];
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self webView:webView didFailNavigation:navigation withError:error];
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView { [self reload]; }
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSString *scheme = action.request.URL.scheme.lowercaseString;
    decisionHandler(([@[@"http", @"https", @"about"] containsObject:scheme]) ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (void)request:(NSString *)operation parameters:(NSDictionary *)parameters completion:(DGResult)completion {
    NSUInteger generation = _generation;
    void (^execute)(NSString *) = ^(NSString *error) {
        if (error) { completion(nil, error); return; }
        [self->_web callAsyncJavaScript:@"return await window.DouGlass.request(operation, params);"
            arguments:@{@"operation": operation, @"params": parameters} inFrame:nil inContentWorld:WKContentWorld.pageWorld
            completionHandler:^(id value, NSError *failure) {
                if (generation != self->_generation) { completion(nil, @"账号状态已变化，请刷新"); return; }
                NSDictionary *result = [value isKindOfClass:NSDictionary.class] ? value : nil;
                NSString *message = result[@"error"];
                if (failure || !result) message = @"网页请求未完成，请刷新或在登录网页完成验证";
                completion(result, message);
            }];
    };
    if (_ready) execute(nil); else [_waiters addObject:[execute copy]];
}
- (void)signOut:(void (^)(void))completion {
    [_web stopLoading];
    [WKWebsiteDataStore.defaultDataStore removeDataOfTypes:WKWebsiteDataStore.allWebsiteDataTypes modifiedSince:NSDate.distantPast completionHandler:^{
        [self reload];
        completion();
    }];
}
@end
