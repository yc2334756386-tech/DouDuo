#import "DGCommon.h"
#import "DGColor.h"
void DGHaptic(void){dispatch_async(dispatch_get_main_queue(),^{static CFTimeInterval last=0;CFTimeInterval now=CACurrentMediaTime();if(now-last<.08)return;last=now;[[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleLight]impactOccurred];});}
@implementation DGImage {
    NSURLSessionDataTask *_task;
    NSString *_source;
    UIImage *_original;NSUInteger _colorGeneration,_loadGeneration;
}
- (void)setColorAdjusted:(BOOL)value{if(_colorAdjusted==value)return;_colorAdjusted=value;[NSNotificationCenter.defaultCenter removeObserver:self name:@"DGColorChanged" object:nil];if(value)[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(colorChanged) name:@"DGColorChanged" object:nil];[self colorChanged];}
- (void)setImage:(UIImage *)image{_original=image;[super setImage:image];if(_colorAdjusted)[self colorChanged];}
- (void)colorChanged{NSUInteger generation=++_colorGeneration;UIImage *original=_original;if(!_colorAdjusted||!original){[super setImage:original];return;}__weak DGImage *weak=self;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{UIImage *result=DGColorImage(original);dispatch_async(dispatch_get_main_queue(),^{DGImage *self=weak;if(self&&generation==self->_colorGeneration)[self setRenderedImage:result];});});}
- (void)setRenderedImage:(UIImage *)image{[super setImage:image];}
+ (NSCache *)cache {
    static NSCache *cache; static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.totalCostLimit = 32 * 1024 * 1024; });
    return cache;
}
+ (void)purgeCache{[DGImage.cache removeAllObjects];}
- (void)remote:(NSString *)url {
    if ([_source isEqualToString:url]) return;
    NSUInteger load=++_loadGeneration;[_task cancel]; _source = url.copy;self.image = nil;
    if (!url.length) return;
    NSUInteger maxPixels=self.maximumPixelSize?:1440;NSString *cacheKey=[NSString stringWithFormat:@"%@|%lu",url,(unsigned long)maxPixels];
    UIImage *cached = [DGImage.cache objectForKey:cacheKey];
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
            (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@(maxPixels)});
        UIImage *image = thumbnail ? [UIImage imageWithCGImage:thumbnail] : nil;
        size_t frames=CGImageSourceGetCount(source);
        if(frames>1 && data.length<12*1024*1024){
            NSMutableArray<UIImage *> *animation=[NSMutableArray array];double duration=0;
            size_t stride=MAX((size_t)1,(frames+23)/24);
            for(size_t index=0;index<frames;index+=stride){
                CGImageRef frame=CGImageSourceCreateThumbnailAtIndex(source,index,(__bridge CFDictionaryRef)@{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
(__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@320});
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
        [DGImage.cache setObject:image forKey:cacheKey cost:(NSUInteger)(image.size.width * image.size.height * image.scale * image.scale * 4 * MAX((NSUInteger)1,image.images.count))];
        dispatch_async(dispatch_get_main_queue(), ^{ DGImage *self = weakSelf; if (self && load==self->_loadGeneration && [self->_source isEqualToString:url]) self.image = image; });
    }];
    [_task resume];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self];[_task cancel]; }
@end

@implementation DGLogin {
 WKWebView *_web;NSString *_baseline;BOOL _closing,_saving;NSTimer *_poll;
}
- (void)viewDidLoad {
 [super viewDidLoad];self.title=@"抖音账号登录";self.view.backgroundColor=UIColor.systemBackgroundColor;
 self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(cancel)];
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"完成" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
 WKWebViewConfiguration *configuration=[WKWebViewConfiguration new];DGSessionConfigure(configuration);configuration.allowsInlineMediaPlayback=YES;configuration.mediaTypesRequiringUserActionForPlayback=WKAudiovisualMediaTypeAll;
 _web=[[WKWebView alloc]initWithFrame:CGRectZero configuration:configuration];_web.navigationDelegate=self;_web.UIDelegate=self;_web.customUserAgent=DGUserAgent();_web.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:_web];
 [NSLayoutConstraint activateConstraints:@[[_web.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[_web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[_web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[_web.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
 [configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies){for(NSHTTPCookie *cookie in cookies)if([cookie.name isEqualToString:@"sessionid"]&&[cookie.domain hasSuffix:@"douyin.com"])self->_baseline=cookie.value;DGSessionPrepare(self->_web,NO,^{[self->_web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://www.douyin.com/login_page?service=https%3A%2F%2Fwww.douyin.com"]]];});}];
 __weak DGLogin *weak=self;_poll=[NSTimer scheduledTimerWithTimeInterval:.8 repeats:YES block:^(NSTimer *timer){[weak inspectSession];}];
}
- (void)cancel {if(_closing)return;_closing=YES;[_poll invalidate];[_web stopLoading];[self dismissViewControllerAnimated:YES completion:^{if(self.finished)self.finished();}];}
- (void)finish {if(_closing)return;DGSessionCapture(^{if(self->_closing)return;self->_closing=YES;[self->_poll invalidate];[self->_web stopLoading];[self dismissViewControllerAnimated:YES completion:^{if(self.finished)self.finished();}];});}
- (void)saveAndFinish {if(_saving||_closing)return;_saving=YES;self.title=@"正在保存登录信息…";[self waitForTrust:NSDate.date];}
- (void)waitForTrust:(NSDate *)started {if(_closing)return;[_web evaluateJavaScript:@"window.__dgTrustSaved || 0" completionHandler:^(id value,NSError *error){if(self->_closing)return;double at=[value respondsToSelector:@selector(doubleValue)]?[value doubleValue]:0;BOOL settled=at>0&&NSDate.date.timeIntervalSince1970-at/1000.0>1.5;if(settled||[NSDate.date timeIntervalSinceDate:started]>=8){[self finish];return;}dispatch_after(dispatch_time(DISPATCH_TIME_NOW,350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self waitForTrust:started];});}];}
- (void)done {[WKWebsiteDataStore.defaultDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies){for(NSHTTPCookie *cookie in cookies)if([cookie.name isEqualToString:@"sessionid"]&&[cookie.domain hasSuffix:@"douyin.com"]&&cookie.value.length){[self saveAndFinish];return;}DGToast(self,@"请先在页面完成登录和安全验证");}];}
- (void)inspectSession {if(_saving||_closing)return;[WKWebsiteDataStore.defaultDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies){for(NSHTTPCookie *cookie in cookies)if([cookie.name isEqualToString:@"sessionid"]&&[cookie.domain hasSuffix:@"douyin.com"]&&cookie.value.length&&![cookie.value isEqualToString:self->_baseline]){[self saveAndFinish];break;}}];}
- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation {[self inspectSession];}
- (void)webView:(WKWebView *)web decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decision {decision([@[@"https",@"http",@"about",@"blob",@"data"]containsObject:action.request.URL.scheme.lowercaseString]?WKNavigationActionPolicyAllow:WKNavigationActionPolicyCancel);}
- (WKWebView *)webView:(WKWebView *)web createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {if(!action.targetFrame)[web loadRequest:action.request];return nil;}
- (void)webView:(WKWebView *)web runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completion {UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"抖音登录" message:message preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){completion();}]];[self presentViewController:alert animated:YES completion:nil];}
- (void)dealloc {[_poll invalidate];}
@end

