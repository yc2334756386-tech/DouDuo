#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLIENT="$ROOT/cpp-client"
OUTPUT="$ROOT/build/douglass"
APP="$OUTPUT/Payload/DouGlass.app"
mkdir -p "$APP"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
echo "Building DouGlass with iPhoneOS SDK $SDK_VERSION"
if [ "${SDK_VERSION%%.*}" -lt 26 ]; then
  echo 'An iOS 26 or newer SDK is required for native Liquid Glass.' >&2
  exit 1
fi
BUILD="${GITHUB_RUN_NUMBER:-1}"
python3 "$CLIENT/scripts/make_assets.py" "$OUTPUT/Assets.xcassets"
xcrun --sdk iphoneos actool "$OUTPUT/Assets.xcassets" \
  --compile "$APP" --platform iphoneos --minimum-deployment-target 18.0 \
  --app-icon AppIcon --target-device iphone --target-device ipad \
  --output-partial-info-plist "$OUTPUT/asset-info.plist"

OBJECTS=()
for source in "$CLIENT"/*.cpp; do
  object="$OUTPUT/$(basename "${source%.cpp}").o"
  xcrun --sdk iphoneos clang++ -std=c++20 -O2 -DNDEBUG -arch arm64 -isysroot "$SDK" \
    -miphoneos-version-min=18.0 -c "$source" -o "$object"
  OBJECTS+=("$object")
done
xcrun --sdk iphoneos clang++ \
  -std=c++20 -O2 -DNDEBUG -fobjc-arc -fmodules -fvisibility=hidden \
  -Wno-deprecated-declarations -arch arm64 -isysroot "$SDK" \
  -miphoneos-version-min=18.0 -Wl,-dead_strip \
  "${OBJECTS[@]}" "$CLIENT"/*.mm \
  -framework UIKit -framework Foundation -framework WebKit -framework AVFoundation \
  -framework CoreMedia -framework CoreGraphics -framework QuartzCore -framework ImageIO -framework AudioToolbox -framework Photos -framework QuickLook -framework Security -framework MediaPlayer -framework CoreImage -framework CoreVideo -framework AVKit -framework CoreText -framework UniformTypeIdentifiers -lz \
  -o "$APP/DouGlass"
cp "$CLIENT/bridge.js" "$APP/bridge.js"
cp "$CLIENT/messages.js" "$APP/messages.js"
cp "$CLIENT/music-page.js" "$APP/music-page.js"
cp "$CLIENT/search-page.js" "$APP/search-page.js"
cp "$ROOT/DouDuo/DouyinPublicationRegions.json" "$APP/DouyinPublicationRegions.json"
cp "$ROOT/LICENSE" "$APP/DOUDUO-LICENSE.txt"
cp "$CLIENT/NOTICE.txt" "$APP/NOTICE.txt"
python3 - "$APP" "$OUTPUT/asset-info.plist" "$BUILD" <<'PY'
import pathlib, plistlib, sys
app=pathlib.Path(sys.argv[1])
info={
  'CFBundleDevelopmentRegion':'zh_CN',
  'CFBundleDisplayName':'抖音极简版',
  'CFBundleExecutable':'DouGlass',
  'CFBundleIdentifier':'io.github.yc2334756386.douglass',
  'CFBundleInfoDictionaryVersion':'6.0',
  'CFBundleName':'抖音极简版',
  'CFBundlePackageType':'APPL',
  'CFBundleShortVersionString':'0.15.0',
  'UIBackgroundModes':['audio'],
  'NSPhotoLibraryAddUsageDescription':'保存你选择的视频、图集和评论图片到相册',
  'CFBundleVersion':sys.argv[3],
  'LSRequiresIPhoneOS':True,
  'CADisableMinimumFrameDurationOnPhone':True,
  'MinimumOSVersion':'18.0',
  'UIDeviceFamily':[1,2],
  'CFBundleSupportedPlatforms':['iPhoneOS'],
  'UIRequiredDeviceCapabilities':['arm64'],
  'UILaunchScreen':{},
  'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{
    'UIWindowSceneSessionRoleApplication':[{'UISceneConfigurationName':'Default','UISceneDelegateClassName':'DGScene'}]}},
  'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],
  'UISupportedInterfaceOrientations~ipad':['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],
  'ITSAppUsesNonExemptEncryption':False,
  'NSAppTransportSecurity':{'NSAllowsArbitraryLoadsForMedia':True,'NSAllowsArbitraryLoadsInWebContent':True},
}
with open(sys.argv[2],'rb') as f: info.update(plistlib.load(f))
with open(app/'Info.plist','wb') as f: plistlib.dump(info,f,fmt=plistlib.FMT_BINARY)
(app/'PkgInfo').write_bytes(b'APPL????')
PY
chmod 755 "$APP/DouGlass"
cd "$OUTPUT"
COPYFILE_DISABLE=1 /usr/bin/zip -qry DouGlass-0.15.0-unsigned.ipa Payload
shasum -a 256 DouGlass-0.15.0-unsigned.ipa > SHA256.txt
printf 'Built unsigned IPA: %s\n' "$OUTPUT/DouGlass-0.15.0-unsigned.ipa"
