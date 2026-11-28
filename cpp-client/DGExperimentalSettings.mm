#import "DGCommon.h"
#import "DGExperimentalSettings.h"
#import "DGMediaEnhancement.h"
#import "DGAudioEnhancement.h"
#import "DGAnimation.h"
#import "DGMedia.h"
#import "DGVideoEffects.h"
#import "DGRife.h"

@interface DGExperimentalControlCell:UITableViewCell
@property(nonatomic,strong) UILabel *controlTitle,*controlDetail;
@property(nonatomic,strong) UIStackView *controlStack;
@property(nonatomic,strong) UILabel *effectStatusLabel;
@property(nonatomic) DGVideoEffect trackedEffect;
@end
@implementation DGExperimentalControlCell
- (instancetype)init{
 if((self=[super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil])){
  self.selectionStyle=UITableViewCellSelectionStyleNone;
  _controlTitle=[UILabel new];_controlTitle.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];_controlTitle.adjustsFontForContentSizeCategory=YES;_controlTitle.numberOfLines=0;
  _controlDetail=[UILabel new];_controlDetail.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];_controlDetail.adjustsFontForContentSizeCategory=YES;_controlDetail.textColor=UIColor.secondaryLabelColor;_controlDetail.numberOfLines=0;
  UIStackView *text=[[UIStackView alloc]initWithArrangedSubviews:@[_controlTitle,_controlDetail]];text.axis=UILayoutConstraintAxisVertical;text.spacing=4;
  _controlStack=[[UIStackView alloc]initWithArrangedSubviews:@[text]];_controlStack.axis=UILayoutConstraintAxisVertical;_controlStack.spacing=12;_controlStack.translatesAutoresizingMaskIntoConstraints=NO;
  [self.contentView addSubview:_controlStack];UILayoutGuide *margins=self.contentView.layoutMarginsGuide;
  [NSLayoutConstraint activateConstraints:@[[_controlStack.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],[_controlStack.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],[_controlStack.topAnchor constraintEqualToAnchor:margins.topAnchor constant:6],[_controlStack.bottomAnchor constraintEqualToAnchor:margins.bottomAnchor constant:-6]]];
 }return self;
}
@end

@interface DGExperimentalSettings:UITableViewController
@end
@implementation DGExperimentalSettings
- (void)viewDidLoad{[super viewDidLoad];self.title=@"画面与音频实验室";self.tableView.backgroundColor=UIColor.systemGroupedBackgroundColor;self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=92;self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(effectStatusChanged) name:DGVideoEffectStatusChanged object:nil];}
- (void)trackEffect:(DGVideoEffect)effect inCell:(DGExperimentalControlCell *)cell {
 UILabel *label=[UILabel new];
 label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
 label.adjustsFontForContentSizeCategory=YES;
 label.numberOfLines=0;
 label.textColor=UIColor.secondaryLabelColor;
 label.text=DGVideoEffectStatusText(effect);
 cell.effectStatusLabel=label;
 cell.trackedEffect=effect;
 [cell.controlStack addArrangedSubview:label];
}
- (void)effectStatusChanged {
 for(UITableViewCell *visible in self.tableView.visibleCells){
  if(![visible isKindOfClass:DGExperimentalControlCell.class])continue;
  DGExperimentalControlCell *cell=(DGExperimentalControlCell *)visible;
  if(cell.effectStatusLabel)cell.effectStatusLabel.text=DGVideoEffectStatusText(cell.trackedEffect);
 }
}
- (void)close{[self dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 4;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?7:section==1?2:section==2?8:1;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return @[@"画面增强 · 默认关闭",@"音频增强 · 默认关闭",@"八段均衡 · ±12 dB",@"实现与限制"][section];}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{return section==0?@"MetalFX 为单帧空间放大，不生成原片没有的真实细节。最高 1.5×、长边不超过 1920；高温时旁路。画面预设独立于音频。":section==1?@"首次开启调音对后续新作品生效，参数调节实时生效。处理不了的音频格式和直播 HLS 保留原声；不切换音频会话。":section==2?@"预设会覆盖八段增益，选好后可逐项调节。低延迟 IIR，无频谱可视化持续刷新。":@"AutoEq 用于生成耳机校正参数；本版没有冒用通用耳机校正。OctaEQ 仅作设计参考，不移植 VST3 或 GPL 源码。处理核心为本项目 C++，系统框架由 Objective-C++ 适配。";}
- (DGExperimentalControlCell *)base:(NSString *)title detail:(NSString *)detail{DGExperimentalControlCell *cell=[DGExperimentalControlCell new];cell.controlTitle.text=title;cell.controlDetail.text=detail;cell.controlDetail.hidden=!detail.length;return cell;}
- (UITableViewCell *)toggle:(NSString *)title key:(NSString *)key detail:(NSString *)detail{
 DGExperimentalControlCell *cell=[self base:title detail:detail];
 UISwitch *control=[UISwitch new];control.accessibilityIdentifier=key;
 BOOL available=YES;
 if([key isEqualToString:@"douglass.experimental.metalfx"])available=DGMetalFXSpatialAvailable();
 if([key isEqualToString:@"douglass.experimental.vtSuperResolution"])available=DGVTSuperResolutionAvailable();
 control.enabled=available;
 NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
 BOOL value=[prefs boolForKey:key];
 if([key isEqualToString:@"douglass.experimental.transitionProtection"])value=DGSuperResolutionTransitionProtection();
 if([key isEqualToString:DGInterpolationProtectionKey])value=DGInterpolationTransitionProtection();
 control.on=available&&value;
 if(!available)cell.controlDetail.text=@"当前设备或系统不支持";
 [control addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
 cell.accessoryView=control;
 if([key isEqualToString:@"douglass.experimental.metalfx"])[self trackEffect:DGVideoEffectMetalFX inCell:cell];
 if([key isEqualToString:@"douglass.experimental.vtSuperResolution"])[self trackEffect:DGVideoEffectSuperResolution inCell:cell];
 return cell;
}
- (UITableViewCell *)segments:(NSString *)title key:(NSString *)key items:(NSArray *)items{DGExperimentalControlCell *cell=[self base:title detail:nil];UISegmentedControl *control=[[UISegmentedControl alloc]initWithItems:items];control.apportionsSegmentWidthsByContent=YES;control.accessibilityIdentifier=key;control.selectedSegmentIndex=MIN((NSInteger)items.count-1,MAX(0,[NSUserDefaults.standardUserDefaults integerForKey:key]));[control addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];[cell.controlStack addArrangedSubview:control];[control.heightAnchor constraintGreaterThanOrEqualToConstant:32].active=YES;return cell;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path{
 if(path.section==0){if(path.row==0)return [self toggle:@"MetalFX 空间超采样" key:@"douglass.experimental.metalfx" detail:@"仅处理画面，保持原比例与原视频时间线"];if(path.row==1){DGExperimentalControlCell *cell=(DGExperimentalControlCell *)[self segments:@"画面预设" key:@"douglass.experimental.picturePreset" items:@[@"原始",@"自然",@"柔和",@"鲜明",@"原画增强"]];cell.controlDetail.text=@"原画增强：提高亮度细节的质感与清晰度，保留原有色彩";cell.controlDetail.hidden=NO;return cell;}
  if(path.row==2){
   DGExperimentalControlCell *cell=[self base:@"插帧方式" detail:nil];
   UISegmentedControl *control=[[UISegmentedControl alloc]initWithItems:@[@"关闭",@"低延迟",@"RIFE 4.25"]];
   control.selectedSegmentIndex=DGRifeRequested()?2:[NSUserDefaults.standardUserDefaults boolForKey:@"douglass.experimental.frameInterpolation"]?1:0;
   [control setEnabled:DGRifeAvailable() forSegmentAtIndex:2];
   [control addTarget:self action:@selector(interpolationChanged:) forControlEvents:UIControlEventValueChanged];
   [cell.controlStack addArrangedSubview:control];
   [control.heightAnchor constraintGreaterThanOrEqualToConstant:32].active=YES;
   cell.controlDetail.hidden=NO;
   if(control.selectedSegmentIndex==2)cell.controlDetail.text=@"实验模式。由 Core ML 检查 ANE 分配，超时回到原帧。";
   else cell.controlDetail.text=DGVTFSystemInterpolationAvailable()?@"低延迟优先使用系统插帧。":@"低延迟使用兼容插帧，快速运动时可能出现残影。";
   [self trackEffect:DGVideoEffectInterpolation inCell:cell];
   return cell;
  }
  if(path.row==3){
   DGExperimentalControlCell *cell=[self base:@"插帧倍率" detail:@"低延迟模式的 3× 使用兼容插帧。刷新率或处理性能不足时自动降至 2×。"];
   UISegmentedControl *control=[[UISegmentedControl alloc]initWithItems:@[@"2×",@"3×",@"4×"]];
   control.accessibilityIdentifier=DGInterpolationMultiplierKey;
   control.selectedSegmentIndex=DGInterpolationMultiplier()-2;
   [control addTarget:self action:@selector(interpolationMultiplierChanged:) forControlEvents:UIControlEventValueChanged];
   [cell.controlStack addArrangedSubview:control];
   [control.heightAnchor constraintGreaterThanOrEqualToConstant:32].active=YES;
   return cell;
  }
  if(path.row==4)return [self toggle:@"插帧转场保护" key:DGInterpolationProtectionKey detail:@"切换作品时释放插帧资源。视频内快切和快运镜时暂用原始帧。"];
  if(path.row==5)return [self toggle:@"低延迟超分" key:@"douglass.experimental.vtSuperResolution" detail:@"对支持的视频尺寸进行实时放大，与 MetalFX 二选一"];
  return [self toggle:@"超分转场保护" key:@"douglass.experimental.transitionProtection" detail:@"滑动换片时提前释放超分资源。新作品有可处理的帧就启动超分。"];
 }

 if(path.section==1){if(path.row==0)return [self toggle:@"启用音频增强" key:@"douglass.experimental.audio" detail:@"八段 C++ IIR，参数平滑与峰值保护"];return [self segments:@"均衡预设" key:@"douglass.experimental.audioPreset" items:@[@"平直",@"人声",@"低音",@"柔和"]];}
 if(path.section==2){NSArray *names=@[@"60 Hz",@"150 Hz",@"400 Hz",@"1 kHz",@"2.4 kHz",@"5 kHz",@"9 kHz",@"14 kHz"];NSString *key=[NSString stringWithFormat:@"douglass.experimental.eq.%ld",(long)path.row];float value=[NSUserDefaults.standardUserDefaults floatForKey:key];DGExperimentalControlCell *cell=[self base:[NSString stringWithFormat:@"%@ · %+.1f dB",names[path.row],value] detail:nil];UISlider *slider=[UISlider new];slider.minimumValue=-12;slider.maximumValue=12;slider.value=value;slider.tag=path.row;slider.accessibilityIdentifier=key;[slider addTarget:self action:@selector(gainChanged:) forControlEvents:UIControlEventValueChanged];[cell.controlStack addArrangedSubview:slider];[slider.heightAnchor constraintGreaterThanOrEqualToConstant:32].active=YES;return cell;}
 return [self base:@"系统能力检测" detail:DGMediaEnhancementStatus()];
}
- (void)interpolationChanged:(UISegmentedControl *)control {
 NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
 [prefs setInteger:control.selectedSegmentIndex forKey:@"douglass.experimental.interpolationBackend"];
 [prefs setBool:control.selectedSegmentIndex==1 forKey:@"douglass.experimental.frameInterpolation"];
 [NSNotificationCenter.defaultCenter postNotificationName:@"DGVideoEffectsChanged" object:nil];
 DGLogVideoEffectSnapshot();
 [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)interpolationMultiplierChanged:(UISegmentedControl *)control {
 [NSUserDefaults.standardUserDefaults setInteger:control.selectedSegmentIndex+2 forKey:DGInterpolationMultiplierKey];
 [NSNotificationCenter.defaultCenter postNotificationName:@"DGVideoEffectsChanged" object:nil];
 DGLogVideoEffectSnapshot();
}
- (void)toggleChanged:(UISwitch *)control{NSString *key=control.accessibilityIdentifier;[NSUserDefaults.standardUserDefaults setBool:control.on forKey:key];if([key isEqualToString:@"douglass.experimental.transitionProtection"]||[key isEqualToString:DGInterpolationProtectionKey]){
 [NSNotificationCenter.defaultCenter postNotificationName:@"DGVideoEffectsChanged" object:nil];return;
}
if([key isEqualToString:@"douglass.experimental.metalfx"]||[key isEqualToString:@"douglass.experimental.vtSuperResolution"]){
 if(control.on){
  NSString *other=[key isEqualToString:@"douglass.experimental.metalfx"]?@"douglass.experimental.vtSuperResolution":@"douglass.experimental.metalfx";
  [NSUserDefaults.standardUserDefaults setBool:NO forKey:other];
 }
 DGMediaEnhancementApply();
 DGLogVideoEffectSnapshot();
 [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
}else{DGUpdateAudioControls();if([key isEqualToString:@"douglass.experimental.audio"]){DGInvalidateAudioPreloads();[NSNotificationCenter.defaultCenter postNotificationName:@"DGAudioEnhancementChanged" object:nil];}}}
- (void)segmentChanged:(UISegmentedControl *)control{NSString *key=control.accessibilityIdentifier;[NSUserDefaults.standardUserDefaults setInteger:control.selectedSegmentIndex forKey:key];if([key isEqualToString:@"douglass.experimental.picturePreset"]){DGMediaEnhancementApply();return;}if([key isEqualToString:@"douglass.experimental.audioPreset"]){static const float presets[4][8]={{0,0,0,0,0,0,0,0},{-1,-1,0,1.5,2,1,-.5,-1},{3,2,0,-.5,0,.5,0,-.5},{0,0,.5,.5,0,-1,-2,-2}};for(unsigned i=0;i<8;++i)[NSUserDefaults.standardUserDefaults setFloat:presets[control.selectedSegmentIndex][i] forKey:[NSString stringWithFormat:@"douglass.experimental.eq.%u",i]];[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];}DGUpdateAudioControls();}
- (void)gainChanged:(UISlider *)slider{[NSUserDefaults.standardUserDefaults setFloat:slider.value forKey:slider.accessibilityIdentifier];DGUpdateAudioControls();for(UIView *view=slider.superview;view;view=view.superview)if([view isKindOfClass:DGExperimentalControlCell.class]){DGExperimentalControlCell *cell=(DGExperimentalControlCell *)view;NSString *name=[cell.controlTitle.text componentsSeparatedByString:@" · "].firstObject;cell.controlTitle.text=[NSString stringWithFormat:@"%@ · %+.1f dB",name,slider.value];break;}}
@end
UIViewController *DGMakeExperimentalSettings(void){return [[DGExperimentalSettings alloc]initWithStyle:UITableViewStyleInsetGrouped];}
BOOL DGIsExperimentalSettings(UIViewController *controller){if([controller isKindOfClass:DGExperimentalSettings.class])return YES;if([controller isKindOfClass:UINavigationController.class])return [((UINavigationController *)controller).topViewController isKindOfClass:DGExperimentalSettings.class];return NO;}
