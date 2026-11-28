#import "DGCommon.h"
#import "DGExperimentalSettings.h"
#import "DGMediaEnhancement.h"
#import "DGAudioEnhancement.h"
#import "DGAnimation.h"
#import "DGMedia.h"

@interface DGExperimentalControlCell:UITableViewCell
@property(nonatomic,strong) UILabel *controlTitle,*controlDetail;
@property(nonatomic,strong) UIStackView *controlStack;
@property(nonatomic,strong) UILabel *effectStatusLabel;
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
- (void)trackMetalFXInCell:(DGExperimentalControlCell *)cell {
 UILabel *label=[UILabel new];
 label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
 label.adjustsFontForContentSizeCategory=YES;
 label.numberOfLines=0;
 label.textColor=UIColor.secondaryLabelColor;
 label.text=DGMetalFXStatusText();
 cell.effectStatusLabel=label;
 [cell.controlStack addArrangedSubview:label];
}
- (void)effectStatusChanged {
 for(UITableViewCell *visible in self.tableView.visibleCells){
  if(![visible isKindOfClass:DGExperimentalControlCell.class])continue;
  DGExperimentalControlCell *cell=(DGExperimentalControlCell *)visible;
  if(cell.effectStatusLabel)cell.effectStatusLabel.text=DGMetalFXStatusText();
 }
}
- (void)close{[self dismissViewControllerAnimated:YES completion:^{[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 3;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?3:section==1?2:8;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return @[@"画面增强",@"音频增强 · 默认关闭",@"八段均衡 · ±12 dB"][section];}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{
 if(section==1)return @"首次开启调音对后续新作品生效，参数调节实时生效。处理不了的音频格式和直播 HLS 保留原声。";
 if(section==2)return @"预设会覆盖八段增益，选好后可逐项调节。";
 return nil;
}
- (DGExperimentalControlCell *)base:(NSString *)title detail:(NSString *)detail{DGExperimentalControlCell *cell=[DGExperimentalControlCell new];cell.controlTitle.text=title;cell.controlDetail.text=detail;cell.controlDetail.hidden=!detail.length;return cell;}
- (UITableViewCell *)toggle:(NSString *)title key:(NSString *)key detail:(NSString *)detail{
 DGExperimentalControlCell *cell=[self base:title detail:detail];
 UISwitch *control=[UISwitch new];control.accessibilityIdentifier=key;
 BOOL available=YES;
 if([key isEqualToString:DGMetalFXKey])available=DGMetalFXSpatialAvailable();
 control.enabled=available;
 NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
 BOOL value=[prefs boolForKey:key];
 if([key isEqualToString:@"douglass.experimental.transitionProtection"])value=DGMetalFXTransitionProtection();
 control.on=available&&value;
 if(!available)cell.controlDetail.text=@"当前设备或系统不支持";
 [control addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
 cell.accessoryView=control;
 if([key isEqualToString:DGMetalFXKey])[self trackMetalFXInCell:cell];
 return cell;
}
- (UITableViewCell *)segments:(NSString *)title key:(NSString *)key items:(NSArray *)items{DGExperimentalControlCell *cell=[self base:title detail:nil];UISegmentedControl *control=[[UISegmentedControl alloc]initWithItems:items];control.apportionsSegmentWidthsByContent=YES;control.accessibilityIdentifier=key;control.selectedSegmentIndex=MIN((NSInteger)items.count-1,MAX(0,[NSUserDefaults.standardUserDefaults integerForKey:key]));[control addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];[cell.controlStack addArrangedSubview:control];[control.heightAnchor constraintGreaterThanOrEqualToConstant:32].active=YES;return cell;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path{
 if(path.section==0){
  if(path.row==0)return [self toggle:@"MetalFX 空间超采样" key:DGMetalFXKey detail:@"开启后将视频解码帧的宽高各放大 2×。"];
  if(path.row==1){DGExperimentalControlCell *cell=(DGExperimentalControlCell *)[self segments:@"画面预设" key:@"douglass.experimental.picturePreset" items:@[@"原始",@"自然",@"柔和",@"鲜明",@"原画增强"]];cell.controlDetail.text=@"原画增强：提高亮度细节的质感与清晰度，保留原有色彩";cell.controlDetail.hidden=NO;return cell;}
  return [self toggle:@"MetalFX 转场保护" key:@"douglass.experimental.transitionProtection" detail:@"滑动换片时提前释放上一条视频的渲染资源。"];
 }

 if(path.section==1){if(path.row==0)return [self toggle:@"启用音频增强" key:@"douglass.experimental.audio" detail:@"八段 C++ IIR，参数平滑与峰值保护"];return [self segments:@"均衡预设" key:@"douglass.experimental.audioPreset" items:@[@"平直",@"人声",@"低音",@"柔和"]];}
 if(path.section==2){NSArray *names=@[@"60 Hz",@"150 Hz",@"400 Hz",@"1 kHz",@"2.4 kHz",@"5 kHz",@"9 kHz",@"14 kHz"];NSString *key=[NSString stringWithFormat:@"douglass.experimental.eq.%ld",(long)path.row];float value=[NSUserDefaults.standardUserDefaults floatForKey:key];DGExperimentalControlCell *cell=[self base:[NSString stringWithFormat:@"%@ · %+.1f dB",names[path.row],value] detail:nil];UISlider *slider=[UISlider new];slider.minimumValue=-12;slider.maximumValue=12;slider.value=value;slider.tag=path.row;slider.accessibilityIdentifier=key;[slider addTarget:self action:@selector(gainChanged:) forControlEvents:UIControlEventValueChanged];[cell.controlStack addArrangedSubview:slider];[slider.heightAnchor constraintGreaterThanOrEqualToConstant:32].active=YES;return cell;}
 return [UITableViewCell new];
}
- (void)toggleChanged:(UISwitch *)control{
 NSString *key=control.accessibilityIdentifier;
 [NSUserDefaults.standardUserDefaults setBool:control.on forKey:key];
 if([key isEqualToString:DGMetalFXKey]){
  [NSNotificationCenter.defaultCenter postNotificationName:@"DGMetalFXSettingsChanged" object:nil];
  DGLogVideoEffectSnapshot();
  [self effectStatusChanged];
 }else if([key isEqualToString:@"douglass.experimental.audio"]){
  DGUpdateAudioControls();
  DGInvalidateAudioPreloads();
  [NSNotificationCenter.defaultCenter postNotificationName:@"DGAudioEnhancementChanged" object:nil];
 }
}
- (void)segmentChanged:(UISegmentedControl *)control{NSString *key=control.accessibilityIdentifier;[NSUserDefaults.standardUserDefaults setInteger:control.selectedSegmentIndex forKey:key];if([key isEqualToString:@"douglass.experimental.picturePreset"]){DGMediaEnhancementApply();return;}if([key isEqualToString:@"douglass.experimental.audioPreset"]){static const float presets[4][8]={{0,0,0,0,0,0,0,0},{-1,-1,0,1.5,2,1,-.5,-1},{3,2,0,-.5,0,.5,0,-.5},{0,0,.5,.5,0,-1,-2,-2}};for(unsigned i=0;i<8;++i)[NSUserDefaults.standardUserDefaults setFloat:presets[control.selectedSegmentIndex][i] forKey:[NSString stringWithFormat:@"douglass.experimental.eq.%u",i]];[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];}DGUpdateAudioControls();}
- (void)gainChanged:(UISlider *)slider{[NSUserDefaults.standardUserDefaults setFloat:slider.value forKey:slider.accessibilityIdentifier];DGUpdateAudioControls();for(UIView *view=slider.superview;view;view=view.superview)if([view isKindOfClass:DGExperimentalControlCell.class]){DGExperimentalControlCell *cell=(DGExperimentalControlCell *)view;NSString *name=[cell.controlTitle.text componentsSeparatedByString:@" · "].firstObject;cell.controlTitle.text=[NSString stringWithFormat:@"%@ · %+.1f dB",name,slider.value];break;}}
@end
UIViewController *DGMakeExperimentalSettings(void){return [[DGExperimentalSettings alloc]initWithStyle:UITableViewStyleInsetGrouped];}
BOOL DGIsExperimentalSettings(UIViewController *controller){if([controller isKindOfClass:DGExperimentalSettings.class])return YES;if([controller isKindOfClass:UINavigationController.class])return [((UINavigationController *)controller).topViewController isKindOfClass:DGExperimentalSettings.class];return NO;}
