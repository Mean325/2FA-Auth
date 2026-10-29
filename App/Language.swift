import Foundation
import LocalAuthentication
import SwiftUI
import TwoFACore

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans
    case en

    var id: String { rawValue }
    static let defaultsKey = "appLanguage"

    var code: String? {
        switch self {
        case .system: return nil
        case .zhHans: return "zh-Hans"
        case .en: return "en"
        }
    }

    static func stored() -> AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey) else { return .system }
        return AppLanguage(rawValue: raw) ?? .system
    }

    /// 界面文案按这里的语言立即切换。不标 MainActor，正文里读取时才能跟着界面一起刷新。
    @Observable
    final class ActiveLanguage {
        static let shared = ActiveLanguage()
        var value: AppLanguage = .stored()

        func code() -> String {
            switch value {
            case .en:
                return "en"
            case .zhHans:
                return "zh-Hans"
            case .system:
                let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
                let first = (global?["AppleLanguages"] as? [String])?.first ?? "zh-Hans"
                if first.hasPrefix("en") { return "en" }
                return "zh-Hans"
            }
        }
    }

    /// 写入 AppleLanguages，供下次启动使用。当前界面走 ActiveLanguage，所以这次就能换语言。
    static func apply(_ language: AppLanguage) {
        if let code = language.code {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        ActiveLanguage.shared.value = language
    }
}

enum L10n {
    /// String(localized:locale:) 会忽略传入的 locale，一直用启动时的语言，所以要自己按语言包取。
    private static var bundles: [String: Bundle] = [:]

    static func text(_ key: String) -> String {
        // 读当前语言，视图在 body 里调用时才能登记依赖，切换后整棵界面会重绘。
        let code = AppLanguage.ActiveLanguage.shared.code()
        let bundle = localizedBundle(code)
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? key : value
    }

    static func format(_ key: String, _ number: Int) -> String {
        let code = AppLanguage.ActiveLanguage.shared.code()
        return String(format: text(key), locale: Locale(identifier: code), Int64(number))
    }

    private static func localizedBundle(_ code: String) -> Bundle {
        if let cached = bundles[code] { return cached }
        let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap { Bundle(path: $0) } ?? .main
        bundles[code] = bundle
        return bundle
    }
}

@MainActor
@Observable
final class AppSettings {
    static let showInStatusBarKey = "showInStatusBar"
    static let showInDockKey = "showInDock"

    var showInStatusBar: Bool
    var showInDock: Bool
    var twoFAEnabled: Bool
    var smartCopyEnabled: Bool
    var themeID: ThemeID
    var language: AppLanguage
    var touchIDRequired: Bool
    var unlocked: Bool
    var listLayout: ListLayout
    private var lockObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        showInStatusBar = defaults.object(forKey: Self.showInStatusBarKey) as? Bool ?? true
        showInDock = defaults.bool(forKey: Self.showInDockKey)
        twoFAEnabled = defaults.object(forKey: "twoFAEnabled") as? Bool ?? true
        smartCopyEnabled = defaults.bool(forKey: "smartCopyEnabled")
        themeID = ThemeID(rawValue: defaults.string(forKey: "appTheme") ?? "") ?? .system
        listLayout = ListLayout(rawValue: defaults.string(forKey: "listLayout") ?? "") ?? .list
        language = AppLanguage.stored()
        touchIDRequired = defaults.bool(forKey: "requireTouchID")
        unlocked = !defaults.bool(forKey: "requireTouchID")
        let center = DistributedNotificationCenter.default()
        lockObserver = center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.touchIDRequired else { return }
                self.unlocked = false
            }
        }
    }

    func setTheme(_ id: ThemeID) {
        themeID = id
        UserDefaults.standard.set(id.rawValue, forKey: "appTheme")
    }

    func setTwoFAEnabled(_ enabled: Bool) {
        twoFAEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "twoFAEnabled")
        if !enabled {
            StatusBarController.shared.closePopover()
            CodeClipboard.shared.cancelSmartCopy()
        }
    }

    func setSmartCopyEnabled(_ enabled: Bool) {
        smartCopyEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "smartCopyEnabled")
        if !enabled { CodeClipboard.shared.cancelSmartCopy() }
    }

    func setShowInStatusBar(_ visible: Bool) {
        showInStatusBar = visible
        UserDefaults.standard.set(visible, forKey: Self.showInStatusBarKey)
        StatusBarController.shared.setVisible(visible)
    }

    func setShowInDock(_ visible: Bool) {
        showInDock = visible
        UserDefaults.standard.set(visible, forKey: Self.showInDockKey)
        AppVisibility.setDockVisible(visible)
    }

    /// 云端较新的主题直接改本机显示，不另写更新时间，避免刚应用完又被当成更新上传。
    func applyRemoteTheme(_ id: ThemeID) {
        themeID = id
        UserDefaults.standard.set(id.rawValue, forKey: "appTheme")
    }

    func setLanguage(_ value: AppLanguage) {
        language = value
        UserDefaults.standard.set(value.rawValue, forKey: AppLanguage.defaultsKey)
        AppLanguage.apply(value)
    }

    func setListLayout(_ layout: ListLayout) {
        listLayout = layout
        UserDefaults.standard.set(layout.rawValue, forKey: "listLayout")
    }

    func setTouchID(_ enabled: Bool) {
        touchIDRequired = enabled
        unlocked = !enabled
        UserDefaults.standard.set(enabled, forKey: "requireTouchID")
    }

    /// 用系统的本机认证。没有 Touch ID 时会落到本机登录密码，所以界面不放主密码框。
    func requestUnlock() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L10n.text(L10nKey.unlockPrompt)) { ok, _ in
            Task { @MainActor in
                if ok { self.unlocked = true }
            }
        }
    }
}
