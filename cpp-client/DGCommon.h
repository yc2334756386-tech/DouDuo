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
    work.id = String(value[@"id"]); work.caption = String(value[@"caption"]);
    work.author = String(value[@"author"]); work.avatar = String(value[@"avatar"]);
    work.cover = String(value[@"cover"]); work.play = String(value[@"play"]);
    work.alternate = String(value[@"alternate"]); work.music = String(value[@"music"]);
    work.comments = Number(value[@"comments"]); work.likes = Number(value[@"likes"]);
    work.duration = [value[@"duration"] doubleValue];
work.authorID=String(value[@"authorID"]);work.authorUID=String(value[@"authorUID"]);
work.musicID=String(value[@"musicID"]);work.musicTitle=String(value[@"musicTitle"]);work.musicAuthor=String(value[@"musicAuthor"]);
work.location=String(value[@"location"]);work.locationKind=String(value[@"locationKind"]);
work.publishedAt=Number(value[@"publishedAt"]);work.collects=Number(value[@"collects"]);
work.liked=[value[@"liked"] boolValue];work.collected=[value[@"collected"] boolValue];
    for (id image in Array(value[@"images"])) work.images.emplace_back(String(image));
    return work;
}
static inline Comment ReadComment(NSDictionary *value) {
    Comment comment;
    comment.id = String(value[@"id"]); comment.text = String(value[@"text"]);
    comment.author = String(value[@"author"]); comment.avatar = String(value[@"avatar"]);
    comment.location = String(value[@"location"]); comment.authorID=String(value[@"authorID"]); comment.sticker=String(value[@"sticker"]); comment.likes = Number(value[@"likes"]);
    comment.replies = Number(value[@"replies"]); comment.timestamp = Number(value[@"timestamp"]);
    for (id image in Array(value[@"images"])) comment.images.emplace_back(String(image));
    for (NSDictionary *emoji in Array(value[@"emoticons"])) comment.emoticons.emplace_back(String(emoji[@"name"]),String(emoji[@"url"]));
    return comment;
}
static inline UILabel *Label(CGFloat size, UIFontWeight weight) {
    UILabel *label = [UILabel new];
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = UIColor.whiteColor;
    return label;
}
static inline UIButton *Symbol(NSString *name, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightMedium]] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
static inline UIVisualEffectView *Glass(CGFloat radius) {
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
static inline AVURLAsset *Asset(NSString *url) {
    return [AVURLAsset URLAssetWithURL:[NSURL URLWithString:url] options:@{@"AVURLAssetHTTPHeaderFieldsKey":@{@"User-Agent":DGUserAgent(),@"Referer":@"https://www.douyin.com/"}}];
}


@interface DGImage : UIImageView
- (void)remote:(NSString *)url;
@end
@interface DGLogin : UIViewController <WKNavigationDelegate,WKUIDelegate>
@property(nonatomic,copy) void (^finished)(void);
@end
void DGToast(UIViewController *host, NSString *message);
void DGSaveURL(UIViewController *host, NSString *url, BOOL video);
void DGSaveAudio(UIViewController *host, NSString *url, NSString *name);
void DGConfirmCopy(UIViewController *host, NSString *text);
void DGShowImage(UIViewController *host, NSString *url, UIImageView *source);
UIViewController *DGMakeFeedController(void);
UIViewController *DGMakeWorkPlayer(NSArray<NSDictionary *> *works, NSInteger selected, DGBridge *bridge);
UIViewController *DGMakeProfile(DGBridge *bridge, NSString *sec, NSString *name, NSString *locate);
UIViewController *DGMakeSearch(DGBridge *bridge);
UIViewController *DGMakeMusic(DGBridge *bridge, NSDictionary *music);
UIViewController *DGMakeMessages(DGBridge *bridge);
