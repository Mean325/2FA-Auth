import AppKit
import SwiftUI
import TwoFACore

/// 沿用 CodexLinxDisplay 的 NavigationSplitView 设置窗口布局。
struct MainWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(AccountStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @ObservedObject private var updater = AppUpdater.shared
    @State private var selectedPane = SettingsPane.twoFA
    @State private var searchText = ""
    @State private var accountQuery = ""
    @State private var hoveredPane: SettingsPane?
    @State private var backHistory: [SettingsPane] = []
    @State private var forwardHistory: [SettingsPane] = []
    @State private var showAdd = false
    @State private var editing: VaultRecord?
    @State private var pendingDelete: VaultRecord?
    @State private var dropTarget: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 232, maxWidth: 232)
                .navigationSplitViewColumnWidth(min: 232, ideal: 232, max: 232)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detailBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle(selectedPane.title)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        ControlGroup {
                            Button {
                                guard let pane = backHistory.popLast() else { return }
                                forwardHistory.append(selectedPane)
                                selectedPane = pane
                            } label: {
                                Label(L10n.text(L10nKey.settingsBack), systemImage: "chevron.backward")
                                    .font(.system(size: 17, weight: .medium))
                                    .frame(width: 22, height: 24)
                            }
                            .disabled(backHistory.isEmpty)
                            .help(L10n.text(L10nKey.settingsBack))
                            Button {
                                guard let pane = forwardHistory.popLast() else { return }
                                backHistory.append(selectedPane)
                                selectedPane = pane
                            } label: {
                                Label(L10n.text(L10nKey.settingsForward), systemImage: "chevron.forward")
                                    .font(.system(size: 17, weight: .medium))
                                    .frame(width: 22, height: 24)
                            }
                            .disabled(forwardHistory.isEmpty)
                            .help(L10n.text(L10nKey.settingsForward))
                        }
                        .controlGroupStyle(.navigation)
                        .controlSize(.large)
                        .frame(width: 74)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, idealWidth: 760, maxWidth: .infinity,
               minHeight: 600, idealHeight: 660, maxHeight: .infinity)
        .font(.system(size: 13))
        .controlSize(.regular)
        .background(detailCanvasBackground)
        .background(SettingsWindowConfigurator(title: selectedPane.title))
        .sheet(isPresented: $showAdd) { AddSheet().environment(\.palette, palette) }
        .sheet(item: $editing) { record in
            EditAccountSheet(record: record).environment(\.palette, palette)
        }
        .overlay {
            if let record = pendingDelete {
                ConfirmDialog(
                    title: L10n.text(L10nKey.deleteConfirm),
                    confirmTitle: L10n.text(L10nKey.deleteAction),
                    name: record.displayTitle,
                    account: record.account,
                    destructive: true,
                    onConfirm: {
                        if store.tombstone(id: record.id) { pendingDelete = nil }
                    },
                    onCancel: { pendingDelete = nil }
                )
            }
        }
        .onAppear {
            StatusBarController.shared.openMain = { SettingsWindowPresenter.show { openWindow(id: "main") } }
            StatusBarController.shared.attach(store: store, settings: settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .twofaShowAdd)) { _ in
            guard settings.twoFAEnabled else { return }
            navigate(to: .accounts)
            showAdd = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .twofaShowSettings)) { _ in
            navigate(to: .general)
        }
        .onChange(of: settings.twoFAEnabled) { _, enabled in
            if !enabled {
                showAdd = false
                editing = nil
                pendingDelete = nil
                if selectedPane == .accounts { navigate(to: .twoFA) }
                backHistory.removeAll { $0 == .accounts }
                forwardHistory.removeAll { $0 == .accounts }
            }
        }
    }

    private var detailCanvasBackground: Color {
        colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : .white
    }

    private var systemGroupBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color(white: 0.965)
    }

    private func navigate(to pane: SettingsPane) {
        guard pane != .accounts || settings.twoFAEnabled else { return }
        guard selectedPane != pane else { return }
        backHistory.append(selectedPane)
        forwardHistory.removeAll()
        selectedPane = pane
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            SettingsSearchField(text: $searchText)
                .frame(height: 30)
                .padding(.horizontal, 10)
                .padding(.top, 8)
            HStack(spacing: 11) {
                Image(nsImage: IconMark.appIcon(side: 38))
                    .frame(width: 38, height: 38)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(L10nKey.appTitle))
                        .font(.system(size: 14, weight: .semibold))
                    Text(L10n.text(L10nKey.settingsApp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(SettingsPane.sidebarPanes.filter {
                        searchText.isEmpty || ($0.title + $0.subtitle).localizedCaseInsensitiveContains(searchText)
                    }) { pane in
                        sidebarItem(pane)
                    }
                    if !searchText.isEmpty && !SettingsPane.sidebarPanes.contains(where: {
                        ($0.title + $0.subtitle).localizedCaseInsensitiveContains(searchText)
                    }) {
                        Text(L10n.text(L10nKey.settingsNoResults))
                            .foregroundStyle(.secondary)
                            .padding(.top, 12)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func sidebarItem(_ pane: SettingsPane) -> some View {
        let selected = selectedPane == pane || (pane == .twoFA && selectedPane == .accounts)
        let emphasized = selected && controlActiveState != .inactive
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Button { navigate(to: pane) } label: {
            HStack(spacing: 7) {
                SettingsSystemIcon(kind: pane.systemIcon, size: 20)
                Text(pane.title)
                    .font(.system(size: 13))
                    .foregroundStyle(emphasized ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 32)
            .background(selected ? (emphasized ? Color(nsColor: .selectedContentBackgroundColor) : Color.primary.opacity(0.10)) : Color.primary.opacity(hoveredPane == pane ? 0.04 : 0), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hoveredPane = $0 ? pane : nil }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var detailBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    detailHeader.id("paneTop")
                    storageNotice
                    Group {
                        switch selectedPane {
                        case .twoFA: twoFAPane
                        case .accounts: accountsPane
                        case .general: generalPane
                        }
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .background(ScrollViewChrome().allowsHitTesting(false))
            }
            .scrollIndicators(.automatic)
            .background(detailCanvasBackground)
            .onChange(of: selectedPane) { _, _ in proxy.scrollTo("paneTop", anchor: .top) }
        }
    }

    private var detailHeader: some View {
        VStack(spacing: 0) {
            SettingsSystemIcon(kind: selectedPane.systemIcon, size: 52)
                .padding(.bottom, 10)
            Text(selectedPane.title)
                .font(.system(size: 22, weight: .bold))
                .padding(.bottom, 2)
            Text(selectedPane.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(systemGroupBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var storageNotice: some View {
        if let error = store.storageError {
            FormNotice(text: L10n.text(error))
            if store.blocksAdding {
                Button(L10n.text(L10nKey.storageRetry)) { store.reload() }
                    .modifier(SettingsGlassButton())
            }
        }
    }

    private var accountsPane: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                SettingsSearchField(text: $accountQuery, placeholder: L10n.text(L10nKey.searchPlaceholder))
                    .frame(height: 30)
                Button { showAdd = true } label: {
                    Label(L10n.text(L10nKey.addTitle), systemImage: "plus")
                }
                .modifier(SettingsGlassButton(prominent: true))
                .disabled(store.blocksAdding)
            }
            .padding(.vertical, 4)
            if settings.touchIDRequired && !settings.unlocked {
                VStack(spacing: 14) {
                    Image(systemName: "touchid").font(.system(size: 30)).foregroundStyle(.secondary)
                    Text(L10n.text(L10nKey.unlockPrompt)).foregroundStyle(.secondary)
                    Button(L10n.text(L10nKey.unlockAction)) { settings.requestUnlock() }
                        .modifier(SettingsGlassButton(prominent: true))
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                let rows = store.displayed(matching: accountQuery)
                if rows.isEmpty {
                    if !store.blocksAdding {
                        Text(L10n.text(L10nKey.emptyMenu))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(rows, id: \.id) { record in
                            accountRow(record)
                            if record.id != rows.last?.id { Divider().opacity(0.55).padding(.leading, 78) }
                        }
                    }
                    .background(systemGroupBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(L10n.format(L10nKey.listCount, rows.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    private var twoFAPane: some View {
        VStack(spacing: 0) {
            settingRow(L10n.text(L10nKey.settingsTwoFAEnabled)) {
                Toggle("", isOn: Binding(get: { settings.twoFAEnabled }, set: { settings.setTwoFAEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .controlAccentColor))
                    .accessibilityLabel(L10n.text(L10nKey.settingsTwoFAEnabled))
            }
            .padding(12)
            Divider().opacity(0.55).padding(.leading, 12)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(L10nKey.settingsSmartCopy)).font(.callout)
                    Text(L10n.text(L10nKey.settingsSmartCopyHint))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(get: { settings.smartCopyEnabled }, set: { settings.setSmartCopyEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .controlAccentColor))
                    .accessibilityLabel(L10n.text(L10nKey.settingsSmartCopy))
            }
            .padding(12)
            .disabled(!settings.twoFAEnabled)
            Divider().opacity(0.55).padding(.leading, 12)
            Button { navigate(to: .accounts) } label: {
                HStack {
                    Text(L10n.text(L10nKey.settingsAccounts)).font(.callout)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!settings.twoFAEnabled)
        }
        .background(systemGroupBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func accountRow(_ record: VaultRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
                .help(L10n.text(L10nKey.accountsReorderHint))
            IssuerAvatar(title: record.displayTitle, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.account.isEmpty ? "—" : record.account)
                    .font(.system(size: 13, weight: .medium))
                Text(record.issuer.isEmpty ? "—" : record.issuer)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if record.kind == .hotp {
                managementButton("arrow.clockwise", title: L10n.text(L10nKey.hotpNext)) { store.advanceHotp(id: record.id) }
            }
            managementButton("pencil", title: L10n.text(L10nKey.actionEdit)) { editing = record }
            managementButton("trash", title: L10n.text(L10nKey.deleteAction)) { pendingDelete = record }
        }
        .padding(12)
        .background(dropTarget == record.id ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .draggable(record.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard items.count == 1, let source = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            dropTarget = nil
            return store.moveAccount(id: source, to: record.id)
        } isTargeted: { targeted in
            if targeted { dropTarget = record.id }
            else if dropTarget == record.id { dropTarget = nil }
        }
    }

    private func managementButton(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 16, height: 18) }
            .modifier(SettingsGlassButton())
            .help(title)
            .accessibilityLabel(title)
    }

    private var generalPane: some View {
        VStack(spacing: 10) {
            settingsCard(title: L10n.text(L10nKey.settingsAppearance), subtitle: L10n.text(L10nKey.settingsAppearanceHint), icon: .appearance) {
                settingRow(L10n.text(L10nKey.settingsLanguage)) {
                    Picker("", selection: Binding(get: { settings.language }, set: { settings.setLanguage($0) })) {
                        Text(L10n.text(L10nKey.settingsLanguageSystem)).tag(AppLanguage.system)
                        Text(L10n.text(L10nKey.settingsLanguageChinese)).tag(AppLanguage.zhHans)
                        Text(L10n.text(L10nKey.settingsLanguageEnglish)).tag(AppLanguage.en)
                    }
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 160, alignment: .trailing)
                }
                Divider().opacity(0.55)
                settingRow(L10n.text(L10nKey.settingsDarkMode)) {
                    Picker("", selection: Binding(get: { settings.themeID }, set: { settings.setTheme($0); store.noteLocalTheme($0) })) {
                        ForEach(ThemeID.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 160, alignment: .trailing)
                }
            }
            settingsCard(title: L10n.text(L10nKey.settingsVisibility), subtitle: L10n.text(L10nKey.settingsVisibilityHint), icon: .display) {
                settingRow(L10n.text(L10nKey.settingsShowStatusBar)) {
                    Toggle("", isOn: Binding(get: { settings.showInStatusBar }, set: { settings.setShowInStatusBar($0) }))
                        .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .controlAccentColor))
                        .accessibilityLabel(L10n.text(L10nKey.settingsShowStatusBar))
                }
                Divider().opacity(0.55)
                settingRow(L10n.text(L10nKey.settingsShowDock)) {
                    Toggle("", isOn: Binding(get: { settings.showInDock }, set: { settings.setShowInDock($0) }))
                        .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .controlAccentColor))
                        .accessibilityLabel(L10n.text(L10nKey.settingsShowDock))
                }
            }
            settingsCard(title: L10n.text(L10nKey.settingsSecurity), subtitle: L10n.text(L10nKey.settingsSecurityHint), icon: .general) {
                settingRow(L10n.text(L10nKey.settingsTouchID)) {
                    Toggle("", isOn: Binding(get: { settings.touchIDRequired }, set: { settings.setTouchID($0) }))
                        .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .controlAccentColor))
                        .accessibilityLabel(L10n.text(L10nKey.settingsTouchID))
                }
            }
            settingsCard(title: L10n.text(L10nKey.settingsIcloudTitle), subtitle: L10n.text(L10nKey.settingsSyncHint), icon: .sync) {
                Text(syncTitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            settingsCard(title: L10n.text(L10nKey.settingsAbout), subtitle: AppUpdater.versionDescription, icon: .about) {
                HStack(spacing: 14) {
                    Image(nsImage: IconMark.appIcon(side: 52)).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text(L10nKey.appTitle)).font(.headline)
                        Text(L10n.text(L10nKey.settingsAboutHint)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.text(L10nKey.updatesCheck), action: updater.checkForUpdates)
                        .modifier(SettingsGlassButton())
                        .disabled(!updater.canCheckForUpdates)
                }
                if !updater.isConfigured || updater.failedToStart {
                    Text(L10n.text(updater.failedToStart ? L10nKey.updatesStartFailed : L10nKey.updatesNotConfigured))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Divider().opacity(0.55)
                    settingRow(L10n.text(L10nKey.updatesAutomaticChecks)) {
                        Toggle("", isOn: Binding(get: { updater.automaticallyChecks }, set: updater.setAutomaticallyChecks))
                            .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .controlAccentColor))
                            .accessibilityLabel(L10n.text(L10nKey.updatesAutomaticChecks))
                    }
                    settingRow(L10n.text(L10nKey.updatesAutomaticDownloads)) {
                        Toggle("", isOn: Binding(get: { updater.automaticallyDownloads }, set: updater.setAutomaticallyDownloads))
                            .labelsHidden().toggleStyle(.switch).tint(Color(nsColor: .controlAccentColor))
                            .accessibilityLabel(L10n.text(L10nKey.updatesAutomaticDownloads))
                            .disabled(!updater.automaticallyChecks)
                    }
                    Text(L10n.text(updater.updateAvailable ? L10nKey.updatesAvailable : L10nKey.updatesAutomaticHint))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func settingsCard<Content: View>(title: String, subtitle: String, icon: SettingsSystemIcon.Kind, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SettingsSystemIcon(kind: icon, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Divider().opacity(0.55)
            content()
        }
        .padding(12)
        .background(systemGroupBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func settingRow<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.callout)
            Spacer(minLength: 0)
            trailing()
        }
    }

    private var syncTitle: String {
        switch store.syncStatus {
        case .localOnly: return L10n.text(L10nKey.settingsIcloudLocalOnly)
        case .retrying: return L10n.text(L10nKey.settingsIcloudRetry)
        case .unreadable(let count): return L10n.format(L10nKey.settingsIcloudUnreadable, count)
        case .synced: return L10n.text(L10nKey.settingsIcloudSynced)
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case twoFA, accounts, general
    static let sidebarPanes: [SettingsPane] = [.twoFA, .general]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .twoFA: return L10n.text(L10nKey.settingsTwoFA)
        case .accounts: return L10n.text(L10nKey.settingsAccounts)
        case .general: return L10n.text(L10nKey.settingsGeneral)
        }
    }
    var subtitle: String {
        switch self {
        case .twoFA: return L10n.text(L10nKey.settingsTwoFAHint)
        case .accounts: return L10n.text(L10nKey.settingsAccountsHint)
        case .general: return L10n.text(L10nKey.settingsGeneralHint)
        }
    }
    var systemIcon: SettingsSystemIcon.Kind { self == .general ? .general : .monitoring }
}

/// Reopen the single settings window without creating duplicate windows.
enum SettingsWindowPresenter {
    static func show(open: () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        if bringForward() { return }
        open()
        DispatchQueue.main.async { _ = bringForward() }
    }

    @discardableResult
    private static func bringForward() -> Bool {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "keymark-settings" }) else { return false }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        window.orderFrontRegardless()
        return true
    }
}

struct EditAccountSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var store
    var record: VaultRecord
    @State private var issuer = ""
    @State private var account = ""
    @State private var secret = ""
    @State private var kind: OTPKind = .totp
    @State private var algorithm: OTPAlgorithm = .sha1
    @State private var digits = 6
    @State private var period = 30
    @State private var counter = ""
    @State private var message: String?

    var body: some View {
        ManualForm(
            title: L10n.text(L10nKey.actionEdit),
            showsOTPOptions: false,
            submitTitle: L10n.text(L10nKey.actionSave),
            issuer: $issuer,
            account: $account,
            secret: $secret,
            kind: $kind,
            algorithm: $algorithm,
            digits: $digits,
            period: $period,
            counter: $counter,
            message: message,
            onCancel: { dismiss() },
            onSubmit: save
        )
        .environment(\.palette, palette)
        .onAppear {
            issuer = record.issuer
            account = record.account
            secret = SecretCodec.base32Encode(record.secret)
            kind = record.kind
            algorithm = record.algorithm
            digits = record.digits
            period = record.period
            counter = String(record.counter)
        }
    }

    private func save() {
        guard let draft = ManualForm.draft(issuer: issuer, account: account, secret: secret, kind: kind, algorithm: algorithm, digits: digits, period: period, counter: counter) else {
            message = L10n.text(L10nKey.addBadSecret)
            return
        }
        switch store.commit(draft, replacing: record.id) {
        case .saved:
            dismiss()
        case .failed:
            message = L10n.text(L10nKey.storageWriteFailed)
        case .needName:
            message = L10n.text(L10nKey.addNeedName)
        case .duplicate:
            message = L10n.text(L10nKey.duplicateExists)
        }
    }
}
