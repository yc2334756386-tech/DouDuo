#import "DGAudio.h"
static const double EQF[]={63,122,225,416,770,1420,2640,4890,9060,13890};
static UIColor *Accent(){return [UIColor colorWithRed:.98 green:.16 blue:.32 alpha:1];}
static NSString *EQKey(NSString *kind,NSInteger index){return [NSString stringWithFormat:@"douglass.eq.%@.%ld",kind,(long)index];}
static double Pref(NSString *key,double initial=0){id value=[NSUserDefaults.standardUserDefaults objectForKey:key];double number=[value respondsToSelector:@selector(doubleValue)]?[value doubleValue]:initial;return std::isfinite(number)?number:initial;}
static NSString *Frequency(double f){return f>=1000?[NSString stringWithFormat:@"%.2f kHz",f/1000]:[NSString stringWithFormat:@"%.0f Hz",f];}

@interface DGRotary:UIControl
@property(nonatomic) double value,minimum,maximum;
@property(nonatomic,copy) NSString *caption;
@property(nonatomic,copy) void (^changed)(double);
@end
@implementation DGRotary{double _start;CGFloat _touchY;}
- (instancetype)init{if((self=[super init])){self.minimum=-100;self.maximum=100;self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitAdjustable;self.backgroundColor=UIColor.clearColor;}return self;}
- (void)setValue:(double)value{_value=std::clamp(value,self.minimum,self.maximum);self.accessibilityValue=[NSString stringWithFormat:@"%.0f",_value];[self setNeedsDisplay];}
- (void)drawRect:(CGRect)rect{CGContextClearRect(UIGraphicsGetCurrentContext(),self.bounds);CGFloat r=MAX(0,MIN(34,(self.bounds.size.width-20)/2)),x=self.bounds.size.width/2,y=43;double fraction=(_value-_minimum)/MAX(.001,_maximum-_minimum),start=M_PI*.75,end=M_PI*2.25;UIBezierPath *track=[UIBezierPath bezierPathWithArcCenter:CGPointMake(x,y) radius:r startAngle:start endAngle:end clockwise:YES];track.lineWidth=5;track.lineCapStyle=kCGLineCapRound;[[UIColor colorWithWhite:1 alpha:.1]setStroke];[track stroke];UIBezierPath *arc=[UIBezierPath bezierPathWithArcCenter:CGPointMake(x,y) radius:r startAngle:start endAngle:start+(end-start)*fraction clockwise:YES];arc.lineWidth=5;arc.lineCapStyle=kCGLineCapRound;[Accent()setStroke];[arc stroke];NSString *value=[NSString stringWithFormat:@"%+.0f",_value];CGSize size=[value sizeWithAttributes:@{NSFontAttributeName:[UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightSemibold]}];[value drawAtPoint:CGPointMake(x-size.width/2,y-size.height/2) withAttributes:@{NSFontAttributeName:[UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.whiteColor}];[self.caption drawInRect:CGRectMake(0,88,self.bounds.size.width,24) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.whiteColor,NSParagraphStyleAttributeName:[self centered]}];}
- (NSParagraphStyle *)centered{NSMutableParagraphStyle *style=[NSMutableParagraphStyle new];style.alignment=NSTextAlignmentCenter;return style;}
- (BOOL)beginTracking:(UITouch *)touch withEvent:(UIEvent *)event{_start=_value;_touchY=[touch locationInView:self].y;return YES;}
- (BOOL)continueTracking:(UITouch *)touch withEvent:(UIEvent *)event{self.value=_start+(_touchY-[touch locationInView:self].y)*(_maximum-_minimum)/180;if(self.changed)self.changed(_value);return YES;}
- (void)accessibilityIncrement{self.value+=5;if(self.changed)self.changed(_value);}
- (void)accessibilityDecrement{self.value-=5;if(self.changed)self.changed(_value);}
@end

@interface DGEQGraph:UIView<UIGestureRecognizerDelegate>
@property(nonatomic,strong) NSArray *gains,*frequencies,*levels;
@property(nonatomic) NSInteger selectedBand,selectedGroup;
@property(nonatomic,copy) void (^changed)(NSInteger,BOOL,double);
@property(nonatomic,copy) void (^bandSelected)(NSInteger);
- (void)prioritizeEditingIn:(UIScrollView *)vertical horizontal:(UIScrollView *)horizontal;
@end
@implementation DGEQGraph{UIPanGestureRecognizer *_pan;BOOL _frequencyMode;double _startFrequency,_startGain;NSInteger _touchedBand;}
- (instancetype)init{if((self=[super init])){self.backgroundColor=[UIColor colorWithWhite:.025 alpha:1];self.layer.cornerRadius=22;self.clipsToBounds=YES;_pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(pan:)];_pan.delegate=self;[self addGestureRecognizer:_pan];[self addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tap:)]];}return self;}
- (CGFloat)x:(NSInteger)i{return 38+(self.bounds.size.width-76)*i/9.;}
- (CGFloat)y:(double)gain{return 22+(self.bounds.size.height-140)*(18-gain)/36.;}
- (void)drawRect:(CGRect)rect{
 CGContextClearRect(UIGraphicsGetCurrentContext(),self.bounds);if(self.gains.count!=10||self.frequencies.count!=10||self.bounds.size.height<160)return;CGFloat h=self.bounds.size.height,bottom=h-118;
 NSInteger first=self.selectedGroup==0?0:self.selectedGroup==1?3:7,last=self.selectedGroup==0?2:self.selectedGroup==1?6:9;
 CGRect box=CGRectMake([self x:first]-27,10,[self x:last]-[self x:first]+54,h-20);UIBezierPath *group=[UIBezierPath bezierPathWithRoundedRect:box cornerRadius:20];group.lineWidth=2.5;[[Accent()colorWithAlphaComponent:.85]setStroke];[group stroke];
 UIBezierPath *curve=[UIBezierPath bezierPath];for(int i=0;i<10;i++){
  CGFloat x=[self x:i];UIBezierPath *grid=[UIBezierPath bezierPath];[grid moveToPoint:CGPointMake(x,28)];[grid addLineToPoint:CGPointMake(x,bottom)];CGFloat dash[]={3,4};[grid setLineDash:dash count:2 phase:0];[[UIColor colorWithWhite:1 alpha:.13]setStroke];[grid stroke];
  if(self.levels.count==10){CGFloat energy=[self.levels[i]doubleValue]*30;[[Accent()colorWithAlphaComponent:.08]setFill];[[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x-10,bottom-energy,20,energy) cornerRadius:4]fill];}
  CGPoint point=CGPointMake(x,[self y:[self.gains[i]doubleValue]]);if(i)[curve addLineToPoint:point];else[curve moveToPoint:point];
 }
 UIBezierPath *fill=[curve copy];[fill addLineToPoint:CGPointMake([self x:9],bottom)];[fill addLineToPoint:CGPointMake([self x:0],bottom)];[fill closePath];[[Accent()colorWithAlphaComponent:.06]setFill];[fill fill];curve.lineWidth=2.5;[Accent()setStroke];[curve stroke];
 for(int i=0;i<10;i++){
  CGFloat x=[self x:i],y=[self y:[self.gains[i]doubleValue]],r=i==self.selectedBand?6.5:5;[self.backgroundColor setFill];UIBezierPath *node=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(x-r,y-r,r*2,r*2)];[node fill];node.lineWidth=3;[Accent()setStroke];[node stroke];
  NSString *gain=[NSString stringWithFormat:@"%+.1f",[self.gains[i]doubleValue]];[gain drawInRect:CGRectMake(x-26,y-25,52,18) withAttributes:@{NSFontAttributeName:[UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightMedium],NSForegroundColorAttributeName:UIColor.secondaryLabelColor,NSParagraphStyleAttributeName:[self textAlignmentStyle]}];
  [Frequency([self.frequencies[i]doubleValue]) drawInRect:CGRectMake(x-33,h-91,66,18) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold],NSForegroundColorAttributeName:UIColor.whiteColor,NSParagraphStyleAttributeName:[self textAlignmentStyle]}];
  CGFloat cy=h-42;double fraction=(log10(std::clamp([self.frequencies[i]doubleValue],20.,20000.))-log10(20))/(log10(20000)-log10(20)),angle=M_PI*.75+M_PI*1.5*std::clamp(fraction,0.,1.);UIBezierPath *ring=[UIBezierPath bezierPathWithArcCenter:CGPointMake(x,cy) radius:15 startAngle:M_PI*.75 endAngle:M_PI*2.25 clockwise:YES];ring.lineWidth=4;[[Accent()colorWithAlphaComponent:.2]setStroke];[ring stroke];ring=[UIBezierPath bezierPathWithArcCenter:CGPointMake(x,cy) radius:15 startAngle:M_PI*.75 endAngle:angle clockwise:YES];ring.lineWidth=4;ring.lineCapStyle=kCGLineCapRound;[Accent()setStroke];[ring stroke];[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(x+15*cos(angle)-3,cy+15*sin(angle)-3,6,6)]stroke];
 }
}
- (NSParagraphStyle *)textAlignmentStyle{NSMutableParagraphStyle *p=[NSMutableParagraphStyle new];p.alignment=NSTextAlignmentCenter;return p;}
- (NSInteger)bandAt:(CGPoint)point{return std::clamp((NSInteger)lround((point.x-38)/MAX(1,self.bounds.size.width-76)*9),(NSInteger)0,(NSInteger)9);}
- (void)selectBand:(NSInteger)band{self.selectedBand=band;self.selectedGroup=band<3?0:band<7?1:2;[self setNeedsDisplay];if(self.bandSelected)self.bandSelected(band);}
- (void)tap:(UITapGestureRecognizer *)tap{[self selectBand:[self bandAt:[tap locationInView:self]]];DGHaptic();}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
 if(gesture!=_pan)return YES;
 if(self.gains.count!=10||self.frequencies.count!=10)return NO;
 CGPoint point=[touch locationInView:self];NSInteger band=[self bandAt:point];
 CGFloat x=[self x:band],nodeY=[self y:[self.gains[band] doubleValue]],rotaryY=self.bounds.size.height-42;
 BOOL knob=hypot(point.x-x,point.y-rotaryY)<=24;
 BOOL node=hypot(point.x-x,point.y-nodeY)<=21;
 if(!knob&&!node)return NO;
 _touchedBand=band;_frequencyMode=knob;return YES;
}
- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gesture {
 CGPoint velocity=[gesture velocityInView:self];return fabs(velocity.y)>fabs(velocity.x)*1.2;
}
- (void)prioritizeEditingIn:(UIScrollView *)vertical horizontal:(UIScrollView *)horizontal {
 [vertical.panGestureRecognizer requireGestureRecognizerToFail:_pan];
 [horizontal.panGestureRecognizer requireGestureRecognizerToFail:_pan];
}
- (void)pan:(UIPanGestureRecognizer *)pan {
 if(pan.state==UIGestureRecognizerStateBegan){
  [self selectBand:_touchedBand];
  _startFrequency=[self.frequencies[_touchedBand]doubleValue];
  _startGain=[self.gains[_touchedBand]doubleValue];
 }
 if(pan.state!=UIGestureRecognizerStateBegan&&pan.state!=UIGestureRecognizerStateChanged)return;
 double dy=[pan translationInView:self].y;
 double value=_frequencyMode?std::clamp(_startFrequency*pow(2,-dy/100),20.,20000.):std::clamp(_startGain-dy/MAX(1,self.bounds.size.height-140)*36,-18.,18.);
 if(self.changed)self.changed(_touchedBand,_frequencyMode,value);
}

@end

@interface DGEffectRow:UIView
@property(nonatomic,copy) NSString *key;
@property(nonatomic,strong) UILabel *title,*detail;
@property(nonatomic,strong) UIButton *valueButton;
@property(nonatomic,strong) UISlider *slider;
@property(nonatomic,copy) void (^changed)(void),(^edit)(void);
@end
@implementation DGEffectRow
- (instancetype)init{if((self=[super init])){self.backgroundColor=[UIColor colorWithWhite:1 alpha:.035];self.layer.cornerRadius=18;_title=Label(15,UIFontWeightSemibold);_detail=Label(11,UIFontWeightRegular);_detail.numberOfLines=2;_detail.textColor=UIColor.secondaryLabelColor;_valueButton=[UIButton buttonWithType:UIButtonTypeSystem];_valueButton.tintColor=Accent();_valueButton.titleLabel.font=[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];[_valueButton addTarget:self action:@selector(editValue) forControlEvents:UIControlEventTouchUpInside];_slider=[UISlider new];_slider.tintColor=Accent();_slider.minimumValue=0;_slider.maximumValue=100;[_slider addTarget:self action:@selector(slide) forControlEvents:UIControlEventValueChanged];for(UIView *v in @[_title,_detail,_valueButton,_slider])[self addSubview:v];[self.heightAnchor constraintEqualToConstant:118].active=YES;}return self;}
- (void)layoutSubviews{[super layoutSubviews];CGFloat w=self.bounds.size.width;_title.frame=CGRectMake(16,10,w-105,25);_valueButton.frame=CGRectMake(w-84,8,70,28);_detail.frame=CGRectMake(16,38,w-32,30);_slider.frame=CGRectMake(16,77,w-32,30);}
- (void)slide{[_valueButton setTitle:[NSString stringWithFormat:@"%.0f%%",_slider.value] forState:UIControlStateNormal];if(self.changed)self.changed();}
- (void)editValue{if(self.edit)self.edit();}
@end

@interface DGEqualizer:UIViewController
@end
@implementation DGEqualizer{
 UIScrollView *_scroll,*_graphScroll;UIStackView *_stack;DGEQGraph *_graph;BOOL _refreshPending;
 UILabel *_route,*_meter,*_bandLabel,*_spatialNote;UISwitch *_enabled,*_adaptive,*_airpods;UIButton *_numbers,*_styleButton;
 NSArray<DGRotary *> *_tone;NSMutableDictionary<NSString *,DGEffectRow *> *_effects;NSInteger _band;NSTimer *_timer;uint64_t _lastFrames;CFTimeInterval _lastSampleAt;
}
- (UILabel *)label:(NSString *)text size:(CGFloat)size{UILabel *label=Label(size,UIFontWeightMedium);label.text=text;label.numberOfLines=0;return label;}
- (UIView *)row:(NSString *)text control:(UIView *)control{UILabel *label=[self label:text size:15];UIStackView *row=[[UIStackView alloc]initWithArrangedSubviews:@[label,control]];row.spacing=12;row.alignment=UIStackViewAlignmentCenter;[row.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;return row;}
- (void)heading:(NSString *)text{UILabel *label=[self label:text size:18];[_stack addArrangedSubview:label];}
- (void)viewDidLoad{
 [super viewDidLoad];self.title=@"音效与均衡器";self.view.backgroundColor=[UIColor colorWithWhite:.025 alpha:1];self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"预设" style:UIBarButtonItemStylePlain target:self action:@selector(presets)];
 _effects=[NSMutableDictionary dictionary];_scroll=[UIScrollView new];_scroll.delaysContentTouches=NO;_scroll.canCancelContentTouches=YES;_scroll.directionalLockEnabled=YES;_scroll.alwaysBounceVertical=YES;[self.view addSubview:_scroll];_stack=[UIStackView new];_stack.axis=UILayoutConstraintAxisVertical;_stack.spacing=14;_stack.translatesAutoresizingMaskIntoConstraints=NO;[_scroll addSubview:_stack];[NSLayoutConstraint activateConstraints:@[[_stack.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor constant:18],[_stack.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor constant:-18],[_stack.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor constant:12],[_stack.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor constant:-28],[_stack.widthAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.widthAnchor constant:-36]]];
 _route=[self label:@"" size:12];_route.textColor=UIColor.secondaryLabelColor;[_stack addArrangedSubview:_route];_enabled=[UISwitch new];_enabled.onTintColor=Accent();[_enabled addTarget:self action:@selector(enabledChanged) forControlEvents:UIControlEventValueChanged];[_stack addArrangedSubview:[self row:@"启用音效处理" control:_enabled]];_meter=[self label:@"等待音轨采样" size:12];[_stack addArrangedSubview:_meter];

 _graphScroll=[UIScrollView new];_graphScroll.showsHorizontalScrollIndicator=YES;_graphScroll.directionalLockEnabled=YES;_graphScroll.alwaysBounceVertical=NO;_graphScroll.delaysContentTouches=NO;[_graphScroll.heightAnchor constraintEqualToConstant:294].active=YES;[_stack addArrangedSubview:_graphScroll];_graph=[DGEQGraph new];[_graphScroll addSubview:_graph];[_graph prioritizeEditingIn:_scroll horizontal:_graphScroll];__weak DGEqualizer *weak=self;
 _graph.bandSelected=^(NSInteger band){DGEqualizer *self=weak;if(!self)return;self->_band=band;[self refresh];};
 _graph.changed=^(NSInteger band,BOOL frequency,double value){DGEqualizer *self=weak;if(!self)return;self->_band=band;[NSUserDefaults.standardUserDefaults setDouble:value forKey:EQKey(frequency?@"freq":@"gain",band)];[self changed];};
 UILabel *hint=[self label:@"左右滑动查看频段，上下滑动浏览设置。按住节点或旋钮上下拖动可调节数值。" size:11];hint.textColor=UIColor.secondaryLabelColor;[_stack addArrangedSubview:hint];_bandLabel=[self label:@"" size:12];[_stack addArrangedSubview:_bandLabel];_numbers=[UIButton buttonWithType:UIButtonTypeSystem];_numbers.tintColor=Accent();[_numbers setTitle:@"精确填写当前频段：频率／强弱／带宽" forState:UIControlStateNormal];[_numbers addTarget:self action:@selector(numbers) forControlEvents:UIControlEventTouchUpInside];[_stack addArrangedSubview:_numbers];
 [self heading:@"低 · 中 · 高频听感"];UIStackView *tones=[UIStackView new];tones.distribution=UIStackViewDistributionFillEqually;[tones.heightAnchor constraintEqualToConstant:122].active=YES;NSMutableArray *knobs=[NSMutableArray array];NSArray *names=@[@"低频",@"中频",@"高频"],*keys=@[@"tone.low",@"tone.mid",@"tone.high"];for(NSInteger i=0;i<3;i++){DGRotary *knob=[DGRotary new];knob.caption=names[i];knob.accessibilityLabel=names[i];NSString *key=[@"douglass.audio." stringByAppendingString:keys[i]];knob.changed=^(double value){DGEqualizer *self=weak;if(!self)return;[NSUserDefaults.standardUserDefaults setDouble:value forKey:key];[self changed];};[tones addArrangedSubview:knob];[knobs addObject:knob];}_tone=knobs;[_stack addArrangedSubview:tones];
 [self heading:@"空间与混音"];
 [self effect:@"width" title:@"声场宽度" detail:@"展开立体声左右声场；单声道保留原声场" initial:0];
 [self effect:@"room" title:@"环绕空间" detail:@"立体声交叉反射与短延迟，模拟空间感" initial:0];
 [self effect:@"mix" title:@"干湿混音" detail:@"0% 为原声，100% 为处理后声音，调节两者混合比例" initial:100];
 _spatialNote=[self label:@"" size:11];_spatialNote.textColor=UIColor.secondaryLabelColor;[_stack addArrangedSubview:_spatialNote];
 [self heading:@"声音质感"];
 [self effect:@"transparency" title:@"通透" detail:@"减少低中频浑浊，轻提高频空气感" initial:0];
 [self effect:@"clarity" title:@"清晰度" detail:@"突出人声和乐器的存在感频段" initial:0];
 [self effect:@"dynamics" title:@"动态增强" detail:@"平滑控制峰值与弱音，提升细节可闻性" initial:0];
 [self effect:@"bass" title:@"低音增强" detail:@"强化低频厚度，保留输出峰值保护" initial:0];
 [self heading:@"自适应听感"];_adaptive=[UISwitch new];_adaptive.onTintColor=Accent();[_adaptive addTarget:self action:@selector(adaptiveChanged) forControlEvents:UIControlEventValueChanged];[_stack addArrangedSubview:[self row:@"按所选风格实时平衡" control:_adaptive]];_styleButton=[UIButton buttonWithType:UIButtonTypeSystem];_styleButton.tintColor=Accent();[_styleButton addTarget:self action:@selector(chooseStyle) forControlEvents:UIControlEventTouchUpInside];[_stack addArrangedSubview:_styleButton];UILabel *adaptive=[self label:@"开启前选择风格，按真实频段能量缓慢修正，自动调整限制为每段 ±4.5 dB。" size:11];adaptive.textColor=UIColor.secondaryLabelColor;[_stack addArrangedSubview:adaptive];
 [self heading:@"AirPods 专属调音"];_airpods=[UISwitch new];_airpods.onTintColor=Accent();[_airpods addTarget:self action:@selector(airpodsChanged) forControlEvents:UIControlEventValueChanged];[_stack addArrangedSubview:[self row:@"AirPods 设备增强" control:_airpods]];[self effect:@"airpods.strength" title:@"增强强度" detail:@"加强低频轮廓、人声与高频细节，仅用于当前 AirPods 输出" initial:60];UILabel *note=[self label:@"这是本机音频处理，不修改耳机固件、降噪或系统通透模式。只对输出名称可识别为 AirPods 的连接开放，无法读取实际佩戴传感器。" size:11];note.textColor=UIColor.secondaryLabelColor;[_stack addArrangedSubview:note];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:@"DGAudioRouteChanged" object:nil];[self refresh];
}
- (void)effect:(NSString *)suffix title:(NSString *)title detail:(NSString *)detail initial:(double)initial{DGEffectRow *row=[DGEffectRow new];row.key=[@"douglass.audio." stringByAppendingString:suffix];row.title.text=title;row.detail.text=detail;row.slider.value=Pref(row.key,initial);[row.valueButton setTitle:[NSString stringWithFormat:@"%.0f%%",row.slider.value] forState:UIControlStateNormal];__weak DGEqualizer *weak=self;__weak DGEffectRow *weakRow=row;row.changed=^{DGEqualizer *self=weak;DGEffectRow *row=weakRow;if(!self||!row)return;[NSUserDefaults.standardUserDefaults setDouble:row.slider.value forKey:row.key];[self changed];};row.edit=^{[weak editEffect:weakRow];};_effects[suffix]=row;[_stack addArrangedSubview:row];}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];_scroll.frame=self.view.bounds;CGFloat w=MAX(740,_graphScroll.bounds.size.width);_graph.frame=CGRectMake(0,0,w,282);_graphScroll.contentSize=CGSizeMake(w,282);}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];DGSetAudioMetering(YES);__weak DGEqualizer *weak=self;_timer=[NSTimer scheduledTimerWithTimeInterval:.28 repeats:YES block:^(NSTimer *timer){[weak meter];}];[self meter];}
- (void)viewWillDisappear:(BOOL)animated{[super viewWillDisappear:animated];[_timer invalidate];_timer=nil;DGSetAudioMetering(NO);if(_refreshPending)DGRefreshAudioPreferences();}
- (void)dealloc{[_timer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];}
- (void)close{[self dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];}
- (void)refresh{
 NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;NSMutableArray *gains=[NSMutableArray array],*frequencies=[NSMutableArray array];NSArray *old=@[@"douglass.eq.low",@"douglass.eq.mid",@"douglass.eq.high"];for(int i=0;i<10;i++){[gains addObject:@(Pref(EQKey(@"gain",i),Pref(old[i<3?0:i<7?1:2])))];[frequencies addObject:@(Pref(EQKey(@"freq",i),EQF[i]))];}_graph.gains=gains;_graph.frequencies=frequencies;_graph.selectedBand=_band;_graph.selectedGroup=_band<3?0:_band<7?1:2;[_graph setNeedsDisplay];_bandLabel.text=[NSString stringWithFormat:@"频段 %ld · %@ · %+.2f dB · Q %.2f",(long)_band+1,Frequency([frequencies[_band]doubleValue]),[gains[_band]doubleValue],Pref(EQKey(@"q",_band),1.1)];_enabled.on=[prefs boolForKey:@"douglass.eq.enabled"];_adaptive.on=[prefs boolForKey:@"douglass.eq.adaptive"];_route.text=[@"当前输出：" stringByAppendingString:DGAudioOutputName()];
 NSArray *keys=@[@"tone.low",@"tone.mid",@"tone.high"];for(int i=0;i<3;i++)_tone[i].value=Pref([@"douglass.audio." stringByAppendingString:keys[i]]);
 for(NSString *key in _effects){DGEffectRow *row=_effects[key];row.slider.value=Pref(row.key,[key isEqualToString:@"mix"]?100:[key isEqualToString:@"airpods.strength"]?60:0);[row.valueButton setTitle:[NSString stringWithFormat:@"%.0f%%",row.slider.value] forState:UIControlStateNormal];}
 BOOL connected=DGAirPodsConnected(),spatial=[prefs boolForKey:@"douglass.dolby"];_airpods.enabled=connected;_airpods.on=connected&&[prefs boolForKey:@"douglass.airpods.enhance"];_effects[@"airpods.strength"].slider.enabled=connected&&_airpods.on;_effects[@"airpods.strength"].valueButton.enabled=connected&&_airpods.on;_effects[@"airpods.strength"].alpha=connected&&_airpods.on?1:.4;
 for(NSString *key in @[@"width",@"room"]){_effects[key].slider.enabled=!spatial;_effects[key].valueButton.enabled=!spatial;_effects[key].alpha=spatial?.4:1;}
 _spatialNote.text=spatial?@"系统空间音频优先：本机声场宽度和环绕空间不叠加；频段与质感处理仍可生效。":@"环绕空间是立体声模拟，不等同于杜比 Atmos 或头部追踪。";
 NSArray *styles=@[@"自然均衡",@"清晰人声",@"温暖低频",@"明亮通透",@"轻柔耐听"];[_styleButton setTitle:[@"听感风格：" stringByAppendingString:styles[std::clamp((NSInteger)[prefs integerForKey:@"douglass.eq.style"],(NSInteger)0,(NSInteger)4)]] forState:UIControlStateNormal];
}
- (void)meter{if(UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||!self.view.window)return;NSDictionary *snapshot=DGAudioSnapshot();uint64_t frames=[snapshot[@"frames"]unsignedLongLongValue];if(frames!=_lastFrames){_lastFrames=frames;_lastSampleAt=CACurrentMediaTime();}_graph.levels=Array(snapshot[@"levels"]);[_graph setNeedsDisplay];BOOL active=[snapshot[@"attached"]boolValue]&&frames>0&&CACurrentMediaTime()-_lastSampleAt<2;
 NSString *message=Text(String(snapshot[@"message"]));if(!_enabled.on){_meter.text=@"音效处理已关闭 · 当前为原声";active=NO;}else if([snapshot[@"bypassed"]boolValue]){_meter.text=@"音轨处理异常，已自动旁路至原声";active=NO;}else if(![snapshot[@"supported"]boolValue]){_meter.text=@"当前解码格式不支持处理，保持原声";active=NO;}else if(Pref(@"douglass.audio.mix",100)==0){_meter.text=@"干湿混音为 0% · 仅输出原声";active=NO;}else if(![snapshot[@"playing"]boolValue]){_meter.text=@"当前音轨未播放，播放后可查看处理状态";active=NO;}else if(active){_meter.text=[NSString stringWithFormat:@"● 正在处理真实音频 · %@ 声道%@",snapshot[@"channels"],[snapshot[@"channels"]intValue]==1?@" · 单声道不展开环绕":@""];}else _meter.text=message.length?message:@"尚未收到处理采样 · 暂不能确认此音源已应用音效";_meter.textColor=active?UIColor.systemGreenColor:UIColor.secondaryLabelColor;
}
- (void)changed {
 [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"douglass.eq.enabled"];
 if(_refreshPending)return;
 _refreshPending=YES;
 __weak DGEqualizer *weak=self;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,70*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
  DGEqualizer *self=weak;if(!self)return;
  self->_refreshPending=NO;DGRefreshAudioPreferences();[self refresh];
 });
}
- (void)enabledChanged{[NSUserDefaults.standardUserDefaults setBool:_enabled.on forKey:@"douglass.eq.enabled"];DGRefreshAudioPreferences();[self refresh];}

- (void)adaptiveChanged{if(_adaptive.on){_adaptive.on=NO;[self chooseStyle];}else{[NSUserDefaults.standardUserDefaults setBool:NO forKey:@"douglass.eq.adaptive"];[self changed];}}
- (void)chooseStyle{UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"选择自适应听感风格" message:@"按真实音轨缓慢修正，不保证所有音源都适合相同风格。" preferredStyle:UIAlertControllerStyleActionSheet];NSArray *styles=@[@"自然均衡",@"清晰人声",@"温暖低频",@"明亮通透",@"轻柔耐听"];for(NSUInteger index=0;index<styles.count;index++)[sheet addAction:[UIAlertAction actionWithTitle:styles[index] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[NSUserDefaults.standardUserDefaults setInteger:index forKey:@"douglass.eq.style"];[NSUserDefaults.standardUserDefaults setBool:YES forKey:@"douglass.eq.adaptive"];[self changed];}]];[sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];sheet.popoverPresentationController.sourceView=_styleButton;sheet.popoverPresentationController.sourceRect=_styleButton.bounds;[self presentViewController:sheet animated:YES completion:nil];}
- (void)airpodsChanged{if(!DGAirPodsConnected()){_airpods.on=NO;return;}[NSUserDefaults.standardUserDefaults setBool:_airpods.on forKey:@"douglass.airpods.enhance"];[self changed];}
- (void)editEffect:(DGEffectRow *)row{if(!row||!row.slider.enabled)return;UIAlertController *alert=[UIAlertController alertControllerWithTitle:row.title.text message:@"输入 0～100，可使用小数" preferredStyle:UIAlertControllerStyleAlert];[alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.text=[NSString stringWithFormat:@"%.2f",row.slider.value];field.keyboardType=UIKeyboardTypeDecimalPad;}];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"应用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){NSScanner *scanner=[NSScanner scannerWithString:alert.textFields.firstObject.text];double value;if(![scanner scanDouble:&value]||!scanner.isAtEnd||!std::isfinite(value)||value<0||value>100){DGToast(self,@"请输入 0～100 的有效数值");return;}[NSUserDefaults.standardUserDefaults setDouble:value forKey:row.key];[self changed];}]];[self presentViewController:alert animated:YES completion:nil];}
- (void)numbers{NSArray *keys=@[EQKey(@"freq",_band),EQKey(@"gain",_band),EQKey(@"q",_band)];NSArray *initial=@[@(EQF[_band]),@0,@1.1];UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"当前频段" message:@"频率 20～20000 Hz；强弱 ±18 dB；Q 0.2～8" preferredStyle:UIAlertControllerStyleAlert];for(NSUInteger i=0;i<3;i++)[alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.text=[NSString stringWithFormat:@"%.3f",Pref(keys[i],[initial[i]doubleValue])];field.placeholder=@[@"频率 Hz",@"频段强弱 dB",@"Q／带宽"][i];field.keyboardType=UIKeyboardTypeNumbersAndPunctuation;}];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"应用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){double values[3],minimum[]={20,-18,.2},maximum[]={20000,18,8};for(int i=0;i<3;i++){NSScanner *scanner=[NSScanner scannerWithString:alert.textFields[i].text];if(![scanner scanDouble:&values[i]]||!scanner.isAtEnd||!std::isfinite(values[i])||values[i]<minimum[i]||values[i]>maximum[i]){DGToast(self,@"请输入范围内的有效数值");return;}}for(int i=0;i<3;i++)[NSUserDefaults.standardUserDefaults setDouble:values[i] forKey:keys[i]];[self changed];}]];[self presentViewController:alert animated:YES completion:nil];}
- (void)presets{UIAlertController *sheet=[UIAlertController alertControllerWithTitle:@"音效预设" message:@"替换十段均衡和听感控制；不改变播放速度。" preferredStyle:UIAlertControllerStyleActionSheet];NSArray *names=@[@"平直原声",@"自然均衡",@"低音强化",@"人声清晰",@"明亮通透",@"空间环绕",@"轻柔耐听"];NSArray *profiles=@[@{},@{@"tone.low":@5,@"clarity":@12,@"transparency":@10,@"bass":@8},@{@"tone.low":@22,@"tone.mid":@(-5),@"bass":@45,@"dynamics":@18,@"clarity":@10},@{@"tone.mid":@15,@"tone.low":@(-10),@"clarity":@42,@"transparency":@24,@"dynamics":@12},@{@"tone.high":@12,@"transparency":@42,@"clarity":@22,@"width":@15,@"room":@10},@{@"width":@60,@"room":@42,@"bass":@15,@"clarity":@15,@"mix":@85},@{@"tone.high":@(-20),@"dynamics":@20,@"transparency":@8}];for(NSUInteger index=0;index<names.count;index++)[sheet addAction:[UIAlertAction actionWithTitle:names[index] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;for(int i=0;i<10;i++){[prefs setDouble:0 forKey:EQKey(@"gain",i)];[prefs setDouble:EQF[i] forKey:EQKey(@"freq",i)];[prefs setDouble:1.1 forKey:EQKey(@"q",i)];}for(NSString *key in @[@"tone.low",@"tone.mid",@"tone.high",@"width",@"room",@"mix",@"transparency",@"clarity",@"dynamics",@"bass"])[prefs setDouble:profiles[index][key]?[profiles[index][key]doubleValue]:[key isEqualToString:@"mix"]?100:0 forKey:[@"douglass.audio." stringByAppendingString:key]];[prefs setBool:NO forKey:@"douglass.eq.adaptive"];if(index==0)[prefs setBool:NO forKey:@"douglass.airpods.enhance"];[self changed];}]];[sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];sheet.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:sheet animated:YES completion:nil];}
@end
UIViewController *DGMakeEQSettings(void){return [DGEqualizer new];}
