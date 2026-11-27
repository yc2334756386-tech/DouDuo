#pragma once
#import <UIKit/UIKit.h>
@class DGBridge;
@protocol DGPageResume <NSObject>
- (NSDictionary *)dgResumeState;
@end
void DGSaveNavigationResume(UIWindow *window);
BOOL DGRestoreNavigationResume(UIViewController *root,DGBridge *bridge);
void DGClearNavigationResume(void);
UIViewController *DGMakeResumedExplore(DGBridge *bridge,NSDictionary *state);
UIViewController *DGMakeResumedWorkPlayer(DGBridge *bridge,NSDictionary *state);
