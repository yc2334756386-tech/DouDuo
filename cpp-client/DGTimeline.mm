#import "DGTimeline.h"
@implementation DGTimeline
- (CGRect)trackRectForBounds:(CGRect)bounds{return CGRectMake(0,(bounds.size.height-3)/2,bounds.size.width,3);}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event{return CGRectContainsPoint(CGRectInset(self.bounds,-8,-12),point);}
- (void)update:(UITouch *)touch{CGFloat x=[touch locationInView:self].x;self.value=self.minimumValue+(self.maximumValue-self.minimumValue)*MIN(1,MAX(0,x/MAX(1,self.bounds.size.width)));[self sendActionsForControlEvents:UIControlEventValueChanged];}
- (BOOL)beginTracking:(UITouch *)touch withEvent:(UIEvent *)event{[self update:touch];[self sendActionsForControlEvents:UIControlEventTouchDown];return YES;}
- (BOOL)continueTracking:(UITouch *)touch withEvent:(UIEvent *)event{[self update:touch];return YES;}
- (void)endTracking:(UITouch *)touch withEvent:(UIEvent *)event{if(touch)[self update:touch];[self sendActionsForControlEvents:UIControlEventTouchUpInside];}
- (void)cancelTrackingWithEvent:(UIEvent *)event{[self sendActionsForControlEvents:UIControlEventTouchCancel];}
@end

