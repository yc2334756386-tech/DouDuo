#import "DGDanmaku.h"
#import "DGAnimation.h"
#import <QuartzCore/QuartzCore.h>
@implementation DGDanmakuLabel{
 BOOL _adaptive;UILabel *_white,*_black;CALayer *_whiteMask,*_blackMask;
}
- (void)drawTextInRect:(CGRect)rect{if(!_adaptive)[super drawTextInRect:rect];}
- (void)adaptive:(BOOL)enabled{if(_adaptive==enabled)return;_adaptive=enabled;[self refreshAppearance];}
- (void)refreshAppearance{
 id shadow=[NSUserDefaults.standardUserDefaults objectForKey:@"douglass.danmaku.shadow"];BOOL shadows=!shadow||[shadow boolValue];
 if(!_adaptive){[_white removeFromSuperview];[_black removeFromSuperview];_white=nil;_black=nil;_whiteMask=nil;_blackMask=nil;self.layer.shadowOpacity=shadows?.85:0;[self setNeedsDisplay];return;}
 if(!_white){_white=[UILabel new];_black=[UILabel new];_whiteMask=[CALayer layer];_blackMask=[CALayer layer];[self addSubview:_white];[self addSubview:_black];}
 NSArray<UILabel *> *copies=@[_white,_black];NSArray<UIColor *> *ink=@[UIColor.whiteColor,UIColor.blackColor],*shade=@[UIColor.blackColor,UIColor.whiteColor];
 for(NSUInteger index=0;index<2;++index){UILabel *copy=copies[index];NSMutableAttributedString *text=[self.attributedText mutableCopy];if(text.length)[text addAttribute:NSForegroundColorAttributeName value:ink[index] range:NSMakeRange(0,text.length)];copy.font=self.font;copy.numberOfLines=self.numberOfLines;copy.lineBreakMode=self.lineBreakMode;copy.textAlignment=self.textAlignment;copy.attributedText=text;copy.textColor=ink[index];copy.layer.shadowColor=shade[index].CGColor;copy.layer.shadowOpacity=index==0&&shadows?.85:0;copy.layer.shadowRadius=2;copy.layer.shadowOffset=CGSizeMake(0,1);copy.userInteractionEnabled=NO;}
 self.layer.shadowOpacity=0;[self setNeedsDisplay];[self setNeedsLayout];
}
- (void)layoutSubviews{[super layoutSubviews];_white.frame=self.bounds;_black.frame=self.bounds;}
- (void)whiteMask:(UIImage *)white blackMask:(UIImage *)black{
 if(!_adaptive)return;
 NSArray<CALayer *> *layers=@[_whiteMask,_blackMask];NSArray *images=@[white?(id)white.CGImage:NSNull.null,black?(id)black.CGImage:NSNull.null];
 for(NSUInteger index=0;index<2;++index){CALayer *layer=layers[index];id next=images[index]==NSNull.null?nil:images[index],previous=layer.contents;layer.contents=next;if(previous&&next&&previous!=next){CABasicAnimation *fade=[CABasicAnimation animationWithKeyPath:@"contents"];fade.fromValue=previous;fade.toValue=next;fade.duration=1./12;fade.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];[layer addAnimation:fade forKey:@"contrast-fade"];}else [layer removeAnimationForKey:@"contrast-fade"];}
 _white.layer.mask=white?_whiteMask:nil;_black.layer.mask=black?_blackMask:nil;_black.hidden=!black;
}
- (void)alignMask:(CGRect)frame overlaySize:(CGSize)size{
 if(!_adaptive)return;CGRect region=CGRectMake(-frame.origin.x,-frame.origin.y,size.width,size.height);_whiteMask.frame=region;_blackMask.frame=region;
}
@end
@interface DGDanmakuClock:NSObject
@property(nonatomic,weak) DGDanmakuOverlay *overlay;
- (void)tick:(CADisplayLink *)link;
@end
@interface DGDanmakuOverlay()
- (void)alignMasks;
@end
@implementation DGDanmakuClock
- (void)tick:(CADisplayLink *)link{DGDanmakuOverlay *overlay=_overlay;if(overlay)[overlay alignMasks];else [link invalidate];}
@end
@implementation DGDanmakuOverlay{
 BOOL _adaptive,_playing,_sampling;CADisplayLink *_clock;UIImage *_whiteMask,*_blackMask;
}
- (instancetype)initWithFrame:(CGRect)frame{if((self=[super initWithFrame:frame]))[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshRateChanged) name:@"DGRefreshRateChanged" object:nil];return self;}
- (void)refreshRateChanged{DGApplyDisplayLinkRate(_clock,self);}
- (NSString *)textAtPoint:(CGPoint)point{
 if(!CGRectContainsPoint(self.bounds,point))return nil;
 for(DGDanmakuLabel *label in self.subviews.reverseObjectEnumerator){CALayer *layer=label.layer.presentationLayer?:label.layer;if(CGRectContainsPoint(CGRectInset(layer.frame,-6,-5),point))return label.plain;}return nil;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event{if(self.hidden||self.alpha<.01||!self.userInteractionEnabled)return nil;return [self textAtPoint:point].length?self:nil;}
- (void)adaptive:(BOOL)enabled playing:(BOOL)playing{
 BOOL changed=_adaptive!=enabled;_adaptive=enabled;_playing=playing;
 if(changed){for(DGDanmakuLabel *label in self.subviews){[label adaptive:enabled];[label whiteMask:_whiteMask blackMask:_blackMask];}if(!enabled){_whiteMask=nil;_blackMask=nil;}}
 [self updateClock];
}
- (void)whiteMask:(UIImage *)white blackMask:(UIImage *)black{
 if(!_adaptive)return;_whiteMask=white;_blackMask=black;
 [CATransaction begin];[CATransaction setDisableActions:YES];for(DGDanmakuLabel *label in self.subviews)[label whiteMask:white blackMask:black];[self alignMasks];[CATransaction commit];
}
- (void)alignMasks{
 [CATransaction begin];[CATransaction setDisableActions:YES];for(DGDanmakuLabel *label in self.subviews){CALayer *layer=label.layer.presentationLayer?:label.layer;[label alignMask:layer.frame overlaySize:self.bounds.size];}[CATransaction commit];
}
- (void)updateClock{
 BOOL run=_adaptive&&_playing&&self.window&&!self.hidden&&self.alpha>.01&&self.subviews.count>0;
 if(run&&!_clock){DGDanmakuClock *target=[DGDanmakuClock new];target.overlay=self;_clock=[CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];DGApplyDisplayLinkRate(_clock,self);[_clock addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];}
 else if(!run&&_clock){[_clock invalidate];_clock=nil;[self alignMasks];}
 if(_sampling!=run){_sampling=run;if(self.samplingChanged)self.samplingChanged(run);}
}
- (void)didAddSubview:(UIView *)subview{[super didAddSubview:subview];if([subview isKindOfClass:DGDanmakuLabel.class]){DGDanmakuLabel *label=(DGDanmakuLabel *)subview;[label adaptive:_adaptive];[label whiteMask:_whiteMask blackMask:_blackMask];}[self updateClock];}
- (void)willRemoveSubview:(UIView *)subview{[super willRemoveSubview:subview];__weak DGDanmakuOverlay *weak=self;dispatch_async(dispatch_get_main_queue(),^{[weak updateClock];});}
- (void)didMoveToWindow{[super didMoveToWindow];[self updateClock];}
- (void)setHidden:(BOOL)hidden{[super setHidden:hidden];[self updateClock];}
- (void)layoutSubviews{[super layoutSubviews];[self alignMasks];}
- (void)dealloc{[_clock invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
