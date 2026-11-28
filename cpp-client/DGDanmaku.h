#pragma once
#import <UIKit/UIKit.h>
#include "ContrastMap.hpp"
@interface DGDanmakuLabel:UILabel
@property(nonatomic) CFTimeInterval born;
@property(nonatomic,copy) NSString *plain;
@property(nonatomic,strong) NSArray *emoticons;
- (void)adaptive:(BOOL)enabled;
- (void)refreshAppearance;
- (void)resetContrast;
- (void)contrastFrame:(const std::shared_ptr<const douglass::ContrastFrame> &)sample inFrame:(CGRect)frame overlaySize:(CGSize)size;
@end
@interface DGDanmakuOverlay:UIView
@property(nonatomic,copy) void (^samplingChanged)(BOOL enabled);
- (NSString *)textAtPoint:(CGPoint)point;
- (void)adaptive:(BOOL)enabled playing:(BOOL)playing;
- (void)contrastFrame:(std::shared_ptr<const douglass::ContrastFrame>)sample;
@end
