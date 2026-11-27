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
@property(nonatomic,copy) void (^viewedAction)(void);
@property(nonatomic,copy) void (^checkpointAction)(void);
@property(nonatomic,strong) DGBridge *bridge;
@property(nonatomic,weak) UIViewController *presenter;
- (void)display:(const Work &)work;
- (void)active:(BOOL)active;
- (void)compact:(BOOL)compact;
- (void)cleanScreen:(BOOL)clean;
- (void)mediaHeight:(CGFloat)height;
- (void)interactiveMediaHeight:(CGFloat)height;
- (void)enterBackgroundKeepingPlayback:(BOOL)keep audioOnly:(BOOL)audioOnly;
- (void)leaveBackground;
- (void)suspendForegroundWork;
- (NSString *)selectedImageURL;
- (void)releaseUnusedResources;
- (void)pagingInMotion:(BOOL)inMotion;
- (BOOL)hasRenderedMedia;
- (void)stagePreparedVideo;
- (double)currentPlaybackPosition;
- (BOOL)isPlaybackPaused;
- (void)restorePlaybackPosition:(double)seconds paused:(BOOL)paused;
@end
void DGWarmWorks(const std::vector<Work> &works, NSInteger index);
void DGClearPlayers(void);
void DGResetWorkPlayback(NSString *identifier);

void DGTrimPlayers(void);

BOOL DGAutomaticPiPAvailable(void);
