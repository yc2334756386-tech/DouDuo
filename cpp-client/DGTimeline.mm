#import "DGTimeline.h"
#include <cmath>
@implementation DGTimeline{CGPoint _origin;float _originalValue;BOOL _scrubbing;}
- (BOOL)scrubbing{return _scrubbing;}
- (CGRect)trackRectForBounds:(CGRect)bounds{return CGRectMake(0,(bounds.size.height-3)/2,bounds.size.width,3);}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event{return CGRectContainsPoint(CGRectInset(self.bounds,-8,-12),point);}
- (void)update:(UITouch *)touch{CGFloat x=[touch locationInView:self].x;self.value=self.minimumValue+(self.maximumValue-self.minimumValue)*MIN(1,MAX(0,x/MAX(1,self.bounds.size.width)));}
- (BOOL)beginTracking:(UITouch *)touch withEvent:(UIEvent *)event{_origin=[touch locationInView:self];_originalValue=self.value;_scrubbing=NO;[self update:touch];if(self.trackingBegan)self.trackingBegan();return YES;}
- (BOOL)continueTracking:(UITouch *)touch withEvent:(UIEvent *)event{CGPoint point=[touch locationInView:self];if(!_scrubbing&&fabs(point.x-_origin.x)>=5)_scrubbing=YES;[self update:touch];if(_scrubbing&&self.trackingChanged)self.trackingChanged();return YES;}
- (void)endTracking:(UITouch *)touch withEvent:(UIEvent *)event{if(touch)[self update:touch];if(self.trackingEnded)self.trackingEnded(NO);_scrubbing=NO;}
- (void)cancelTrackingWithEvent:(UIEvent *)event{self.value=_originalValue;if(self.trackingEnded)self.trackingEnded(YES);_scrubbing=NO;}
@end

