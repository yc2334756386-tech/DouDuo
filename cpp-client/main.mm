#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreText/CoreText.h>
#import "DGAnimation.h"
#import "DGFeedCache.h"
#import "DGDiagnostics.h"
#import "DGAppearance.h"
#include <cmath>
UIViewController *DGMakeFeedController(void);

@interface DGScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation DGScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.overrideUserInterfaceStyle=DGPreferredStyle();
    self.window.rootViewController = DGMakeFeedController();
    [self.window makeKeyAndVisible];DGRefreshRateApply();
}
@end

@interface DGApplication : UIResponder <UIApplicationDelegate>
@end
@implementation DGApplication
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;
    if(![prefs boolForKey:@"douglass.migration.v07refit"]){
        NSArray *oldPoints=[prefs arrayForKey:@"douglass.animation.points"];
        if(!oldPoints||[oldPoints isEqualToArray:@[@.25,@.1,@.25,@1]])[prefs setObject:@[@.16,@1,@.3,@1] forKey:@"douglass.animation.points"];
        double speed=[prefs doubleForKey:@"douglass.animation.speed"];
        if(![prefs objectForKey:@"douglass.animation.speed"]||fabs(speed-1)<.001||fabs(speed-.9)<.001)[prefs setDouble:.8 forKey:@"douglass.animation.speed"];
        [prefs removeObjectForKey:@"douglass.comments.write"];
        [prefs setBool:YES forKey:@"douglass.migration.v07refit"];
    }
    DGDiagnosticStart();DGRestoreFeedScope();
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
