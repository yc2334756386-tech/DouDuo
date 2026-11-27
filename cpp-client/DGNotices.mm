#import "DGCommon.h"
#import "DGInboxCache.h"
#import "DGFeedCache.h"
@interface DGNotices:UIViewController<UITableViewDataSource,UITableViewDelegate>
@property(nonatomic,strong) DGBridge *bridge;
@property(nonatomic) NSInteger initialGroup;
@end
@implementation DGNotices{UITableView *_table;UISegmentedControl *_filter;NSMutableArray *_items;NSMutableSet *_ids;NSString *_cursor;UILabel *_empty;UIButton *_footer;BOOL _loading,_more,_opening,_refreshTop;NSUInteger _generation;NSInteger _loadedGroup;}
- (void)viewDidLoad{[super viewDidLoad];self.title=@"互动消息";self.view.backgroundColor=UIColor.systemBackgroundColor;_items=[NSMutableArray array];_ids=[NSMutableSet set];_cursor=@"0";_more=YES;_filter=[[UISegmentedControl alloc]initWithItems:@[@"全部",@"评论",@"赞",@"@我",@"粉丝"]];_filter.selectedSegmentIndex=self.initialGroup;[_filter addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];[self.view addSubview:_filter];_table=[[UITableView alloc]initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];_table.backgroundColor=UIColor.clearColor;_table.dataSource=self;_table.delegate=self;_table.rowHeight=UITableViewAutomaticDimension;_table.estimatedRowHeight=104;[self.view addSubview:_table];_empty=Label(14,UIFontWeightRegular);_empty.textAlignment=NSTextAlignmentCenter;_empty.textColor=UIColor.secondaryLabelColor;_empty.numberOfLines=0;_table.backgroundView=_empty;_footer=[UIButton buttonWithType:UIButtonTypeSystem];_footer.frame=CGRectMake(0,0,320,60);[_footer addTarget:self action:@selector(load) forControlEvents:UIControlEventTouchUpInside];_table.tableFooterView=_footer;self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];[self restoreCache];[self load];}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];CGFloat top=self.view.safeAreaInsets.top;_filter.frame=CGRectMake(16,top+10,self.view.bounds.size.width-32,34);_table.frame=CGRectMake(0,top+52,self.view.bounds.size.width,self.view.bounds.size.height-top-52);}
- (NSString *)cacheKey{return [NSString stringWithFormat:@"notices:%ld",(long)_filter.selectedSegmentIndex];}
- (void)restoreCache{
 _loadedGroup=_filter.selectedSegmentIndex;_items=[DGMergeInboxRows(@[],Array(DGReadInboxCache([self cacheKey])[@"items"]),YES,300)mutableCopy];[_ids removeAllObjects];for(NSDictionary *item in _items)[_ids addObject:Text(String(item[@"id"]))];_refreshTop=YES;_cursor=@"0";_more=YES;_empty.text=_items.count?@"":@"正在同步互动消息…";[_table reloadData];
}
- (void)refresh{++_generation;_loading=NO;_more=YES;_cursor=@"0";_refreshTop=YES;if(_loadedGroup!=_filter.selectedSegmentIndex)[self restoreCache];[self load];}
- (void)load{
 if(_loading||!_more)return;_loading=YES;_footer.enabled=NO;[_footer setTitle:_items.count?@"正在检查新消息…":@"正在读取…" forState:UIControlStateNormal];
 NSUInteger generation=_generation;NSString *cursor=_cursor,*scope=DGCurrentFeedScope();BOOL refreshTop=_refreshTop;NSNumber *group=@[@700,@2,@3,@6,@401][_filter.selectedSegmentIndex];__weak DGNotices *weak=self;
 [_bridge request:@"notices" parameters:@{@"group":group,@"cursor":cursor,@"markRead":@YES} completion:^(NSDictionary *result,NSString *error){
  DGNotices *self=weak;if(!self||generation!=self->_generation)return;self->_loading=NO;self->_footer.enabled=YES;if(![scope isEqual:DGCurrentFeedScope()])return;
  if(error){if(!self->_items.count)self->_empty.text=error;[self->_footer setTitle:@"更新失败，点此重试" forState:UIControlStateNormal];return;}
  DGInboxMarkNoticesRead(group.integerValue);
  NSArray *previous=self->_items.copy,*incoming=Array(result[@"items"]);
  NSArray *merged=DGMergeInboxRows(previous,incoming,refreshTop,NSUIntegerMax);self->_items=merged.mutableCopy;
  [self->_ids removeAllObjects];for(NSDictionary *item in merged)[self->_ids addObject:Text(String(item[@"id"]))];
  self->_refreshTop=NO;self->_cursor=Text(String(result[@"cursor"]));self->_more=[result[@"more"]boolValue]&&![cursor isEqualToString:self->_cursor];self->_empty.text=merged.count?@"":@"暂时没有互动消息";
  [self->_footer setTitle:self->_more?@"继续加载":@"已显示当前可读取的互动消息" forState:UIControlStateNormal];
  if(![previous isEqual:merged]){NSArray *cached=[merged subarrayWithRange:NSMakeRange(0,MIN((NSUInteger)300,merged.count))];DGWriteInboxCache([self cacheKey],@{@"items":cached});DGReloadInboxRows(self->_table,previous,merged);}
 }];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return _items.count;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path{NSDictionary *item=_items[path.row];UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];cell.textLabel.numberOfLines=2;cell.textLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];cell.detailTextLabel.numberOfLines=0;cell.detailTextLabel.font=[UIFont systemFontOfSize:13];cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;cell.textLabel.text=[NSString stringWithFormat:@"%@ · %@",Text(String(item[@"name"])),Text(String(item[@"action"]))];NSDateFormatter *format=[NSDateFormatter new];format.dateFormat=@"MM-dd HH:mm";NSString *date=Number(item[@"time"])>0?[format stringFromDate:[NSDate dateWithTimeIntervalSince1970:Number(item[@"time"])]]:@"";cell.detailTextLabel.text=[NSString stringWithFormat:@"%@\n%@",Text(String(item[@"detail"])),date];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
 [table deselectRowAtIndexPath:path animated:YES];if(_opening||path.row>=(NSInteger)_items.count)return;
 NSDictionary *item=_items[path.row];NSString *identifier=Text(String(item[@"workID"]));
 if(!identifier.length){
  NSInteger type=Number(item[@"type"]);NSString *sec=Text(String(item[@"authorID"]));
  if((type==33||type==98)&&sec.length)[self.navigationController pushViewController:DGMakeProfile(_bridge,sec,Text(String(item[@"name"])),@"") animated:YES];
  else DGToast(self,@"这条消息未提供可定位的作品");return;
 }
 _opening=YES;__weak DGNotices *weak=self;
 [_bridge request:@"detail" parameters:@{@"id":identifier} completion:^(NSDictionary *result,NSString *error){
  DGNotices *self=weak;if(!self)return;self->_opening=NO;if(self.navigationController.topViewController!=self)return;
  NSArray *works=Array(result[@"items"]);if(error||!works.count){DGToast(self,error?:@"该作品暂不可查看");return;}
  DGMusicStop();UIViewController *player=DGMakeNoticePlayer(works,self.bridge,Text(String(item[@"commentID"])),Text(String(item[@"parentID"])));
  [self.navigationController pushViewController:player animated:YES];
 }];
}
- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path{if(path.row+3>=(NSInteger)_items.count&&_more&&!_loading)[self load];}
@end
UIViewController *DGMakeNotices(DGBridge *bridge){DGNotices *view=[DGNotices new];view.bridge=bridge;return view;}


UIViewController *DGMakeNoticesGroup(DGBridge *bridge,NSInteger group){DGNotices *page=[DGNotices new];page.bridge=bridge;page.initialGroup=group;return page;}
