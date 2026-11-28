#pragma once
#import <AVFoundation/AVFoundation.h>

@interface DGMetalFXPlayback : NSObject
- (void)showForPlayerLayer:(AVPlayerLayer *)layer;
- (void)stop;
- (void)resetFrame;
- (void)layout;
@end
