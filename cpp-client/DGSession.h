#pragma once
#import <WebKit/WebKit.h>
void DGSessionConfigure(WKWebViewConfiguration *configuration);
void DGSessionPrepare(WKWebView *web, BOOL blockMedia, void (^completion)(void));
void DGSessionCapture(void (^completion)(void));
void DGSessionRestore(void (^completion)(void));
BOOL DGSessionMayBeSignedIn(void);
void DGSessionForget(void);
BOOL DGBackgroundAudioEnabled(void);

