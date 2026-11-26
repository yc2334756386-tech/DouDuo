#pragma once
#import "DGCommon.h"
// Fixed-height child panel. The owner supplies its frame and close action;
// opening comments does not alter playback or introduce sheet detents.
@interface DGComments : UIViewController
@property(nonatomic,copy) NSString *coverURL;
@property(nonatomic,copy) void (^closeAction)(void);
@property(nonatomic,copy) void (^profileAction)(NSString *sec,NSString *name);
- (instancetype)initWithBridge:(DGBridge *)bridge work:(NSString *)work parent:(NSString *)parent;
@end
