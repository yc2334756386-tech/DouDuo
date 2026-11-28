#pragma once
#import <AVFoundation/AVFoundation.h>
void DGUpdateAudioControls(void);
void DGPrepareAudioEnhancement(AVPlayerItem *item,dispatch_block_t completion);
void DGSealAudioEnhancement(AVPlayerItem *item);
BOOL DGRecoverAudioEnhancement(AVPlayer *player);
AVPlayer *DGMakeAudioPlayer(AVPlayerItem *item,void (^ready)(AVPlayer *player));
