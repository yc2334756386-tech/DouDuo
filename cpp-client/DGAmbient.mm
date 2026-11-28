#import "DGAmbient.h"
#import "DGDiagnostics.h"
#import "DGAnimation.h"
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
#include "ContrastMap.hpp"
#include <memory>
@implementation DGAmbient{
 AVPlayerItem *_item;AVPlayerItemVideoOutput *_output;__weak UIImageView *_image;__weak AVPlayerLayer *_videoLayer;NSTimer *_timer;
 CAGradientLayer *_gradient;BOOL _busy,_active,_adaptive,_transformRequested,_transformReady;NSUInteger _generation;UIImage *_previousImage;
 CGRect _contrastRect;CGAffineTransform _trackTransform;CFTimeInterval _lastAmbient;
 std::shared_ptr<douglass::ContrastMap> _contrastMap;
}
- (instancetype)initWithFrame:(CGRect)frame{
 if((self=[super initWithFrame:frame])){self.backgroundColor=UIColor.blackColor;self.userInteractionEnabled=NO;_trackTransform=CGAffineTransformIdentity;_contrastMap=std::make_shared<douglass::ContrastMap>();_gradient=[CAGradientLayer layer];_gradient.startPoint=CGPointMake(.15,0);_gradient.endPoint=CGPointMake(.85,1);_gradient.colors=@[(id)UIColor.blackColor.CGColor,(id)UIColor.blackColor.CGColor];[self.layer addSublayer:_gradient];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settings) name:@"DouGlassSettingsChanged" object:nil];}return self;
}
- (void)layoutSubviews{[super layoutSubviews];_gradient.frame=self.bounds;}
- (void)resetContrast{
 ++_generation;_contrastMap=std::make_shared<douglass::ContrastMap>();if(self.contrastReady)self.contrastReady(nullptr);
}
- (void)item:(AVPlayerItem *)item imageView:(UIImageView *)image{
 if(item==_item&&image==_image)return;[self resetContrast];if(_output&&_item)[_item removeOutput:_output];_item=item;_image=image;_previousImage=nil;_output=nil;_trackTransform=CGAffineTransformIdentity;_transformRequested=NO;_transformReady=item==nil;_lastAmbient=0;
 if(item){
  _output=[[AVPlayerItemVideoOutput alloc]initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];[item addOutput:_output];
 }
 if(_adaptive)[self loadTransform];
}
- (void)loadTransform{
 AVPlayerItem *item=_item;if(!item||_transformRequested)return;_transformRequested=YES;
 __weak DGAmbient *weak=self;
 [item.asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks,NSError *error){AVAssetTrack *track=tracks.firstObject;if(!track)return;
   [track loadValuesAsynchronouslyForKeys:@[@"preferredTransform"] completionHandler:^{NSError *failure=nil;if([track statusOfValueForKey:@"preferredTransform" error:&failure]!=AVKeyValueStatusLoaded)return;CGAffineTransform transform=track.preferredTransform;
    dispatch_async(dispatch_get_main_queue(),^{DGAmbient *self=weak;if(self&&self->_item==item){self->_trackTransform=CGAffineTransformMake(transform.a,-transform.b,-transform.c,transform.d,0,0);self->_transformReady=YES;[self resetContrast];DGDiagnostic(@"contrast.orientation",[NSString stringWithFormat:@"a=%.0f b=%.0f c=%.0f d=%.0f",transform.a,transform.b,transform.c,transform.d]);}});
   }];
  }];
}
- (NSInteger)level{id value=[NSUserDefaults.standardUserDefaults objectForKey:@"douglass.ambient"];return value?MIN(4,MAX(0,[value integerValue])):1;}
- (void)settings{_previousImage=nil;_gradient.hidden=[self level]==4;if(_active)[self sample];}
- (void)restartTimer{
 [_timer invalidate];_timer=nil;if(!_active)return;__weak DGAmbient *weak=self;
 _timer=[NSTimer timerWithTimeInterval:_adaptive?1./12:.65 repeats:YES block:^(NSTimer *timer){[weak sample];}];[NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];[self sample];
}
- (void)active:(BOOL)active{if(_active==active)return;_active=active;[self restartTimer];}
- (void)adaptive:(BOOL)enabled{if(_adaptive==enabled)return;_adaptive=enabled;if(enabled)[self loadTransform];[self restartTimer];}
- (void)contrastInRect:(CGRect)region playerLayer:(AVPlayerLayer *)layer{
 if(CGRectEqualToRect(region,_contrastRect)&&layer==_videoLayer)return;_contrastRect=region;_videoLayer=layer;[self resetContrast];
}
- (void)sample{
 NSInteger level=[self level];BOOL adaptive=_adaptive&&_transformReady&&(_item||_image.image)&&_contrastRect.size.width>0&&_contrastRect.size.height>0;
 if(!_active||_busy||DGAnimationPriorityActive()||(level==4&&!adaptive)||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||NSProcessInfo.processInfo.thermalState>=NSProcessInfoThermalStateSerious)return;
 CIImage *input=nil;
 if(_output){CMTime time=[_output itemTimeForHostTime:CACurrentMediaTime()];if([_output hasNewPixelBufferForItemTime:time]){CVPixelBufferRef buffer=[_output copyPixelBufferForItemTime:time itemTimeForDisplay:NULL];if(buffer){input=[CIImage imageWithCVPixelBuffer:buffer];CVPixelBufferRelease(buffer);}}}
 else{UIImage *image=_image.image;if(image&&(adaptive||image!=_previousImage)){_previousImage=image;if(image.CGImage)input=[CIImage imageWithCGImage:image.CGImage];}}
 if(!input)return;
 AVPlayerLayer *video=_item?_videoLayer:nil;CALayer *media=video?:_image.layer,*geometry=media.presentationLayer?:media,*destination=self.layer.presentationLayer?:self.layer;
 CGRect content=video.videoRect;CGSize source=_item?_item.presentationSize:_image.image.size;CGRect visibleBounds=geometry.bounds;
 if(CGRectIsEmpty(content)&&source.width>0&&source.height>0){BOOL fill=video?[video.videoGravity isEqualToString:AVLayerVideoGravityResizeAspectFill]:_image.contentMode==UIViewContentModeScaleAspectFill;auto rect=douglass::fittedMedia(source.width,source.height,{visibleBounds.origin.x,visibleBounds.origin.y,visibleBounds.size.width,visibleBounds.size.height},fill);content=CGRectMake(rect.x,rect.y,rect.width,rect.height);}
 CGRect videoRect=geometry?[geometry convertRect:content toLayer:destination]:CGRectZero,viewport=geometry?[geometry convertRect:visibleBounds toLayer:destination]:CGRectZero;
 if(CGRectIsEmpty(videoRect))adaptive=NO;
 BOOL average=level!=4&&CACurrentMediaTime()-_lastAmbient>=.6;if(!average&&!adaptive)return;if(average)_lastAmbient=CACurrentMediaTime();
 _busy=YES;CFTimeInterval captured=CACurrentMediaTime();NSUInteger generation=_generation;__weak DGAmbient *weak=self;CIImage *inputFrame=input;CGRect bounds=self.bounds,region=_contrastRect;CGAffineTransform transform=_trackTransform;NSArray *background=((CAGradientLayer *)_gradient.presentationLayer).colors?:_gradient.colors;background=background.copy;auto contrastMap=_contrastMap;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{@autoreleasepool{
  static CIContext *context;static dispatch_once_t once;dispatch_once(&once,^{context=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@NO,kCIContextWorkingColorSpace:NSNull.null,kCIContextCacheIntermediates:@NO}];});
  CIImage *frame=[inputFrame imageByApplyingTransform:transform];CGRect extent=frame.extent;NSMutableArray *colors=nil;CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  if(average){
   CGFloat ratio=32/MAX(1,MAX(extent.size.width,extent.size.height));CIImage *small=[frame imageByApplyingTransform:CGAffineTransformMakeScale(ratio,ratio)];CGRect e=small.extent;colors=[NSMutableArray array];CGFloat gains[]={.78,.5,.3,.16,0};
   for(NSInteger part=0;part<2;part++){CGRect half=CGRectMake(e.origin.x,e.origin.y+(1-part)*e.size.height/2,e.size.width,e.size.height/2);CIFilter *filter=[CIFilter filterWithName:@"CIAreaAverage" withInputParameters:@{kCIInputImageKey:small,kCIInputExtentKey:[CIVector vectorWithCGRect:half]}];uint8_t rgba[4]={0};[context render:filter.outputImage toBitmap:rgba rowBytes:4 bounds:CGRectMake(0,0,1,1) format:kCIFormatRGBA8 colorSpace:space];CGFloat gain=gains[level];[colors addObject:(id)[UIColor colorWithRed:rgba[0]/255.0*gain green:rgba[1]/255.0*gain blue:rgba[2]/255.0*gain alpha:1].CGColor];}
  }
  std::shared_ptr<const douglass::ContrastFrame> contrast;
  if(adaptive&&extent.size.width>0&&extent.size.height>0){
   CGFloat height=bounds.size.height;
   CIImage *scene=[[CIImage imageWithColor:[CIColor colorWithRed:0 green:0 blue:0 alpha:1]] imageByCroppingToRect:bounds];
   if(level!=4&&background.count==2){CIFilter *gradient=[CIFilter filterWithName:@"CILinearGradient" withInputParameters:@{@"inputPoint0":[CIVector vectorWithX:bounds.size.width*.15 Y:height],@"inputPoint1":[CIVector vectorWithX:bounds.size.width*.85 Y:0],@"inputColor0":[CIColor colorWithCGColor:(CGColorRef)background[0]],@"inputColor1":[CIColor colorWithCGColor:(CGColorRef)background[1]]}];scene=[gradient.outputImage imageByCroppingToRect:bounds];}
   CIImage *normalized=[frame imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x,-extent.origin.y)];
   CIImage *placed=[[normalized imageByApplyingTransform:CGAffineTransformMakeScale(videoRect.size.width/extent.size.width,videoRect.size.height/extent.size.height)] imageByApplyingTransform:CGAffineTransformMakeTranslation(videoRect.origin.x,height-CGRectGetMaxY(videoRect))];
   CGRect clip=CGRectMake(viewport.origin.x,height-CGRectGetMaxY(viewport),viewport.size.width,viewport.size.height);scene=[[placed imageByCroppingToRect:clip] imageByCompositingOverImage:scene];
   CGRect roi=CGRectMake(region.origin.x,height-CGRectGetMaxY(region),region.size.width,region.size.height);CGFloat scale=MIN(1,128/MAX(1,region.size.width));size_t width=MAX(1,(size_t)ceil(region.size.width*scale)),rows=MAX(1,(size_t)ceil(region.size.height*scale));
   CIImage *cropped=[[[scene imageByCroppingToRect:roi] imageByApplyingTransform:CGAffineTransformMakeTranslation(-roi.origin.x,-roi.origin.y)] imageByApplyingTransform:CGAffineTransformMakeScale(scale,scale)];
   CGImageRef small=[context createCGImage:cropped fromRect:CGRectMake(0,0,width,rows) format:kCIFormatRGBA8 colorSpace:space];
   if(small){CFDataRef pixels=CGDataProviderCopyData(CGImageGetDataProvider(small));size_t stride=CGImageGetBytesPerRow(small);if(pixels&&stride>=width*4&&CFDataGetLength(pixels)>=(CFIndex)(stride*rows))contrast=contrastMap->makeFrame(CFDataGetBytePtr(pixels),width,rows,stride);if(pixels)CFRelease(pixels);CGImageRelease(small);}
  }
  CGColorSpaceRelease(space);
  dispatch_async(dispatch_get_main_queue(),^{DGAmbient *self=weak;if(!self)return;self->_busy=NO;if(generation!=self->_generation||!self->_active||DGAnimationPriorityActive()||CACurrentMediaTime()-captured>.2)return;if(colors){self->_gradient.hidden=[self level]==4;[CATransaction begin];[CATransaction setAnimationDuration:.65];self->_gradient.colors=colors;[CATransaction commit];}if(contrast&&self->_adaptive&&self.contrastReady)self.contrastReady(contrast);});
 }});
}
- (void)dealloc{[_timer invalidate];if(_output&&_item)[_item removeOutput:_output];[NSNotificationCenter.defaultCenter removeObserver:self];}
@end
