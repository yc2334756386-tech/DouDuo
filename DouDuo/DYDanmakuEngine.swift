import SwiftUI
import QuartzCore

// MARK: - 抖音式实时弹幕引擎
//
// 老板要的抖音行为：
//   1. 长弹幕跑得快、短弹幕跑得慢（每条用固定的「过屏时长」，而不是固定速度）；
//   2. 字体大一点；
//   3. 快进/拖动：清空屏上弹幕，从新位置重新出；
//   4. 开头不卡。
//
// 原来的做法：把整条视频的弹幕一次性排好（预先算每条的轨道和出场时刻），渲染层按时钟去「查表」。
// 长视频的弹幕是分段到达的（30 秒一段），每到一段就整片重排一次、并把屏上所有图层清掉重放，
// 于是开头几秒（各段陆续到达时）弹幕一跳一跳、一卡一卡。
//
// 现在改成实时调度（跟抖音一样）：
//   - 只维护「此刻在屏上的弹幕」。每帧看下一条该出场的弹幕，找一条右侧已腾出空位的轨道放进去；
//   - 新数据到了只是并入「待出场队列」，不影响已经在飞的弹幕；
//   - 每条一旦出场，它自己的起点和速度就固定，位置 = 起点 - (now - 出场时刻) × 自己的速度，绝不回头修；
//   - 跳转/暂停后重新开始就清屏，从当前时间往后排。

enum DYDanmakuStyle {
    /// 抖音的弹幕比原来大一号（原来 15）
    static let fontSize: CGFloat = 17
    static let laneHeight: CGFloat = 32
    /// 一条弹幕从右边进屏到左边完全出屏用的时间：短的偏慢、长的偏快（抖音观感）
    /// 过屏时长按长度线性插值：屏宽的弹幕约 8.5s，宽度为屏宽 60% 以上的长弹幕约 6.0s
    static func travelSeconds(width: CGFloat, screen: CGFloat) -> Double {
        DYDMTravelSeconds(Double(width), Double(screen))
    }
    /// 同一条轨道上后一条与前一条的最小间距（pt）
    static let gap: CGFloat = 24
    /// 待出场的弹幕最多能晚多少秒出来（轨道一直满就丢掉，跟抖音一样）
    static let maxDelay: Double = 2.5
}

/// 一条正在屏上飞的弹幕
private struct DYFlying {
    let layer: CALayer
    let end: Double
}

final class DYDanmakuEngineView: UIView {
    private let clip = CALayer()
    private let core = DYDMCreate()
    private var coreWidth: CGFloat = 0
    private var timelineRate: Float = -1
    private var lastItemCount = -1
    private var lastFirstID: String?
    private var lastLastID: String?
    private var normalized: [String: String] = [:]
    private var queue: [DYDanmaku] = []        // 已拉到的全部弹幕（按 offset 排序）；跳回前面时从这里重排
    private var queued = Set<String>()        // 已收进 queue 的 id，防重复
    private var cursor = 0                    // queue 中下一条要看的位置
    private var done = Set<String>()          // 本轮（上次清屏后）已出场或已丢弃的 id
    private var flying: [DYFlying] = []
    private var pool: [CALayer] = []
    private var images: [String: CGImage] = [:]
    private var sizes: [String: CGSize] = [:]
    private var rasterizing: Set<String> = []
    private var cacheOrder: [String] = []
    private var lastWarmTime: Double = -1
    private let rasterQueue = DispatchQueue(label: "douduo.danmaku.text", qos: .userInitiated)
    private var lastShown: [String: Double] = [:]   // 去重：同文本 10s 内不重复
    private var link: CADisplayLink?
    private var clock = DYDanmakuClock()
    private var lanes = 0
    private var lastT: Double = -1
    private var deduplicate = true
    private var maxPerSecond = 4
    private var spawnedAt: [Double] = []      // 最近一秒的出场时刻（限流）
    // 诊断
    private var lastTS: CFTimeInterval = 0
    private var gaps: [Double] = []
    private var maxOn = 0
    private var spawned = 0
    private var dropped = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clip.masksToBounds = true
        clip.speed = 0
        flying.reserveCapacity(256)
        pool.reserveCapacity(64)
        layer.addSublayer(clip)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { DYDMDestroy(core) }

    func update(items: [DYDanmaku], clock c: DYDanmakuClock, regionTop: CGFloat, regionHeight: CGFloat,
                lanes l: Int, density: DYDanmakuPolicy.Density, deduplicate dd: Bool) {
        let jumped = c.epoch != clock.epoch
        clock = c
        lanes = l
        coreWidth = bounds.width
        DYDMConfigure(core, Double(coreWidth), Int32(max(0, min(l, 64))), Double(DYDanmakuStyle.gap))
        deduplicate = dd
        maxPerSecond = density.maxPerSecond * 3   // 抖音密度：每秒能出的条数比原来宽
        CATransaction.begin(); CATransaction.setDisableActions(true)
        clip.frame = CGRect(x: 0, y: regionTop, width: bounds.width, height: regionHeight)
        CATransaction.commit()
        merge(items)
        let now = clock.now(Date())
        syncTimeline(at: now, force: jumped)
        if jumped { restart(at: now) }
        if clock.playing && hasWork { start() } else { stop() }
        render(clip.convertTime(CACurrentMediaTime(), from: nil))
    }

    // Core Animation 在渲染进程平移字形。主线程只调度新弹幕，不再逐帧修改每个图层的位置。
    private func syncTimeline(at time: Double, force: Bool) {
        let rate = clock.playing ? Float(clock.rate * (1 + clock.slew)) : 0
        let host = CACurrentMediaTime()
        let current = clip.convertTime(host, from: nil)
        guard force || abs(rate - timelineRate) > 0.0005 || abs(current - time) > 0.35 else { return }
        let position = force || timelineRate < 0 || abs(current - time) > 0.35 ? time : current
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clip.speed = rate
        clip.timeOffset = rate > 0 ? 0 : position
        clip.beginTime = rate > 0 ? layer.convertTime(host, from: nil) - position / Double(rate) : 0
        CATransaction.commit()
        timelineRate = rate
    }

    /// 没有在飞的、也没有待出场的弹幕时不跑逐帧刷新（否则 120 帧空转。真机：弹幕刷新占主线程约 1 成）
    private var hasWork: Bool { !flying.isEmpty || cursor < queue.count }

    /// 新到的弹幕并入队列；已经在飞的不受影响，过去时间点的不倒着补（跟抖音一样）
    private func merge(_ items: [DYDanmaku]) {
        guard items.count != lastItemCount || items.first?.id != lastFirstID || items.last?.id != lastLastID else { return }
        lastItemCount = items.count
        lastFirstID = items.first?.id
        lastLastID = items.last?.id
        let fresh = items.filter { $0.offset.isFinite && $0.offset >= 0 && !$0.id.isEmpty && !queued.contains($0.id) }
        guard !fresh.isEmpty else { return }
        for d in fresh {
            queued.insert(d.id)
            normalized[d.id] = DYDanmakuPolicy.normalized(d.text)
        }
        let resumeFrom = cursor < queue.count ? queue[cursor].offset : (lastT >= 0 ? lastT : 0)
        queue = (queue + fresh).sorted { $0.offset == $1.offset ? $0.id < $1.id : $0.offset < $1.offset }
        cursor = queue.firstIndex { $0.offset >= resumeFrom } ?? queue.count
    }

    /// 跳转/重新开始：清屏，从 t 往后排
    private func restart(at t: Double) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for f in flying { f.layer.removeAllAnimations(); f.layer.removeFromSuperlayer(); pool.append(f.layer) }
        CATransaction.commit()
        flying.removeAll()
        DYDMReset(core)
        lastWarmTime = -1
        spawnedAt.removeAll()
        lastShown.removeAll()
        done.removeAll()
        // 从新位置往后排（抖音：快进/拖动后清屏，从当前时间重新出）
        cursor = queue.firstIndex { $0.offset >= t } ?? queue.count
        lastT = t
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() } else if clock.playing && hasWork { start() }
    }

    private func start() {
        guard link == nil, window != nil, !DDPerfExperiment.off("DANMAKU") else { return }
        let l = CADisplayLink(target: DYDanmakuEngineTick(self), selector: #selector(DYDanmakuEngineTick.tick(_:)))
        // 发热（serious 及以上）时降到 60 帧：弹幕平移 60 帧肉眼也是顺的
        let hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        // 调度器 30Hz 即可，字形动画由合成器按屏幕刷新率独立运行。
        l.preferredFrameRateRange = hot ? CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
                                        : CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        l.add(to: .main, forMode: .common)
        link = l
        lastTS = 0
    }

    func stop() {
        #if DEBUG
        if link != nil { DDDanmakuIdleStat.stops += 1 }
        #endif
        link?.invalidate(); link = nil
    }

    #if DEBUG
    static var idleStops: Int { DDDanmakuIdleStat.stops }
    #else
    static var idleStops: Int { -1 }
    #endif
    private var wakeToken = 0
    private func scheduleWake(after seconds: Double) {
        wakeToken &+= 1
        let token = wakeToken
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, seconds)) { [weak self] in
            guard let self, token == self.wakeToken, self.clock.playing, self.window != nil else { return }
            self.start()
        }
    }

    fileprivate func tick(_ l: CADisplayLink) {
        #if DEBUG
        if lastTS > 0 {
            gaps.append(l.timestamp - lastTS)
            if gaps.count >= 480 {
                let avg = gaps.reduce(0, +) / Double(gaps.count)
                let over = gaps.filter { $0 > 0.02 }.count
                let p95 = gaps.sorted()[Int(Double(gaps.count) * 0.95)]
                DYLiveModel.log("DDDMFRAME idleStops=\(Self.idleStops) fps=\(Int(1 / max(avg, 0.001))) p95=\(Int(p95 * 1000))ms over20ms=\(over)/\(gaps.count) maxOnScreen=\(maxOn) spawned=\(spawned) dropped=\(dropped) queue=\(queue.count - cursor) engine=live")
                gaps.removeAll(); maxOn = 0; spawned = 0; dropped = 0
            }
        }
        #endif
        lastTS = l.timestamp
        render(clip.convertTime(CACurrentMediaTime(), from: nil))
    }

    private func render(_ t: Double) {
        let w = bounds.width
        guard w > 0 else { return }
        if lastWarmTime < 0 || abs(t - lastWarmTime) >= 0.25 {
            lastWarmTime = t
            for item in queue.dropFirst(cursor).prefix(32) where item.offset <= t + 6 { prepareRaster(item) }
        }
        // 时间倒退（不是用户跳转，比如循环回开头）：清屏重排
        if lastT >= 0, t + 0.5 < lastT { restart(at: t) }
        lastT = t
        CATransaction.begin(); CATransaction.setDisableActions(true)
        DYDMAdvance(core, t)
        for index in flying.indices.reversed() where flying[index].end <= t {
            let old = flying.remove(at: index).layer
            old.removeAllAnimations()
            old.removeFromSuperlayer()
            pool.append(old)
        }
        spawn(upTo: t, screen: w)
        maxOn = max(maxOn, flying.count)
        CATransaction.commit()
        // 屏上没有在飞的：队列排完就停；下一条还早（>0.4s）就停掉、到点前再起（不在等待期间 120 帧空转）
        if flying.isEmpty {
            if cursor >= queue.count { stop() }
            else {
                let wait = (queue[cursor].offset - t) / max(clock.rate, 0.1)
                if wait > 0.4 { stop(); scheduleWake(after: wait - 0.15) }
            }
        }
    }

    /// 让到点的弹幕出场：找右侧空出来、而且不会被追尾的轨道
    private func spawn(upTo t: Double, screen: CGFloat) {
        guard lanes > 0 else { return }
        spawnedAt.removeAll { t - $0 > 1 }
        while cursor < queue.count, queue[cursor].offset <= t {
            let d = queue[cursor]
            cursor += 1
            if done.contains(d.id) { continue }
            if t - d.offset > DYDanmakuStyle.maxDelay { done.insert(d.id); dropped += 1; continue }   // 太迟了，丢掉
            let key = normalized[d.id] ?? ""
            if key.isEmpty { continue }
            if deduplicate, let last = lastShown[key], d.offset - last < 10 { done.insert(d.id); continue }
            if spawnedAt.count >= maxPerSecond { cursor -= 1; break }   // 这一秒满了，下一帧再看
            guard let size = sizes[d.id], let raster = images[d.id] else {
                prepareRaster(d)
                cursor -= 1
                break
            }
            let travel = DYDMTravelSeconds(Double(size.width), Double(screen))
            let lane = Int(DYDMTrySpawn(core, t, Double(size.width)))
            guard lane >= 0 else {
                // 轨道都满：先放回队列，下一帧再试（最多等 maxDelay）
                cursor -= 1
                break
            }
            let layer = pool.popLast() ?? CALayer()
            layer.anchorPoint = .zero
            layer.contentsScale = UIScreen.main.scale
            layer.contents = raster
            layer.bounds = CGRect(origin: .zero, size: size)
            layer.position = CGPoint(x: -size.width, y: CGFloat(lane) * DYDanmakuStyle.laneHeight)
            clip.addSublayer(layer)
            let motion = CABasicAnimation(keyPath: "position.x")
            motion.fromValue = screen
            motion.toValue = -size.width
            motion.duration = travel
            motion.beginTime = t
            motion.timingFunction = CAMediaTimingFunction(name: .linear)
            layer.add(motion, forKey: "douduo.danmaku.motion")
            flying.append(DYFlying(layer: layer, end: t + travel))
            lastShown[key] = d.offset
            done.insert(d.id)
            spawnedAt.append(t)
            spawned += 1
        }
    }

    private func prepareRaster(_ item: DYDanmaku) {
        guard images[item.id] == nil, rasterizing.insert(item.id).inserted else { return }
        let scale = window?.screen.scale ?? UIScreen.main.scale
        rasterQueue.async { [weak self] in
            let result = Self.makeRaster(text: item.text, scale: scale)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.rasterizing.remove(item.id)
                guard let (image, size) = result else { return }
                self.images[item.id] = image
                self.sizes[item.id] = size
                self.cacheOrder.append(item.id)
                if self.cacheOrder.count > 512 {
                    for id in self.cacheOrder.prefix(64) { self.images[id] = nil; self.sizes[id] = nil }
                    self.cacheOrder.removeFirst(64)
                }
            }
        }
    }

    nonisolated private static func makeRaster(text value: String, scale: CGFloat) -> (CGImage, CGSize)? {
        let font = UIFont.systemFont(ofSize: DYDanmakuStyle.fontSize, weight: .semibold)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.7)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.white.withAlphaComponent(0.95), .shadow: shadow,
        ]
        let text = value as NSString
        let size = text.size(withAttributes: attributes)
        let box = CGSize(width: ceil(size.width) + 6, height: ceil(size.height) + 6)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: box, format: format).image { _ in
            text.draw(at: CGPoint(x: 3, y: 3), withAttributes: attributes)
        }
        guard let raster = image.cgImage else { return nil }
        return (raster, box)
    }

}

/// CADisplayLink 强引用 target：弱引用中转，视图销毁不泄漏
private final class DYDanmakuEngineTick: NSObject {
    weak var view: DYDanmakuEngineView?
    init(_ v: DYDanmakuEngineView) { view = v }
    @objc func tick(_ l: CADisplayLink) {
        guard let view else { l.invalidate(); return }
        MainActor.assumeIsolated { view.tick(l) }
    }
}

struct DYDanmakuLiveSurface: UIViewRepresentable {
    let items: [DYDanmaku]
    let clock: DYDanmakuClock
    let regionTop: CGFloat
    let regionHeight: CGFloat
    let lanes: Int
    let density: DYDanmakuPolicy.Density
    let deduplicate: Bool

    func makeUIView(context: Context) -> DYDanmakuEngineView { DYDanmakuEngineView() }
    func updateUIView(_ v: DYDanmakuEngineView, context: Context) {
        v.update(items: items, clock: clock, regionTop: regionTop, regionHeight: regionHeight,
                 lanes: lanes, density: density, deduplicate: deduplicate)
    }
    static func dismantleUIView(_ v: DYDanmakuEngineView, coordinator: ()) { v.stop() }
}

#if DEBUG
enum DDDanmakuIdleStat { static var stops = 0 }
#endif
