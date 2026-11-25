"""Execute the production pane geometry and search URL builder with Foundation."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
layout = (root / 'DouDuo/DouyinDuoLayout.swift').read_text()
geometry = layout[layout.index('struct DYCommentPaneMetrics {'):layout.index('/// Used by the list player')]
extras = (root / 'DouDuo/DouyinExtras.swift').read_text()
url_builder = re.search(r'    static func videoSearchURL\(.*?\n    }', extras, re.S).group()
panel_source = (root / 'DouDuo/DouyinFeedView.swift').read_text()
panel = panel_source.split('struct DYCommentPanel: View {', 1)[1].split('// MARK: - 评论表情', 1)[0]
for forbidden in ('publishComment', 'deleteComment', 'diggComment', 'TextField(', 'TextEditor(', 'PhotosPicker('):
    assert forbidden not in panel, forbidden

swift = r'''
import Foundation
import CoreGraphics
struct Insets { var top: CGFloat = 0; var bottom: CGFloat = 34; var leading: CGFloat = 0; var trailing: CGFloat = 0 }
struct GeometryProxy { let size: CGSize; var safeAreaInsets = Insets() }
enum DYDuoMetrics {
    static var legacyWideMin: CGFloat { 700 }
    static func foldIsActive(_ g: GeometryProxy) -> Bool { false }
    static func bottomSafeAreaExtension(in g: GeometryProxy) -> CGFloat { g.safeAreaInsets.bottom }
    static func trailingOcclusionInset(_ g: GeometryProxy, pane: CGRect) -> CGFloat { 0 }
    static func videoCommentPanes(_ g: GeometryProxy) -> (book: Bool, video: CGRect, panel: CGRect)? { nil }
}
'''
swift += geometry + '\nenum SearchURL {\n' + url_builder + '\n}\n'
swift += r'''
for size in [CGSize(width: 430, height: 932), CGSize(width: 932, height: 430), CGSize(width: 1024, height: 1366)] {
    let geo = GeometryProxy(size: size)
    let closed = DYCommentPaneMetrics(geo, isPresented: false)
    assert(closed.videoSize == size)
    let open = DYCommentPaneMetrics(geo, isPresented: true)
    assert(open.showsPane && !open.sideBySide)
    assert(open.videoSize.height > 0 && open.paneSize.height > 0)
    assert(open.videoSize.height <= open.paneOrigin.y)
    assert(abs(open.paneOrigin.y + open.paneSize.height - size.height - 34) < 0.01)
}
for term in ["ios14", "#音乐 / 测试?", "a&b%/c", "音乐🎵"] {
    let url = SearchURL.videoSearchURL(term)!
    let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    assert(parts.host == "www.douyin.com")
    assert(parts.percentEncodedPath.removingPercentEncoding == "/search/" + term)
    assert(parts.queryItems?.first?.value == "video")
}
print("Passed portrait, landscape and iPad pane separation, encoded queries and read-only panel")
'''
with tempfile.TemporaryDirectory() as folder:
    source = Path(folder) / 'main.swift'
    source.write_text(swift)
    subprocess.run(['swift', str(source)], check=True)
