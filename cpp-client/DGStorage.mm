#import "DGCommon.h"

void DGToast(UIViewController *host, NSString *message) {
    if (!host || !message.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        UILabel *label=Label(13,UIFontWeightMedium);label.text=message;label.numberOfLines=0;label.textAlignment=NSTextAlignmentCenter;
        UIVisualEffectView *glass=Glass(18); [glass.contentView addSubview:label]; [host.view addSubview:glass];
        CGFloat w=MIN(host.view.bounds.size.width-40,360);CGSize size=[label sizeThatFits:CGSizeMake(w-28,150)];
        glass.frame=CGRectMake((host.view.bounds.size.width-w)/2,MAX(90,host.view.bounds.size.height-host.view.safeAreaInsets.bottom-145),w,size.height+28);
        label.frame=CGRectInset(glass.bounds,14,14);glass.alpha=0;
        [UIView animateWithDuration:0.2 animations:^{glass.alpha=1;}];
        [UIView animateWithDuration:0.25 delay:2.8 options:0 animations:^{glass.alpha=0;} completion:^(BOOL done){[glass removeFromSuperview];}];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,message);
    });
}
static NSString *DGExtension(NSData *data, NSURLResponse *response, BOOL video) {
    if(video)return @"mp4";
    NSString *mime=response.MIMEType.lowercaseString;
    if([mime containsString:@"gif"])return @"gif";
    if([mime containsString:@"webp"])return @"webp";
    if([mime containsString:@"png"])return @"png";
    if(data.length>=6 && !memcmp(data.bytes,"GIF8",4))return @"gif";
    return @"jpg";
}
static void DGDownload(NSString *url,void (^completion)(NSData *,NSURLResponse *,NSError *)) {
    NSURL *address=[NSURL URLWithString:url ?: @""];
    if(!address){completion(nil,nil,[NSError errorWithDomain:@"DouGlass" code:1 userInfo:nil]);return;}
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:address cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:60];
    [request setValue:DGUserAgent() forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"https://www.douyin.com/" forHTTPHeaderField:@"Referer"];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        if([response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)response).statusCode>=400) error=[NSError errorWithDomain:@"DouGlass" code:2 userInfo:nil];
        completion(data,response,error);
    }] resume];
}
void DGSaveURL(UIViewController *host,NSString *url,BOOL video) {
    if(video)[[[UIImpactFeedbackGenerator alloc]initWithStyle:UIImpactFeedbackStyleMedium]impactOccurred];
    if(!url.length){DGToast(host,@"该内容没有可保存的地址");return;}
    DGToast(host,video ? @"正在下载视频…" : @"正在保存图片…");
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status){
        if(status!=PHAuthorizationStatusAuthorized && status!=PHAuthorizationStatusLimited){DGToast(host,@"请在系统设置允许添加照片");return;}
        NSURL *address=[NSURL URLWithString:url];if(!address){DGToast(host,@"下载地址无效");return;}
        NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:address cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:120];
        [request setValue:DGUserAgent() forHTTPHeaderField:@"User-Agent"];[request setValue:@"https://www.douyin.com/" forHTTPHeaderField:@"Referer"];
        [[NSURLSession.sharedSession downloadTaskWithRequest:request completionHandler:^(NSURL *download,NSURLResponse *response,NSError *error){
            if(error||!download||([response isKindOfClass:NSHTTPURLResponse.class]&&((NSHTTPURLResponse *)response).statusCode>=400)){DGToast(host,@"下载失败，请稍后重试");return;}
            NSString *name=[NSString stringWithFormat:@"douglass-%@.%@",NSUUID.UUID.UUIDString,DGExtension(nil,response,video)];
            NSURL *file=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
            if(![NSFileManager.defaultManager copyItemAtURL:download toURL:file error:nil]){DGToast(host,@"保存文件失败");return;}
            [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
                PHAssetCreationRequest *asset=[PHAssetCreationRequest creationRequestForAsset];
                [asset addResourceWithType:video?PHAssetResourceTypeVideo:PHAssetResourceTypePhoto fileURL:file options:nil];
            } completionHandler:^(BOOL success,NSError *failure){
                [NSFileManager.defaultManager removeItemAtURL:file error:nil];DGToast(host,success?@"已保存到相册":@"相册保存失败，请稍后重试");
            }];
        }] resume];
    }];
}
static void DGDownloadAudioConfirmed(UIViewController *host,NSString *url,NSString *name) {
    if(!url.length){DGToast(host,@"平台未提供可保存的原声地址");return;}
    DGToast(host,@"正在下载原声…");
    DGDownload(url,^(NSData *data,NSURLResponse *response,NSError *error){
        if(error || !data.length){DGToast(host,@"原声下载失败");return;}
        NSString *extension=[response.MIMEType containsString:@"mpeg"]?@"mp3":@"m4a";
        NSURL *file=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"原声-%@.%@",NSUUID.UUID.UUIDString,extension]]];
        [data writeToURL:file atomically:YES];
        dispatch_async(dispatch_get_main_queue(),^{
            UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
            share.completionWithItemsHandler=^(UIActivityType activity,BOOL completed,NSArray *items,NSError *failure){[NSFileManager.defaultManager removeItemAtURL:file error:nil];};
            share.popoverPresentationController.sourceView=host.view;share.popoverPresentationController.sourceRect=CGRectMake(host.view.bounds.size.width/2,host.view.bounds.size.height/2,1,1);
            [host presentViewController:share animated:YES completion:nil];
        });
    });
}
void DGSaveAudio(UIViewController *host,NSString *url,NSString *name){
    if(!host||host.presentedViewController)return;UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"下载原声？" message:name.length?name:@"下载后可保存到文件或分享" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"确认下载" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){DGDownloadAudioConfirmed(host,url,name);}]];[host presentViewController:alert animated:YES completion:nil];
}
void DGConfirmTextCopy(UIViewController *host,NSString *text,NSString *title,NSString *success){
    if(!host||host.presentedViewController||!text.length)return;NSString *preview=text.length>180?[[text substringToIndex:180]stringByAppendingString:@"…"]:text;UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:preview preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"确认复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){UIPasteboard.generalPasteboard.string=text;DGToast(host,success);}]];[host presentViewController:alert animated:YES completion:nil];
}
void DGConfirmCopy(UIViewController *host,NSString *text){DGConfirmTextCopy(host,text,@"复制作品文案？",@"文案已复制");}
void DGConfirmAvatarSave(UIViewController *host,NSString *url){if(!host||host.presentedViewController||!url.length)return;UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"保存用户头像？" message:@"将这张头像添加到系统相册" preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"确认保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){DGSaveURL(host,url,NO);}]];[host presentViewController:alert animated:YES completion:nil];}
void DGConfirmImageSave(UIViewController *host,NSString *url){if(!host||host.presentedViewController)return;UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"保存评论图片？" message:@"将这张图片或表情包添加到相册" preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"确认保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){DGSaveURL(host,url,NO);}]];[host presentViewController:alert animated:YES completion:nil];}
@interface DGPreview : QLPreviewController <QLPreviewControllerDataSource,QLPreviewControllerDelegate>
@property(nonatomic,strong) NSURL *file;
@property(nonatomic,weak) UIImageView *source;
@end
@implementation DGPreview
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller{return 1;}
- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index{return self.file;}
- (UIView *)previewController:(QLPreviewController *)controller transitionViewForPreviewItem:(id<QLPreviewItem>)item{return self.source;}
- (void)previewControllerDidDismiss:(QLPreviewController *)controller{[NSFileManager.defaultManager removeItemAtURL:self.file error:nil];[NSNotificationCenter.defaultCenter postNotificationName:@"DGResumePlayback" object:nil];}
@end
void DGShowImage(UIViewController *host,NSString *url,UIImageView *source) {
    if(!url.length)return;
    DGDownload(url,^(NSData *data,NSURLResponse *response,NSError *error){
        if(error || !data.length){DGToast(host,@"图片加载失败");return;}
        NSURL *file=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"图片-%@.%@",NSUUID.UUID.UUIDString,DGExtension(data,response,NO)]]];
        [data writeToURL:file atomically:YES];
        dispatch_async(dispatch_get_main_queue(),^{
            DGPreview *preview=[DGPreview new];preview.file=file;preview.source=source;preview.dataSource=preview;preview.delegate=preview;
            UIViewController *presenter=host;while(presenter.parentViewController && ![presenter.parentViewController isKindOfClass:UINavigationController.class])presenter=presenter.parentViewController;
            [presenter presentViewController:preview animated:YES completion:nil];
        });
    });
}

