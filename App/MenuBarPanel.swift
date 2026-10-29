import AppKit
import SwiftUI
import TwoFACore

struct MenuBarPanel: View {
    @Environment(\.palette) private var palette
    @Environment(\.openWindow) private var openWindow
    @Environment(AccountStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        let rows = store.displayed(matching: query)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: IconMark.appIcon(side: 20))
                    .frame(width: 20, height: 20)
                Text(L10n.text(L10nKey.appTitle))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: openMain) {
                    Label(L10n.text(L10nKey.settingsTitle), systemImage: "gearshape")
                        .font(.system(size: 12, weight: .semibold))
                }
                .modifier(SettingsGlassButton())
                .controlSize(.small)
                .help(L10n.text(L10nKey.settingsTitle))
            }
            .foregroundStyle(palette.text)
            .padding(.horizontal, 18)
            .frame(height: 36 * AppTheme.menuScale)

            SearchField(text: $query, kind: .menu, focused: $searchFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 6 * AppTheme.menuScale)

            if store.blocksAdding || rows.isEmpty {
                Text(L10n.text(store.blocksAdding ? store.storageMessageKey : L10nKey.emptyMenu))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: 132)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    ScrollView {
                        LazyVStack(spacing: 6 * AppTheme.menuScale) {
                            ForEach(rows, id: \.id) { record in
                                AccountRow(
                                    record: record,
                                    now: timeline.date.timeIntervalSince1970,
                                    locked: settings.touchIDRequired && !settings.unlocked,
                                    style: .menu,
                                    onUnlock: { settings.requestUnlock() },
                                    onNext: { store.advanceHotp(id: record.id) }
                                )
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .background(ScrollViewChrome(showsVerticalIndicator: false).allowsHitTesting(false))
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: AppTheme.menuListHeight)
                }
            }

        }
        .frame(width: AppTheme.menuWidth)
        // 保留 NSPopover 自带的半透明材质。
        .background(Color.clear)
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .onChange(of: settings.themeID) { _, _ in
            StatusBarController.shared.updatePopoverAppearance()
        }
    }

    private func openMain() {
        StatusBarController.shared.closePopover()
        SettingsWindowPresenter.show { openWindow(id: "main") }
        NSApp.activate(ignoringOtherApps: true)
    }
}

