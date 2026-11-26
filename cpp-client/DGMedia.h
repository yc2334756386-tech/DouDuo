#pragma once
#import "DGCommon.h"
@interface DGFeedCell : UICollectionViewCell
@property(nonatomic,copy) void (^commentsAction)(void);
@property(nonatomic,copy) void (^profileAction)(void);
@property(nonatomic,copy) void (^musicAction)(void);
@property(nonatomic,copy) void (^moreAction)(void);
@property(nonatomic,strong) DGBridge *bridge;
@property(nonatomic,weak) UIViewController *presenter;
- (void)display:(const Work &)work;
- (void)active:(BOOL)active;
- (void)compact:(BOOL)compact;
@end
void DGWarmWorks(const std::vector<Work> &works, NSInteger index);
void DGClearPlayers(void);
