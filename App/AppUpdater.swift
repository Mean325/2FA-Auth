import AppKit
import Combine
import Sparkle
import TwoFACore

/// 所有窗口和菜单共用一个更新器，避免重复下载或重复安装。
@MainActor
final class AppUpdater: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var automaticallyDownloads = false
    @Published private(set) var updateAvailable = false
    @Published private(set) var failedToStart = false

    private(set) var controller: SPUStandardUpdaterController!
    private var started = false

    var isConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return false }
        return true
    }

    static var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return version == build ? version : "\(version) (\(build))"
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates)
            .assign(to: &$automaticallyDownloads)
    }

    func start() {
        guard !started, isConfigured else { return }
        do {
            try controller.updater.start()
            started = true
        } catch {
            failedToStart = true
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        StatusBarController.shared.closePopover()
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloads(_ enabled: Bool) {
        controller.updater.automaticallyDownloadsUpdates = enabled
    }

    // 菜单栏应用在后台发现更新时，保留设置页和状态栏提示，由 Sparkle 展示安装窗口。
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        updateAvailable = true
        StatusBarController.shared.setUpdateAvailable(true)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateAvailable = false
        StatusBarController.shared.setUpdateAvailable(false)
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateAvailable = false
        StatusBarController.shared.setUpdateAvailable(false)
    }
}
