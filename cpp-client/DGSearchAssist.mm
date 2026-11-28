#import "DGSearchAssist.h"
static NSString *const DGSearchHistoryKey=@"douglass.searchHistory.v1";
@interface DGSearchAssist()<UITableViewDataSource,UITableViewDelegate>
@end
@implementation DGSearchAssist{
 DGBridge *_bridge;UITableView *_table;UIView *_header;UILabel *_title,*_empty;UIButton *_clear;NSArray<NSString *> *_words;NSString *_keyword;NSUInteger _generation;
}
- (instancetype)initWithBridge:(DGBridge *)bridge{
 if((self=[super initWithFrame:CGRectZero])){_bridge=bridge;self.backgroundColor=UIColor.systemBackgroundColor;_table=[[UITableView alloc]initWithFrame:self.bounds style:UITableViewStylePlain];_table.backgroundColor=UIColor.clearColor;_table.dataSource=self;_table.delegate=self;_table.rowHeight=54;_table.keyboardDismissMode=UIScrollViewKeyboardDismissModeNone;_table.separatorColor=UIColor.separatorColor;_table.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;[self addSubview:_table];
 _header=[[UIView alloc]initWithFrame:CGRectMake(0,0,320,42)];_title=Label(13,UIFontWeightSemibold);_title.textColor=UIColor.secondaryLabelColor;[_header addSubview:_title];_clear=[UIButton buttonWithType:UIButtonTypeSystem];[_clear setTitle:@"清空历史" forState:UIControlStateNormal];_clear.titleLabel.font=[UIFont systemFontOfSize:12];[_clear addTarget:self action:@selector(clearHistory) forControlEvents:UIControlEventTouchUpInside];[_header addSubview:_clear];_table.tableHeaderView=_header;_empty=Label(13,UIFontWeightRegular);_empty.textColor=UIColor.secondaryLabelColor;_empty.textAlignment=NSTextAlignmentCenter;_table.backgroundView=_empty;[self keyword:@""];
 }return self;
}
- (void)layoutSubviews{[super layoutSubviews];_table.frame=self.bounds;_header.frame=CGRectMake(0,0,self.bounds.size.width,42);_title.frame=CGRectMake(20,6,self.bounds.size.width-130,30);_clear.frame=CGRectMake(self.bounds.size.width-102,3,86,36);}
- (NSArray<NSString *> *)history{NSMutableArray *valid=[NSMutableArray array];for(id word in Array([NSUserDefaults.standardUserDefaults objectForKey:DGSearchHistoryKey]))if([word isKindOfClass:NSString.class]&&[word length])[valid addObject:word];return valid;}
- (void)remember:(NSString *)keyword{if(!keyword.length)return;NSMutableArray *history=[[self history]mutableCopy];[history removeObject:keyword];[history insertObject:keyword atIndex:0];if(history.count>30)[history removeObjectsInRange:NSMakeRange(30,history.count-30)];[NSUserDefaults.standardUserDefaults setObject:history forKey:DGSearchHistoryKey];}
- (void)clearHistory{[NSUserDefaults.standardUserDefaults removeObjectForKey:DGSearchHistoryKey];[self keyword:@""];}
- (void)deleteHistoryWord:(NSString *)word{
 if(_keyword.length||!word.length)return;NSMutableArray *history=[[self history]mutableCopy];[history removeObject:word];[NSUserDefaults.standardUserDefaults setObject:history forKey:DGSearchHistoryKey];[self keyword:@""];
}
- (void)deleteWord:(UIButton *)button{if(button.tag>=0&&button.tag<(NSInteger)_words.count)[self deleteHistoryWord:_words[button.tag]];}
- (void)keyword:(NSString *)keyword{
 _keyword=[keyword stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]?:@"";NSUInteger generation=++_generation;_clear.hidden=_keyword.length>0;_title.text=_keyword.length?@"搜索联想":@"搜索历史";_words=_keyword.length?@[]:[self history];_empty.text=_words.count?@"":_keyword.length?@"正在读取联想词…":@"还没有搜索历史";[_table reloadData];if(!_keyword.length)return;
 NSString *query=_keyword.copy;__weak DGSearchAssist *weak=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{DGSearchAssist *self=weak;if(!self||generation!=self->_generation)return;[self->_bridge request:@"suggest" parameters:@{@"kw":query} completion:^(NSDictionary *result,NSString *error){DGSearchAssist *self=weak;if(!self||generation!=self->_generation)return;NSMutableArray *words=[NSMutableArray array];NSMutableSet *seen=[NSMutableSet set];for(NSDictionary *record in Array(result[@"items"])){NSString *word=Text(String(record[@"word"]));if(word.length&&![seen containsObject:word]){[seen addObject:word];[words addObject:word];if(words.count>=15)break;}}self->_words=words;self->_empty.text=words.count?@"":@"暂无联想，按搜索键提交当前关键词";[self->_table reloadData];}];});
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section{return _words.count;}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path{
 UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];cell.backgroundColor=UIColor.clearColor;cell.textLabel.font=[UIFont systemFontOfSize:16];cell.imageView.image=[UIImage systemImageNamed:_keyword.length?@"magnifyingglass":@"clock"];cell.imageView.tintColor=UIColor.tertiaryLabelColor;NSString *word=_words[path.row];NSMutableAttributedString *text=[[NSMutableAttributedString alloc]initWithString:word attributes:@{NSForegroundColorAttributeName:UIColor.labelColor}];if(_keyword.length){NSRange range=[word rangeOfString:_keyword options:NSCaseInsensitiveSearch];if(range.location!=NSNotFound)[text addAttribute:NSForegroundColorAttributeName value:UIColor.systemPinkColor range:range];}cell.textLabel.attributedText=text;UIButton *accessory=Symbol(_keyword.length?@"arrow.up.left":@"xmark",self,_keyword.length?@selector(fillWord:):@selector(deleteWord:));accessory.tintColor=UIColor.tertiaryLabelColor;accessory.tag=path.row;accessory.frame=CGRectMake(0,0,40,44);accessory.accessibilityLabel=_keyword.length?@"填入搜索框":[@"删除搜索历史：" stringByAppendingString:word];cell.accessoryView=accessory;return cell;
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path{
 if(_keyword.length||path.row>=(NSInteger)_words.count)return nil;NSString *word=_words[path.row];__weak DGSearchAssist *weak=self;
 UIContextualAction *remove=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *action,UIView *source,void(^done)(BOOL)){[weak deleteHistoryWord:word];done(YES);}];return [UISwipeActionsConfiguration configurationWithActions:@[remove]];
}
- (void)fillWord:(UIButton *)button{if(button.tag<(NSInteger)_words.count&&self.fill)self.fill(_words[button.tag]);}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path{[table deselectRowAtIndexPath:path animated:YES];if(path.row<(NSInteger)_words.count&&self.selected)self.selected(_words[path.row]);}
@end
