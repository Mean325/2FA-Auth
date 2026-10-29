import AppKit

@MainActor
enum AppVisibility {
    static func setDockVisible(_ visible: Bool) {
        let window = NSApp.keyWindow
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        // 切换应用类型后继续保留当前设置窗口的焦点。
        if let window, window.isVisible {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

@MainActor
final class TwoFAApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppVisibility.setDockVisible(UserDefaults.standard.bool(forKey: AppSettings.showInDockKey))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusBarController.shared.openMain?()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
