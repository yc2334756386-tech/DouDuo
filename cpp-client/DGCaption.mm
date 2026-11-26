#import "DGCommon.h"
@interface DGFullCaption:UIViewController
@property(nonatomic,copy) NSString *text;
@end
@implementation DGFullCaption
- (void)viewDidLoad{[super viewDidLoad];self.view.backgroundColor=UIColor.secondarySystemBackgroundColor;self.title=@"作品文案";UITextView *text=[[UITextView alloc]initWithFrame:self.view.bounds];text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;text.editable=NO;text.selectable=YES;text.backgroundColor=UIColor.clearColor;text.font=[UIFont systemFontOfSize:17];text.textColor=UIColor.labelColor;text.text=self.text;text.textContainerInset=UIEdgeInsetsMake(24,18,40,18);[self.view addSubview:text];self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)];}
- (void)close{[self dismissViewControllerAnimated:YES completion:nil];}
@end
void DGShowFullCaption(UIViewController *host,NSString *text){if(!host||host.presentedViewController)return;DGFullCaption *caption=[DGFullCaption new];caption.text=text;DGNavigationController *nav=[[DGNavigationController alloc]initWithRootViewController:caption];nav.sheetPresentationController.detents=@[UISheetPresentationControllerDetent.mediumDetent,UISheetPresentationControllerDetent.largeDetent];nav.sheetPresentationController.prefersGrabberVisible=YES;[host presentViewController:nav animated:YES completion:nil];}

