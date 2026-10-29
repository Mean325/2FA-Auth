import AppKit
import SwiftUI
import TwoFACore

extension Notification.Name {
    static let twofaShowAdd = Notification.Name("twofa.showAdd")
    static let twofaShowSettings = Notification.Name("twofa.showSettings")
}

/// 左键弹出验证码，右键是菜单。SwiftUI 的 MenuBarExtra 分不开这两种点击。
@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var store: AccountStore?
    private var settings: AppSettings?
    var openMain: (() -> Void)?

    func closePopover() {
        popover.performClose(nil)
    }

    func setVisible(_ visible: Bool) {
        if !visible { closePopover() }
        statusItem?.isVisible = visible
    }

    /// 系统浮层材质与深色模式设置保持一致。
    func updatePopoverAppearance() {
        guard let theme = settings?.themeID, theme != .system else {
            popover.appearance = nil
            return
        }
        popover.appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
    }

    func attach(store: AccountStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        CodeClipboard.shared.attach(store: store, settings: settings)
        guard statusItem == nil else {
            setVisible(settings.showInStatusBar)
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = settings.showInStatusBar
        if let button = item.button {
            let image = IconMark.menuBarImage()
            image.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.animates = true
        statusItem = item
        let root = ThemedRoot(store: store, settings: settings) {
            MenuBarPanel()
                .transformEnvironment(\.palette) { palette in
                    // 浮层使用随深浅色外观变化的高对比文字，小字不再降低透明度。
                    palette.text = Color(nsColor: .labelColor)
                    palette.secondary = palette.text
                    palette.codeWeight = .semibold
                }
        }
        let host = NSHostingController(rootView: root)
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent, let button = statusItem?.button else { return }
        let right = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if right {
            if popover.isShown { popover.performClose(nil) }
            let menu = makeMenu()
            statusItem?.menu = menu
            button.performClick(nil)
            statusItem?.menu = nil
            return
        }
        guard settings?.twoFAEnabled == true else {
            openMainWindow()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            updatePopoverAppearance()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(L10n.text(L10nKey.settingsTitle), #selector(openMainWindow)))
        menu.addItem(.separator())
        let quit = item(L10n.text(L10nKey.menuQuit), #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openMainWindow() {
        openMain?()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAdd() {
        openMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .twofaShowAdd, object: nil)
        }
    }

    @objc private func openSettings() {
        openMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .twofaShowSettings, object: nil)
        }
    }

    @objc private func lock() {
        settings?.unlocked = false
    }

    @objc private func unlock() {
        settings?.requestUnlock()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
