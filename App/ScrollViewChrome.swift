import AppKit
import SwiftUI

/// 滚动条覆盖在内容上，不因系统“始终显示滚动条”设置或内容高度变化占用页面宽度。
struct ScrollViewChrome: NSViewRepresentable {
    var showsVerticalIndicator = true

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView()
        view.showsVerticalIndicator = showsVerticalIndicator
        return view
    }

    func updateNSView(_ view: ChromeView, context: Context) {
        view.showsVerticalIndicator = showsVerticalIndicator
        DispatchQueue.main.async { [weak view] in view?.configure() }
    }

    final class ChromeView: NSView {
        var showsVerticalIndicator = true

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configure()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configure()
        }

        func configure() {
            guard let scrollView = enclosingScrollView else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = showsVerticalIndicator
            scrollView.hasHorizontalScroller = false
        }
    }
}
