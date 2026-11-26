#pragma once
#import "DGBridge.h"
void DGOpenVerification(DGBridge *bridge, NSString *operation, NSDictionary *parameters);
void DGOpenVerificationPage(DGBridge *bridge, WKWebView *web, NSString *operation, NSDictionary *parameters);

