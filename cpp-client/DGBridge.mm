#import "DGBridge.h"

NSString *DGUserAgent(void) {
    return @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";
}
@implementation DGBridge {
    WKWebView *_web;
    BOOL _ready, _started;
    NSUInteger _generation;
    NSMutableArray *_waiters;
    NSString *_script, *_failure;
}
- (instancetype)init {
    if ((self = [super init])) {
        _waiters = [NSMutableArray array];
        NSString *path = [NSBundle.mainBundle pathForResource:@"bridge" ofType:@"js"];
        _script = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"";
        NSString *regions=[NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"DouyinPublicationRegions" ofType:@"json"] encoding:NSUTF8StringEncoding error:nil];
        if(regions.length)_script=[[NSString stringWithFormat:@"window.DGPublicationRegions=%@;\n",regions] stringByAppendingString:_script];
        WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
        configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
        configuration.allowsInlineMediaPlayback = YES;
        configuration.allowsPictureInPictureMediaPlayback = NO;
        configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
        NSString *quiet = @"(()=>{HTMLMediaElement.prototype.play=function(){this.muted=true;return Promise.resolve()};let pending=false;const silence=()=>{pending=false;document.querySelectorAll('video,audio').forEach(v=>{v.muted=true;v.pause()})};new MutationObserver(()=>{if(!pending){pending=true;setTimeout(silence,250)}}).observe(document,{childList:true,subtree:true})})();";
        [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:quiet injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]];
        [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:_script injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES]];
        _web = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 1280, 900) configuration:configuration];
        _web.customUserAgent = DGUserAgent();
        _web.navigationDelegate = self;
        _web.userInteractionEnabled = NO;
        NSString *rules = @"[{\"trigger\":{\"url-filter\":\".*\",\"resource-type\":[\"media\"]},\"action\":{\"type\":\"block\"}}]";
        __weak DGBridge *weakSelf = self;
        [WKContentRuleListStore.defaultStore compileContentRuleListForIdentifier:@"douglass-signer-media-v2" encodedContentRuleList:rules completionHandler:^(WKContentRuleList *list, NSError *error) {
            DGBridge *strongSelf = weakSelf;
            if (strongSelf && list) [strongSelf->_web.configuration.userContentController addContentRuleList:list];
        }];
    }
    return self;
}
- (WKWebView *)web { return _web; }
- (void)mount:(UIView *)host {
    if (!_web.superview) {
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
        container.clipsToBounds = YES;
        container.alpha = 0.01;
        container.userInteractionEnabled = NO;
        container.accessibilityElementsHidden = YES;
        [host insertSubview:container atIndex:0];
        [container addSubview:_web];
    }
    if (!_started) { _started = YES; [self reload]; }
}
- (void)flush:(NSString *)error {
    NSArray *blocks = _waiters.copy;
    [_waiters removeAllObjects];
    for (void (^block)(NSString *) in blocks) block(error);
}
- (void)fail:(NSString *)message {
    _ready = NO;
    _failure = message;
    [self flush:message];
}
- (void)reload {
    ++_generation;
    [_web stopLoading];
    [self flush:@"登录状态已更新，请刷新重试"];
    _ready = NO; _failure = nil;
    NSUInteger generation = _generation;
    [_web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.douyin.com/jingxuan"] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:25]];
    __weak DGBridge *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 28 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        DGBridge *self = weakSelf;
        if (self && generation == self->_generation && !self->_ready) [self fail:@"官网连接超时，请打开登录网页或重新刷新"];
    });
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSUInteger generation = _generation;
    if (!_script.length) { [self fail:@"网页接口脚本缺失，请重新安装"]; return; }
    __weak DGBridge *weakSelf = self;
    // The script is also installed at document-end. No unconditional two-second sleep.
    [webView evaluateJavaScript:_script completionHandler:^(id result, NSError *error) {
        DGBridge *self = weakSelf;
        if (!self || generation != self->_generation) return;
        if (error) { [self fail:@"网页初始化失败，请刷新重试"]; return; }
        self->_ready = YES; self->_failure = nil;
        [self flush:nil];
    }];
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (error.code != NSURLErrorCancelled) [self fail:@"官网暂时无法连接，请检查网络后刷新"];
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
    if (_failure) { completion(nil, _failure); return; }
    NSUInteger generation = _generation;
    __block BOOL delivered = NO;
    void (^deliver)(NSDictionary *, NSString *) = ^(NSDictionary *result, NSString *error) {
        if (delivered) return;
        delivered = YES;
        completion(result, error);
    };
    // Includes queueing and JS execution. A stuck page may not strand a screen forever.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 32 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        deliver(nil, @"请求超时，请稍后刷新或打开登录网页完成验证");
    });
    __weak DGBridge *weakSelf = self;
    void (^execute)(NSString *) = ^(NSString *error) {
        DGBridge *self = weakSelf;
        if (delivered) return;
        if (!self || error) { deliver(nil, error ?: @"网页已关闭"); return; }
        if (generation != self->_generation) { deliver(nil, @"账号状态已变化，请刷新"); return; }
        [self->_web callAsyncJavaScript:@"return await window.DouGlass.request(operation, params);"
            arguments:@{@"operation": operation, @"params": parameters} inFrame:nil inContentWorld:WKContentWorld.pageWorld
            completionHandler:^(id value, NSError *failure) {
                DGBridge *self = weakSelf;
                if (!self || generation != self->_generation) { deliver(nil, @"账号状态已变化，请刷新"); return; }
                NSDictionary *result = [value isKindOfClass:NSDictionary.class] ? value : nil;
                NSString *message = [result[@"error"] isKindOfClass:NSString.class] ? result[@"error"] : nil;
                if (failure || !result) message = @"网页请求未完成，请刷新或在登录网页完成验证";
                deliver(result, message);
            }];
    };
    if (_ready) execute(nil); else [_waiters addObject:[execute copy]];
}
- (void)signOut:(void (^)(void))completion {
    ++_generation; _ready = NO;
    [_web stopLoading];
    [self flush:@"已退出当前账号"];
    [WKWebsiteDataStore.defaultDataStore removeDataOfTypes:WKWebsiteDataStore.allWebsiteDataTypes modifiedSince:NSDate.distantPast completionHandler:^{
        [self reload];
        completion();
    }];
}
@end

