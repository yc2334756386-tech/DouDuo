#pragma once
#import "DGCommon.h"
@interface DGFeedCell : UICollectionViewCell
@property(nonatomic,copy) void (^commentsAction)(void);
@property(nonatomic,copy) void (^profileAction)(void);
@property(nonatomic,copy) void (^musicAction)(void);
@property(nonatomic,copy) void (^moreAction)(void);
@property(nonatomic,copy) void (^actionMenuAction)(CGPoint point);
@property(nonatomic,copy) void (^dismissCommentsAction)(void);
@property(nonatomic,copy) BOOL (^advanceAction)(void);
@property(nonatomic,strong) DGBridge *bridge;
@property(nonatomic,weak) UIViewController *presenter;
- (void)display:(const Work &)work;
- (void)active:(BOOL)active;
- (void)compact:(BOOL)compact;
- (void)mediaHeight:(CGFloat)height;
- (void)interactiveMediaHeight:(CGFloat)height;
- (void)backgroundAudio:(BOOL)enabled;
- (NSString *)selectedImageURL;
@end
void DGWarmWorks(const std::vector<Work> &works, NSInteger index);
void DGClearPlayers(void);
