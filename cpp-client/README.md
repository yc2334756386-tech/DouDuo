# 澄流 / DouGlass 0.1.0

使用 C++20 和 Objective-C++ 编写的独立 iPhone / iPad 客户端。首版提供视频与图文推荐、图集横滑、视频暂停和进度拖动、只读评论与回复，以及抖音官网登录页。登录会话保存在本机 WebKit 存储。

iOS 26 及以上使用 UIKit 原生 `UIGlassEffect`；iOS 18–25 使用系统材质回退。业务核心是 `Core.cpp`，系统界面和网页、播放器桥接使用 `.mm`，应用不依赖 Swift 或额外播放器二进制。

## 云端编译

GitHub Actions 工作流：`.github/workflows/douglass-cpp-ipa.yml`。需要具备 iOS 26 或更新 SDK 的 macOS/Xcode runner。只执行编译与打包，不执行测试。

也可在对应 macOS 环境运行：

```bash
bash cpp-client/scripts/build-ipa.sh
```

输出：`build/douglass/DouGlass-0.1.0-unsigned.ipa`。

## 自签安装

将未签名 IPA 导入全能签、ESign 或其他支持 IPA 的自签工具，使用自己的有效证书与描述文件签名，再安装。安装后点击右上角账号按钮，在抖音官网页面登录；需要安全验证时在同一页面完成，然后点“完成”返回。

评论区仅支持阅读、分页、查看评论配图和展开回复，没有发送、点赞或删除入口。推荐内容由平台网页接口提供，平台验证或接口变化可能影响读取。

本版按需求不运行自动化测试与真机测试；云端构建成功不代表真实账号与设备上的运行行为已验证。上游许可和署名见根目录 `LICENSE` 与 `NOTICE.txt`。
