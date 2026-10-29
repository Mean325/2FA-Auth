import AppKit
import SwiftUI
import TwoFACore
import UniformTypeIdentifiers

struct AddSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var route: Route = .choose
    @State private var issuer = ""
    @State private var account = ""
    @State private var secret = ""
    @State private var kind: OTPKind = .totp
    @State private var algorithm: OTPAlgorithm = .sha1
    @State private var digits = 6
    @State private var period = 30
    @State private var counter = "0"
    @State private var message: String?
    @State private var pasteText = ""
    /// 空粘贴区第一次点下去如果剪贴板没内容，展开输入，方便接着手打密钥。
    @State private var pasteCompose = false
    @State private var confirmItems: [ConfirmItem] = []
    @State private var backupData: Data?
    @State private var backupPassword = ""
    @State private var backupNeedsPassword = false
    @State private var qrTargeted = false
    @State private var pasteTargeted = false
    @State private var backupTargeted = false

    enum Route {
        case choose, manual, paste, qr, camera, backup, confirm
    }

    var body: some View {
        Group {
            switch route {
            case .choose: choosePanel
            case .manual:
                ManualForm(
                    title: L10n.text(L10nKey.addManual),
                    badge: themeBadge,
                    submitTitle: L10n.text(L10nKey.addTitle),
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
                    onSubmit: submitManual
                )
            case .paste: pastePanel
            case .qr: qrPanel
            case .camera:
                CameraScanPanel(onCancel: { openRoute(.qr) }) { payload in
                    switch Importers.readText(payload) {
                    case .accounts:
                        absorb([payload])
                        return true
                    case .secret:
                        applyTextRead(payload)
                        return true
                    case .issue:
                        return false
                    }
                }
            case .backup: backupPanel
            case .confirm: confirmPanel
            }
        }
        .onExitCommand { dismiss() }
    }

    /// 错误只属于当前这一步。换方式或回到列表时清掉，避免二维码失败文案留在粘贴页。
    private func openRoute(_ next: Route) {
        message = nil
        if next != .paste { pasteCompose = false }
        route = next
    }

    private var themeBadge: String {
        settings.themeID.title
    }

    private var choosePanel: some View {
        PaperPanel(width: 420) {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 10) {
                        TrafficLights(onClose: { dismiss() })
                        Text(L10n.text(L10nKey.addTitle))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.text)
                    }
                    Spacer()
                    Button(L10n.text(L10nKey.actionCancel)) { dismiss() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.border.opacity(0.65)).frame(height: 1) }
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text(L10nKey.addChooseHint))
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 4)
                    VStack(spacing: 14) {
                        methodCard(L10n.text(L10nKey.addQR), L10n.text(L10nKey.addQRDetail)) { openRoute(.qr) }
                        methodCard(L10n.text(L10nKey.addPaste), L10n.text(L10nKey.addPasteDetail)) { openRoute(.paste) }
                        methodCard(L10n.text(L10nKey.addManual), L10n.text(L10nKey.addManualDetail)) { openRoute(.manual) }
                        methodCard(L10n.text(L10nKey.addBackup), L10n.text(L10nKey.addBackupDetail)) { openRoute(.backup) }
                    }
                }
                .padding(20)
                HStack {
                    Text(L10n.text(L10nKey.addEsc))
                    Spacer()
                    Text(L10n.text(L10nKey.addHelp))
                        .foregroundStyle(palette.accent)
                }
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(palette.menuBackground)
                .overlay(alignment: .top) { Rectangle().fill(palette.border.opacity(0.65)).frame(height: 1) }
            }
        }
    }

    private func methodCard(_ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.text)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(palette.menuBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var pastePanel: some View {
        formShell(title: L10n.text(L10nKey.addPaste), width: 440, submit: L10n.text(L10nKey.addTitle), action: submitPaste) {
            Text(L10n.text(L10nKey.addPasteHint))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            pasteWell
            if let message {
                FormNotice(text: message)
            }
        }
    }

    private var pasteWell: some View {
        DropWell(targeted: pasteTargeted, minHeight: 176) {
            if pasteText.isEmpty && !pasteCompose {
                Button {
                    readPasteboard(reportEmpty: false)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 22))
                            .foregroundStyle(pasteTargeted ? palette.accent : palette.secondary)
                        Text(L10n.text(L10nKey.addPasteDrop))
                            .font(.system(size: 13))
                            .foregroundStyle(pasteTargeted ? palette.accent : palette.text)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    .frame(maxWidth: .infinity, minHeight: 176)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $pasteText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.text)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                    HStack {
                        Spacer()
                        OutlineButton(title: L10n.text(L10nKey.addPasteClipboard)) {
                            readPasteboard(reportEmpty: true)
                        }
                    }
                }
                .padding(12)
            }
        }
        .onDrop(of: [.fileURL, .image, .utf8PlainText, .plainText, .text], isTargeted: $pasteTargeted) { providers in
            importDroppedPaste(providers)
        }
    }

    private var qrPanel: some View {
        formShell(title: L10n.text(L10nKey.addQR), width: 440, submit: L10n.text(L10nKey.addConfirm), action: { route = .confirm }) {
            Text(L10n.text(L10nKey.addQRHint))
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
            DropWell(targeted: qrTargeted, minHeight: 176) {
                VStack(spacing: 10) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 26))
                        .foregroundStyle(qrTargeted ? palette.accent : palette.secondary)
                    Text(L10n.text(L10nKey.addQRDrop))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(qrTargeted ? palette.accent : palette.text)
                    HStack(spacing: 8) {
                        OutlineButton(title: L10n.text(L10nKey.addQRPasteShot)) { pasteImage() }
                        OutlineButton(title: L10n.text(L10nKey.actionChooseFile)) { chooseQRImage() }
                    }
                }
                .padding(.vertical, 22)
                .padding(.horizontal, 16)
            }
            .onDrop(of: [.image, .fileURL], isTargeted: $qrTargeted) { providers in
                importDroppedImages(providers)
            }
            cameraMethodRow
            pasteMethodRow
            if let message {
                FormNotice(text: message)
            }
        }
    }

    /// 和拖图片不是同一条路。做成一行入口，避免看起来像点不了的说明文字。
    private var cameraMethodRow: some View {
        qrMethodRow(L10n.text(L10nKey.cameraScan), detail: L10n.text(L10nKey.cameraScanDetail), symbol: "camera") {
            openRoute(.camera)
        }
    }

    private var pasteMethodRow: some View {
        qrMethodRow(L10n.text(L10nKey.addPaste), detail: L10n.text(L10nKey.addPasteDetail), symbol: "link") {
            openRoute(.paste)
        }
    }

    private func qrMethodRow(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .frame(width: 28, height: 28)
                    .background(palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.text)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(palette.menuBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var backupPanel: some View {
        formShell(title: L10n.text(L10nKey.addBackup), width: 440, submit: L10n.text(L10nKey.addConfirm), action: {
            if let backupData { openBackup(backupData, password: backupNeedsPassword ? backupPassword : nil) }
            else { chooseBackupFile() }
        }) {
            DropWell(targeted: backupTargeted, minHeight: 176) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 26))
                        .foregroundStyle(backupTargeted ? palette.accent : palette.secondary)
                    Text(L10n.text(L10nKey.addBackupDrop))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(backupTargeted ? palette.accent : palette.text)
                    Text(L10n.text(L10nKey.addBackupFormats))
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                    OutlineButton(title: L10n.text(L10nKey.actionChooseFile)) { chooseBackupFile() }
                        .padding(.top, 4)
                }
                .padding(.vertical, 22)
                .padding(.horizontal, 12)
            }
            .onDrop(of: [.fileURL, .json, .plainText, .utf8PlainText], isTargeted: $backupTargeted) { providers in
                importDroppedBackup(providers)
            }
            if backupNeedsPassword {
                SecureField(L10n.text(L10nKey.backupPassword), text: $backupPassword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(palette.border, lineWidth: 1))
            }
            if let message {
                FormNotice(text: message)
            }
        }
    }

    private var selectableItems: [ConfirmItem] {
        confirmItems.filter { $0.problem == nil || $0.existingID != nil }
    }

    private var confirmPanel: some View {
        PaperPanel(width: 480) {
            VStack(spacing: 0) {
                ZStack {
                    Text(L10n.text(L10nKey.addConfirm))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.text)
                    HStack {
                        TrafficLights(onClose: { dismiss() })
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.secondary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.format(L10nKey.importDetected, confirmItems.count))
                            .font(.system(size: 13))
                            .foregroundStyle(palette.secondary)
                        Spacer()
                        Text("\(selectableItems.filter(\.selected).count)/\(max(confirmItems.count, 1))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(palette.menuFooter, in: RoundedRectangle(cornerRadius: 4))
                    }
                    VStack(spacing: 0) {
                        HStack {
                            Toggle(isOn: selectAllBinding) {
                                Text(L10n.text(L10nKey.importSelectAll))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(palette.secondary)
                            }
                            .toggleStyle(.checkbox)
                            .tint(palette.accent)
                            Spacer()
                            Text(L10n.text(L10nKey.importAlgorithmNote))
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(palette.menuFooter)
                        ForEach($confirmItems) { $item in
                            HStack {
                                Toggle(isOn: $item.selected) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.draft.issuer.isEmpty ? item.draft.account : item.draft.issuer)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(palette.text)
                                        Text(item.problem ?? item.draft.account)
                                            .font(.system(size: 11))
                                            .foregroundStyle(item.problem == nil ? palette.secondary : Color.red)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .tint(palette.accent)
                                .disabled(item.problem != nil && item.existingID == nil)
                                Spacer()
                                Text(kindBadge(item.draft.kind))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(palette.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(palette.border.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
                        }
                    }
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(palette.border, lineWidth: 1))
                    if let message { FormNotice(text: message) }
                    HStack(spacing: 6) {
                        Image(systemName: "doc")
                            .font(.system(size: 12))
                        Text(L10n.text(L10nKey.importSecure))
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(palette.secondary)
                }
                .padding(16)
                HStack {
                    Spacer()
                    Button(L10n.text(L10nKey.actionCancel)) { dismiss() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 16)
                        .frame(height: 28)
                        .background(palette.border.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    AccentButton(title: L10n.text(L10nKey.addConfirm), action: confirmImport)
                }
                .padding(10)
                .background(palette.menuFooter)
                .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
            }
        }
    }

    private var selectAllBinding: Binding<Bool> {
        Binding(
            get: { !selectableItems.isEmpty && selectableItems.allSatisfy(\.selected) },
            set: { value in
                for index in confirmItems.indices where confirmItems[index].problem == nil || confirmItems[index].existingID != nil {
                    confirmItems[index].selected = value
                }
            }
        )
    }

    private func kindBadge(_ kind: OTPKind) -> String {
        switch kind {
        case .totp: return "TOTP"
        case .hotp: return "HOTP"
        case .steam: return "STEAM"
        }
    }

    private func formShell<Content: View>(title: String, width: CGFloat, submit: String, action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) -> some View {
        PaperPanel(width: width) {
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(palette.menuBackground.opacity(0.6))
                .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
                VStack(alignment: .leading, spacing: 16) { content() }
                    .padding(20)
                HStack {
                    Spacer()
                    Button(L10n.text(L10nKey.actionCancel)) { openRoute(.choose) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                    AccentButton(title: submit, action: action)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(palette.menuFooter)
                .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
            }
        }
    }

    private func submitManual() {
        guard let draft = ManualForm.draft(issuer: issuer, account: account, secret: secret, kind: kind, algorithm: algorithm, digits: digits, period: period, counter: counter) else {
            message = L10n.text(L10nKey.addBadSecret)
            return
        }
        switch store.commit(draft, replacing: nil) {
        case .saved:
            dismiss()
        case .failed:
            message = L10n.text(L10nKey.storageWriteFailed)
        case .needName:
            message = L10n.text(L10nKey.addNeedName)
        case .duplicate:
            // 重复时只提示，不关闭。再点一次添加仍然是同一条错误，不能当成确认覆盖。
            message = L10n.text(L10nKey.duplicatePrompt)
        }
    }

    private func submitPaste() {
        applyTextRead(pasteText)
    }

    private func pasteImage() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            message = L10n.text(L10nKey.qrNone)
            return
        }
        absorb(QRScanner.strings(in: image))
    }

    /// 剪贴板优先认二维码图片，没有码再取文本。空剪贴板在大块空白上点击时不报错，留给手打。
    private func readPasteboard(reportEmpty: Bool) {
        let board = NSPasteboard.general
        if let image = board.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            let payloads = QRScanner.strings(in: image)
            if !payloads.isEmpty {
                absorb(payloads)
                return
            }
            if board.string(forType: .string) == nil {
                message = L10n.text(L10nKey.addPasteFailed)
                return
            }
        }
        if let text = board.string(forType: .string) {
            fillPasteText(text)
            return
        }
        if reportEmpty {
            message = L10n.text(L10nKey.addPasteFailed)
        } else {
            pasteCompose = true
            message = nil
        }
    }

    private func fillPasteText(_ raw: String?) {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            message = L10n.text(L10nKey.addPasteFailed)
            return
        }
        pasteText = text
        pasteCompose = true
        message = nil
    }

    /// 一张码失败时保留已经识别的行，确认前不写库。
    private func absorb(_ payloads: [String]) {
        guard !payloads.isEmpty else {
            message = route == .qr ? L10n.text(L10nKey.qrNone) : L10n.text(L10nKey.addPasteFailed)
            return
        }
        var added = false
        for payload in payloads {
            switch Importers.readText(payload) {
            case .accounts(let drafts):
                confirmItems.append(contentsOf: drafts.map { makeItem($0, problem: nil) })
                added = true
            case .secret, .issue:
                confirmItems.append(makeItem(placeholder(), problem: L10n.text(L10nKey.importBadItem)))
            }
        }
        if added {
            message = nil
            route = .confirm
        } else {
            message = route == .qr ? L10n.text(L10nKey.importBadItem) : L10n.text(L10nKey.addPasteFailed)
        }
    }

    private func applyTextRead(_ raw: String) {
        switch Importers.readText(raw) {
        case .accounts(let drafts):
            confirmItems = drafts.map { makeItem($0, problem: nil) }
            message = nil
            route = .confirm
        case .secret(let data):
            secret = SecretCodec.base32Encode(data)
            openRoute(.manual)
        case .issue(let issue):
            if route == .paste, issue == .secret || issue == .url {
                message = L10n.text(L10nKey.addPasteFailed)
            } else {
                message = Importers.message(for: issue)
            }
        }
    }

    /// fileImporter 挂在这张自定义 sheet 上时选择器出不来：窗口已经在展示 sheet，面板被挡在后面或直接失败。
    /// 失败回调以前还被写成「没有识别到二维码」。runModal 不依赖那层 sheet，取消也不写错误。
    @MainActor
    private func chooseFile(contentTypes: [UTType], allowsOther: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = contentTypes
        panel.allowsOtherFileTypes = allowsOther
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.text(L10nKey.actionChooseFile)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func chooseQRImage() {
        guard let url = chooseFile(contentTypes: Self.imageTypes, allowsOther: true) else { return }
        guard let data = Self.scopedData(at: url), let image = NSImage(data: data), image.isValid else {
            message = L10n.text(L10nKey.qrNone)
            return
        }
        absorb(QRScanner.strings(in: image))
    }

    private func chooseBackupFile() {
        guard let url = chooseFile(contentTypes: Self.backupTypes, allowsOther: true) else { return }
        guard let data = Self.scopedData(at: url) else {
            message = L10n.text(L10nKey.backupUnsupported)
            return
        }
        ingestBackupData(data)
    }

    /// 文件导入只走现有解析。1Password 没有解析器，不在这里宣称支持。
    /// 文本若是 otpauth 或 Google 迁移链接，交给 readText；JSON 仍走 2FAS / Aegis。
    private func ingestBackupData(_ data: Data) {
        message = nil
        backupNeedsPassword = false
        backupPassword = ""
        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("otpauth://") || lower.hasPrefix("otpauth-migration://") {
                backupData = nil
                applyTextRead(trimmed)
                return
            }
        }
        backupData = data
        openBackup(data, password: nil)
    }

    private func importDroppedImages(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        let canImage = provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        let canFile = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        guard canImage || canFile else { return false }
        loadDroppedImage(provider) { image in
            guard self.route == .qr else { return }
            guard let image else {
                self.message = L10n.text(L10nKey.qrNone)
                return
            }
            self.absorb(QRScanner.strings(in: image))
        }
        return true
    }

    private func importDroppedPaste(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            readSecurityScopedFile(provider) { data in
                guard self.route == .paste else { return }
                self.consumeDroppedPasteData(data)
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            loadDroppedImage(provider) { image in
                guard self.route == .paste else { return }
                guard let image else {
                    self.message = L10n.text(L10nKey.addPasteFailed)
                    return
                }
                let payloads = QRScanner.strings(in: image)
                if payloads.isEmpty {
                    self.message = L10n.text(L10nKey.addPasteFailed)
                } else {
                    self.absorb(payloads)
                }
            }
            return true
        }
        let textTypes = [UTType.utf8PlainText, .plainText, .text]
        guard let type = textTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            Task { @MainActor in
                guard self.route == .paste else { return }
                self.fillPasteText(text)
            }
        }
        return true
    }

    private func importDroppedBackup(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            readSecurityScopedFile(provider) { data in
                guard self.route == .backup else { return }
                guard let data else {
                    self.message = L10n.text(L10nKey.backupUnsupported)
                    return
                }
                self.ingestBackupData(data)
            }
            return true
        }
        let inline = [UTType.json, .utf8PlainText, .plainText, .text]
        guard let type = inline.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            Task { @MainActor in
                guard self.route == .backup else { return }
                guard let data else {
                    self.message = L10n.text(L10nKey.backupUnsupported)
                    return
                }
                self.ingestBackupData(data)
            }
        }
        return true
    }

    private func consumeDroppedPasteData(_ data: Data?) {
        guard let data else {
            message = L10n.text(L10nKey.addPasteFailed)
            return
        }
        if let image = NSImage(data: data), image.isValid {
            let payloads = QRScanner.strings(in: image)
            if payloads.isEmpty {
                message = L10n.text(L10nKey.addPasteFailed)
            } else {
                absorb(payloads)
            }
            return
        }
        fillPasteText(String(data: data, encoding: .utf8))
    }

    private func loadDroppedImage(_ provider: NSItemProvider, done: @escaping (NSImage?) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data, let image = NSImage(data: data), image.isValid {
                    Task { @MainActor in done(image) }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    self.readSecurityScopedFile(provider) { fileData in
                        done(fileData.flatMap { NSImage(data: $0) })
                    }
                } else {
                    Task { @MainActor in done(nil) }
                }
            }
            return
        }
        readSecurityScopedFile(provider) { fileData in
            done(fileData.flatMap { NSImage(data: $0) })
        }
    }

    /// 拖进来的文件 URL 在沙盒里是临时授权，必须在回调里读完再放开。
    private func readSecurityScopedFile(_ provider: NSItemProvider, done: @escaping (Data?) -> Void) {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            Task { @MainActor in done(nil) }
            return
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let data = item.flatMap { AddSheet.readFile($0) }
            Task { @MainActor in done(data) }
        }
    }

    private static func readFile(_ item: NSSecureCoding) -> Data? {
        guard let url = fileURL(from: item) else { return nil }
        return scopedData(at: url)
    }

    private static func fileURL(from item: NSSecureCoding) -> URL? {
        if let url = item as? URL { return url }
        guard let data = item as? Data else { return nil }
        if let url = URL(dataRepresentation: data, relativeTo: nil) { return url }
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text), url.isFileURL else { return nil }
        return url
    }

    private static func scopedData(at url: URL) -> Data? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }

    /// 抽象的 public.image 会让打开面板直接失败，所以用具体图片类型，其它扩展靠 allowsOtherFileTypes。
    private static let imageTypes: [UTType] = [.png, .jpeg, .gif, .tiff, .heic, .webP, .bmp]

    private static var backupTypes: [UTType] {
        var types: [UTType] = [.json, .plainText]
        if let twofas = UTType(filenameExtension: "2fas", conformingTo: .json) {
            types.append(twofas)
        }
        return types
    }

    private func openBackup(_ data: Data, password: String?) {
        switch Importers.readBackup(data, password: password) {
        case .accounts(let drafts, let rejected):
            confirmItems = drafts.map { makeItem($0, problem: nil) }
            confirmItems.append(contentsOf: rejected.map { makeItem(placeholder($0.name), problem: $0.reason) })
            backupNeedsPassword = false
            route = .confirm
        case .needsPassword:
            backupNeedsPassword = true
            message = nil
        case .badPassword:
            message = L10n.text(L10nKey.backupBadPassword)
        case .unsupported:
            message = L10n.text(L10nKey.backupUnsupported)
        }
    }

    private func confirmImport() {
        for index in confirmItems.indices {
            let item = confirmItems[index]
            guard item.selected && (item.problem == nil || item.existingID != nil) else { continue }
            switch store.commit(item.draft, replacing: item.existingID) {
            case .saved:
                confirmItems[index].selected = false
                confirmItems[index].existingID = store.duplicateID(issuer: item.draft.issuer, secret: item.draft.secret, ignoring: nil)
            case .failed:
                message = L10n.text(L10nKey.storageWriteFailed)
                return
            case .duplicate:
                message = L10n.text(L10nKey.duplicateExists)
                return
            case .needName:
                message = L10n.text(L10nKey.addNeedName)
                return
            }
        }
        dismiss()
    }

    private func makeItem(_ draft: DraftAccount, problem: String?) -> ConfirmItem {
        let existing = problem == nil ? store.duplicateID(issuer: draft.issuer, secret: draft.secret, ignoring: nil) : nil
        return ConfirmItem(
            draft: draft,
            selected: problem == nil && existing == nil,
            existingID: existing,
            problem: existing == nil ? problem : L10n.text(L10nKey.duplicateExists)
        )
    }

    private func placeholder(_ name: String = "") -> DraftAccount {
        DraftAccount(issuer: name, account: "", secret: Data(), kind: .totp, algorithm: .sha1, digits: 6, period: 30, counter: 0)
    }
}

struct ConfirmItem: Identifiable {
    let id = UUID()
    var draft: DraftAccount
    var selected: Bool
    var existingID: UUID?
    var problem: String?
}

struct ManualForm: View {
    @Environment(\.palette) private var palette
    var title: String
    var badge: String? = nil
    var showsOTPOptions = true
    var submitTitle: String
    @Binding var issuer: String
    @Binding var account: String
    @Binding var secret: String
    @Binding var kind: OTPKind
    @Binding var algorithm: OTPAlgorithm
    @Binding var digits: Int
    @Binding var period: Int
    @Binding var counter: String
    var message: String?
    var onCancel: () -> Void
    var onSubmit: () -> Void
    @State private var advanced = false
    @State private var openMenu: AdvancedField?
    @State private var menuAnchor: CGRect = .zero
    @State private var formHeight: CGFloat = 0

    private enum AdvancedField {
        case algorithm, digits, period
    }

    var body: some View {
        PaperPanel(width: 440) {
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Spacer()
                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(palette.menuFooter, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(palette.menuBackground.opacity(0.6))
                .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
                VStack(alignment: .leading, spacing: 16) {
                    DesignField(title: L10n.text(L10nKey.fieldIssuer), placeholder: L10n.text(L10nKey.fieldIssuerPlaceholder), text: $issuer)
                    DesignField(title: L10n.text(L10nKey.fieldAccount), placeholder: L10n.text(L10nKey.fieldAccountPlaceholder), text: $account)
                    DesignField(title: L10n.text(L10nKey.fieldSecret), placeholder: L10n.text(L10nKey.fieldSecretPlaceholder), text: $secret, monospaced: true)
                    if showsOTPOptions {
                        KindSegments(kind: $kind)
                        if kind == .hotp {
                            DesignField(title: L10n.text(L10nKey.fieldCounter), placeholder: "0", text: $counter)
                        }
                        if kind != .steam {
                            Button {
                                advanced.toggle()
                                if !advanced { openMenu = nil }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .rotationEffect(.degrees(advanced ? 90 : 0))
                                    Text(L10n.text(L10nKey.fieldAdvanced))
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(palette.secondary)
                            }
                            .buttonStyle(.plain)
                            if advanced {
                                HStack(alignment: .top, spacing: 10) {
                                    ThemeMenuField(
                                        title: L10n.text(L10nKey.fieldAlgorithm),
                                        selection: algorithmLabel,
                                        isOpen: openMenu == .algorithm
                                    ) {
                                        openMenu = openMenu == .algorithm ? nil : .algorithm
                                    }
                                    ThemeMenuField(
                                        title: L10n.text(L10nKey.fieldDigits),
                                        selection: "\(digits)",
                                        isOpen: openMenu == .digits
                                    ) {
                                        openMenu = openMenu == .digits ? nil : .digits
                                    }
                                    ThemeMenuField(
                                        title: L10n.text(L10nKey.fieldPeriod),
                                        selection: L10n.format(L10nKey.unitSeconds, period),
                                        isOpen: openMenu == .period
                                    ) {
                                        openMenu = openMenu == .period ? nil : .period
                                    }
                                }
                            }
                        }
                    }
                    if let message {
                        FormNotice(text: message)
                    }
                }
                .padding(20)
                HStack {
                    Spacer()
                    Button(L10n.text(L10nKey.actionCancel), action: onCancel)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                    AccentButton(title: submitTitle, action: onSubmit)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(palette.menuFooter)
                .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
            }
            .coordinateSpace(name: ThemeMenuSpace.name)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: ManualFormHeightKey.self, value: proxy.size.height)
                }
            }
            .onPreferenceChange(ThemeMenuAnchorKey.self) { frame in
                guard let frame else { return }
                let moved = abs(frame.minX - menuAnchor.minX) > 0.5
                    || abs(frame.minY - menuAnchor.minY) > 0.5
                    || abs(frame.width - menuAnchor.width) > 0.5
                if moved { menuAnchor = frame }
            }
            .onPreferenceChange(ManualFormHeightKey.self) { height in
                if height != formHeight { formHeight = height }
            }
            .overlay { menuOverlay }
            .onChange(of: kind) { _, new in
                if new == .steam { openMenu = nil }
            }
        }
    }

    /// 点列表外面关掉。盖住整张表单，包括底栏，避免系统菜单那种脱离主题的浮层。
    @ViewBuilder
    private var menuOverlay: some View {
        if let options = menuOptions, menuAnchor.width > 1 {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { openMenu = nil }
                ThemeOptionList(options: options) { openMenu = nil }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: menuAnchor.width)
                    .offset(x: menuAnchor.minX, y: menuListTop(count: options.count))
            }
        }
    }

    private var menuOptions: [ThemeMenuOption]? {
        switch openMenu {
        case .algorithm:
            return [
                ThemeMenuOption(title: "SHA1", selected: algorithm == .sha1) { algorithm = .sha1 },
                ThemeMenuOption(title: "SHA256", selected: algorithm == .sha256) { algorithm = .sha256 },
                ThemeMenuOption(title: "SHA512", selected: algorithm == .sha512) { algorithm = .sha512 },
            ]
        case .digits:
            return [
                ThemeMenuOption(title: "6", selected: digits == 6) { digits = 6 },
                ThemeMenuOption(title: "8", selected: digits == 8) { digits = 8 },
            ]
        case .period:
            return [
                ThemeMenuOption(title: L10n.format(L10nKey.unitSeconds, 30), selected: period == 30) { period = 30 },
                ThemeMenuOption(title: L10n.format(L10nKey.unitSeconds, 60), selected: period == 60) { period = 60 },
            ]
        case nil:
            return nil
        }
    }

    private func menuListTop(count: Int) -> CGFloat {
        let listHeight = 28 * CGFloat(count) + 8
        let below = menuAnchor.maxY + 4
        let opensUp = formHeight > 0 && below + listHeight > formHeight - 6
        return opensUp ? max(6, menuAnchor.minY - 4 - listHeight) : below
    }

    private var algorithmLabel: String {
        switch algorithm {
        case .sha1: return "SHA1"
        case .sha256: return "SHA256"
        case .sha512: return "SHA512"
        }
    }

    /// 手动 Steam 才做十六进制和 Base64 兜底。其他类型只认 Base32。
    static func draft(
        issuer: String,
        account: String,
        secret: String,
        kind: OTPKind,
        algorithm: OTPAlgorithm,
        digits: Int,
        period: Int,
        counter: String
    ) -> DraftAccount? {
        let decoded = kind == .steam ? SecretCodec.steamManual(secret) : SecretCodec.base32(secret)
        guard let decoded else { return nil }
        return DraftAccount(
            issuer: issuer,
            account: account,
            secret: decoded,
            kind: kind,
            algorithm: kind == .steam ? .sha1 : algorithm,
            digits: kind == .steam ? 5 : digits,
            period: kind == .steam ? 30 : period,
            counter: kind == .hotp ? (UInt64(counter) ?? 0) : 0
        )
    }
}

private struct ManualFormHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 拖放落点。虚线表示可以放下；拖进来时边框和底色改跟主题强调色，避免和普通输入框混在一起。
private struct DropWell<Content: View>: View {
    @Environment(\.palette) private var palette
    var targeted: Bool
    var minHeight: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(targeted ? palette.accent.opacity(0.14) : palette.menuBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        targeted ? palette.accent : palette.border,
                        style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: [6, 4])
                    )
            )
            .animation(.easeOut(duration: 0.12), value: targeted)
    }
}

/// 选择文件、粘贴截图要用看得见的按钮。原来的纯文字点下去像说明，也容易被当成没接动作。
private struct OutlineButton: View {
    @Environment(\.palette) private var palette
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: palette.controlRadius, style: .continuous)
                        .stroke(palette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

enum QRScanner {
    static func strings(in image: NSImage) -> [String] {
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return [] }
        return QRCodeReader.payloads(in: cgImage)
    }
}
