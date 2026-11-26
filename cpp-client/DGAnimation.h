#pragma once
#import "DGCommon.h"
NSTimeInterval DGDuration(NSTimeInterval base);
CAMediaTimingFunction *DGTiming(void);
UIViewPropertyAnimator *DGAnimate(NSTimeInterval duration, void (^changes)(void), void (^done)(BOOL));
UIViewController *DGMakeAnimationSettings(void);
void DGRefreshRateApply(void);
