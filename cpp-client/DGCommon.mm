#import "DGCommon.h"
@implementation DGImage {
    NSURLSessionDataTask *_task;
    NSString *_source;
}
+ (NSCache *)cache {
    static NSCache *cache; static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.totalCostLimit = 72 * 1024 * 1024; });
    return cache;
}
- (void)remote:(NSString *)url {
    if ([_source isEqualToString:url]) return;
    [_task cancel]; _source = url.copy; self.image = nil;
    if (!url.length) return;
    UIImage *cached = [DGImage.cache objectForKey:url];
    if (cached) { self.image = cached; return; }
    NSURL *address = [NSURL URLWithString:url];
    if (!address) return;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:address cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:20];
    [request setValue:DGUserAgent() forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"https://www.douyin.com/" forHTTPHeaderField:@"Referer"];
    __weak DGImage *weakSelf = self;
    _task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!data || error) return;
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (!source) return;
        CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{
            (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
            (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES,
            (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@2048});
        UIImage *image = thumbnail ? [UIImage imageWithCGImage:thumbnail] : nil;
        size_t frames=CGImageSourceGetCount(source);
        if(frames>1 && data.length<12*1024*1024){
            NSMutableArray<UIImage *> *animation=[NSMutableArray array];double duration=0;
            size_t stride=MAX((size_t)1,(frames+23)/24);
            for(size_t index=0;index<frames;index+=stride){
                CGImageRef frame=CGImageSourceCreateThumbnailAtIndex(source,index,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@320});
                if(!frame)continue;[animation addObject:[UIImage imageWithCGImage:frame]];CGImageRelease(frame);
                NSDictionary *properties=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,index,NULL));
                NSDictionary *gif=properties[(__bridge NSString *)kCGImagePropertyGIFDictionary];
                double delay=[gif[(__bridge NSString *)kCGImagePropertyGIFUnclampedDelayTime] doubleValue];
                if(delay<0.02)delay=[gif[(__bridge NSString *)kCGImagePropertyGIFDelayTime] doubleValue];
                duration+=MAX(delay,0.06)*stride;
            }
            if(animation.count>1)image=[UIImage animatedImageWithImages:animation duration:duration];
        }
        if (thumbnail) CGImageRelease(thumbnail);
        CFRelease(source);
        if (!image) return;
        [DGImage.cache setObject:image forKey:url cost:(NSUInteger)(image.size.width * image.size.height * image.scale * image.scale * 4 * MAX((NSUInteger)1,image.images.count))];
        dispatch_async(dispatch_get_main_queue(), ^{ DGImage *self = weakSelf; if (self && [self->_source isEqualToString:url]) self.image = image; });
    }];
    [_task resume];
}
- (void)dealloc { [_task cancel]; }
@end

@implementation DGLogin {
    WKWebView *_web;
    NSString *_baseline;
    BOOL _closing;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"抖音账号登录";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(done)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
    configuration.allowsInlineMediaPlayback = YES;
    configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeAll;
    _web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    _web.navigationDelegate = self; _web.UIDelegate = self; _web.customUserAgent = DGUserAgent();
    _web.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_web];
    [NSLayoutConstraint activateConstraints:@[
        [_web.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_web.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
    [configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        for (NSHTTPCookie *cookie in cookies) if ([cookie.name isEqualToString:@"sessionid"] && [cookie.domain hasSuffix:@"douyin.com"]) self->_baseline = cookie.value;
        [self->_web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.douyin.com/login_page?service=https%3A%2F%2Fwww.douyin.com"]]];
    }];
}
- (void)done {
    if (_closing) return; _closing = YES;
    [_web evaluateJavaScript:@"document.querySelectorAll('video,audio').forEach(v=>v.pause())" completionHandler:nil];
    [self dismissViewControllerAnimated:YES completion:^{ if (self.finished) self.finished(); }];
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [WKWebsiteDataStore.defaultDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        for (NSHTTPCookie *cookie in cookies) {
            if ([cookie.name isEqualToString:@"sessionid"] && [cookie.domain hasSuffix:@"douyin.com"] && cookie.value.length && ![cookie.value isEqualToString:self->_baseline]) { [self done]; break; }
        }
    }];
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))handler {
    NSString *scheme = action.request.URL.scheme.lowercaseString;
    handler([@[@"http",@"https",@"about",@"blob",@"data"] containsObject:scheme] ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    if (!action.targetFrame) [webView loadRequest:action.request];
    return nil;
}
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"抖音登录" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { completion(); }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

