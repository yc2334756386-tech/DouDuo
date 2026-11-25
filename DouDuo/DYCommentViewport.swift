import SwiftUI
import UIKit

@MainActor
final class DYCxxCache {
    private let core = DYCacheCreate(512 * 1024)
    deinit { DYCacheDestroy(core) }
    func put(_ data: Data, key: String) {
        key.withCString { key in data.withUnsafeBytes { DYCachePut(core, key, $0.baseAddress, $0.count) } }
    }
    func data(_ key: String) -> Data? {
        key.withCString { key in
            let count = DYCacheCopy(core, key, nil, 0)
            guard count > 0 else { return nil }
            var output = Data(count: count)
            let copied = output.withUnsafeMutableBytes { DYCacheCopy(core, key, $0.baseAddress, $0.count) }
            return copied == count ? output : nil
        }
    }
    func remove(_ key: String) { key.withCString { DYCacheRemove(core, $0) } }
    func clear() { DYCacheClear(core) }
}

final class DYCxxUniqueIDs {
    private let core = DYIndexCreate()
    deinit { DYIndexDestroy(core) }
    func insert(_ key: String) -> Bool { key.withCString { DYIndexInsert(core, $0) } }
    func clear() { DYIndexClear(core) }
}

@MainActor
final class DYCommentWindow: ObservableObject {
    struct Page { let cursor: Int; let ids: [String] }
    @Published private(set) var revision = 0
    @Published private(set) var total = 0
    private(set) var ids: [String] = []
    private(set) var loading = false
    private(set) var hasMore = true
    private(set) var error: String?
    private var cursor = 0
    private var pages: [Page] = []
    private var pageForID: [String: Int] = [:]
    private let cache = DYCxxCache()
    private let unique = DYCxxUniqueIDs()
    private var decoded: [String: DYComment] = [:]
    private var visible: Set<String> = []
    private var cachedPages: Set<Int> = []
    private var failedPages: Set<Int> = []
    private var unavailable: Set<String> = []
    private var requests: [Int: Task<Void, Never>] = [:]
    private var generation = 0
    let bridge: DouyinBridge
    let aweme: DYAweme
    let focus: DYCommentFocus?

    init(bridge: DouyinBridge, aweme: DYAweme, focus: DYCommentFocus?) {
        self.bridge = bridge; self.aweme = aweme; self.focus = focus
        total = aweme.stats.comment
    }

    func loadNext() async {
        guard !loading, hasMore else { return }
        loading = true; error = nil; revision += 1
        let token = generation
        let requestedCursor = cursor
        defer { if generation == token { loading = false; revision += 1 } }
        do {
            let insert = pages.isEmpty ? focus.map { [$0.parentCid, $0.cid].compactMap { $0 }.joined(separator: ",") } : nil
            let result = try await bridge.fetchComments(aweme.id, cursor: requestedCursor, insert: insert)
            guard !Task.isCancelled, generation == token else { return }
            let comments = result.items.filter { unique.insert($0.id) }
            let page = pages.count
            pages.append(Page(cursor: requestedCursor, ids: comments.map(\.id)))
            for comment in comments { pageForID[comment.id] = page }
            ids.append(contentsOf: comments.map(\.id))
            store(comments, page: page)
            hasMore = result.hasMore && !result.items.isEmpty && result.cursor != requestedCursor
            cursor = result.cursor
            total = max(total, result.total)
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    private func store(_ comments: [DYComment], page: Int) {
        let encoder = JSONEncoder()
        for comment in comments {
            if let data = try? encoder.encode(comment) { cache.put(data, key: comment.id) }
        }
        cachedPages.insert(page)
    }

    func comment(at row: Int) -> DYComment? {
        guard ids.indices.contains(row) else { return nil }
        let id = ids[row]
        guard !unavailable.contains(id) else { return nil }
        if let comment = decoded[id] { return comment }
        if let data = cache.data(id), let comment = try? JSONDecoder().decode(DYComment.self, from: data) {
            decoded[id] = comment
            return comment
        }
        reloadPage(for: id)
        return nil
    }

    private func reloadPage(for id: String) {
        guard let page = pageForID[id], requests[page] == nil, !failedPages.contains(page) else { return }
        let token = generation
        let pageCursor = pages[page].cursor
        requests[page] = Task { [weak self] in
            guard let self else { return }
            defer { self.requests[page] = nil }
            do {
                let result = try await self.bridge.fetchComments(self.aweme.id, cursor: pageCursor, insert: id)
                guard !Task.isCancelled, self.generation == token,
                      self.pages[page].ids.contains(where: self.visible.contains) else { return }
                self.store(result.items, page: page)
                if !result.items.contains(where: { $0.id == id }) { self.unavailable.insert(id) }
                self.revision += 1
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.failedPages.insert(page)
                self.error = error.localizedDescription; self.revision += 1
            }
        }
    }

    func setVisible(rows: [Int]) {
        visible = Set(rows.compactMap { ids.indices.contains($0) ? ids[$0] : nil })
        decoded = decoded.filter { visible.contains($0.key) }
        guard !visible.isEmpty else { return }
        let keep = Set(visible.compactMap { pageForID[$0] })
        for page in cachedPages.subtracting(keep) {
            for id in pages[page].ids { cache.remove(id) }
            cachedPages.remove(page)
        }
        for page in Array(requests.keys) where !keep.contains(page) {
            requests.removeValue(forKey: page)?.cancel()
        }
    }

    func clear() {
        generation += 1
        requests.values.forEach { $0.cancel() }; requests.removeAll()
        decoded.removeAll(); cache.clear(); cachedPages.removeAll(); visible.removeAll()
        ids.removeAll(); pages.removeAll(); pageForID.removeAll(); unique.clear()
        failedPages.removeAll(); unavailable.removeAll()
        cursor = 0; hasMore = true; loading = false; error = nil; revision += 1
    }

    func trimMemory() {
        cache.clear()
        cachedPages.removeAll()
        decoded = decoded.filter { visible.contains($0.key) }
    }

    func rowMessage(_ row: Int) -> String? {
        guard ids.indices.contains(row) else { return nil }
        if unavailable.contains(ids[row]) { return "这条评论已不可见" }
        if let page = pageForID[ids[row]], failedPages.contains(page) { return "加载失败，点击下方重试" }
        return nil
    }

    func retry() async {
        failedPages.removeAll()
        error = nil
        for id in visible where cache.data(id) == nil && !unavailable.contains(id) { reloadPage(for: id) }
        if requests.isEmpty { await loadNext() }
        revision += 1
    }
}

struct DYCommentViewport: View {
    @StateObject private var model: DYCommentWindow
    @Binding var atTop: Bool
    let onAuthor: (DYAweme.Author) -> Void
    let onTotal: (Int) -> Void

    init(bridge: DouyinBridge, aweme: DYAweme, focus: DYCommentFocus?, atTop: Binding<Bool>,
         onAuthor: @escaping (DYAweme.Author) -> Void, onTotal: @escaping (Int) -> Void) {
        _model = StateObject(wrappedValue: DYCommentWindow(bridge: bridge, aweme: aweme, focus: focus))
        _atTop = atTop; self.onAuthor = onAuthor; self.onTotal = onTotal
    }
    var body: some View {
        DYNativeCommentList(model: model, atTop: $atTop, onAuthor: onAuthor)
            .task {
                do { try await Task.sleep(for: .milliseconds(320)) } catch { return }
                await model.loadNext()
            }
            .onReceive(model.$total, perform: onTotal)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                model.trimMemory()
            }
    }
}

private struct DYNativeCommentList: UIViewRepresentable {
    @ObservedObject var model: DYCommentWindow
    @Binding var atTop: Bool
    let onAuthor: (DYAweme.Author) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITableView {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 112
        table.isPrefetchingEnabled = false
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.register(DYReusableCommentCell.self, forCellReuseIdentifier: "comment")
        table.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 20, right: 0)
        table.accessibilityIdentifier = "douyin.comments.list"
        context.coordinator.table = table
        return table
    }
    func updateUIView(_ table: UITableView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refresh()
    }
    static func dismantleUIView(_ table: UITableView, coordinator: Coordinator) {
        coordinator.parent.model.clear()
    }

    @MainActor
    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var parent: DYNativeCommentList
        weak var table: UITableView?
        private var revision = -1
        private var rows = 0
        private var heights: [Int: CGFloat] = [:]
        private var didFocus = false
        init(_ parent: DYNativeCommentList) { self.parent = parent }
        func refresh() {
            guard let table, revision != parent.model.revision else { return }
            revision = parent.model.revision
            if rows != parent.model.ids.count {
                let previous = rows
                rows = parent.model.ids.count
                if rows > previous {
                    table.insertRows(at: (previous..<rows).map { IndexPath(row: $0, section: 0) }, with: .none)
                } else { table.reloadData() }
            }
            for path in table.indexPathsForVisibleRows ?? [] {
                if let cell = table.cellForRow(at: path) { configure(cell, row: path.row) }
            }
            let button = UIButton(type: .system)
            button.frame.size = CGSize(width: max(table.bounds.width, 100), height: 64)
            button.setTitle(parent.model.error.map { $0 + " · 点击重试" } ??
                (parent.model.loading ? "正在加载…" : parent.model.hasMore ? "继续查看评论" : rows == 0 ? "还没有评论" : "已显示全部评论"), for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
            button.titleLabel?.numberOfLines = 2
            button.isEnabled = !parent.model.loading && (parent.model.hasMore || parent.model.error != nil)
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                Task {
                    if self.parent.model.error != nil { await self.parent.model.retry() }
                    else { await self.parent.model.loadNext() }
                }
            }, for: .touchUpInside)
            table.tableFooterView = button
            if !didFocus, let focus = parent.model.focus,
               let row = parent.model.ids.firstIndex(of: focus.parentCid ?? focus.cid) {
                didFocus = true
                table.scrollToRow(at: IndexPath(row: row, section: 0), at: .top, animated: false)
            }
        }
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "comment", for: indexPath)
            cell.backgroundColor = .clear; cell.selectionStyle = .none
            cell.contentConfiguration = nil
            (cell as? DYReusableCommentCell)?.representedID = nil
            return cell
        }
        private func configure(_ cell: UITableViewCell, row: Int) {
            guard let comment = parent.model.comment(at: row) else {
                let message = parent.model.rowMessage(row)
                cell.contentConfiguration = UIHostingConfiguration {
                    Group {
                        if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                        else { ProgressView() }
                    }.frame(maxWidth: .infinity, minHeight: 72)
                }
                    .margins(.all, 12)
                return
            }
            let reusable = cell as? DYReusableCommentCell
            guard reusable?.representedID != comment.id else { return }
            reusable?.representedID = comment.id
            let bridge = parent.model.bridge, awemeID = parent.model.aweme.id, onAuthor = parent.onAuthor
            cell.contentConfiguration = UIHostingConfiguration {
                DYViewportCommentThread(bridge: bridge, awemeID: awemeID, comment: comment, onAuthor: onAuthor)
                    .id(comment.id)
            }.margins(.all, 14)
        }
        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            configure(cell, row: indexPath.row)
            updateVisible()
        }
        func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            heights[indexPath.row] = cell.bounds.height
            cell.contentConfiguration = nil
            (cell as? DYReusableCommentCell)?.representedID = nil
            updateVisible()
        }
        func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
            heights[indexPath.row] ?? 112
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let top = scrollView.contentOffset.y + scrollView.adjustedContentInset.top <= 1
            if parent.atTop != top { parent.atTop = top }
            updateVisible()
            let bottom = scrollView.contentOffset.y + scrollView.bounds.height - scrollView.adjustedContentInset.bottom
            if bottom >= scrollView.contentSize.height - 64, scrollView.isDragging || scrollView.isDecelerating {
                Task { await parent.model.loadNext() }
            }
        }
        private func updateVisible() {
            guard let paths = table?.indexPathsForVisibleRows, !paths.isEmpty else { return }
            parent.model.setVisible(rows: paths.map(\.row))
        }
    }
}

private final class DYReusableCommentCell: UITableViewCell {
    var representedID: String?
    override func prepareForReuse() {
        super.prepareForReuse()
        contentConfiguration = nil
        representedID = nil
    }
}

struct DYViewportThumbnail: UIViewRepresentable {
    let url: URL?
    let maxPixel: Int
    func makeUIView(context: Context) -> DYViewportImageView { DYViewportImageView() }
    func updateUIView(_ view: DYViewportImageView, context: Context) { view.configure(url: url, maxPixel: maxPixel) }
    static func dismantleUIView(_ view: DYViewportImageView, coordinator: ()) { view.releaseImage() }
}

final class DYViewportImageView: UIImageView {
    private var source: URL?
    private var maxPixel = 384
    private var visible = false
    private var generation = 0
    private var loading: Task<Void, Never>?
    private weak var viewport: UIScrollView?
    private var observation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        backgroundColor = .secondarySystemFill
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(url: URL?, maxPixel: Int) {
        if source != url || self.maxPixel != maxPixel {
            releaseImage()
            source = url
            self.maxPixel = maxPixel
        }
        updateVisibility()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        observation = nil
        guard window != nil else { releaseImage(); return }
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView {
                viewport = scroll
                observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.updateVisibility() }
                }
                break
            }
            ancestor = view.superview
        }
        updateVisibility()
    }
    override func layoutSubviews() { super.layoutSubviews(); updateVisibility() }

    private func updateVisibility() {
        let intersects = viewport.map { convert(bounds, to: $0).intersects($0.bounds) } ?? true
        let nowVisible = window != nil && bounds.width > 0 && bounds.height > 0 && intersects
        guard nowVisible != visible else { return }
        visible = nowVisible
        guard nowVisible, let source else { releaseImage(); return }
        let token = generation
        let pixels = maxPixel
        loading = Task { [weak self] in
            var request = URLRequest(url: source)
            request.cachePolicy = .returnCacheDataElseLoad
            DYMedia.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !Task.isCancelled else { return }
            let decoded = await Task.detached(priority: .utility) { ImageCache.downsample(data, maxPixel: pixels) }.value
            guard !Task.isCancelled, let self, self.generation == token, self.visible else { return }
            self.image = decoded
        }
    }
    func releaseImage() {
        generation += 1
        loading?.cancel()
        loading = nil
        image = nil
        visible = false
    }
}

private struct DYViewportCommentThread: View {
    let bridge: DouyinBridge
    let awemeID: String
    let comment: DYComment
    let onAuthor: (DYAweme.Author) -> Void
    @State private var replies: [DYComment] = []
    @State private var cursor = 0
    @State private var more = true
    @State private var loading = false
    @State private var error: String?
    @State private var replyRequest = 0
    @State private var processedReplyRequest = 0

    init(bridge: DouyinBridge, awemeID: String, comment: DYComment, onAuthor: @escaping (DYAweme.Author) -> Void) {
        self.bridge = bridge
        self.awemeID = awemeID
        self.comment = comment
        self.onAuthor = onAuthor
        _replies = State(initialValue: comment.pinned ?? [])
        _more = State(initialValue: comment.replies > (comment.pinned?.count ?? 0))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(comment)
            if !replies.isEmpty {
                ForEach(replies) { reply in row(reply).padding(.leading, 38) }
            }
            if comment.replies > 0, more {
                Button(error ?? (loading ? "正在加载…" : "查看回复")) {
                    replyRequest += 1
                }.font(.caption).padding(.leading, 42).disabled(loading)
            }
        }
        .task(id: replyRequest) {
            guard replyRequest > processedReplyRequest else { return }
            processedReplyRequest = replyRequest
            await loadReplies()
        }
    }
    private func row(_ item: DYComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { onAuthor(.init(name: item.name, avatar: item.avatar, secUid: item.sec, uid: item.uid)) } label: {
                CachedAsyncImage(url: item.avatar.flatMap(URL.init(string:)), thumbnailMaxPixel: 96, ephemeral: true) {
                    $0.resizable().scaledToFill()
                } placeholder: { Color.primary.opacity(0.08) }
                    .frame(width: 32, height: 32).clipShape(Circle())
            }.buttonStyle(.plain).disabled(item.sec == nil && item.uid == nil)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if !item.text.isEmpty { DYEmojiStore.shared.rich(item.text).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
                DYCommentMedia(comment: item)
                Text([DYFormat.time(item.time), item.ip].compactMap { $0 }.joined(separator: "  "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if item.digg > 0 { Label(DYFormat.count(item.digg), systemImage: "heart").font(.caption2).foregroundStyle(.secondary) }
        }
        .contextMenu { Button("复制评论", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.text } }
        .accessibilityIdentifier("douyin.comment.row")
    }
    private func loadReplies() async {
        guard !loading else { return }; loading = true
        defer { loading = false }
        do {
            let result = try await bridge.fetchReplies(awemeID, commentID: comment.id, cursor: cursor)
            guard !Task.isCancelled else { return }
            let ids = Set(replies.map(\.id))
            replies.append(contentsOf: result.items.filter { !ids.contains($0.id) })
            more = result.hasMore && !result.items.isEmpty && result.cursor != cursor
            cursor = result.cursor; error = nil
        } catch { self.error = "回复加载失败，点击重试" }
    }
}
