#import "DGCommon.h"
@interface DGOptions:UIViewController<UITableViewDataSource,UITableViewDelegate>
@property(nonatomic,strong) DGBridge *bridge;
@property(nonatomic,strong) NSDictionary *work;
@end
@implementation DGOptions{UITableView *_table;DGImage *_cover;UIVisualEffectView *_glass;UILabel *_title;UIButton *_close;}
- (void)viewDidLoad{[super viewDidLoad];self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;self.view.backgroundColor=UIColor.clearColor;_cover=[DGImage new];_cover.contentMode=UIViewContentModeScaleAspectFill;_cover.clipsToBounds=YES;[_cover remote:Text(String(self.work[@"cover"]))];[self.view addSubview:_cover];_glass=Glass(28);[self.view addSubview:_glass];_title=Label(21,UIFontWeightSemibold);_title.text=@"更多选项";[_glass.contentView addSubview:_title];_close=Symbol(@"xmark.circle.fill",self,@selector(close));[_glass.contentView addSubview:_close];_table=[[UITableView alloc]initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];_table.backgroundColor=UIColor.clearColor;_table.dataSource=self;_table.delegate=self;[_glass.contentView addSubview:_table];}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];_cover.frame=self.view.bounds;_glass.frame=self.view.bounds;_title.frame=CGRectMake(24,24,self.view.bounds.size.width-90,34);_close.frame=CGRectMake(self.view.bounds.size.width-62,20,44,44);_table.frame=CGRectMake(0,68,self.view.bounds.size.width,self.view.bounds.size.height-68);}
- (void)viewDidDisappear:(BOOL)animated{[super viewDidDisappear:animated];[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}
- (void)close{[self dismissViewControllerAnimated:YES completion:nil];}
- (void)finish:(void (^)(UIViewController *host))action{UIViewController *host=self.presentingViewController;[self dismissViewControllerAnimated:YES completion:^{if(action)action(host);}];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 4;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?3:section==1?2:section==2?4:3;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return @[@"推荐过滤",@"弹幕",@"当前作品",@"账号与播放"][section];}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{return indexPath.section==1&&indexPath.row==1?76:56;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path{
 UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.backgroundColor=[UIColor colorWithWhite:0 alpha:.15];cell.textLabel.textColor=UIColor.whiteColor;cell.textLabel.font=[UIFont systemFontOfSize:15];cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
 if(path.section==0||path.section==1&&path.row==0||path.section==3&&path.row==0){UISwitch *toggle=[UISwitch new];NSString *key;BOOL value;
  if(path.section==0){key=@[@"douglass.filter.ads",@"douglass.filter.live",@"douglass.filter.seen"][path.row];cell.textLabel.text=@[@"过滤广告",@"过滤直播间",@"过滤已刷视频"][path.row];toggle.tag=path.row;value=path.row==1&&![NSUserDefaults.standardUserDefaults objectForKey:key]?YES:[NSUserDefaults.standardUserDefaults boolForKey:key];}
  else if(path.section==1){key=@"douglass.danmaku";toggle.tag=3;cell.textLabel.text=@"显示弹幕";value=[NSUserDefaults.standardUserDefaults objectForKey:key]?[NSUserDefaults.standardUserDefaults boolForKey:key]:YES;}
  else{key=@"douglass.backgroundAudio";toggle.tag=4;cell.textLabel.text=@"后台音频播放";value=DGBackgroundAudioEnabled();}
  toggle.on=value;[toggle addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;cell.selectionStyle=UITableViewCellSelectionStyleNone;return cell;
 }
 if(path.section==1){double size=[NSUserDefaults.standardUserDefaults doubleForKey:@"douglass.danmaku.size"];if(size<12||size>28)size=14;cell.textLabel.text=[NSString stringWithFormat:@"弹幕大小 · %.0f",size];UISlider *slider=[[UISlider alloc]initWithFrame:CGRectMake(18,39,tableView.bounds.size.width-72,28)];slider.minimumValue=12;slider.maximumValue=28;slider.value=size;slider.autoresizingMask=UIViewAutoresizingFlexibleWidth;[slider addTarget:self action:@selector(fontChanged:) forControlEvents:UIControlEventValueChanged];[cell.contentView addSubview:slider];cell.selectionStyle=UITableViewCellSelectionStyleNone;return cell;}
 if(path.section==2){cell.textLabel.text=@[@"保存当前视频 / 图片",@"保存全部图集",@"下载作品原声",@"复制作品文案"][path.row];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;}
 else{cell.textLabel.text=path.row==1?@"登录 / 安全验证":@"退出当前账号";if(path.row==2)cell.textLabel.textColor=UIColor.systemRedColor;}
 return cell;
}
- (void)changed:(UISwitch *)toggle{NSArray *keys=@[@"douglass.filter.ads",@"douglass.filter.live",@"douglass.filter.seen",@"douglass.danmaku",@"douglass.backgroundAudio"];[NSUserDefaults.standardUserDefaults setBool:toggle.on forKey:keys[toggle.tag]];[NSNotificationCenter.defaultCenter postNotificationName:toggle.tag<3?@"DGFiltersChanged":@"DouGlassSettingsChanged" object:nil];}
- (void)fontChanged:(UISlider *)slider{NSInteger size=lround(slider.value);[NSUserDefaults.standardUserDefaults setDouble:size forKey:@"douglass.danmaku.size"];UITableViewCell *cell=(UITableViewCell *)slider.superview.superview;if([cell isKindOfClass:UITableViewCell.class])cell.textLabel.text=[NSString stringWithFormat:@"弹幕大小 · %ld",(long)size];[NSNotificationCenter.defaultCenter postNotificationName:@"DouGlassSettingsChanged" object:nil];}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path{
 [tableView deselectRowAtIndexPath:path animated:YES];if(path.section==2){NSDictionary *work=self.work;
  if(path.row==0){NSString *image=Text(String(work[@"selectedImage"]));if(!image.length)image=Text(String(Array(work[@"images"]).firstObject));NSString *url=image.length?image:Text(String(work[@"play"]));[self finish:^(UIViewController *host){if(!url.length)DGToast(host,@"当前没有可保存的媒体");else DGSaveURL(host,url,!image.length);}];}
  if(path.row==1){NSArray *urls=Array(work[@"images"]);[self finish:^(UIViewController *host){if(!urls.count){DGToast(host,@"当前作品不是图集");return;}UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"保存全部图集？" message:[NSString stringWithFormat:@"共 %lu 张图片",(unsigned long)urls.count] preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"确认保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){for(NSString *url in urls)DGSaveURL(host,url,NO);}]];[host presentViewController:alert animated:YES completion:nil];}];}
  if(path.row==2)[self finish:^(UIViewController *host){DGSaveAudio(host,Text(String(work[@"music"])),Text(String(work[@"musicTitle"])));}];
  if(path.row==3)[self finish:^(UIViewController *host){DGConfirmCopy(host,Text(String(work[@"caption"])));}];
 }else if(path.section==3&&path.row==1){[self finish:^(UIViewController *host){if([host respondsToSelector:@selector(openLogin)])[host performSelector:@selector(openLogin)];}];}
 else if(path.section==3&&path.row==2){DGBridge *bridge=self.bridge;[self finish:^(UIViewController *host){UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"退出当前账号？" message:@"这会清除本机保存的当前登录信息" preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"退出" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){[bridge signOut:^{[NSNotificationCenter.defaultCenter postNotificationName:@"DGAccountChanged" object:nil];}];}]];[host presentViewController:alert animated:YES completion:nil];}];}
}
@end
UIViewController *DGMakeOptions(DGBridge *bridge,NSDictionary *work){DGOptions *options=[DGOptions new];options.bridge=bridge;options.work=work?:@{};options.modalPresentationStyle=UIModalPresentationPageSheet;options.sheetPresentationController.detents=@[UISheetPresentationControllerDetent.mediumDetent,UISheetPresentationControllerDetent.largeDetent];options.sheetPresentationController.prefersGrabberVisible=YES;options.sheetPresentationController.preferredCornerRadius=30;return options;}

