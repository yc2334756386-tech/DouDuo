#import "DGDanmaku.h"
#import <QuartzCore/QuartzCore.h>
#include <algorithm>
#include <cmath>

static UIColor *DGCharcoalInk(CGFloat lineHeight){
 static NSCache<NSNumber *,UIColor *> *cache;static dispatch_once_t once;dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=32;});NSNumber *key=@(ceil(lineHeight+8));UIColor *ink=[cache objectForKey:key];if(ink)return ink;
 UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;format.opaque=YES;CGSize size=CGSizeMake(1,key.doubleValue);
 UIImage *image=[[[UIGraphicsImageRenderer alloc]initWithSize:size format:format]imageWithActions:^(UIGraphicsImageRendererContext *renderer){CGContextRef context=renderer.CGContext;CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();CGFloat colors[]={.14,.15,.17,1,.10,.11,.13,1,.12,.13,.15,1},stops[]={0,.48,1};CGGradientRef gradient=CGGradientCreateWithColorComponents(space,colors,stops,3);CGContextDrawLinearGradient(context,gradient,CGPointZero,CGPointMake(0,size.height),0);CGGradientRelease(gradient);CGColorSpaceRelease(space);}];
 ink=[UIColor colorWithPatternImage:image];[cache setObject:ink forKey:key];return ink;
}
static CGImageRef DGGroupMask(NSData *bytes,size_t width){
 CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)bytes);CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
 CGImageRef image=CGImageCreate(width,1,8,32,width*4,space,kCGBitmapByteOrder32Big|kCGImageAlphaPremultipliedLast,provider,NULL,NO,kCGRenderingIntentDefault);
 CGColorSpaceRelease(space);CGDataProviderRelease(provider);return image;
}
@implementation DGDanmakuLabel{
 BOOL _adaptive,_eligible;UILabel *_white,*_black;CALayer *_whiteMask,*_blackMask;
 douglass::GroupedInk _ink;CGSize _inkLayoutSize;CGFloat _inkTop,_inkHeight;
}
- (BOOL)adaptiveEligible{
 NSString *text=self.attributedText.string?:self.plain;NSUInteger count=0;
 for(NSUInteger i=0;i<text.length;){NSRange range=[text rangeOfComposedCharacterSequenceAtIndex:i];i=NSMaxRange(range);if([[text substringWithRange:range]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length&&++count>=2)return YES;}return NO;
}
- (void)drawTextInRect:(CGRect)rect{if(!_adaptive||!_eligible)[super drawTextInRect:rect];}
- (void)adaptive:(BOOL)enabled{if(_adaptive==enabled)return;_adaptive=enabled;[self refreshAppearance];}
- (void)refreshAppearance{
 _eligible=[self adaptiveEligible];id shadow=[NSUserDefaults.standardUserDefaults objectForKey:@"douglass.danmaku.shadow"];BOOL shadows=!shadow||[shadow boolValue];
 if(!_adaptive||!_eligible){[_white removeFromSuperview];[_black removeFromSuperview];_white=nil;_black=nil;_whiteMask=nil;_blackMask=nil;self.layer.shadowOpacity=shadows?.85:0;[self setNeedsDisplay];return;}
 if(!_white){_white=[UILabel new];_black=[UILabel new];_whiteMask=[CALayer layer];_blackMask=[CALayer layer];[self addSubview:_white];[self addSubview:_black];}
 NSArray<UILabel *> *copies=@[_white,_black];NSArray<UIColor *> *ink=@[[UIColor colorWithWhite:.98 alpha:1],DGCharcoalInk(self.font.lineHeight)];
 for(NSUInteger index=0;index<2;++index){UILabel *copy=copies[index];NSMutableAttributedString *text=[self.attributedText mutableCopy];if(text.length)[text addAttribute:NSForegroundColorAttributeName value:ink[index] range:NSMakeRange(0,text.length)];if(index==1&&text.length)[text addAttributes:@{NSStrokeColorAttributeName:[UIColor colorWithWhite:1 alpha:.25],NSStrokeWidthAttributeName:@(-.75)} range:NSMakeRange(0,text.length)];copy.font=self.font;copy.numberOfLines=self.numberOfLines;copy.lineBreakMode=self.lineBreakMode;copy.textAlignment=self.textAlignment;copy.attributedText=text;copy.textColor=ink[index];copy.layer.shadowColor=UIColor.blackColor.CGColor;copy.layer.shadowOpacity=index==0&&shadows?.85:0;copy.layer.shadowRadius=index==0?2:0;copy.layer.shadowOffset=index==0?CGSizeMake(0,1):CGSizeZero;copy.layer.zPosition=index==1?2:1;copy.userInteractionEnabled=NO;}
 self.layer.shadowOpacity=0;[self rebuildInkGroups];[self setNeedsDisplay];[self setNeedsLayout];
}
- (void)rebuildInkGroups{
 _inkLayoutSize=self.bounds.size;if(!_adaptive||!_eligible)return;
 NSAttributedString *text=self.attributedText;std::vector<douglass::InkGlyph> glyphs;
 CGRect rect=[self textRectForBounds:self.bounds limitedToNumberOfLines:1];
 // A suppressed UILabel may report an empty draw rect before its sublabels have
 // laid out. Sampling still needs the actual lane and font height.
 _inkHeight=MIN(self.font.lineHeight,self.bounds.size.height);
 _inkTop=MAX(0,(self.bounds.size.height-_inkHeight)/2);
 if(text.length){NSTextStorage *storage=[[NSTextStorage alloc]initWithAttributedString:text];NSLayoutManager *layout=[NSLayoutManager new];[storage addLayoutManager:layout];NSTextContainer *container=[[NSTextContainer alloc]initWithSize:CGSizeMake(MAX(4096,self.bounds.size.width),CGFLOAT_MAX)];container.lineFragmentPadding=0;container.maximumNumberOfLines=1;[layout addTextContainer:container];[layout ensureLayoutForTextContainer:container];NSString *string=text.string;
  // TextKit includes NSTextAttachment advances used by custom emoticons.
  for(NSUInteger i=0;i<string.length;){NSRange range=[string rangeOfComposedCharacterSequenceAtIndex:i];i=NSMaxRange(range);if(![[string substringWithRange:range]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)continue;NSRange glyphRange=[layout glyphRangeForCharacterRange:range actualCharacterRange:NULL];CGRect glyph=[layout boundingRectForGlyphRange:glyphRange inTextContainer:container];if(std::isfinite(glyph.origin.x)&&std::isfinite(glyph.size.width)&&glyph.size.width>.25)glyphs.push_back({MAX(0,rect.origin.x)+glyph.origin.x,glyph.size.width});}
 }
 _ink.setGlyphs(std::move(glyphs));[self renderGroupMasks:NO];
}
- (void)renderGroupMasks:(BOOL)animated{
 if(!_white||self.bounds.size.width<=0)return;size_t width=MIN(4096,MAX(1,(size_t)ceil(self.bounds.size.width)));
 NSMutableData *white=[NSMutableData dataWithLength:width*4],*black=[NSMutableData dataWithLength:width*4];_ink.masks(width,(uint8_t *)white.mutableBytes,(uint8_t *)black.mutableBytes);
 CGImageRef images[]={DGGroupMask(white,width),DGGroupMask(black,width)};NSArray<CALayer *> *layers=@[_whiteMask,_blackMask];
 [CATransaction begin];[CATransaction setDisableActions:YES];
 for(NSUInteger i=0;i<2;++i){CALayer *layer=layers[i];id previous=layer.contents;layer.frame=self.bounds;layer.magnificationFilter=kCAFilterNearest;layer.minificationFilter=kCAFilterNearest;layer.contents=(__bridge id)images[i];if(animated&&previous&&images[i]){CABasicAnimation *fade=[CABasicAnimation animationWithKeyPath:@"contents"];fade.fromValue=previous;fade.toValue=(__bridge id)images[i];fade.duration=.14;fade.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];[layer addAnimation:fade forKey:@"contrast-fade"];}else [layer removeAnimationForKey:@"contrast-fade"];if(images[i])CGImageRelease(images[i]);}
 _white.layer.mask=_whiteMask;_black.layer.mask=_blackMask;[CATransaction commit];
}
- (void)layoutSubviews{[super layoutSubviews];_white.frame=self.bounds;_black.frame=self.bounds;if(!CGSizeEqualToSize(_inkLayoutSize,self.bounds.size))[self rebuildInkGroups];}
- (void)resetContrast{[self rebuildInkGroups];}
- (void)contrastFrame:(const std::shared_ptr<const douglass::ContrastFrame> &)sample inFrame:(CGRect)frame overlaySize:(CGSize)size{
 if(!_adaptive||!_eligible||!sample)return;
 if(_ink.update(*sample,{frame.origin.x,frame.origin.y+_inkTop,self.bounds.size.width,_inkHeight},size.width,size.height))[self renderGroupMasks:YES];
}
@end

@implementation DGDanmakuOverlay{
 BOOL _adaptive,_playing,_sampling,_tearingDown;std::shared_ptr<const douglass::ContrastFrame> _contrastFrame;
}
- (NSString *)textAtPoint:(CGPoint)point{
 if(!CGRectContainsPoint(self.bounds,point))return nil;
 for(DGDanmakuLabel *label in self.subviews.reverseObjectEnumerator){CALayer *layer=label.layer.presentationLayer?:label.layer;if(CGRectContainsPoint(CGRectInset(layer.frame,-6,-5),point))return label.plain;}return nil;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event{if(self.hidden||self.alpha<.01||!self.userInteractionEnabled)return nil;return [self textAtPoint:point].length?self:nil;}
- (void)adaptive:(BOOL)enabled playing:(BOOL)playing{
 BOOL changed=_adaptive!=enabled;_adaptive=enabled;_playing=playing;
 if(changed){for(DGDanmakuLabel *label in self.subviews)[label adaptive:enabled];if(!enabled)_contrastFrame.reset();}
 [self updateSampling];
}
- (void)contrastFrame:(std::shared_ptr<const douglass::ContrastFrame>)sample{
 if(!_adaptive)return;_contrastFrame=std::move(sample);
 for(DGDanmakuLabel *label in self.subviews){if(!_contrastFrame){[label resetContrast];continue;}CALayer *layer=label.layer.presentationLayer?:label.layer;[label contrastFrame:_contrastFrame inFrame:layer.frame overlaySize:self.bounds.size];}
}
- (void)updateSampling{
 if(_tearingDown)return;BOOL run=_adaptive&&_playing&&self.window&&!self.hidden&&self.alpha>.01&&self.subviews.count>0;
 if(_sampling!=run){_sampling=run;if(self.samplingChanged)self.samplingChanged(run);}
}
- (void)didAddSubview:(UIView *)subview{[super didAddSubview:subview];if([subview isKindOfClass:DGDanmakuLabel.class]){DGDanmakuLabel *label=(DGDanmakuLabel *)subview;[label adaptive:_adaptive];if(_contrastFrame)[label contrastFrame:_contrastFrame inFrame:label.frame overlaySize:self.bounds.size];}[self updateSampling];}
- (void)willRemoveSubview:(UIView *)subview{
 [super willRemoveSubview:subview];if(_tearingDown)return;
 // UIView invokes this during destruction too: no new weak reference or work.
 if(self.subviews.count<=1&&_sampling){_sampling=NO;if(self.samplingChanged)self.samplingChanged(NO);}
}
- (void)didMoveToWindow{[super didMoveToWindow];[self updateSampling];}
- (void)setHidden:(BOOL)hidden{[super setHidden:hidden];[self updateSampling];}
- (void)dealloc{_tearingDown=YES;_samplingChanged=nil;}
@end
