#import "DGAppearance.h"
UIUserInterfaceStyle DGPreferredStyle(void) {
 switch([NSUserDefaults.standardUserDefaults integerForKey:@"douglass.appearance"]){
  case 1:return UIUserInterfaceStyleLight;
  case 2:return UIUserInterfaceStyleUnspecified;
  default:return UIUserInterfaceStyleDark;
 }
}
void DGApplyAppearance(void) {
 for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
  if(![scene isKindOfClass:UIWindowScene.class])continue;
  for(UIWindow *window in ((UIWindowScene *)scene).windows){window.overrideUserInterfaceStyle=DGPreferredStyle();[window.rootViewController setNeedsStatusBarAppearanceUpdate];}
 }
}
