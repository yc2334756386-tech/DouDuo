#import "DGAppearance.h"
UIUserInterfaceStyle DGPreferredStyle(void) {
 switch([NSUserDefaults.standardUserDefaults integerForKey:@"douglass.appearance"]){
  case 1:return UIUserInterfaceStyleLight;
  case 2:return UIUserInterfaceStyleUnspecified;
  default:return UIUserInterfaceStyleDark;
 }
}
static void DGUpdateStatusAppearance(UIViewController *controller){
 if(!controller)return;[controller setNeedsStatusBarAppearanceUpdate];
 for(UIViewController *child in controller.childViewControllers)DGUpdateStatusAppearance(child);
 DGUpdateStatusAppearance(controller.presentedViewController);
}
void DGApplyAppearance(void) {
 for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
  if(![scene isKindOfClass:UIWindowScene.class])continue;
  for(UIWindow *window in ((UIWindowScene *)scene).windows){window.overrideUserInterfaceStyle=DGPreferredStyle();window.backgroundColor=UIColor.systemBackgroundColor;DGUpdateStatusAppearance(window.rootViewController);}
 }
 [NSNotificationCenter.defaultCenter postNotificationName:@"DGAppearanceChanged" object:nil];
}
