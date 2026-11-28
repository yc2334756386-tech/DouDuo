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
void DGConfigureWorkTransition(UIViewController *player,UIView *(^source)(void));
