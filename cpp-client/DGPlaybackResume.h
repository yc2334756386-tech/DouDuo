#pragma once
#import <Foundation/Foundation.h>
NSDictionary *DGPlaybackResumeLoad(void);
BOOL DGPlaybackResumeSave(NSDictionary *record,NSString *channel,double seconds,BOOL paused);
void DGPlaybackResumeClearCheckpoint(void);
NSURL *DGPlaybackResumeLocalVideo(NSString *identifier);
