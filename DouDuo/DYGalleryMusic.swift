import AVFoundation
import Combine
import SwiftUI

/// 图文（图集）作品的背景音乐。
/// 之前图集只显示图片、完全不播音乐，老板反馈「播放图文的时候没有背景音乐」。
/// 这里用 AVQueuePlayer + AVPlayerLooper 循环播放作品的音乐地址，跟随「当前页 / 静音」开关。
@MainActor
final class DYGalleryAudio: ObservableObject {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?
    private var wantsPlay = false
    private var mutedNow = false
    private let owner = UUID()
    private var coverLevel = 0
    private var registered = false
    private var resolver: (() async -> URL?)?
    private var resolveTask: Task<Void, Never>?
    private var status: NSKeyValueObservation?
    private var generation = 0
    private var retries = 0

    /// 全局静音偏好（设置/菜单里的「静音」）
    static var globalMuted: Bool { UserDefaults.standard.bool(forKey: "douyin_muted_v1") }

    /// 只在页面成为当前页时 true；切走/进后台立刻停
    func sync(url: URL?, active: Bool, muted: Bool, resolve: (() async -> URL?)? = nil) {
        mutedNow = muted
        if let resolve { resolver = resolve }
        wantsPlay = active
        guard active else { apply(); return }
        if let url, currentURL != url {
            retries = 0
            build(url)
        }
        wantsPlay = active
        if active, !registered {
            coverLevel = DDPlayback.shared.coverDepth
            registered = true
            DDPlayback.shared.register(owner, stop: { [weak self] in self?.player?.pause() },
                start: { [weak self] in self?.apply() }, playsInsideCover: true, coverLevel: coverLevel)
        }
        if player == nil, let currentURL { build(currentURL) }
        apply()
        if active, player == nil { refreshSound() }
    }

    private func build(_ url: URL) {
        generation += 1
        status = nil
        player?.pause()
        looper?.disableLooping()
        currentURL = url
        let item = AVPlayerItem(asset: DYMedia.asset(url))
        let q = AVQueuePlayer()
        q.automaticallyWaitsToMinimizeStalling = true
        q.isMuted = mutedNow
        looper = AVPlayerLooper(player: q, templateItem: item)
        player = q
        status = q.observe(\.currentItem?.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.player?.currentItem?.status == .failed { self.refreshSound() }
                else { self.apply() }
            }
        }
    }

    private func refreshSound() {
        guard wantsPlay, resolveTask == nil, retries < 2, let resolver else { return }
        retries += 1
        let requestGeneration = generation
        resolveTask = Task { [weak self] in
            let url = await resolver()
            guard let self else { return }
            defer { self.resolveTask = nil }
            guard !Task.isCancelled, self.generation == requestGeneration, self.wantsPlay,
                  let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            self.build(url)
            self.apply()
        }
    }

    private func apply() {
        guard let p = player else { return }
        p.isMuted = mutedNow
        let allowed = DYCorePlaybackAllowed(wantsPlay, UIApplication.shared.applicationState == .active,
                                            DDPlayback.shared.isUncovered(level: coverLevel))
        if allowed {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: DYLaunchMute.sessionOptions)
            try? AVAudioSession.sharedInstance().setActive(true)
            if p.rate == 0 { p.play() }
        } else {
            p.pause()
        }
    }

    func teardown() {
        generation += 1
        resolveTask?.cancel()
        resolveTask = nil
        status = nil
        wantsPlay = false
        retries = 0
        if registered { DDPlayback.shared.unregister(owner); registered = false }
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        currentURL = nil
    }
}

/// 图集画面（多图左右翻）+ 背景音乐
struct DYImageGallery: View {
    let images: [String]
    let musicURL: URL?
    let isActive: Bool
    let muted: Bool
    var source: DYAweme? = nil
    var bridge: DouyinBridge? = nil
    var hidesIndex = false
    /// 双击点赞（视频页是播放器手势处理的；图集原来没接 → 老板说「图文无法双击点赞」）
    var onDoubleTap: (() -> Void)? = nil

    @StateObject private var audio = DYGalleryAudio()

    var body: some View {
        TabView {
            ForEach(images, id: \.self) { s in
                CachedAsyncImage(url: URL(string: s)) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .modifier(DYSaveImageMenu(source: s, title: "保存这张图片"))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: hidesIndex ? .never : .always))
        // simultaneous：不抢 TabView 左右翻图的滑动
        .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleTap?() })
        .accessibilityIdentifier("douyin.gallery")
        .onAppear {
            DYLiveModel.log("DDGALLERY 打开 n=\(images.count) music=\(musicURL?.host ?? "-") active=\(isActive) muted=\(muted)")
            syncAudio()
        }
        .onDisappear { audio.teardown() }
        .onChange(of: isActive) { _, active in
            syncAudio()
        }
        .onChange(of: muted) { _, m in
            syncAudio()
        }
        .onChange(of: musicURL) { _, _ in syncAudio() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            audio.sync(url: musicURL, active: false, muted: muted)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            syncAudio()
        }
    }

    private func syncAudio() {
        audio.sync(url: musicURL, active: isActive, muted: muted, resolve: {
            guard let bridge, let source,
                  let music = try? await bridge.originalSound(source),
                  let value = music.playURL else { return nil }
            return URL(string: value)
        })
    }
}

struct DYSaveImageMenu: ViewModifier {
    let source: String?
    let title: String
    @State private var saving = false
    @State private var message: String?

    func body(content: Content) -> some View {
        content.contextMenu {
            if let source {
                Button(title, systemImage: "square.and.arrow.down") {
                    guard !saving else { return }
                    saving = true
                    Task {
                        defer { saving = false }
                        do { try await DYSaver.saveImage(source); message = "已保存到相册" }
                        catch { message = error.localizedDescription }
                    }
                }.disabled(saving)
            }
        }
        .alert("保存图片", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }
}
