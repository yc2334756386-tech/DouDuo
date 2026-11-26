#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import "DGBridge.h"
#include "Core.hpp"
#include <algorithm>
#include <cmath>
#include <utility>

using douglass::Work;
using douglass::Comment;
static NSString *Text(const std::string &value) { return [NSString stringWithUTF8String:value.c_str()] ?: @""; }
static std::string String(id value) {
    if (!value || value == NSNull.null) return {};
    NSString *text = [value isKindOfClass:NSString.class] ? value : [value description];
    return text.UTF8String ?: "";
}
static long long Number(id value) { return [value respondsToSelector:@selector(longLongValue)] ? [value longLongValue] : 0; }
static NSArray *Array(id value) { return [value isKindOfClass:NSArray.class] ? value : @[]; }
static Work ReadWork(NSDictionary *value) {
    Work work;
    work.id = String(value[@"id"]); work.caption = String(value[@"caption"]);
    work.author = String(value[@"author"]); work.avatar = String(value[@"avatar"]);
    work.cover = String(value[@"cover"]); work.play = String(value[@"play"]);
    work.alternate = String(value[@"alternate"]); work.music = String(value[@"music"]);
    work.comments = Number(value[@"comments"]); work.likes = Number(value[@"likes"]);
    work.duration = [value[@"duration"] doubleValue];
    for (id image in Array(value[@"images"])) work.images.emplace_back(String(image));
    return work;
}
static Comment ReadComment(NSDictionary *value) {
    Comment comment;
    comment.id = String(value[@"id"]); comment.text = String(value[@"text"]);
    comment.author = String(value[@"author"]); comment.avatar = String(value[@"avatar"]);
    comment.location = String(value[@"location"]); comment.likes = Number(value[@"likes"]);
    comment.replies = Number(value[@"replies"]); comment.timestamp = Number(value[@"timestamp"]);
    for (id image in Array(value[@"images"])) comment.images.emplace_back(String(image));
    return comment;
}
static UILabel *Label(CGFloat size, UIFontWeight weight) {
    UILabel *label = [UILabel new];
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = UIColor.whiteColor;
    return label;
}
static UIButton *Symbol(NSString *name, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
static UIVisualEffectView *Glass(CGFloat radius) {
    UIVisualEffect *effect;
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        glass.interactive = YES;
        effect = glass;
    } else effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *view = [[UIVisualEffectView alloc] initWithEffect:effect];
    view.layer.cornerRadius = radius;
    view.clipsToBounds = YES;
    return view;
}
static AVURLAsset *Asset(NSString *url) {
    return [AVURLAsset URLAssetWithURL:[NSURL URLWithString:url] options:@{@"AVURLAssetHTTPHeaderFieldsKey":@{@"User-Agent":DGUserAgent(),@"Referer":@"https://www.douyin.com/"}}];
}

@interface DGImage : UIImageView
- (void)remote:(NSString *)url;
@end
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
        if (thumbnail) CGImageRelease(thumbnail);
        CFRelease(source);
        if (!image) return;
        [DGImage.cache setObject:image forKey:url cost:(NSUInteger)(image.size.width * image.size.height * 4)];
        dispatch_async(dispatch_get_main_queue(), ^{ DGImage *self = weakSelf; if (self && [self->_source isEqualToString:url]) self.image = image; });
    }];
    [_task resume];
}
- (void)dealloc { [_task cancel]; }
@end

@interface DGLogin : UIViewController <WKNavigationDelegate, WKUIDelegate>
@property(nonatomic, copy) void (^finished)(void);
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

@interface DGFeedCell : UICollectionViewCell <UIScrollViewDelegate>
@property(nonatomic, copy) void (^commentsAction)(void);
- (void)display:(const Work &)work;
- (void)active:(BOOL)active;
@end
@implementation DGFeedCell {
    Work _work;
    DGImage *_cover;
    UIScrollView *_photos;
    NSMutableArray<DGImage *> *_photoViews;
    UILabel *_author, *_caption, *_photoCount, *_count, *_pause, *_message;
    UIVisualEffectView *_photoGlass, *_commentGlass;
    UIButton *_commentButton;
    UIView *_gradientView;
    CAGradientLayer *_gradient;
    AVPlayer *_player, *_musicPlayer;
    AVPlayerLayer *_playerLayer;
    AVPlayerItem *_observedItem;
    id _loopToken, _musicLoopToken, _clock;
    UISlider *_slider;
    BOOL _active, _manuallyPaused, _alternateUsed, _dragging;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.backgroundColor = UIColor.blackColor;
        _cover = [DGImage new]; _cover.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:_cover];
        _playerLayer = [AVPlayerLayer playerLayerWithPlayer:nil]; _playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        [self.contentView.layer addSublayer:_playerLayer];
        _photos = [UIScrollView new]; _photos.pagingEnabled = YES; _photos.showsHorizontalScrollIndicator = NO;
        _photos.delegate = self; _photos.alwaysBounceHorizontal = NO;
        [self.contentView addSubview:_photos];
        _photoViews = [NSMutableArray array];
        _gradientView = [UIView new]; _gradientView.userInteractionEnabled = NO;
        _gradient = [CAGradientLayer layer]; _gradient.colors = @[(id)UIColor.clearColor.CGColor,(id)[UIColor colorWithWhite:0 alpha:0.78].CGColor];
        [_gradientView.layer addSublayer:_gradient]; [self.contentView addSubview:_gradientView];
        _author = Label(18, UIFontWeightSemibold); _caption = Label(15, UIFontWeightRegular); _caption.numberOfLines = 3;
        [self.contentView addSubview:_author]; [self.contentView addSubview:_caption];
        _photoGlass = Glass(17); _photoCount = Label(12, UIFontWeightMedium); _photoCount.textAlignment = NSTextAlignmentCenter;
        [_photoGlass.contentView addSubview:_photoCount]; [self.contentView addSubview:_photoGlass];
        _commentGlass = Glass(27); _commentButton = Symbol(@"text.bubble", self, @selector(comments));
        _commentButton.accessibilityLabel = @"浏览评论";
        [_commentGlass.contentView addSubview:_commentButton]; [self.contentView addSubview:_commentGlass];
        _count = Label(12, UIFontWeightMedium); _count.textAlignment = NSTextAlignmentCenter; [self.contentView addSubview:_count];
        _pause = Label(56, UIFontWeightLight); _pause.text = @"▶"; _pause.textAlignment = NSTextAlignmentCenter; _pause.hidden = YES;
        _pause.layer.shadowColor = UIColor.blackColor.CGColor; _pause.layer.shadowOpacity = 0.3; _pause.layer.shadowRadius = 8;
        [self.contentView addSubview:_pause];
        _message = Label(13, UIFontWeightRegular); _message.textAlignment = NSTextAlignmentCenter; _message.numberOfLines = 2; [self.contentView addSubview:_message];
        _slider = [UISlider new]; _slider.tintColor = [UIColor colorWithRed:0.76 green:0.96 blue:0.96 alpha:1];
        _slider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.16];
        [_slider setThumbImage:[UIImage systemImageNamed:@"circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:7]] forState:UIControlStateNormal];
        [_slider addTarget:self action:@selector(seekStart) forControlEvents:UIControlEventTouchDown];
        [_slider addTarget:self action:@selector(seekEnd) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
        [self.contentView addSubview:_slider];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggle)];
        tap.cancelsTouchesInView = NO; [self.contentView addGestureRecognizer:tap];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect rect = self.contentView.bounds;
    CGFloat width = rect.size.width, height = rect.size.height, bottom = MAX(self.safeAreaInsets.bottom, 18);
    _cover.frame = rect; _playerLayer.frame = rect; _photos.frame = rect;
    _photos.contentSize = CGSizeMake(width * _photoViews.count, height);
    for (NSUInteger i = 0; i < _photoViews.count; ++i) _photoViews[i].frame = CGRectMake(i * width, 0, width, height);
    _gradientView.frame = CGRectMake(0, MAX(0, height - 320), width, 320); _gradient.frame = _gradientView.bounds;
    CGFloat textWidth = MIN(width - 104, 680);
    CGSize size = [_caption sizeThatFits:CGSizeMake(textWidth, 78)];
    CGFloat textHeight = MIN(size.height, 72);
    _caption.frame = CGRectMake(22, height - bottom - 44 - textHeight, textWidth, textHeight);
    _author.frame = CGRectMake(22, CGRectGetMinY(_caption.frame) - 34, textWidth, 26);
    _commentGlass.frame = CGRectMake(width - 74, height - bottom - 158, 54, 54); _commentButton.frame = _commentGlass.bounds;
    _count.frame = CGRectMake(width - 84, CGRectGetMaxY(_commentGlass.frame) + 5, 74, 18);
    _photoGlass.frame = CGRectMake(width - 98, MAX(self.safeAreaInsets.top, 20) + 78, 78, 34); _photoCount.frame = _photoGlass.bounds;
    _pause.frame = CGRectMake((width - 90) / 2, (height - 90) / 2, 90, 90);
    _message.frame = CGRectMake(30, height / 2 + 58, width - 60, 52);
    _slider.frame = CGRectMake(22, height - bottom - 34, width - 44, 24);
    if (_work.photo() && width > 0) [self loadPhotos];
}
- (void)resetPlayer {
    if (_observedItem) { [_observedItem removeObserver:self forKeyPath:@"status"]; _observedItem = nil; }
    if (_clock && _player) { [_player removeTimeObserver:_clock]; _clock = nil; }
    if (_loopToken) { [NSNotificationCenter.defaultCenter removeObserver:_loopToken]; _loopToken = nil; }
    if (_musicLoopToken) { [NSNotificationCenter.defaultCenter removeObserver:_musicLoopToken]; _musicLoopToken = nil; }
    [_player pause]; [_musicPlayer pause]; _player = nil; _musicPlayer = nil; _playerLayer.player = nil;
}
- (void)prepareForReuse {
    [super prepareForReuse]; [self resetPlayer]; _active = NO; self.commentsAction = nil;
    for (DGImage *image in _photoViews) [image removeFromSuperview];
    [_photoViews removeAllObjects];
}
- (void)display:(const Work &)work {
    [self resetPlayer];
    _work = work; _manuallyPaused = NO; _alternateUsed = NO; _pause.hidden = YES; _message.text = @""; _slider.value = 0;
    _author.text = [@"@" stringByAppendingString:Text(work.author)]; _caption.text = Text(work.caption);
    _count.text = Text(douglass::compact(work.comments)); [_cover remote:Text(work.cover)]; _cover.hidden = NO;
    for (DGImage *image in _photoViews) [image removeFromSuperview]; [_photoViews removeAllObjects];
    _photos.contentOffset = CGPointZero; _photos.hidden = !work.photo(); _photoGlass.hidden = !work.photo(); _slider.hidden = work.photo();
    if (work.photo()) {
        for (const auto &url : work.images) {
            DGImage *image = [DGImage new]; image.contentMode = UIViewContentModeScaleAspectFit;
            [_photos addSubview:image]; [_photoViews addObject:image];
        }
        _photoCount.text = [NSString stringWithFormat:@"图文 1/%lu", (unsigned long)work.images.size()];
        if (!work.music.empty()) {
            _musicPlayer = [AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:Asset(Text(work.music))]];
            __weak DGFeedCell *weakSelf = self;
            _musicLoopToken = [NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:_musicPlayer.currentItem queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                DGFeedCell *self = weakSelf; if (!self) return;
                [self->_musicPlayer seekToTime:kCMTimeZero]; if (self->_active && !self->_manuallyPaused) [self->_musicPlayer play];
            }];
        }
    } else [self playURL:Text(work.play)];
    [self setNeedsLayout];
}
- (void)playURL:(NSString *)url {
    [self resetPlayer];
    if (!url.length) return;
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:Asset(url)]; item.preferredForwardBufferDuration = 8;
    _player = [AVPlayer playerWithPlayerItem:item]; _playerLayer.player = _player;
    _observedItem = item; [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];
    __weak DGFeedCell *weakSelf = self;
    _loopToken = [NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:item queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        DGFeedCell *self = weakSelf; if (!self) return;
        [self->_player seekToTime:kCMTimeZero completionHandler:^(BOOL complete) { if (self->_active && !self->_manuallyPaused) [self->_player play]; }];
    }];
    _clock = [_player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.25, 600) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        DGFeedCell *self = weakSelf; if (!self || self->_dragging) return;
        double duration = CMTimeGetSeconds(self->_player.currentItem.duration), seconds = CMTimeGetSeconds(time);
        if (std::isfinite(duration) && duration > 0 && std::isfinite(seconds)) self->_slider.value = seconds / duration;
    }];
    if (_active && !_manuallyPaused) [_player play];
}
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object != _observedItem) return;
    if (_observedItem.status == AVPlayerItemStatusReadyToPlay) {
        _cover.hidden = YES; _message.text = @"";
        if (_active && !_manuallyPaused) [_player play];
    } else if (_observedItem.status == AVPlayerItemStatusFailed) {
        if (!_alternateUsed && !_work.alternate.empty() && _work.alternate != _work.play) { _alternateUsed = YES; [self playURL:Text(_work.alternate)]; }
        else _message.text = @"视频暂时无法播放\n点击画面重试，或上滑查看下一条";
    }
}
- (void)active:(BOOL)active {
    _active = active;
    if (active && !_manuallyPaused) { [_player play]; [_musicPlayer play]; }
    else { [_player pause]; [_musicPlayer pause]; }
}
- (void)toggle {
    if (_observedItem.status == AVPlayerItemStatusFailed) { _alternateUsed = NO; [self playURL:Text(_work.play)]; return; }
    _manuallyPaused = !_manuallyPaused; _pause.hidden = !_manuallyPaused; [self active:_active];
}
- (void)comments { if (self.commentsAction) self.commentsAction(); }
- (void)loadPhotos {
    if (_photos.bounds.size.width <= 0) return;
    NSInteger page = MAX(0, MIN((NSInteger)_photoViews.count - 1, (NSInteger)llround(_photos.contentOffset.x / _photos.bounds.size.width)));
    for (NSInteger i = MAX(0, page - 1); i <= MIN((NSInteger)_photoViews.count - 1, page + 1); ++i) [_photoViews[i] remote:Text(_work.images[i])];
    _photoCount.text = [NSString stringWithFormat:@"图文 %ld/%lu", (long)page + 1, (unsigned long)_photoViews.count];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView { [self loadPhotos]; }
- (void)seekStart { _dragging = YES; }
- (void)seekEnd {
    double duration = CMTimeGetSeconds(_player.currentItem.duration);
    if (std::isfinite(duration) && duration > 0) [_player seekToTime:CMTimeMakeWithSeconds(_slider.value * duration, 600) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    _dragging = NO;
}
- (void)dealloc { [self resetPlayer]; }
@end

@interface DGCommentCell : UITableViewCell
@property(nonatomic, copy) void (^replyAction)(void);
- (void)display:(const Comment &)comment;
@end
@implementation DGCommentCell {
    DGImage *_avatar, *_image;
    UILabel *_name, *_body, *_meta;
    UIButton *_reply;
    NSLayoutConstraint *_imageHeight;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        self.backgroundColor = UIColor.clearColor; self.selectionStyle = UITableViewCellSelectionStyleNone;
        _avatar = [DGImage new]; _avatar.layer.cornerRadius = 18; _avatar.clipsToBounds = YES; _avatar.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08]; _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _name = Label(12, UIFontWeightSemibold); _name.textColor = [UIColor colorWithWhite:1 alpha:0.6];
        _body = Label(15, UIFontWeightRegular); _body.numberOfLines = 0;
        _meta = Label(11, UIFontWeightRegular); _meta.textColor = [UIColor colorWithWhite:1 alpha:0.4];
        _image = [DGImage new]; _image.contentMode = UIViewContentModeScaleAspectFit; _image.clipsToBounds = YES; _image.layer.cornerRadius = 12;
        _reply = [UIButton buttonWithType:UIButtonTypeSystem]; _reply.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        _reply.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold]; _reply.tintColor = [UIColor colorWithRed:0.7 green:0.9 blue:0.92 alpha:1];
        [_reply addTarget:self action:@selector(replies) forControlEvents:UIControlEventTouchUpInside];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_name,_body,_image,_meta,_reply]];
        stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 7;
        _avatar.translatesAutoresizingMaskIntoConstraints = NO; stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_avatar]; [self.contentView addSubview:stack];
        _imageHeight = [_image.heightAnchor constraintEqualToConstant:0]; _imageHeight.active = YES;
        [NSLayoutConstraint activateConstraints:@[
            [_avatar.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18],
            [_avatar.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
            [_avatar.widthAnchor constraintEqualToConstant:36],[_avatar.heightAnchor constraintEqualToConstant:36],
            [stack.leadingAnchor constraintEqualToAnchor:_avatar.trailingAnchor constant:12],
            [stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18],
            [stack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
            [stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16]]];
    }
    return self;
}
- (void)display:(const Comment &)comment {
    [_avatar remote:Text(comment.avatar)]; _name.text = Text(comment.author); _body.text = Text(comment.text);
    NSDateFormatter *format = [NSDateFormatter new]; format.dateFormat = @"MM-dd";
    NSString *date = comment.timestamp > 0 ? [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:comment.timestamp]] : @"";
    _meta.text = [NSString stringWithFormat:@"%@  %@    ♡ %@", date, Text(comment.location), Text(douglass::compact(comment.likes))];
    _image.hidden = comment.images.empty(); _imageHeight.constant = comment.images.empty() ? 0 : 170;
    [_image remote:comment.images.empty() ? @"" : Text(comment.images.front())];
    _reply.hidden = comment.replies <= 0;
    [_reply setTitle:[NSString stringWithFormat:@"查看 %@ 条回复 ›",Text(douglass::compact(comment.replies))] forState:UIControlStateNormal];
}
- (void)replies { if (self.replyAction) self.replyAction(); }
- (void)prepareForReuse { [super prepareForReuse]; self.replyAction = nil; }
@end

@interface DGComments : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (instancetype)initWithBridge:(DGBridge *)bridge work:(NSString *)work parent:(NSString *)parent;
@end
@implementation DGComments {
    DGBridge *_bridge;
    NSString *_workID, *_parent, *_cursor;
    UITableView *_table;
    UIButton *_footer;
    UILabel *_empty;
    BOOL _loading, _more;
    std::vector<Comment> _comments;
    std::unordered_set<std::string> _ids;
}
- (instancetype)initWithBridge:(DGBridge *)bridge work:(NSString *)work parent:(NSString *)parent {
    if ((self = [super init])) { _bridge = bridge; _workID = work; _parent = parent; _cursor = @"0"; _more = YES; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = _parent.length ? @"回复 · 只读" : @"评论 · 只读";
    self.view.backgroundColor = UIColor.secondarySystemBackgroundColor;
    if (!_parent.length) self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];
    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    _table.backgroundColor = UIColor.clearColor; _table.separatorColor = [UIColor colorWithWhite:1 alpha:0.08];
    _table.estimatedRowHeight = 110; _table.rowHeight = UITableViewAutomaticDimension;
    _table.dataSource = self; _table.delegate = self; [_table registerClass:DGCommentCell.class forCellReuseIdentifier:@"comment"];
    [self.view addSubview:_table];
    _footer = [UIButton buttonWithType:UIButtonTypeSystem]; _footer.frame = CGRectMake(0,0,320,70);
    _footer.tintColor = UIColor.secondaryLabelColor; _footer.titleLabel.font = [UIFont systemFontOfSize:13];
    [_footer addTarget:self action:@selector(loadMore) forControlEvents:UIControlEventTouchUpInside]; _table.tableFooterView = _footer;
    _empty = Label(14, UIFontWeightRegular); _empty.textColor = UIColor.secondaryLabelColor; _empty.textAlignment = NSTextAlignmentCenter; _empty.numberOfLines = 0;
    _table.backgroundView = _empty; [self loadMore];
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)loadMore {
    if (_loading || !_more) return; _loading = YES;
    [_footer setTitle:@"正在加载…" forState:UIControlStateNormal];
    if (_comments.empty()) _empty.text = @"正在读取评论";
    NSString *oldCursor = _cursor;
    __weak DGComments *weakSelf = self;
    [_bridge request:_parent.length ? @"replies" : @"comments" parameters:@{@"id":_workID,@"parent":_parent ?: @"",@"cursor":_cursor} completion:^(NSDictionary *result, NSString *error) {
        DGComments *self = weakSelf; if (!self) return; self->_loading = NO;
        if (error) {
            if (self->_comments.empty()) self->_empty.text = error;
            [self->_footer setTitle:@"加载失败，点此重试" forState:UIControlStateNormal]; return;
        }
        for (NSDictionary *value in Array(result[@"items"])) {
            Comment comment = ReadComment(value);
            if (!comment.id.empty() && self->_ids.insert(comment.id).second) self->_comments.emplace_back(std::move(comment));
        }
        self->_cursor = [result[@"cursor"] description] ?: @"0";
        self->_more = [result[@"more"] boolValue] && ![oldCursor isEqualToString:self->_cursor];
        self->_empty.text = self->_comments.empty() ? @"还没有评论" : @"";
        [self->_footer setTitle:self->_more ? @"继续加载" : @"已显示全部评论" forState:UIControlStateNormal];
        [self->_table reloadData];
    }];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _comments.size(); }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DGCommentCell *cell = [tableView dequeueReusableCellWithIdentifier:@"comment" forIndexPath:indexPath];
    const Comment &comment = _comments[indexPath.row]; [cell display:comment];
    NSString *commentID = Text(comment.id); __weak DGComments *weakSelf = self;
    cell.replyAction = ^{ DGComments *self = weakSelf; if (!self) return;
        DGComments *replies = [[DGComments alloc] initWithBridge:self->_bridge work:self->_workID parent:commentID];
        [self.navigationController pushViewController:replies animated:YES];
    };
    return cell;
}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((std::size_t)(indexPath.row + 3) >= _comments.size() && _more && !_loading) [self loadMore];
}
@end

@interface DGFeed : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIAdaptivePresentationControllerDelegate>
@end
@implementation DGFeed {
    douglass::Feed _feed;
    DGBridge *_bridge;
    UICollectionView *_collection;
    UIVisualEffectView *_bar;
    UILabel *_brand, *_recommend, *_state, *_subtitle;
    UIButton *_account, *_refresh, *_retry, *_login;
    UIActivityIndicatorView *_spinner;
    UIStackView *_empty;
    UIRefreshControl *_pull;
    BOOL _loading, _loggedIn, _foreground, _failed;
    NSUInteger _requestGeneration;
    NSInteger _refreshIndex, _emptyPages;
    NSString *_nickname;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.blackColor; self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _foreground = YES; _refreshIndex = 1;
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new]; layout.minimumLineSpacing = 0; layout.minimumInteritemSpacing = 0;
    _collection = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:layout];
    _collection.backgroundColor = UIColor.blackColor; _collection.pagingEnabled = YES; _collection.showsVerticalScrollIndicator = NO;
    _collection.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _collection.dataSource = self; _collection.delegate = self; _collection.alwaysBounceVertical = YES;
    [_collection registerClass:DGFeedCell.class forCellWithReuseIdentifier:@"work"]; [self.view addSubview:_collection];
    _pull = [UIRefreshControl new]; _pull.tintColor = UIColor.whiteColor; [_pull addTarget:self action:@selector(refreshFeed) forControlEvents:UIControlEventValueChanged]; _collection.refreshControl = _pull;
    _bridge = [DGBridge new]; [_bridge mount:self.view];
    _bar = Glass(27); [self.view addSubview:_bar];
    _brand = Label(19, UIFontWeightSemibold); _brand.text = @"澄流";
    _recommend = Label(14, UIFontWeightMedium); _recommend.text = @"推荐"; _recommend.textAlignment = NSTextAlignmentCenter;
    _recommend.textColor = [UIColor colorWithWhite:1 alpha:0.72];
    _refresh = Symbol(@"arrow.clockwise", self, @selector(refreshFeed)); _refresh.accessibilityLabel = @"刷新推荐";
    _account = Symbol(@"person.crop.circle", self, @selector(account)); _account.accessibilityLabel = @"登录与账号";
    for (UIView *view in @[_brand,_recommend,_refresh,_account]) [_bar.contentView addSubview:view];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _state = Label(20, UIFontWeightSemibold); _state.textAlignment = NSTextAlignmentCenter;
    _subtitle = Label(14, UIFontWeightRegular); _subtitle.numberOfLines = 0; _subtitle.textAlignment = NSTextAlignmentCenter; _subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.52];
    _retry = [UIButton buttonWithType:UIButtonTypeSystem]; [_retry setTitle:@"重新加载" forState:UIControlStateNormal];
    [_retry addTarget:self action:@selector(refreshFeed) forControlEvents:UIControlEventTouchUpInside];
    _login = [UIButton buttonWithType:UIButtonTypeSystem]; [_login setTitle:@"登录 / 网页验证" forState:UIControlStateNormal];
    [_login addTarget:self action:@selector(openLogin) forControlEvents:UIControlEventTouchUpInside];
    _empty = [[UIStackView alloc] initWithArrangedSubviews:@[_spinner,_state,_subtitle,_retry,_login]];
    _empty.axis = UILayoutConstraintAxisVertical; _empty.spacing = 18; _empty.alignment = UIStackViewAlignmentCenter; [self.view addSubview:_empty];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self loadFeed:YES];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize old = _collection.bounds.size; _collection.frame = self.view.bounds;
    if (!CGSizeEqualToSize(old, _collection.bounds.size)) [_collection.collectionViewLayout invalidateLayout];
    CGFloat width = self.view.bounds.size.width, top = self.view.safeAreaInsets.top;
    CGFloat barWidth = MIN(width - 32, 490);
    _bar.frame = CGRectMake((width - barWidth) / 2, top + 8, barWidth, 54);
    _brand.frame = CGRectMake(19, 0, 75, 54); _recommend.frame = CGRectMake((barWidth - 90) / 2, 0, 90, 54);
    _refresh.frame = CGRectMake(barWidth - 94, 4, 42, 46); _account.frame = CGRectMake(barWidth - 51, 4, 42, 46);
    _empty.frame = CGRectMake(34, self.view.bounds.size.height / 2 - 100, width - 68, 250);
    _subtitle.preferredMaxLayoutWidth = MIN(width - 68, 430);
}
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self activate]; }
- (void)background { _foreground = NO; [self activate]; }
- (void)foreground { _foreground = YES; [self activate]; }
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)refreshFeed {
    if (_loading) return;
    if (_failed) [_bridge reload];
    _refreshIndex = 1; _emptyPages = 0; [self loadFeed:YES];
}
- (void)updateEmpty:(NSString *)message {
    BOOL empty = _feed.works.empty(); _empty.hidden = !empty;
    _state.text = _loading ? @"让喜欢的内容，流进来" : @"暂时没有新内容";
    _subtitle.text = message ?: (_loggedIn ? @"正在获取你的推荐" : @"视频与图文推荐 · 登录后使用你的抖音账号");
    _retry.hidden = _loading; _login.hidden = _loading;
    if (_loading) [_spinner startAnimating]; else [_spinner stopAnimating];
}
- (void)loadFeed:(BOOL)replace {
    if (_loading || (!replace && !_feed.more)) return;
    _loading = YES; _failed = NO; [self updateEmpty:nil];
    _refresh.enabled = NO; NSUInteger generation = _requestGeneration;
    NSInteger refresh = _refreshIndex++;
    __weak DGFeed *weakSelf = self;
    [_bridge request:@"feed" parameters:@{@"refresh":@(refresh)} completion:^(NSDictionary *result, NSString *error) {
        DGFeed *self = weakSelf; if (!self || generation != self->_requestGeneration) return;
        self->_loading = NO; self->_refresh.enabled = YES; [self->_pull endRefreshing];
        if (error) {
            self->_failed = YES; [self updateEmpty:error];
            if (!self->_feed.works.empty()) [self notice:error];
            return;
        }
        std::vector<Work> works;
        for (NSDictionary *value in Array(result[@"items"])) works.emplace_back(ReadWork(value));
        std::size_t added = self->_feed.append(std::move(works), [result[@"more"] boolValue], replace);
        self->_emptyPages = added ? 0 : self->_emptyPages + 1;
        if (self->_emptyPages >= 3) self->_feed.more = false;
        [self->_collection reloadData];
        if (replace && !self->_feed.works.empty()) [self->_collection setContentOffset:CGPointZero animated:NO];
        [self updateEmpty:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ [self activate]; });
        if (self->_feed.works.empty() && self->_feed.more) [self loadFeed:NO];
        if (replace) [self loadProfile];
    }];
}
- (void)loadProfile {
    __weak DGFeed *weakSelf = self; NSUInteger generation = _requestGeneration;
    [_bridge request:@"profile" parameters:@{} completion:^(NSDictionary *result, NSString *error) {
        DGFeed *self = weakSelf; if (!self || generation != self->_requestGeneration) return;
        self->_loggedIn = !error && [result[@"loggedIn"] boolValue];
        self->_nickname = self->_loggedIn ? result[@"nickname"] : nil;
        NSString *symbol = self->_loggedIn ? @"person.crop.circle.badge.checkmark" : @"person.crop.circle";
        [self->_account setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    }];
}
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { return _feed.works.size(); }
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath { return collectionView.bounds.size; }
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    DGFeedCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"work" forIndexPath:indexPath];
    const Work &work = _feed.works[indexPath.item]; [cell display:work];
    NSString *workID = Text(work.id); __weak DGFeed *weakSelf = self;
    cell.commentsAction = ^{
        DGFeed *self = weakSelf; if (!self) return;
        for (DGFeedCell *visible in self->_collection.visibleCells) [visible active:NO];
        DGComments *comments = [[DGComments alloc] initWithBridge:self->_bridge work:workID parent:nil];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:comments];
        navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.mediumDetent,UISheetPresentationControllerDetent.largeDetent];
        navigation.sheetPresentationController.prefersGrabberVisible = YES;
        navigation.sheetPresentationController.preferredCornerRadius = 30;
        [self presentViewController:navigation animated:YES completion:^{ navigation.presentationController.delegate = self; }];
    };
    return cell;
}
- (void)activate {
    CGFloat height = _collection.bounds.size.height; if (height <= 0) return;
    NSInteger index = MAX(0, (NSInteger)llround(_collection.contentOffset.y / height));
    BOOL allowed = _foreground && self.presentedViewController == nil;
    for (DGFeedCell *cell in _collection.visibleCells) [cell active:allowed && [_collection indexPathForCell:cell].item == index];
    if (!_failed && !_loading && _feed.more && !_feed.works.empty() && index + 4 >= (NSInteger)_feed.works.size()) [self loadFeed:NO];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView { [self activate]; }
- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath { [(DGFeedCell *)cell active:NO]; }
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController { [self activate]; }
- (void)notice:(NSString *)message {
    _recommend.text = @"点刷新重试";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ self->_recommend.text = @"推荐"; });
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
}
- (void)account {
    if (!_loggedIn) { [self openLogin]; return; }
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:_nickname ?: @"已登录" message:@"账号登录信息保存在本机" preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"打开登录网页 / 安全验证" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self openLogin]; }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"退出登录" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self->_bridge signOut:^{ [self sessionChanged:NO]; }];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = _account; menu.popoverPresentationController.sourceRect = _account.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)openLogin {
    if (self.presentedViewController) return;
    for (DGFeedCell *cell in _collection.visibleCells) [cell active:NO];
    DGLogin *login = [DGLogin new]; __weak DGFeed *weakSelf = self;
    login.finished = ^{ [weakSelf sessionChanged:YES]; };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:login];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
}
- (void)sessionChanged:(BOOL)reload {
    ++_requestGeneration; _loading = NO; _failed = NO; _loggedIn = NO; _nickname = nil;
    for (DGFeedCell *cell in _collection.visibleCells) [cell active:NO];
    _feed.clear(); [_collection reloadData]; _refreshIndex = 1; _emptyPages = 0;
    if (reload) [_bridge reload]; [self loadFeed:YES];
}
@end

UIViewController *DGMakeFeedController(void) { return [DGFeed new]; }
