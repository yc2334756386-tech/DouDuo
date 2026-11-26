#pragma once
#import "DGCommon.h"
@interface DGInlineComposer : UIViewController
@property(nonatomic,strong) DGBridge *bridge;
@property(nonatomic,copy) NSString *work;
@property(nonatomic,copy) void (^sent)(NSDictionary *item,NSString *parent);
@property(nonatomic,copy) void (^heightChanged)(void);
@property(nonatomic,readonly) CGFloat inputHeight;
- (void)replyTo:(NSString *)parent reply:(NSString *)reply name:(NSString *)name;
@end
