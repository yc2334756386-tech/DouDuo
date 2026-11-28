#pragma once
#import "DGCommon.h"
@interface DGPhotoNavigator:UIControl
@property(nonatomic,copy) void (^onSelect)(NSInteger index);
@property(nonatomic,copy) void (^onBrowsingChanged)(BOOL browsing);
@property(nonatomic,readonly) BOOL browsing;
- (void)images:(NSArray<NSString *> *)urls;
- (void)page:(NSInteger)index;
- (void)cancelBrowsing;
@end
