#pragma once
#import <Foundation/Foundation.h>
NSDictionary *DGPlaybackResumeTake(void);
void DGPlaybackResumeSave(NSDictionary *record,NSString *channel,double seconds,BOOL paused);
void DGPlaybackResumeClearCheckpoint(void);
void DGPlaybackResumeSelectWork(NSString *identifier);
NSURL *DGPlaybackResumeLocalVideo(NSString *identifier);
