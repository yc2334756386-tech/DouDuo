#import "DGAnimation.h"
#import "DGDiagnostics.h"
#import "DGRefreshPiP.h"
#include "RenderBudget.hpp"
#include <atomic>
static douglass::RenderBudget renderBudget;
static std::atomic<double> processingDeadline{0};
uint64_t DGBeginAnimationPriority(NSTimeInterval duration){CFTimeInterval now=CACurrentMediaTime();uint64_t token=renderBudget.begin(now,duration);processingDeadline.store(renderBudget.deadline(now),std::memory_order_relaxed);return token;}
void DGEndAnimationPriority(uint64_t token){renderBudget.end(token);processingDeadline.store(renderBudget.deadline(CACurrentMediaTime()),std::memory_order_relaxed);}
BOOL DGAnimationPriorityActive(void){double deadline=renderBudget.deadline(CACurrentMediaTime());processingDeadline.store(deadline,std::memory_order_relaxed);return deadline>0;}
BOOL DGAnimationProcessingDeferred(void){return processingDeadline.load(std::memory_order_relaxed)>CACurrentMediaTime();}
void DGAfterAnimations(dispatch_block_t action){if(!action)return;if(DGAnimationPriorityActive()){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,50*NSEC_PER_MSEC),dispatch_get_main_queue(),^{DGAfterAnimations(action);});return;}action();}
static NSArray *Points(){NSArray *points=[NSUserDefaults.standardUserDefaults arrayForKey:@"douglass.animation.points"];return points.count==4?points:@[@.16,@1,@.3,@1];}
NSTimeInterval DGDuration(NSTimeInterval base){double speed=[NSUserDefaults.standardUserDefaults doubleForKey:@"douglass.animation.speed"];return base/(speed>=.2&&speed<=4?speed:.8);}
CAMediaTimingFunction *DGTiming(void){NSArray *p=Points();return [CAMediaTimingFunction functionWithControlPoints:[p[0]floatValue]:[p[1]floatValue]:[p[2]floatValue]:[p[3]floatValue]];}
UIViewPropertyAnimator *DGAnimate(NSTimeInterval duration,void (^changes)(void),void (^done)(BOOL)){NSArray *p=Points();UICubicTimingParameters *timing=[[UICubicTimingParameters alloc]initWithControlPoint1:CGPointMake([p[0]doubleValue],[p[1]doubleValue]) controlPoint2:CGPointMake([p[2]doubleValue],[p[3]doubleValue])];NSTimeInterval actual=DGDuration(duration);uint64_t priority=DGBeginAnimationPriority(actual);UIViewPropertyAnimator *animator=[[UIViewPropertyAnimator alloc]initWithDuration:actual timingParameters:timing];animator.userInteractionEnabled=YES;animator.interruptible=YES;[animator addAnimations:changes];[animator addCompletion:^(UIViewAnimatingPosition position){DGEndAnimationPriority(priority);if(done)done(position==UIViewAnimatingPositionEnd);}];[animator startAnimation];return animator;}
@interface DGCurveView:UIControl
@property(nonatomic,copy) NSArray *points;
@end
@implementation DGCurveView{NSInteger _handle;}
- (CGRect)graph{return CGRectInset(self.bounds,36,36);}
- (void)setPoints:(NSArray *)points{_points=points.copy;[self setNeedsDisplay];}
- (CGPoint)point:(NSInteger)index{CGRect b=[self graph];return CGPointMake(b.origin.x+[_points[index*2]doubleValue]*b.size.width,CGRectGetMaxY(b)-[_points[index*2+1]doubleValue]*b.size.height);}
- (void)drawRect:(CGRect)rect{CGContextClearRect(UIGraphicsGetCurrentContext(),self.bounds);CGRect b=[self graph];[[UIColor colorWithWhite:1 alpha:.08]setStroke];for(int i=0;i<=4;i++){CGFloat f=i/4.;UIBezierPath *line=[UIBezierPath bezierPath];[line moveToPoint:CGPointMake(b.origin.x+b.size.width*f,b.origin.y)];[line addLineToPoint:CGPointMake(b.origin.x+b.size.width*f,CGRectGetMaxY(b))];[line moveToPoint:CGPointMake(b.origin.x,b.origin.y+b.size.height*f)];[line addLineToPoint:CGPointMake(CGRectGetMaxX(b),b.origin.y+b.size.height*f)];[line stroke];}CGPoint start=CGPointMake(b.origin.x,CGRectGetMaxY(b)),end=CGPointMake(CGRectGetMaxX(b),b.origin.y),a=[self point:0],z=[self point:1];[UIColor.systemYellowColor setStroke];UIBezierPath *handles=[UIBezierPath bezierPath];[handles moveToPoint:start];[handles addLineToPoint:a];[handles moveToPoint:end];[handles addLineToPoint:z];[handles stroke];[UIColor.whiteColor setStroke];UIBezierPath *curve=[UIBezierPath bezierPath];curve.lineWidth=3;[curve moveToPoint:start];[curve addCurveToPoint:end controlPoint1:a controlPoint2:z];[curve stroke];[UIColor.systemYellowColor setFill];for(NSValue *value in @[[NSValue valueWithCGPoint:a],[NSValue valueWithCGPoint:z]]){CGPoint point=value.CGPointValue;[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(point.x-8,point.y-8,16,16)]fill];}}
- (BOOL)beginTracking:(UITouch *)touch withEvent:(UIEvent *)event{CGPoint point=[touch locationInView:self],a=[self point:0],b=[self point:1];_handle=hypot(point.x-a.x,point.y-a.y)<hypot(point.x-b.x,point.y-b.y)?0:1;[self update:touch];return YES;}
- (BOOL)continueTracking:(UITouch *)touch withEvent:(UIEvent *)event{[self update:touch];return YES;}
- (void)update:(UITouch *)touch{CGPoint point=[touch locationInView:self];CGRect b=[self graph];NSMutableArray *p=[self.points mutableCopy];p[_handle*2]=@(MIN(1,MAX(0,(point.x-b.origin.x)/b.size.width)));p[_handle*2+1]=@(MIN(2,MAX(-1,(CGRectGetMaxY(b)-point.y)/b.size.height)));self.points=p;[self sendActionsForControlEvents:UIControlEventValueChanged];}
@end
@interface DGAnimationSettings:UIViewController
@end
@implementation DGAnimationSettings{DGCurveView *_curve;UILabel *_values,*_speedLabel;UISlider *_speed;UIView *_demo;UIViewPropertyAnimator *_demoAnimator;}
- (void)viewDidLoad{[super viewDidLoad];self.title=@"全局动画曲线与速率";self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];self.view.backgroundColor=UIColor.systemBackgroundColor;_curve=[DGCurveView new];_curve.points=Points();[_curve addTarget:self action:@selector(curveChanged) forControlEvents:UIControlEventValueChanged];[self.view addSubview:_curve];_values=Label(12,UIFontWeightRegular);_values.textAlignment=NSTextAlignmentCenter;[self.view addSubview:_values];_speedLabel=Label(15,UIFontWeightMedium);[self.view addSubview:_speedLabel];_speed=[UISlider new];_speed.minimumValue=.2;_speed.maximumValue=4;double speed=[NSUserDefaults.standardUserDefaults doubleForKey:@"douglass.animation.speed"];_speed.value=speed>=.2?speed:.8;[_speed addTarget:self action:@selector(speedChanged) forControlEvents:UIControlEventValueChanged];[self.view addSubview:_speed];UIStackView *buttons=[UIStackView new];buttons.tag=90;buttons.axis=UILayoutConstraintAxisHorizontal;buttons.distribution=UIStackViewDistributionFillEqually;for(NSString *name in @[@"标准",@"线性",@"缓出",@"回弹",@"数值"]){UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:name forState:UIControlStateNormal];[button addTarget:self action:@selector(preset:) forControlEvents:UIControlEventTouchUpInside];[buttons addArrangedSubview:button];}[self.view addSubview:buttons];_demo=[[UIView alloc]initWithFrame:CGRectMake(0,0,32,32)];_demo.backgroundColor=UIColor.systemTealColor;_demo.layer.cornerRadius=16;[self.view addSubview:_demo];self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"预览" style:UIBarButtonItemStylePlain target:self action:@selector(preview)];[self curveChanged];[self speedChanged];}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];CGFloat width=self.view.bounds.size.width,top=self.view.safeAreaInsets.top;_curve.frame=CGRectMake(16,top+12,width-32,MIN(width-32,320));_values.frame=CGRectMake(16,CGRectGetMaxY(_curve.frame),width-32,30);[self.view viewWithTag:90].frame=CGRectMake(12,CGRectGetMaxY(_values.frame)+8,width-24,44);_speedLabel.frame=CGRectMake(24,CGRectGetMaxY([self.view viewWithTag:90].frame)+18,width-48,26);_speed.frame=CGRectMake(24,CGRectGetMaxY(_speedLabel.frame)+8,width-48,34);_demo.center=CGPointMake(40,CGRectGetMaxY(_speed.frame)+60);}
- (void)close{[self dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];}
- (void)curveChanged{[NSUserDefaults.standardUserDefaults setObject:_curve.points forKey:@"douglass.animation.points"];NSArray *p=_curve.points;_values.text=[NSString stringWithFormat:@"(%.2f, %.2f)   (%.2f, %.2f)",[p[0]doubleValue],[p[1]doubleValue],[p[2]doubleValue],[p[3]doubleValue]];}
- (void)speedChanged{[NSUserDefaults.standardUserDefaults setDouble:_speed.value forKey:@"douglass.animation.speed"];_speedLabel.text=[NSString stringWithFormat:@"全局动画速率 · %.2f×",_speed.value];}
- (void)preset:(UIButton *)button{NSUInteger index=[@[@"标准",@"线性",@"缓出",@"回弹",@"数值"]indexOfObject:button.currentTitle];if(index<4){_curve.points=@[@[@.25,@.1,@.25,@1],@[@0,@0,@1,@1],@[@.16,@1,@.3,@1],@[@.34,@1.56,@.64,@1]][index];[self curveChanged];[self preview];return;}UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"自定义贝塞尔曲线" message:@"X 为 0～1，Y 为 -1～2" preferredStyle:UIAlertControllerStyleAlert];for(NSNumber *number in _curve.points)[alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.text=number.stringValue;field.keyboardType=UIKeyboardTypeNumbersAndPunctuation;}];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"应用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){NSMutableArray *p=[NSMutableArray array];for(NSUInteger i=0;i<4;i++){double v=alert.textFields[i].text.doubleValue;if(!std::isfinite(v)||v<(i%2?-1:0)||v>(i%2?2:1)){DGToast(self,@"曲线数值超出范围");return;}[p addObject:@(v)];}self->_curve.points=p;[self curveChanged];[self preview];}]];[self presentViewController:alert animated:YES completion:nil];}
- (void)preview{[_demoAnimator stopAnimation:YES];_demo.transform=CGAffineTransformIdentity;_demoAnimator=DGAnimate(1,^{self->_demo.transform=CGAffineTransformMakeTranslation(self.view.bounds.size.width-80,0);},nil);}
@end
UIViewController *DGMakeAnimationSettings(void){return [DGAnimationSettings new];}
// A tiny, noninteractive foreground surface performs a real update on every
// requested frame. A fully hidden view would be discarded by the compositor.
@interface DGRefreshPulse:UIView
@property(nonatomic) CFTimeInterval stamp;
@end
@implementation DGRefreshPulse
- (void)drawRect:(CGRect)rect{
 CGContextRef context=UIGraphicsGetCurrentContext();unsigned tick=(unsigned)fmod(_stamp*1000,256);CGFloat value=(tick&1)?.9:.1;CGContextSetGrayFillColor(context,value,1);CGContextFillRect(context,self.bounds);
}
@end
static UIWindow *DGRefreshWindow(){
 for(UIScene *scene in UIApplication.sharedApplication.connectedScenes)if([scene isKindOfClass:UIWindowScene.class]&&scene.activationState==UISceneActivationStateForegroundActive){for(UIWindow *window in ((UIWindowScene *)scene).windows)if(window.isKeyWindow)return window;}return nil;
}
void DGApplyDisplayLinkRate(CADisplayLink *link,UIView *view){
 if(!link)return;UIScreen *screen=view.window.windowScene.screen?:DGRefreshWindow().windowScene.screen?:UIScreen.mainScreen;
 if([NSUserDefaults.standardUserDefaults boolForKey:@"douglass.force120"]){float rate=MIN(120,screen.maximumFramesPerSecond);link.preferredFrameRateRange=CAFrameRateRangeMake(rate,rate,rate);}else link.preferredFrameRateRange=CAFrameRateRangeDefault;
}
@interface DGRefreshRate:NSObject
@property(nonatomic,strong) CADisplayLink *link;
@property(nonatomic,strong) DGRefreshPulse *pulse;
@property(nonatomic) double observedFPS;
@property(nonatomic) CFTimeInterval sampleStart,lastLog;
@property(nonatomic) NSUInteger frames;
@end
@implementation DGRefreshRate
- (void)tick:(CADisplayLink *)link{
 self.pulse.stamp=link.timestamp;[self.pulse setNeedsDisplay];
 if(!_sampleStart){_sampleStart=link.timestamp;_frames=0;return;}++_frames;double elapsed=link.timestamp-_sampleStart;
 if(elapsed>=1){_observedFPS=_frames/elapsed;_frames=0;_sampleStart=link.timestamp;if(DGDiagnosticEnabled()&&link.timestamp-_lastLog>=15){_lastLog=link.timestamp;DGDiagnostic(@"refresh.callback",[NSString stringWithFormat:@"observed_fps=%.1f maximum=%ld low_power=%d thermal=%ld",_observedFPS,(long)(self.pulse.window.windowScene.screen?:UIScreen.mainScreen).maximumFramesPerSecond,NSProcessInfo.processInfo.lowPowerModeEnabled,(long)NSProcessInfo.processInfo.thermalState]);}}
}
@end
static DGRefreshRate *refresh;
void DGRefreshRateSuspend(void){[refresh.link invalidate];refresh.link=nil;[refresh.pulse removeFromSuperview];refresh.pulse=nil;refresh.sampleStart=0;refresh.frames=0;refresh.observedFPS=0;}
NSString *DGRefreshRateStatus(void){
 UIScreen *screen=DGRefreshWindow().windowScene.screen?:UIScreen.mainScreen;NSInteger maximum=screen.maximumFramesPerSecond;
 if(maximum<120)return [NSString stringWithFormat:@"此屏幕上限 %ldHz，无法请求 120Hz",(long)maximum];
 if(![NSUserDefaults.standardUserDefaults boolForKey:@"douglass.force120"])return @"关闭时跟随系统 ProMotion；开启持续请求高刷";
 NSString *rate=refresh.observedFPS>0?[NSString stringWithFormat:@"界面回调约 %.0ffps",refresh.observedFPS]:@"界面回调测量中";
 return [NSString stringWithFormat:@"%@ · %@%@",rate,DGRefreshPiPStatus(),NSProcessInfo.processInfo.lowPowerModeEnabled?@" · 省电模式可能限频":@""];
}
void DGRefreshRateApply(void){
 static dispatch_once_t once;dispatch_once(&once,^{refresh=[DGRefreshRate new];});
 BOOL enabled=UIApplication.sharedApplication.applicationState==UIApplicationStateActive&&[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.force120"];
 if(!enabled)DGRefreshRateSuspend();else{
  UIWindow *window=DGRefreshWindow();
  if(window&&!refresh.pulse){refresh.pulse=[[DGRefreshPulse alloc]initWithFrame:CGRectMake(2,window.safeAreaInsets.top+2,2,2)];refresh.pulse.userInteractionEnabled=NO;refresh.pulse.isAccessibilityElement=NO;refresh.pulse.accessibilityElementsHidden=YES;refresh.pulse.backgroundColor=UIColor.clearColor;refresh.pulse.opaque=NO;refresh.pulse.alpha=.005;refresh.pulse.contentScaleFactor=1;}
  if(window&&refresh.pulse.superview!=window)[window addSubview:refresh.pulse];
  if(!refresh.link){refresh.link=[CADisplayLink displayLinkWithTarget:refresh selector:@selector(tick:)];[refresh.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];}
  DGApplyDisplayLinkRate(refresh.link,refresh.pulse);
  if(DGDiagnosticEnabled())DGDiagnostic(@"refresh.request",[NSString stringWithFormat:@"maximum=%ld foreground_surface=%d low_power=%d",(long)(window.windowScene.screen?:UIScreen.mainScreen).maximumFramesPerSecond,refresh.pulse.window!=nil,NSProcessInfo.processInfo.lowPowerModeEnabled]);
 }
 DGRefreshPiPApply();[NSNotificationCenter.defaultCenter postNotificationName:@"DGRefreshRateChanged" object:nil];
}
