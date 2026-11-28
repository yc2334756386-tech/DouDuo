# 实验媒体方案研究（2026-11-28）

## 结论

- **Atang0406/-fpga- 不适合作为 iOS 视频超分或拼接 DSP 的代码来源。** 检出的仓库是四路摄像头 RGB/同步/SDRAM/输出时序的 Verilog 工程；`image_stitch.v.v` 按输出 X 坐标把 3840 宽画面硬切成四个 960 像素区域，未发现可移植的超分模型、插值核或视频播放器接口。仓库没有 LICENSE 文件，不能把它的代码复制进 DouDuo。
- **AutoEq 适合借鉴“离线测量→目标曲线→参数 EQ/卷积 EQ 设置生成”的算法流程，不是播放时 DSP 引擎。** 当前检出 commit 为 `7ae0f56d53074872b028649617a22bbb4232feb7`；仓库 LICENSE 是 MIT。README 明确说 AutoEq “produces settings … but does not do the equalization itself”，所以应把它视为预设/系数生成器，运行时仍由自有 C++ EQ 处理。
- **OctaEQ 的 DSP 结构很适合做性能参考，但不能复制 GPL 代码。** 当前检出 commit 为 `2244284872e4f1ce34598e69eba2e5e56a5d9db9`；项目 GPL-3.0，VST3 SDK/VSTGUI 采用 GPLv3 或 Steinberg 专有许可。其自述实现包括 double 精度 TDF2 双二阶、每 32 样本重设计并逐样本插值、25 ms 参数平滑、零延迟最小相位和音频线程零分配。DouDuo 应按这些“接口/算法目标”自行实现或继续使用已有自有 C++ DSP，不拷贝源文件、注释或实现细节。
- **iOS 视频放大优先级：VideoToolbox 的低延迟超分 > 自有 Metal/MetalFX 路径。** Apple 的 `VTLowLatencySuperResolutionScalerConfiguration` 和 `VTFrameProcessor` 在 iOS 26 引入，明确面向低延迟超分与逐帧异步处理；它比 MetalFX spatial scaler 更符合“视频超分”的语义。必须按输入宽高、比例和像素格式查询支持能力，不能只按系统版本判断。
- **MetalFX `MTLFXSpatialScalerDescriptor` 从 iOS 16 可用，但 Apple 文档只承诺“spatial scaling effect”。** 它适合作为低延迟空间放大器或渲染兜底，不应在产品文案中称为神经超分/细节重建。运行时用 MetalFX 的设备支持查询；不支持时退回 Metal compute/Core Image 或原始视频。
- **AVPlayer 自定义视频合成可承载 GPU 处理，但它是“帧合成管线”，不是直接改 AVPlayerLayer 的纹理。** 给 `AVPlayerItem.videoComposition` 设置 `customVideoCompositorClass` 后，AVFoundation 创建实现 `AVVideoCompositing` 的对象，并把源帧 CVPixelBuffer 交给 `startRequest(_:) `；实现需要提供源/输出 pixel-buffer 属性、处理 render-context 变化，并在 GPU 命令完成后调用 request 的 finish 方法。适合 Objective-C++ 薄桥接，DSP/Metal/C++ 逻辑留在 C++。
- **音频 tap 的系统兼容性需要分层。** `MTAudioProcessingTap` 与 `AVAudioMixInputParameters.audioTapProcessor` 本身是早期 iOS API；但 Apple 新增的 `AVAudioMixInputParametersTrackMixID.mixID`（iOS 27）才明确用于“把 tap 应用于所有音轨”，并特别注明适合 streaming playback。对 iOS 26 及更早版本，不能假设 HLS/远程直播条目可使用该混合 tap；应对不支持、加密或返回错误的条目自动退回原生 AVPlayer 音频或自有解码/音频引擎。Apple 的 HLS 更新文档还对 FairPlay Streaming 路径给出限制，不能把 tap 当成所有远程媒体的通用能力。

## 仓库证据

### Atang0406/-fpga-

仓库：<https://github.com/Atang0406/-fpga->  
本地证据：`D:\抖音\analysis\atang-fpga`，commit `65755042d4c3695c86a40a2d30ad0863eacf40dd`。

`README.md` 将项目描述为全景会议相机 FPGA。代码入口 `image_stitch.v.v`：

- 4 路 `cam_vsync/cam_hsync/cam_data_valid/cam_rgb`；
- 预留 `calib_param_rom`，通过 `$readmemh("calib_param.hex", ...)` 读入标定参数；
- 生成 3840×1080 的输出时序；
- 输出 X 坐标 0–959、960–1919、1920–2879、2880–3839 分别选择四路缓存 RGB。

代码没有可用于 iOS 的 C++ 接口，也没有看到真正的超分重建、运动估计、卷积/插值或 Metal shader。仓库根目录没有 LICENSE，建议只保留“硬件并行、零拷贝/低延迟”的设计启发，不复制其实现。

### jaakkopasanen/AutoEq

仓库：<https://github.com/jaakkopasanen/AutoEq>  
本地证据：`D:\抖音\analysis\AutoEq`，commit `7ae0f56d53074872b028649617a22bbb4232feb7`。  
许可证：根目录 `LICENSE` 为 MIT。

README 列出的能力是：

- 频响数据、目标曲线和耳机测量数据；
- 参数 EQ 优化器；
- 生成 parametric EQ、卷积 EQ 等设置；
- Web/PyPI/命令行工具。

README 同时明确：AutoEq 只生成设置，不负责实际均衡。适用方式是离线导入目标曲线，生成自有预设（频率、Q、增益或 FIR），由 DouDuo 的 C++ 实时处理器执行。注意仓库中的测量数据来自多个来源，应单独核对数据文件的分发条件；“代码 MIT”不自动等于所有测量数据都可无条件再分发。

### AmeHanare/OctaEQ

仓库：<https://github.com/AmeHanare/OctaEQ>  
本地证据：`D:\抖音\analysis\OctaEQ`，commit `2244284872e4f1ce34598e69eba2e5e56a5d9db9`。  
许可证：`LICENSE` 为 GPL-3.0；`THIRD_PARTY_NOTICES.md` 说明 VST3 SDK/VSTGUI 为 GPLv3 或 Steinberg 专有许可证二选一。

可作为“性能预算与 DSP 设计目标”的参考：

- 8 段串联参数 EQ；
- double 状态/运算，TDF2 双二阶；
- 频率/Q 在对数域、增益在 dB 域平滑；
- 每 32 样本更新系数并逐样本插值；
- 旁路路径仍写输出，音频线程不分配；
- 最小相位、零算法延迟。

这些结论来自 `source/dsp/Equalizer.h` 与 `Biquad.h` 的本地源码注释/实现。不要复制 GPL 源码到闭源或非 GPL 目标；可按数学定义重新实现，并保留独立实现记录。

## Apple 视频路径

### 1. VideoToolbox 低延迟超分（首选，iOS 26+）

`VTLowLatencySuperResolutionScalerConfiguration`：

- iOS/iPadOS/Mac Catalyst/macOS/tvOS/visionOS introducedAt 26.0；
- 初始化参数包含 `frameWidth`、`frameHeight`、`scaleFactor`；
- 有 `isSupported`、最小/最大尺寸、最大像素数、支持像素格式和输出 pixel-buffer 属性查询；
- 文档要求先查询处理器所需 pixel-buffer attributes；
- `VTFrameProcessor.startSession(configuration:)` 可能触发超过一帧时间的模型加载，不能阻塞 UI 或实时渲染线程；
- `process(parameters:completionHandler:)` 逐帧异步处理；异步完成前，传入的 CVPixelBuffer（包括 attachments）必须保持不变。

推荐桥接形态：Objective-C++ 仅负责创建配置、会话、CVPixelBuffer 生命周期和 completion 转发；C++ 负责队列、帧状态和 UI 无关的策略。每种输入分辨率/scaleFactor 独立检查 `isSupported`，失败后保留原始帧。

官方文档：

- <https://developer.apple.com/documentation/videotoolbox/vtlowlatencysuperresolutionscalerconfiguration>
- <https://developer.apple.com/documentation/videotoolbox/vtframeprocessor>
- <https://developer.apple.com/tutorials/data/documentation/videotoolbox/vtlowlatencysuperresolutionscalerconfiguration.json>
- <https://developer.apple.com/tutorials/data/documentation/videotoolbox/vtframeprocessor.json>

### 2. MetalFX spatial scaler（iOS 16+，低延迟空间放大兜底）

`MTLFXSpatialScalerDescriptor` introducedAt iOS 16。Apple 的定义是“configure a spatial scaling effect”，因此它适合：

- 预览画面低延迟放大；
- 在 VideoToolbox SR 不支持时维持 GPU 处理；
- 作为自有 Metal pipeline 的一次空间缩放。

它不应被描述为保证细节恢复的 AI 视频超分。对 AVPlayer 播放，实际做法仍是自定义 `AVVideoCompositing`，将源 CVPixelBuffer 转为 CVMetalTexture/Metal 纹理，编码 scaler，再在 GPU 命令完成后完成 composition request。必须管理纹理、pixel-buffer pool 和命令完成回调，避免在 `startRequest` 阻塞解码队列。

官方文档：

- <https://developer.apple.com/documentation/metalfx/mtlfxspatialscalerdescriptor>
- <https://developer.apple.com/tutorials/data/documentation/metalfx/mtlfxspatialscalerdescriptor.json>

### 3. 自有 Metal/Core Image/Core ML 路径

当部署目标低于 iOS 26，或系统 SR 对输入尺寸不支持，可使用：

1. 自有 Metal compute（双线性、Lanczos、锐化、去块等）；
2. Core Image filter + Metal-backed CIContext；
3. Core ML/BNNS 模型，输入输出通过 CVPixelBuffer/Metal 纹理桥接。

这些路径的优点是系统版本覆盖广、算法可控；缺点是模型/内存/功耗/实时性由应用承担。应把模型加载放在播放前或后台队列，避免首次播放卡顿。若只是播放器预览，优先使用系统 VideoToolbox SR；自有模型作为设备/尺寸不支持时的可选能力。

## AVPlayer 自定义视频合成的准确边界

Apple `AVVideoComposition` 文档说明：内置 compositor 可做空间变换、透明度和裁剪；自定义 compositor 通过实现 `AVVideoCompositing`，由系统在播放期间提供各源视频的 pixel buffers，应用可以执行任意图形操作输出合成帧。

关键公共接口：

- `AVVideoComposition.customVideoCompositorClass`：指定自定义 compositor 类；
- `AVVideoCompositing.startRequest(_:)`：收到异步合成请求；
- `renderContextChanged(_:)`：响应输出上下文变化；
- `sourcePixelBufferAttributes`：声明接受的源帧格式；
- `requiredPixelBufferAttributesForRenderContext`：声明输出缓冲属性；
- `supportsHDRSourceFrames`、`supportsWideColorSourceFrames`：按能力声明；
- `cancelAllPendingVideoCompositionRequests()`：切换/停止时取消挂起请求；
- 可选 `anticipateRendering(using:)` / `prerollForRendering(using:)` 做预热。

建议每个 request 以“取源帧 → 转 Metal 纹理 → GPU 编码 → command-buffer completion → finish/finishWithError”完成；不要在 compositor 回调中等待 GPU、读回 CPU 或做同步磁盘/网络 I/O。为避免播放器回退到 CPU，输出 pixel format、色彩空间、HDR/wide-color 声明要与实际 Metal 管线一致。

官方文档：

- <https://developer.apple.com/documentation/avfoundation/avvideocomposition>
- <https://developer.apple.com/documentation/avfoundation/avvideocompositing>
- <https://developer.apple.com/tutorials/data/documentation/avfoundation/avvideocompositing.json>

## AVPlayer 音频 tap 与远程媒体

### 公共 API 事实

- `AVAudioMixInputParameters.audioTapProcessor` 是音频处理 tap 属性；
- `MTAudioProcessingTapCreate` / `MTAudioProcessingTapGetSourceAudio` 可从解码后的音频取得 AudioBufferList；
- `MTAudioProcessingTapCreateWithPreferredFormat` introducedAt iOS 27，preferred format 必须是 Linear PCM。即使指定 preferred format，实际 tap 格式仍可能在数值类型、交错方式、样本宽度上变化，必须在 prepare 回调读取 `mFormatFlags`、`mBytesPerPacket` 和 `mBitsPerChannel`，必要时自行转换；
- prepare 回调可能在 tap 生命周期内多次调用；应在那里分配/重建输出缓冲；
- process 回调必须产生请求的样本数；先调用 `MTAudioProcessingTapGetSourceAudio`，正确处理实际 frames、StartOfStream/EndOfStream 标志；
- process 是实时音频路径，禁止分配、阻塞系统调用和同步 I/O；参数变化只应使用预分配状态、无锁/无分配 C++ DSP；
- tap 可以原地处理，但自定义 buffer 指针必须保持有效直到下一次执行。

### HLS/远程 MP4 判断

- **本地 MP4 或可随机访问的普通 AVAsset：** 传统按音轨的 `AVAudioMixInputParameters.audioTapProcessor` 通常是可行路线，但仍需处理解码格式变化、seek/重建和 tap 错误。
- **HLS/流式播放：** Apple 的 `AVPlayerItem.audioMix` 文档仍明确写着 audio mix 只适用于 file-based media、HTTP Live Streaming 不支持；这是 iOS 27 HLS 扩展前的基线。Apple 2026 HLS 更新新增 `AVAudioMixInputParametersTrackMixID.mixID`：它把 tap 应用于播放中产生音频的所有音轨，特别适合 streaming playback，但 FairPlay-protected audio 例外。当前 DouDuo deployment target 是 iOS 26.0，因此不能直接依赖 iOS 27 API；运行时/编译时必须隔离 `@available(iOS 27.0, *)` 分支，iOS 26 及更早版本对 HLS 回退到原生 AVPlayer 音频或自有解码/音频引擎。
- **FairPlay/受保护流：** Apple 的 HLS 更新资料对 FairPlay Streaming 音频处理有额外限制；不能承诺受保护 HLS 一定能被 tap 读取。遇到受保护资源应保留原生 AVPlayer 音频，或只对获得授权的本地解码样本做 EQ。

官方资料：

- <https://developer.apple.com/tutorials/data/documentation/avfoundation/avaudiomixinputparameters.json>
- <https://developer.apple.com/tutorials/data/documentation/avfoundation/avaudiomixinputparameterstrackid.json>
- <https://developer.apple.com/tutorials/data/documentation/avfoundation/avaudiomixinputparameterstrackid/mixid.json>
- <https://developer.apple.com/tutorials/data/documentation/mediatoolbox/mtaudioprocessingtapcreatewithpreferredformat(_:_:_:_:_:).json>
- <https://developer.apple.com/tutorials/data/documentation/mediatoolbox/mtaudioprocessingtappreparecallback.json>
- <https://developer.apple.com/tutorials/data/documentation/mediatoolbox/mtaudioprocessingtapprocesscallback.json>
- <https://developer.apple.com/documentation/avfoundation/avplayeritem/audiomix>（旧基线：audio mix 仅 file-based，HLS 不支持）
- <https://developer.apple.com/streaming/Whats-new-HLS.pdf>（iOS 27 HLS mix tap 扩展；FairPlay 音频例外）

## 对 DouDuo 的落地建议

1. **视频：** 以 `AVVideoCompositing` 作为 AVPlayer 集成点；iOS 26+ 先探测 VideoToolbox 低延迟 SR；不支持时使用 MetalFX spatial 或自有 Metal/Core Image 缩放。直播 VLC 路径没有 AVPlayerItem，不能复用这套 compositor。
2. **音频：** 保留现有 C++ EQ 为唯一 DSP；Objective-C++ 只做 AVAudioMix/MTAudioProcessingTap 生命周期和 AudioBufferList ↔ C++ buffer 适配。tap process 线程禁止锁、分配和日志 I/O。
3. **部署：** 以 iOS 26 为最低“系统 SR”能力线，以 iOS 27 为“HLS mix tap”能力线；更低系统只提供原生音频/空间缩放或本地媒体 EQ。
4. **版权：** AutoEq 代码可按 MIT 条件使用；Atang FPGA 无许可证，不复制；OctaEQ GPL-3.0 只做算法概念和性能参考，不复制源码、注释或 VST3 glue。

## 研究限制

本次只做源码、许可证和 Apple 一手文档核对，未运行自动化测试、未在真机验证 VideoToolbox/MetalFX 支持矩阵，也未验证具体 Douyin HLS 资源是否 FairPlay 或是否允许 iOS 27 mixID tap。实现前应针对目标系统和实际输入尺寸做设备能力查询与失败回退。

## 主要一手来源

- <https://github.com/Atang0406/-fpga->
- <https://github.com/jaakkopasanen/AutoEq>
- <https://github.com/AmeHanare/OctaEQ>
- <https://developer.apple.com/documentation/videotoolbox/vtlowlatencysuperresolutionscalerconfiguration>
- <https://developer.apple.com/documentation/videotoolbox/vtframeprocessor>
- <https://developer.apple.com/documentation/metalfx/mtlfxspatialscalerdescriptor>
- <https://developer.apple.com/documentation/avfoundation/avvideocomposition>
- <https://developer.apple.com/documentation/avfoundation/avvideocompositing>
- <https://developer.apple.com/documentation/avfoundation/avplayeritem/audiomix>（旧基线：audio mix 仅 file-based，HLS 不支持）
- <https://developer.apple.com/streaming/Whats-new-HLS.pdf>（iOS 27 HLS mix tap 扩展；FairPlay 音频例外）




