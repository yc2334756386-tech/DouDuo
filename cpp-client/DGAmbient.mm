#import "DGAmbient.h"
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
@implementation DGAmbient{
 AVPlayerItem *_item;AVPlayerItemVideoOutput *_output;__weak UIImageView *_image;NSTimer *_timer;
 CAGradientLayer *_gradient;BOOL _busy,_active;NSUInteger _generation;UIImage *_previousImage;
}
- (instancetype)initWithFrame:(CGRect)frame{if((self=[super initWithFrame:frame])){self.backgroundColor=UIColor.blackColor;self.userInteractionEnabled=NO;_gradient=[CAGradientLayer layer];_gradient.startPoint=CGPointMake(.15,0);_gradient.endPoint=CGPointMake(.85,1);_gradient.colors=@[(id)UIColor.blackColor.CGColor,(id)UIColor.blackColor.CGColor];[self.layer addSublayer:_gradient];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settings) name:@"DouGlassSettingsChanged" object:nil];}return self;}
- (void)layoutSubviews{[super layoutSubviews];_gradient.frame=self.bounds;}
- (void)item:(AVPlayerItem *)item imageView:(UIImageView *)image{if(item==_item&&image==_image)return;++_generation;if(_output&&_item)[_item removeOutput:_output];_item=item;_image=image;_previousImage=nil;_output=nil;if(item){_output=[[AVPlayerItemVideoOutput alloc]initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];[item addOutput:_output];}}
- (NSInteger)level{id value=[NSUserDefaults.standardUserDefaults objectForKey:@"douglass.ambient"];return value?MIN(4,MAX(0,[value integerValue])):1;}
- (void)settings{_previousImage=nil;_gradient.hidden=[self level]==4;if(_active)[self sample];}
- (void)active:(BOOL)active{if(_active==active)return;_active=active;[_timer invalidate];_timer=nil;if(active){__weak DGAmbient *weak=self;_timer=[NSTimer scheduledTimerWithTimeInterval:.65 repeats:YES block:^(NSTimer *timer){[weak sample];}];[self sample];}}
- (void)sample{
 if(!_active||_busy||[self level]==4||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||NSProcessInfo.processInfo.thermalState>=NSProcessInfoThermalStateSerious)return;
 CIImage *input=nil;if(_output){CMTime time=[_output itemTimeForHostTime:CACurrentMediaTime()];if([_output hasNewPixelBufferForItemTime:time]){CVPixelBufferRef buffer=[_output copyPixelBufferForItemTime:time itemTimeForDisplay:NULL];if(buffer){input=[CIImage imageWithCVPixelBuffer:buffer];CVPixelBufferRelease(buffer);}}}else{UIImage *image=_image.image;if(image&&image!=_previousImage){_previousImage=image;if(image.CGImage)input=[CIImage imageWithCGImage:image.CGImage];}}
 if(!input)return;_busy=YES;NSUInteger generation=_generation;NSInteger level=[self level];__weak DGAmbient *weak=self;CIImage *frame=input;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
  static CIContext *context;static dispatch_once_t once;dispatch_once(&once,^{context=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@NO,kCIContextWorkingColorSpace:NSNull.null}];});
  CGRect extent=frame.extent;CGFloat ratio=32/MAX(1,MAX(extent.size.width,extent.size.height));CIImage *small=[frame imageByApplyingTransform:CGAffineTransformMakeScale(ratio,ratio)];CGRect e=small.extent;NSMutableArray *colors=[NSMutableArray array];CGFloat gains[]={.78,.5,.3,.16,0};
  for(NSInteger part=0;part<2;part++){CGRect region=CGRectMake(e.origin.x,e.origin.y+part*e.size.height/2,e.size.width,e.size.height/2);CIFilter *filter=[CIFilter filterWithName:@"CIAreaAverage" withInputParameters:@{kCIInputImageKey:small,kCIInputExtentKey:[CIVector vectorWithCGRect:region]}];uint8_t rgba[4]={0};CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();[context render:filter.outputImage toBitmap:rgba rowBytes:4 bounds:CGRectMake(0,0,1,1) format:kCIFormatRGBA8 colorSpace:space];CGColorSpaceRelease(space);CGFloat gain=gains[level];[colors addObject:(id)[UIColor colorWithRed:rgba[0]/255.0*gain green:rgba[1]/255.0*gain blue:rgba[2]/255.0*gain alpha:1].CGColor];}
  dispatch_async(dispatch_get_main_queue(),^{DGAmbient *self=weak;if(!self)return;self->_busy=NO;if(generation!=self->_generation)return;self->_gradient.hidden=[self level]==4;[CATransaction begin];[CATransaction setAnimationDuration:.65];self->_gradient.colors=colors;[CATransaction commit];});
 });
}
- (void)dealloc{[_timer invalidate];if(_output&&_item)[_item removeOutput:_output];[NSNotificationCenter.defaultCenter removeObserver:self];}
@end

