#pragma once
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <Photos/Photos.h>
#import <QuickLook/QuickLook.h>
#import "DGBridge.h"
#import "DGSession.h"
#include "Core.hpp"
#include <algorithm>
#include <cmath>
#include <utility>
using douglass::Work;
using douglass::Comment;
static inline NSString *Text(const std::string &value) { return [NSString stringWithUTF8String:value.c_str()] ?: @""; }
static inline std::string String(id value) {
    if (!value || value == NSNull.null) return {};
    NSString *text = [value isKindOfClass:NSString.class] ? value : [value description];
    return text.UTF8String ?: "";
}
static inline long long Number(id value) { return [value respondsToSelector:@selector(longLongValue)] ? [value longLongValue] : 0; }
static inline NSArray *Array(id value) { return [value isKindOfClass:NSArray.class] ? value : @[]; }
static inline Work ReadWork(NSDictionary *value) {
    Work work;
    work.id = String(value[@"id"]); work.contentKey=String(value[@"contentKey"]); work.caption = String(value[@"caption"]);
    work.author = String(value[@"author"]); work.avatar = String(value[@"avatar"]);
    work.cover = String(value[@"cover"]); work.play = String(value[@"play"]);
    work.alternate = String(value[@"alternate"]); work.music = String(value[@"music"]);
    BOOL quality=[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.quality"],smooth=[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.highFPS"];
    NSDictionary *variants=[value[@"variants"]isKindOfClass:NSDictionary.class]?value[@"variants"]:@{};id selected=variants[quality&&smooth?@"qualityFPS":quality?@"quality":smooth?@"smooth":@""];
    if([selected isKindOfClass:NSDictionary.class]&&String(selected[@"play"]).size()){work.play=String(selected[@"play"]);work.alternate=String(selected[@"alternate"]);}
    work.comments = Number(value[@"comments"]); work.likes = Number(value[@"likes"]);
    work.duration = [value[@"duration"] doubleValue];
work.authorID=String(value[@"authorID"]);work.authorUID=String(value[@"authorUID"]);
work.musicID=String(value[@"musicID"]);work.musicTitle=String(value[@"musicTitle"]);work.musicAuthor=String(value[@"musicAuthor"]);
work.location=String(value[@"location"]);work.locationKind=String(value[@"locationKind"]);
work.publishedAt=Number(value[@"publishedAt"]);work.collects=Number(value[@"collects"]);
work.liked=[value[@"liked"] boolValue];work.collected=[value[@"collected"] boolValue];
work.isAd=[value[@"isAd"]boolValue];work.isLive=[value[@"isLive"]boolValue];
    for (id image in Array(value[@"images"])) work.images.emplace_back(String(image));
    return work;
}
static inline Comment ReadComment(NSDictionary *value) {
    Comment comment;
    comment.id = String(value[@"id"]); comment.text = String(value[@"text"]);
    comment.author = String(value[@"author"]); comment.avatar = String(value[@"avatar"]);
    comment.location = String(value[@"location"]); comment.authorID=String(value[@"authorID"]); comment.sticker=String(value[@"sticker"]); comment.likes = Number(value[@"likes"]);
    comment.replies = Number(value[@"replies"]); comment.timestamp = Number(value[@"timestamp"]);
    comment.liked=[value[@"liked"]boolValue];
    for (id image in Array(value[@"images"])) comment.images.emplace_back(String(image));
    for (NSDictionary *emoji in Array(value[@"emoticons"])) comment.emoticons.emplace_back(String(emoji[@"name"]),String(emoji[@"url"]));
    return comment;
}
static inline UILabel *Label(CGFloat size, UIFontWeight weight) {
    UILabel *label = [UILabel new];
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = UIColor.labelColor;
    return label;
}
static inline UIButton *Symbol(NSString *name, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    button.tintColor = UIColor.labelColor;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
static inline UIVisualEffectView *Glass(CGFloat radius) {
    UIVisualEffect *effect;
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *glass = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        glass.interactive = YES;
        effect = glass;
    } else effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    UIVisualEffectView *view = [[UIVisualEffectView alloc] initWithEffect:effect];
    view.layer.cornerRadius = radius;
    view.clipsToBounds = YES;
    return view;
}
static inline AVURLAsset *Asset(NSString *url) {
    NSURL *address=[NSURL URLWithString:url];if(address.fileURL)return [AVURLAsset URLAssetWithURL:address options:nil];
    return [AVURLAsset URLAssetWithURL:address options:@{@"AVURLAssetHTTPHeaderFieldsKey":@{@"User-Agent":DGUserAgent(),@"Referer":@"https://www.douyin.com/"}}];
}


@interface DGImage : UIImageView
@property(nonatomic) NSUInteger maximumPixelSize;
- (void)remote:(NSString *)url;
+ (void)purgeCache;
@end
@interface DGNavigationController:UINavigationController
@end
void DGConfigurePageTransition(UIViewController *controller);
double DGHoldSpeed(void);
NSAttributedString *DGRichText(NSString *plain, NSArray *emoticons, UIFont *font, UIColor *color);
void DGShowFullCaption(UIViewController *host, NSString *text);
void DGMusicPlayQueue(NSArray<NSDictionary *> *music, NSInteger index, DGBridge *bridge, NSString *cursor, BOOL more);
@interface DGLogin : UIViewController <WKNavigationDelegate,WKUIDelegate>
@property(nonatomic,copy) void (^finished)(void);
@end
void DGToast(UIViewController *host, NSString *message);
void DGHaptic(void);
void DGSaveURL(UIViewController *host, NSString *url, BOOL video);
void DGSaveAudioDirect(UIViewController *host,NSString *url,NSString *name);
void DGSaveAudio(UIViewController *host, NSString *url, NSString *name);
void DGConfirmCopy(UIViewController *host, NSString *text);
void DGConfirmTextCopy(UIViewController *host, NSString *text, NSString *title, NSString *success);
void DGConfirmImageSave(UIViewController *host, NSString *url);
void DGConfirmAvatarSave(UIViewController *host, NSString *url);
UIViewController *DGMakeSearchPage(NSString *keyword, BOOL users, void (^imported)(NSArray<NSDictionary *> *items));
UIViewController *DGMakeMusicWebPage(NSString *identifier, void (^imported)(NSArray<NSDictionary *> *items));
UIViewController *DGMakeOptions(DGBridge *bridge, NSDictionary *work);
UIViewController *DGMakeActions(DGBridge *bridge, NSDictionary *work);
BOOL DGOptionsKeepsPlayback(UIViewController *controller);
void DGOptimisticAction(DGBridge *bridge, UIViewController *presenter, NSDictionary *snapshot, NSString *kind, BOOL add);
void DGResetInteractions(void);
void DGResetMusicPages(void);
BOOL DGContentAllowed(const Work &work);
void DGSeenScope(NSString *uid);
void DGMusicPlay(NSDictionary *music);
void DGMusicPause(void);
void DGMusicStop(void);
void DGMusicSetOwner(UIViewController *owner);
void DGMusicStopOwned(UIViewController *owner);
AVPlayer *DGMusicPlayer(void);
BOOL DGMusicMatches(NSString *identifier);
NSString *DGCurrentMusicID(void);
void DGShowImage(UIViewController *host, NSString *url, UIImageView *source);
UIViewController *DGMakeFeedController(void);
UIViewController *DGMakeWorkPlayer(NSArray<NSDictionary *> *works, NSInteger selected, DGBridge *bridge);
UIViewController *DGMakeProfile(DGBridge *bridge, NSString *sec, NSString *name, NSString *locate);
UIViewController *DGMakeSearch(DGBridge *bridge);
UIViewController *DGMakeMusic(DGBridge *bridge, NSDictionary *music);
UIViewController *DGMakeMessages(DGBridge *bridge);
UIViewController *DGMakeNotices(DGBridge *bridge);

UIViewController *DGMakeEmbeddedMessages(DGBridge *bridge,void (^navigate)(UIViewController *));
UIViewController *DGMakeNoticesGroup(DGBridge *bridge,NSInteger group);


void DGRefreshEmbeddedMessages(UIViewController *page);


void DGSetEmbeddedMessagesVisible(UIViewController *page,BOOL visible);

NSArray *DGNormalizeWebItems(id items);

UIViewController *DGMakeNoticePlayer(NSArray<NSDictionary *> *works,DGBridge *bridge,NSString *commentID,NSString *parentID);
