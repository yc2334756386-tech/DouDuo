import SwiftUI
import WebKit

extension DYUser: Identifiable {
    var id: String { secUid.isEmpty ? uid : secUid }
}

struct DYUserSearchPage: Decodable {
    let status: Int
    let code: Int
    let items: [DYUser]
    let cursor: String
    let hasMore: Bool
}

struct DYUserSearchResults: View {
    let bridge: DouyinBridge
    let query: String
    let onAuthor: (DYAweme.Author) -> Void
    let onVerification: () -> Void
    @StateObject private var pager: DYSimplePager<DYUser>

    init(bridge: DouyinBridge, query: String, onAuthor: @escaping (DYAweme.Author) -> Void,
         onVerification: @escaping () -> Void = {}) {
        self.bridge = bridge
        self.query = query
        self.onAuthor = onAuthor
        self.onVerification = onVerification
        _pager = StateObject(wrappedValue: DYSimplePager { cursor in try await bridge.searchUsers(query, cursor: cursor) })
    }
    var body: some View {
        List {
            ForEach(pager.items) { user in
                Button {
                    onAuthor(.init(name: user.name, avatar: user.avatar, secUid: user.secUid.isEmpty ? nil : user.secUid,
                                   uid: user.uid))
                } label: {
                    HStack(spacing: 12) {
                        CachedAsyncImage(url: user.avatar.flatMap(URL.init(string:)), thumbnailMaxPixel: 144) {
                            $0.resizable().scaledToFill()
                        } placeholder: { Color.primary.opacity(0.08) }
                            .frame(width: 48, height: 48).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("\(DYFormat.count(user.followers)) 粉丝 · \(DYFormat.count(user.works)) 作品")
                                .font(.caption).foregroundStyle(.secondary)
                            if !user.signature.isEmpty { Text(user.signature).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("douyin.search.user")
            }
            if let error = pager.error {
                Button(error + " · 点击重试") { Task { await pager.reload() } }
                    .font(.footnote).foregroundStyle(.secondary)
            } else if pager.hasMore {
                ProgressView().frame(maxWidth: .infinity).onAppear { Task { await pager.more() } }
            } else if pager.items.isEmpty {
                Text("没有找到相关用户").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
        .listStyle(.plain)
        .refreshable { await pager.reload() }
        .task { if pager.items.isEmpty { await pager.more() } }
        .onChange(of: pager.needsVerification) { _, required in if required { onVerification() } }
    }
}

@MainActor
final class DYNativeSearchTransport: NSObject, WKNavigationDelegate {
    typealias Page = (items: [DYAweme], cursor: String, hasMore: Bool)
    let web: WKWebView
    private let keyword: String
    private let bridge: DouyinBridge?
    private let musicID: String?
    private let order: DYSearchOrder
    var onNeedsVerification: (() -> Bool)?
    var onVerificationSucceeded: (() -> Void)?
    private(set) var isVerifying = false
    private var verificationCompleted = false
    private var verificationUsers = false
    private var verificationMonitor: Task<Void, Never>?
    private var apiCursor = "0"
    private var fallback: Task<Void, Never>?
    private var pageRequest: Task<Void, Never>?
    private var alternatePage: Task<Void, Never>?
    private var loadingPage: Task<Void, Never>?
    private var confirmedEmpty = false
    private var requestSerial = 0
    private var pending: CheckedContinuation<Page, Error>?
    private var timeout: Task<Void, Never>?
    private var settle: Task<Void, Never>?
    private var buffered: [DYAweme] = []
    private var seen: Set<String> = []
    private var delivered = 0
    private var hasMore = true
    private var started = false
    private var generation = 0

    init(keyword: String, bridge: DouyinBridge? = nil, musicID: String? = nil, order: DYSearchOrder = .standard) {
        self.keyword = keyword
        self.bridge = bridge
        self.musicID = musicID
        self.order = order
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
            confirmedEmpty = false
        }
        if !buffered.isEmpty { return takeBuffered() }
        guard hasMore else { return ([], String(delivered), false) }
        return try await withCheckedThrowingContinuation { continuation in
            pending?.resume(throwing: CancellationError())
            pending = continuation
            confirmedEmpty = false
            requestSerial += 1
            let serial = requestSerial
            let requestGeneration = generation
            let requestCursor = apiCursor
            fallback = Task { [weak self] in
                guard let self, let bridge = self.bridge else { return }
                do {
                    let result: Page
                    if let musicID = self.musicID { result = try await bridge.musicVideos(musicID, cursor: requestCursor) }
                    else { result = try await bridge.search(self.keyword, offset: requestCursor, sortType: self.order.apiSort) }
                    guard self.generation == requestGeneration, self.requestSerial == serial else { return }
                    self.apiCursor = result.cursor
                    self.accept(result.items, more: result.hasMore, validEmpty: true)
                } catch {
                    guard self.generation == requestGeneration, self.requestSerial == serial else { return }
                    if error is DYSearchVerificationRequired { self.requestVerification() }
                }
            }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(self?.musicID == nil ? 18 : 24)) } catch { return }
                guard let self, self.generation == requestGeneration, self.requestSerial == serial else { return }
                if self.confirmedEmpty {
                    self.hasMore = false
                    self.pending?.resume(returning: self.takeBuffered())
                    self.pending = nil
                } else {
                    self.fail(self.musicID == nil ? "搜索请求超时，点重试搜索。如账号需要验证，请先在「我的」中登录。" : "原声作品暂时无法获取，点击重试。可下拉刷新重新加载。")
                }
            }
            if !started {
                started = true
                loadingPage = Task { [weak self] in
                    _ = await DYAccountStore.shared.restoreCurrentSessionIfMissing()
                    guard let self, self.generation == requestGeneration, self.pending != nil else { return }
                    let url: URL?
                    if let musicID = self.musicID { url = URL(string: "https://www.douyin.com/music/")?.appendingPathComponent(musicID) }
                    else { url = DYSearchScreen.videoSearchURL(self.keyword, order: self.order) }
                    guard let url else { return }
                    self.web.load(URLRequest(url: url))
                }
                if let musicID {
                    alternatePage = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(5)) } catch { return }
                        guard let self, self.generation == requestGeneration, self.pending != nil, self.buffered.isEmpty,
                              let url = URL(string: "https://www.iesdouyin.com/share/music/\(musicID)/") else { return }
                        self.web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
                        self.web.load(URLRequest(url: url))
                    }
                }
            } else {
                web.evaluateJavaScript(Self.scrollJS, completionHandler: nil)
                requestDocumentPage()
            }
        }
    }

    func close() {
        generation += 1
        timeout?.cancel()
        settle?.cancel()
        fallback?.cancel()
        pageRequest?.cancel()
        alternatePage?.cancel()
        loadingPage?.cancel()
        verificationMonitor?.cancel()
        isVerifying = false
        verificationCompleted = false
        pending?.resume(throwing: CancellationError())
        pending = nil
        buffered.removeAll()
        started = false
        web.stopLoading()
        web.customUserAgent = DouyinWeb.userAgent
    }

    fileprivate func receive(_ raw: String) async {
        if let data = raw.data(using: .utf8),
           let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let kind = event["ddSearchEvent"] as? String {
            if let term = event["keyword"] as? String, !term.isEmpty, term != keyword { return }
            if kind == "verification" { requestVerification() }
            else if kind == "verified", isVerifying { finishVerification() }
            return
        }
        let requestGeneration = generation
        let script = DouyinBridge.requestJS + Self.mapJS
        guard let value = try? await web.callAsyncJavaScript(script,
            arguments: ["responseText": raw, "targetMusicID": musicID ?? ""], contentWorld: .page),
              let text = value as? String, let data = text.data(using: .utf8),
              let result = try? JSONDecoder().decode(SearchResponse.self, from: data),
              requestGeneration == generation else { return }
        if result.verification == true { requestVerification(); return }
        guard result.code == nil || result.code == 0 else { return }
        if let cursor = result.cursor, !cursor.isEmpty { apiCursor = cursor }
        accept(result.items, more: result.hasMore, validEmpty: result.code == 0)
    }

    private func accept(_ items: [DYAweme], more: Bool?, validEmpty: Bool = false) {
        if isVerifying {
            if !items.isEmpty || validEmpty { finishVerification() }
            return
        }
        if items.isEmpty, buffered.isEmpty, delivered == 0 {
            if validEmpty, more == false { confirmedEmpty = true }
            return
        }
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
            self.alternatePage?.cancel()
            continuation.resume(returning: self.takeBuffered())
        }
    }

    private func takeBuffered() -> Page {
        let items = buffered
        buffered.removeAll()
        delivered += items.count
        if apiCursor == "0", delivered > 0 { apiCursor = String(delivered) }
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
        if musicID == nil, (error as NSError).code != NSURLErrorCancelled { fail("搜索连接失败，点重试搜索。") }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        started = false
        fail("搜索页面已暂停，点重试搜索。")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if !isVerifying { requestDocumentPage() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let scheme = action.request.url?.scheme?.lowercased() ?? ""
        guard ["http", "https", "about", "blob", "data"].contains(scheme) else { decisionHandler(.cancel); return }
        decisionHandler(WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow)
    }

    private func requestDocumentPage() {
        let requestGeneration = generation
        let serial = requestSerial
        pageRequest?.cancel()
        pageRequest = Task { [weak self] in
            guard let self else { return }
            if let raw = try? await self.web.evaluateJavaScript(Self.harvestJS) as? String {
                await self.receive(raw)
            }
            guard !Task.isCancelled, self.generation == requestGeneration, self.requestSerial == serial, self.pending != nil else { return }
            if self.web.url?.host == "www.iesdouyin.com", let musicID = self.musicID {
                let body = DouyinBridge.requestJS + Self.sharedMusicPageJS
                guard let value = try? await self.web.callAsyncJavaScript(body,
                    arguments: ["mid": musicID, "cursor": self.apiCursor], contentWorld: .page) as? String,
                      !Task.isCancelled, self.generation == requestGeneration, self.requestSerial == serial else { return }
                await self.receive(value)
                return
            }
            let body = self.musicID == nil ? DouyinBridge.searchJS : DouyinBridge.musicWorksJS
            let arguments = ["kw": self.keyword, "mid": self.musicID ?? "", "cursor": self.apiCursor, "sortType": self.order.apiSort]
            guard let value = try? await self.web.callAsyncJavaScript(DouyinBridge.requestJS + body,
                arguments: arguments, contentWorld: .page), let text = value as? String,
                  let data = text.data(using: .utf8),
                  let result = try? JSONDecoder().decode(SearchResponse.self, from: data),
                  !Task.isCancelled, self.generation == requestGeneration, self.requestSerial == serial else { return }
            if result.verification == true { self.requestVerification(); return }
            guard result.code == nil || result.code == 0 else { return }
            if let cursor = result.cursor { self.apiCursor = cursor }
            self.accept(result.items, more: result.hasMore, validEmpty: result.code == 0)
        }
    }

    private static let sharedMusicPageJS = #"""
    const response = await req('GET', '/web/api/v2/music/list/aweme/?' +
      new URLSearchParams({music_id:mid,cursor:cursor,count:'20'}).toString());
    return response.t || '{}';
    """#

    private struct SearchResponse: Decodable {
        let items: [DYAweme]
        let hasMore: Bool?
        let code: Int?
        let cursor: String?
        let verification: Bool?
    }

    private func requestVerification() {
        guard musicID == nil, !isVerifying, onNeedsVerification != nil else { return }
        if onNeedsVerification?() == true {
            isVerifying = true
            timeout?.cancel()
        } else {
            fail("请点击网页验证，完成后重试搜索")
        }
    }

    func beginVerification(users: Bool) {
        isVerifying = true
        verificationCompleted = false
        verificationUsers = users
        timeout?.cancel()
        verificationMonitor?.cancel()
        if web.url == nil || (users && web.url?.query?.contains("type=user") != true) {
            if let url = DYSearchScreen.videoSearchURL(keyword, order: order, users: users) { web.load(URLRequest(url: url)) }
        }
        verificationMonitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self, self.isVerifying, !self.verificationCompleted else { return }
                let visible = (try? await self.web.evaluateJavaScript(Self.challengeVisibleJS)) as? Bool ?? false
                if !visible, !self.web.isLoading { await self.probeVerification() }
            }
        }
    }

    private func probeVerification() async {
        let body = verificationUsers ? DouyinBridge.searchUsersJS : DouyinBridge.searchJS
        guard let value = try? await web.callAsyncJavaScript(DouyinBridge.requestJS + body,
            arguments: ["kw": keyword, "cursor": "0", "sortType": order.apiSort], contentWorld: .page) as? String,
              let data = value.data(using: .utf8),
              let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              isVerifying, !Task.isCancelled,
              result["code"] as? Int == 0, result["items"] is [Any], result["verification"] as? Bool != true else { return }
        finishVerification()
    }

    private func finishVerification() {
        guard isVerifying, !verificationCompleted else { return }
        verificationCompleted = true
        verificationMonitor?.cancel()
        onVerificationSucceeded?()
    }

    func endVerification() {
        isVerifying = false
        verificationMonitor?.cancel()
        web.autoresizingMask = []
        web.frame = CGRect(x: 0, y: 0, width: 1280, height: 900)
        if pending != nil { fail(verificationCompleted ? "验证完成，正在重新搜索" : "验证未完成，点击重试或重新打开网页验证") }
    }

    private static let challengeVisibleJS = #"""
    (() => [...document.querySelectorAll('[id*="captcha"],[class*="captcha"],[id*="verify-center"],iframe[src*="verifycenter"],iframe[src*="captcha"]')]
      .some(element => { const rect=element.getBoundingClientRect(), style=getComputedStyle(element);
        return rect.width>40 && rect.height>30 && style.display!=='none' && style.visibility!=='hidden' && Number(style.opacity)!==0; }))()
    """#

    private static let captureJS = #"""
    (() => {
      const wanted = url => /\/(?:search\/item|discover\/search|general\/search\/(?:single|stream)|music\/aweme|music\/list\/aweme)(?:[/?]|$)/.test(String(url));
      const post = text => { try { window.webkit.messageHandlers.ddNativeSearch.postMessage(text); } catch (_) {} };
      const event = (kind,url) => {
        let keyword=''; try { keyword=new URL(url || location.href,location.href).searchParams.get('keyword') || ''; } catch (_) {}
        post(JSON.stringify({ddSearchEvent:kind,keyword:keyword}));
      };
      const inspect = (text, headers, url) => {
        let data; try { data=JSON.parse(text); } catch (_) {}
        if (data && Number(data.status_code)===0 && [data.aweme_list,data.user_list,data.data].some(Array.isArray)) {
          event('verified',url); return;
        }
        const message=String(data && (data.status_msg || data.message || data.prompt) || '');
        if (/(?:x-tt-verify-passport-decision|bdturing-verify|x-vc-bdturing-parameters)\s*:/i.test(headers || '') ||
            data && (data.verify_info || data.verify_data || data.verification_url || data.captcha) ||
            /人机验证|安全验证|验证码|完成验证|captcha|verifycenter/i.test(message)) event('verification',url);
      };
      const fetch = window.fetch;
      window.fetch = function(input) {
        const url = typeof input === 'string' ? input : input && input.url;
        return fetch.apply(this, arguments).then(response => {
          if (wanted(url) || wanted(response.url)) response.clone().text().then(text => {
            let headers=''; response.headers.forEach((value,key) => { headers+=key+':'+value+'\n'; });
            inspect(text,headers,response.url || url); post(text);
          }).catch(() => {});
          return response;
        });
      };
      const open = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        if (wanted(url)) this.addEventListener('load', function() {
          try {
            const text=typeof this.response==='string' ? this.response : JSON.stringify(this.response);
            inspect(text,this.getAllResponseHeaders(),this.responseURL || url); post(text);
          } catch (_) {}
        });
        return open.apply(this, arguments);
      };
      let scheduled=false;
      const checkChallenge = () => {
        scheduled=false;
        const visible=[...document.querySelectorAll('[id*="captcha"],[class*="captcha"],[id*="verify-center"],iframe[src*="verifycenter"],iframe[src*="captcha"]')]
          .some(element => {const rect=element.getBoundingClientRect(),style=getComputedStyle(element);
            return rect.width>40 && rect.height>30 && style.display!=='none' && style.visibility!=='hidden' && Number(style.opacity)!==0;});
        if (visible) event('verification',location.href);
      };
      const arm=() => {
        new MutationObserver(() => {if(!scheduled){scheduled=true;setTimeout(checkChallenge,250);}})
          .observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['style','class']});
        checkChallenge();
      };
      if(document.documentElement) arm(); else document.addEventListener('DOMContentLoaded',arm,{once:true});
      const stopMedia = () => document.querySelectorAll('video,audio').forEach(media => {media.muted=true;media.pause();});
      document.addEventListener('play',stopMedia,true);
      document.addEventListener('DOMContentLoaded',stopMedia);
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
        if (targetMusicID && String((node.music && (node.music.id_str || node.music.mid || node.music.id)) || '') !== targetMusicID) return;
        const id = String(node.aweme_id);
        if (!ddSeen.has(id) && !node.is_ads) { ddSeen.add(id); ddItems.push(mapA(node)); }
        return;
      }
      for (const value of Object.values(node)) ddVisit(value, depth + 1);
    };
    for (const frame of ddFrames) ddVisit(frame, 0);
    const ddMetadata = [];
    const ddFindMeta = (node, depth) => {
      if (!node || typeof node !== 'object' || depth > 8) return;
      if (node.has_more != null || node.status_code != null || node.cursor != null) ddMetadata.push(node);
      if (!node.aweme_id) for (const value of Object.values(node)) ddFindMeta(value, depth + 1);
    };
    ddFrames.forEach(frame => ddFindMeta(frame, 0));
    const ddMeta = ddMetadata.find(frame => frame.has_more != null);
    const ddCode = ddMetadata.find(frame => frame.status_code != null);
    const ddCursor = ddMetadata.find(frame => frame.cursor != null);
    return JSON.stringify({ items: ddItems, verification:ddNeedsVerification({h:''},ddRoot), hasMore: ddMeta ? Number(ddMeta.has_more) === 1 : null,
      code: ddCode ? Number(ddCode.status_code) : null, cursor:ddCursor ? String(ddCursor.cursor) : null });
    """#

    private static let harvestJS = #"""
    (() => {
      const roots = [];
      for (const script of document.querySelectorAll('script#RENDER_DATA,script#__NEXT_DATA__,script[type="application/json"]')) {
        let text = script.textContent || '';
        try { text = decodeURIComponent(text); } catch (_) {}
        try {
          text = text.replace(/("(?:id|mid|music_id|aweme_id|uid|user_id)"\s*:\s*)(-?\d{16,})(?=\s*[,}])/g, '$1"$2"');
          roots.push(JSON.parse(text));
        } catch (_) {}
      }
      for (const value of [window._ROUTER_DATA, window.__INITIAL_STATE__, window.__MODERN_ROUTER_DATA__, window.__SSR_DATA__]) if (value && typeof value === 'object') roots.push(value);
      const scoped = [];
      const select = (node, depth) => {
        if (!node || typeof node !== 'object' || depth > 5) return;
        for (const [key, value] of Object.entries(node)) {
          if (/search|music|aweme_list|item_list/i.test(key) && value && typeof value === 'object') scoped.push(value);
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
    func updateUIView(_ view: UIView, context: Context) {
        guard !transport.isVerifying, transport.web.superview !== view else { return }
        view.subviews.forEach { $0.removeFromSuperview() }
        transport.web.removeFromSuperview()
        transport.web.frame = CGRect(x: 0, y: 0, width: 1280, height: 900)
        view.addSubview(transport.web)
    }
}

struct DYSearchVerificationScreen: View {
    let transport: DYNativeSearchTransport
    let onCancel: () -> Void
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("请完成网页中的人机验证，通过后自动返回搜索")
                    .font(.footnote).foregroundStyle(.secondary).padding(12)
                DYVisibleSearchWeb(transport: transport)
            }
            .navigationTitle("搜索验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回搜索", action: onCancel) } }
        }
        .interactiveDismissDisabled()
    }
}

private struct DYVisibleSearchWeb: UIViewRepresentable {
    let transport: DYNativeSearchTransport
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        transport.web.removeFromSuperview()
        transport.web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        transport.web.frame = view.bounds
        view.addSubview(transport.web)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        if transport.web.superview !== view {
            transport.web.removeFromSuperview()
            transport.web.frame = view.bounds
            view.addSubview(transport.web)
        }
    }
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
