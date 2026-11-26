#pragma once
#import "DGCommon.h"
BOOL DGAirPodsConnected(void);
NSString *DGAudioOutputName(void);
void DGRepairPlayerAudio(AVPlayer *player);
NSDictionary *DGAudioSnapshot(void);
UIViewController *DGMakeEQSettings(void);
