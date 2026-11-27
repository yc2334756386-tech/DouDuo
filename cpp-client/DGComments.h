#pragma once
#import "DGCommon.h"
// Fixed-height child panel. The owner supplies its frame and close action;
// opening comments does not alter playback or introduce sheet detents.
@interface DGComments : UIViewController
@property(nonatomic,copy) NSString *coverURL;
@property(nonatomic,copy) void (^closeAction)(void);
@property(nonatomic,copy) void (^profileAction)(NSString *sec,NSString *name);
@property(nonatomic,copy) void (^dragAction)(CGFloat offset, NSInteger phase);
- (instancetype)initWithBridge:(DGBridge *)bridge work:(NSString *)work parent:(NSString *)parent;
- (void)focusComment:(NSString *)identifier parent:(NSString *)parent;
- (void)rememberPosition;
- (void)restorePosition;
@end
