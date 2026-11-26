#pragma once
#import "DGCommon.h"
@interface DGSearchAssist:UIView
@property(nonatomic,copy) void (^selected)(NSString *keyword);
@property(nonatomic,copy) void (^fill)(NSString *keyword);
- (instancetype)initWithBridge:(DGBridge *)bridge;
- (void)keyword:(NSString *)keyword;
- (void)remember:(NSString *)keyword;
@end
