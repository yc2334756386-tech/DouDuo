#pragma once
#import <UIKit/UIKit.h>
@interface DGDanmakuLabel:UILabel
@property(nonatomic) CFTimeInterval born;
@property(nonatomic,copy) NSString *plain;
@property(nonatomic,strong) NSArray *emoticons;
- (void)adaptive:(BOOL)enabled;
- (void)refreshAppearance;
- (void)whiteMask:(UIImage *)white blackMask:(UIImage *)black;
- (void)alignMask:(CGRect)frame overlaySize:(CGSize)size;
@end
@interface DGDanmakuOverlay:UIView
@property(nonatomic,copy) void (^samplingChanged)(BOOL enabled);
- (NSString *)textAtPoint:(CGPoint)point;
- (void)adaptive:(BOOL)enabled playing:(BOOL)playing;
- (void)whiteMask:(UIImage *)white blackMask:(UIImage *)black;
@end
