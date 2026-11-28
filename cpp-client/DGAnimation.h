#pragma once
#import "DGCommon.h"
NSTimeInterval DGDuration(NSTimeInterval base);
CAMediaTimingFunction *DGTiming(void);
UIViewPropertyAnimator *DGAnimate(NSTimeInterval duration, void (^changes)(void), void (^done)(BOOL));
UIViewController *DGMakeAnimationSettings(void);
void DGRefreshRateApply(void);

void DGRefreshRateSuspend(void);
void DGApplyDisplayLinkRate(CADisplayLink *link,UIView *view);
NSString *DGRefreshRateStatus(void);
// UI-thread scheduling: native transitions keep their normal appearance/timing.
uint64_t DGBeginAnimationPriority(NSTimeInterval duration);
void DGEndAnimationPriority(uint64_t token);
BOOL DGAnimationPriorityActive(void);
void DGAfterAnimations(dispatch_block_t action);
