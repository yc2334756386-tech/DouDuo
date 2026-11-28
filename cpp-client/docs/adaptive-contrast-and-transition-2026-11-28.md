# 取色、动画与微型 PiP：0.20.16 源码核对

核对日期：2026-11-28。本轮按用户要求不运行自动化或真机测试；下列结论分开记录源码事实、实施改动与设备端未知项。

## GitHub 参考

| 项目 / 固定版本 | 核对入口 | 用于本项目的判断 |
| --- | --- | --- |
| [Material Color Utilities](https://github.com/material-foundation/material-color-utilities/tree/0f07b68759989d4e065b806229daba6ad000695d)，Apache-2.0 | `cpp/utils/utils.cc` 的 RGB 线性化与亮度，`cpp/contrast/contrast.cc` 的亮度对比度 | 采用线性 sRGB 相对亮度比较两种墨色；不把编码后的 RGB 平均值当作线性亮度。 |
| [TinyColor](https://github.com/bgrins/TinyColor/tree/b49018c9f2dbca313d80d7a4dad25e26143cfe01)，MIT | `tinycolor.js` 的 `getLuminance`、`readability` | 再核对从颜色到对比度的计算路径。其静态颜色工具不负责视频方向、裁切或帧时序。 |
| [BackgroundCheck](https://github.com/kennethcachia/background-check/tree/f52e3f8116dca46f95ce0da548d1458f22eec7f1)，MIT | `background-check.js` 的局部像素平均与方差 | 复杂度可以辅助稳定判断，但不能单凭纹理复杂就固定使用白字；项目中的 DOM/CSS 实现没有搬入 IPA。 |
| [GlobalRefresh-PiP](https://github.com/Yoroin/GlobalRefresh-PiP/tree/7e8f8d6eda86794ee9daebed171d3ca53530e893) | `ViewController.swift` 的内容视图准备、启动就绪核对、有限兼容补试 | 核对公共 VideoCall PiP 的源视图与内容尺寸。未接入其私有控件/共存 Hook，也不编译上游 Swift。 |

前三项用于算法与实现思路核对，未引入其源文件或依赖。`ContrastMap.cpp` 是本项目的 C++ 实现：查表做 sRGB 线性化，比较实际近白与炭黑墨色的对比度，再做局部平均、迟滞、空间羽化及时间过渡。

## 源码中发现的差异

- 旧取色直接在编码 RGB 上加权，且高方差区域强行偏向白字；与线性亮度对比度选择并不一致。
- 图文路径原先需要非空播放器 item 才进入自适应计算，导致图片没有进入同一取色路径。
- 视频显示范围曾由 presentationSize 再推算；现优先使用 `AVPlayerLayer.videoRect`，图文与回退适配几何由纯 C++ 计算。
- 采样原先经过第二次位图绘制；现读取显式 RGBA8 CGImage 的提供者数据，并沿用其行序和 stride 生成遮罩，减少额外坐标转换。
- 作品返回时可以发生统计整表刷新、重复来源视图定位，以及图片首次显示时解码。这些是可争用转场资源的路径，不能仅凭源码认定其是设备卡顿的唯一原因。

## 动画优先调度

`RenderBudget` 的纯 C++ 租约在导航与通用动画开始前建立，正常结束释放，取消后可以到期释放。非关键的取色、预加载、整表刷新、图片提交和页面记录采集延后。取消预算不持有控制器，图片旧请求仍核对代数，导航仍使用原系统 Zoom、原模糊和原时长。

本轮没有把所有队列提升成同一个高 QoS，没有替换 UIKit 私有调度器。系统 UI、实际呈现和热限制由 iOS 控制。转场日志仅记录准备耗时和 CADisplayLink 回调间隔，用于下一次设备反馈，不能当作 GPU 呈现帧率或“零掉帧”的证明。

## 用户提供的 PiP 日志

同一进程先出现 `observed_fps=119.0`，随后出现 `refresh.pip_start_timeout`。这能证明前台刷新回调已接近请求值，以及应用在自己的等待期限内没有确认 PiP 活跃；没有错误域/代码或启停回调，无法确认系统拒绝原因。

新实现先给内容视图有效尺寸与内容更新，再请求 PiP；收到启动成功后才缩为 0.1 点。静默超时最多补试一次 320×180 内容尺寸，关闭开关取消旧代数任务。增加 possible/active/suspended、源窗口/尺寸/透明度、内容尺寸和失败错误域/代码。启动时系统窗口可能短暂可见；这仍需真机确认。

## 仍需设备确认

实际 PiP 成功率、不同方向/HDR 视频的取色观感、局部渐变准确度，以及动画是否减少卡顿均未经本轮真机验证。现有取色也不承诺文字在所有混合明暗像素上同时满足固定可读性比值。
