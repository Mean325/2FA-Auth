import SwiftUI
import TwoFACore

@main
struct TwoFAApp: App {
    @NSApplicationDelegateAdaptor(TwoFAApplicationDelegate.self) private var appDelegate
    @State private var store = AccountStore()
    @State private var settings = AppSettings()
    @ObservedObject private var updater = AppUpdater.shared

    init() {
        AppLanguage.apply(AppLanguage.stored())
    }

    var body: some Scene {
        Window(L10n.text(L10nKey.settingsTitle), id: "main") {
            ThemedRoot(store: store, settings: settings) {
                MainWindowView()
            }
        }
        .defaultSize(width: AppTheme.windowWidth, height: AppTheme.windowHeight)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L10n.text(L10nKey.updatesCheck), action: updater.checkForUpdates)
                    .disabled(!updater.canCheckForUpdates)
            }
            CommandGroup(replacing: .appSettings) {
                Button(L10n.text(L10nKey.settingsTitle)) {
                    StatusBarController.shared.openMain?()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// 菜单栏和主窗口读同一份账号、同一套主题和材质外观。
struct ThemedRoot<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var store: AccountStore
    /// Bindable 才会跟踪 language。普通属性读了也不刷新，语言要重启才变。
    @Bindable var settings: AppSettings
    @ViewBuilder var content: () -> Content

    var body: some View {
        let _ = AppLanguage.ActiveLanguage.shared.value
        content()
            .environment(store)
            .environment(settings)
            .environment(\.palette, AppTheme.palette(settings.themeID, colorScheme: colorScheme))
            .preferredColorScheme(settings.themeID.colorScheme)
            .onChange(of: store.remoteThemeUpdate) { _, update in
                if let update { settings.applyRemoteTheme(update.id) }
            }
    }
}
