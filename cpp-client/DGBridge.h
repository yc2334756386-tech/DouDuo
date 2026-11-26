#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN
typedef void (^DGResult)(NSDictionary * _Nullable result, NSString * _Nullable error);
FOUNDATION_EXPORT NSString *DGUserAgent(void);
@interface DGBridge : NSObject <WKNavigationDelegate>
@property(nonatomic, readonly) WKWebView *web;
- (void)mount:(UIView *)host;
- (void)reload;
- (void)request:(NSString *)operation parameters:(NSDictionary *)parameters completion:(DGResult)completion;
- (void)signOut:(void (^)(void))completion;
@end
NS_ASSUME_NONNULL_END
