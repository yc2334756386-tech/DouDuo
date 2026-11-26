#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreText/CoreText.h>
#include <cmath>
#import "DGAnimation.h"
UIViewController *DGMakeFeedController(void);

@interface DGScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation DGScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = DGMakeFeedController();
    [self.window makeKeyAndVisible];DGRefreshRateApply();
}
@end

@interface DGApplication : UIResponder <UIApplicationDelegate>
@end
@implementation DGApplication
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;if(![defaults boolForKey:@"douglass.migration.09"]){NSArray *points=[defaults arrayForKey:@"douglass.animation.points"];if(!points||[points isEqualToArray:@[@.25,@.1,@.25,@1]])[defaults setObject:@[@.16,@1,@.3,@1] forKey:@"douglass.animation.points"];if(![defaults objectForKey:@"douglass.animation.speed"]||fabs([defaults doubleForKey:@"douglass.animation.speed"]-1)<.001)[defaults setDouble:.9 forKey:@"douglass.animation.speed"];[defaults setBool:YES forKey:@"douglass.migration.09"];}
    [NSURLCache setSharedURLCache:[[NSURLCache alloc] initWithMemoryCapacity:12*1024*1024 diskCapacity:256*1024*1024 diskPath:@"douglass-images"]];
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeMoviePlayback options:0 error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    NSURL *fontDirectory=[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"Fonts"];for(NSURL *file in [NSFileManager.defaultManager contentsOfDirectoryAtURL:fontDirectory includingPropertiesForKeys:nil options:0 error:nil])CTFontManagerRegisterFontsForURL((__bridge CFURLRef)file,kCTFontManagerScopeProcess,NULL);return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
    configuration.delegateClass = DGScene.class;
    return configuration;
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(DGApplication.class)); }
}
