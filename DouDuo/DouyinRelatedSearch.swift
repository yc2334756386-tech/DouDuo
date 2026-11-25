import SwiftUI
import WebKit

@MainActor
final class DYNativeSearchTransport: NSObject, WKNavigationDelegate {
    typealias Page = (items: [DYAweme], cursor: String, hasMore: Bool)
    let web: WKWebView
    private let keyword: String
    private let bridge: DouyinBridge?
    private let musicID: String?
    private var apiCursor = "0"
    private var fallback: Task<Void, Never>?
    private var pageRequest: Task<Void, Never>?
    private var pending: CheckedContinuation<Page, Error>?
    private var timeout: Task<Void, Never>?
    private var settle: Task<Void, Never>?
    private var buffered: [DYAweme] = []
    private var seen: Set<String> = []
    private var delivered = 0
    private var hasMore = true
    private var started = false
    private var generation = 0

    init(keyword: String, bridge: DouyinBridge? = nil, musicID: String? = nil) {
        self.keyword = keyword
        self.bridge = bridge
        self.musicID = musicID
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.mediaTypesRequiringUserActionForPlayback = .all
        DYLogoutBlock.install(in: config)
        let receiver = DYNativeSearchReceiver()
        config.userContentController.add(receiver, name: "ddNativeSearch")
        config.userContentController.addUserScript(WKUserScript(source: Self.captureJS,
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900), configuration: config)
        super.init()
        receiver.owner = self
        web.customUserAgent = DouyinWeb.userAgent
        web.navigationDelegate = self
    }

    func page(_ cursor: String) async throws -> Page {
        if cursor == "0" {
            close()
            seen.removeAll()
            delivered = 0
            hasMore = true
            apiCursor = "0"
        }
        if !buffered.isEmpty { return takeBuffered() }
        guard hasMore else { return ([], String(delivered), false) }
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            let requestGeneration = generation
            let requestCursor = apiCursor
            fallback = Task { [weak self] in
                guard let self, let bridge = self.bridge else { return }
                do {
                    let result: Page
                    if let musicID = self.musicID { result = try await bridge.musicVideos(musicID, cursor: requestCursor) }
                    else { result = try await bridge.search(self.keyword, offset: requestCursor) }
                    guard self.generation == requestGeneration else { return }
                    self.apiCursor = result.cursor
                    self.accept(result.items, more: result.hasMore)
                } catch {}
            }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(12)) } catch { return }
                guard let self else { return }
                self.fail("搜索请求超时，点重试搜索。如账号需要验证，请先在「我的」中登录。")
            }
            if !started {
                started = true
                Task { [weak self] in
                    _ = await DYAccountStore.shared.restoreCurrentSessionIfMissing()
                    guard let self, self.pending != nil else { return }
                    let url: URL?
                    if let musicID = self.musicID { url = URL(string: "https://www.douyin.com/music/")?.appendingPathComponent(musicID) }
                    else { url = DYSearchScreen.videoSearchURL(self.keyword) }
                    guard let url else { return }
                    self.web.load(URLRequest(url: url))
                }
            } else {
                web.evaluateJavaScript(Self.scrollJS, completionHandler: nil)
            }
        }
    }

    func close() {
        generation += 1
        timeout?.cancel()
        settle?.cancel()
        fallback?.cancel()
        pageRequest?.cancel()
        pending?.resume(throwing: CancellationError())
        pending = nil
        buffered.removeAll()
        started = false
        web.stopLoading()
    }

    fileprivate func receive(_ raw: String) async {
        let requestGeneration = generation
        let script = DouyinBridge.requestJS + Self.mapJS
        guard let value = try? await web.callAsyncJavaScript(script,
            arguments: ["responseText": raw], contentWorld: .page),
              let text = value as? String, let data = text.data(using: .utf8),
              let result = try? JSONDecoder().decode(SearchResponse.self, from: data),
              requestGeneration == generation else { return }
        guard result.code == nil || result.code == 0 else { return }
        if let cursor = result.cursor, !cursor.isEmpty { apiCursor = cursor }
        accept(result.items, more: result.hasMore)
    }

    private func accept(_ items: [DYAweme], more: Bool?) {
        if items.isEmpty, buffered.isEmpty, delivered == 0 { return }
        for item in items where item.play != nil || !item.images.isEmpty {
            if seen.insert(item.id).inserted { buffered.append(item) }
        }
        if let more { hasMore = more }
        guard !buffered.isEmpty || !hasMore else { return }
        settle?.cancel()
        settle = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard let self, let continuation = self.pending else { return }
            self.pending = nil
            self.timeout?.cancel()
            continuation.resume(returning: self.takeBuffered())
        }
    }

    private func takeBuffered() -> Page {
        let items = buffered
        buffered.removeAll()
        delivered += items.count
        return (items, String(delivered), hasMore)
    }

    private func fail(_ message: String) {
        guard let continuation = pending else { return }
        pending = nil
        timeout?.cancel()
        settle?.cancel()
        continuation.resume(throwing: DYError.bad(message))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { fail("搜索连接失败，点重试搜索。") }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        started = false
        fail("搜索页面已暂停，点重试搜索。")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let requestGeneration = generation
        pageRequest = Task { [weak self] in
            guard let self else { return }
            if let raw = try? await self.web.evaluateJavaScript(Self.harvestJS) as? String {
                await self.receive(raw)
            }
            guard self.generation == requestGeneration, self.pending != nil else { return }
            let body = self.musicID == nil ? DouyinBridge.searchJS : DouyinBridge.musicWorksJS
            let arguments = ["kw": self.keyword, "mid": self.musicID ?? "", "cursor": self.apiCursor]
            guard let value = try? await self.web.callAsyncJavaScript(DouyinBridge.requestJS + body,
                arguments: arguments, contentWorld: .page), let text = value as? String,
                  let data = text.data(using: .utf8),
                  let result = try? JSONDecoder().decode(SearchResponse.self, from: data),
                  self.generation == requestGeneration, result.code == nil || result.code == 0 else { return }
            if let cursor = result.cursor { self.apiCursor = cursor }
            self.accept(result.items, more: result.hasMore)
        }
    }

    private struct SearchResponse: Decodable {
        let items: [DYAweme]
        let hasMore: Bool?
        let code: Int?
        let cursor: String?
    }

    private static let captureJS = #"""
    (() => {
      const wanted = url => /\/(?:search\/item|general\/search\/(?:single|stream)|music\/aweme)(?:[/?]|$)/.test(String(url));
      const post = text => { try { window.webkit.messageHandlers.ddNativeSearch.postMessage(text); } catch (_) {} };
      const fetch = window.fetch;
      window.fetch = function(input) {
        const url = typeof input === 'string' ? input : input && input.url;
        return fetch.apply(this, arguments).then(response => {
          if (wanted(url) || wanted(response.url)) response.clone().text().then(post).catch(() => {});
          return response;
        });
      };
      const open = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        if (wanted(url)) this.addEventListener('load', function() {
          try { post(typeof this.response === 'string' ? this.response : JSON.stringify(this.response)); } catch (_) {}
        });
        return open.apply(this, arguments);
      };
      const stopMedia = () => document.querySelectorAll('video,audio').forEach(media => { media.muted = true; media.pause(); });
      document.addEventListener('play', stopMedia, true);
      document.addEventListener('DOMContentLoaded', stopMedia);
    })();
    """#

    private static let mapJS = #"""
    const ddRoot = parse(responseText);
    const ddFrames = ddRoot ? [ddRoot] : String(responseText).split(/\r?\n/).map(line => parse(line.replace(/^data:\s*/, ''))).filter(Boolean);
    const ddItems = [], ddSeen = new Set();
    const ddVisit = (node, depth) => {
      if (typeof node === 'string' && /^\s*[\[{]/.test(node)) { const nested = parse(node); if (nested && depth < 10) ddVisit(nested, depth + 1); return; }
      if (!node || typeof node !== 'object' || depth > 10) return;
      if (node.aweme_id && (node.video || node.images)) {
        const id = String(node.aweme_id);
        if (!ddSeen.has(id) && !node.is_ads) { ddSeen.add(id); ddItems.push(mapA(node)); }
        return;
      }
      for (const value of Object.values(node)) ddVisit(value, depth + 1);
    };
    for (const frame of ddFrames) ddVisit(frame, 0);
    const ddMeta = ddFrames.find(frame => frame && frame.has_more != null);
    const ddCode = ddFrames.find(frame => frame && frame.status_code != null);
    const ddCursor = ddFrames.find(frame => frame && frame.cursor != null);
    return JSON.stringify({ items: ddItems, hasMore: ddMeta ? Number(ddMeta.has_more) === 1 : null,
      code: ddCode ? Number(ddCode.status_code) : null, cursor:ddCursor ? String(ddCursor.cursor) : null });
    """#

    private static let harvestJS = #"""
    (() => {
      const roots = [];
      for (const script of document.querySelectorAll('script#RENDER_DATA,script#__NEXT_DATA__,script[type="application/json"]')) {
        let text = script.textContent || '';
        try { text = decodeURIComponent(text); } catch (_) {}
        try { roots.push(JSON.parse(text)); } catch (_) {}
      }
      for (const value of [window._ROUTER_DATA, window.__INITIAL_STATE__]) if (value && typeof value === 'object') roots.push(value);
      const scoped = [];
      const select = (node, depth) => {
        if (!node || typeof node !== 'object' || depth > 5) return;
        for (const [key, value] of Object.entries(node)) {
          if (/search|musicaweme|music_aweme/i.test(key) && value && typeof value === 'object') scoped.push(value);
          else select(value, depth + 1);
        }
      };
      roots.forEach(root => select(root, 0));
      return JSON.stringify(scoped.length ? scoped : roots);
    })();
    """#

    private static let scrollJS = #"""
    (() => {
      const candidates = [...document.querySelectorAll('main,[role="main"],div')]
        .filter(element => element.clientHeight > 180 && element.scrollHeight > element.clientHeight + 80);
      candidates.sort((a, b) => b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight);
      for (const element of candidates.slice(0, 4)) { element.scrollTop = element.scrollHeight; element.dispatchEvent(new Event('scroll', {bubbles:true})); }
      window.scrollTo(0, document.documentElement.scrollHeight);
      window.dispatchEvent(new Event('scroll'));
    })();
    """#
}

private final class DYNativeSearchReceiver: NSObject, WKScriptMessageHandler {
    weak var owner: DYNativeSearchTransport?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let text = message.body as? String else { return }
        Task { @MainActor [weak owner] in await owner?.receive(text) }
    }
}

struct DYNativeSearchHost: UIViewRepresentable {
    let transport: DYNativeSearchTransport
    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.clipsToBounds = true
        container.isUserInteractionEnabled = false
        container.addSubview(transport.web)
        return container
    }
    func updateUIView(_ view: UIView, context: Context) {}
}

extension DouyinBridge {
    /// 网页真实的 related_search 推荐词；接口无词时不展示，不用标题或本地词凑数。
    func relatedSearch(for item: DYAweme) async -> [String] {
        let js = #"""
        const r = await req('GET', '/aweme/v1/web/api/suggest_words/?' + q({
          query: query, business_id: '30125', aid: '6383', app_name: 'douyin_web', pd: 'aweme_general', gid: id
        }));
        const d = parse(r.t);
        const words = r.s === 200 && d && String(d.errno || 0) === '0'
          ? (d.data || []).filter(g => g.type === 'related_search' || g.source === 'related_search')
              .flatMap(g => (g.words || []).map(w => w.word).filter(w => typeof w === 'string' && w.trim())) : [];
        return JSON.stringify([...new Set(words)].slice(0, 6));
        """#
        guard let d = try? await call(js, args: ["query": String(item.desc.prefix(100)), "id": item.id], attempts: 1),
              let words = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return words
    }
}

struct DYRelatedQuery: Identifiable {
    let word: String
    var id: String { word }
}

/// 复用现有原生搜索、作者主页和网页登录组件。
struct DYRelatedSearchScreen: View {
    let bridge: DouyinBridge
    let word: String
    var session: DYSearchSession? = nil
    var onClose: (() -> Void)? = nil
    @State private var author: DYAweme.Author?
    @State private var web: DYWebTarget?

    var body: some View {
        DYSearchScreen(bridge: bridge, onAuthor: { author = $0.author }, initialQuery: word,
                       session: session, onClose: onClose)
            .sheet(item: $author) { a in
                NavigationStack {
                    DYAuthorScreen(bridge: bridge, author: a, onWeb: { url in
                        author = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { web = DYWebTarget(url: url) }
                    })
                }
            }
            .fullScreenCover(item: $web) { t in DouyinWebScreen(start: t.url) }
    }
}
