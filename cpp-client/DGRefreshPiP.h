#pragma once
#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSNotificationName const DGRefreshPiPStatusChanged;
void DGRefreshPiPApply(void);
void DGRefreshPiPPreferVideo(BOOL video);
NSString *DGRefreshPiPStatus(void);
