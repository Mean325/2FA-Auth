import AppKit
import TwoFACore

/// 生命周期独立于验证码列表；关闭浮层不会取消到期后的补复制。
@MainActor
final class CodeClipboard {
    static let shared = CodeClipboard()

    private let board: NSPasteboard
    private weak var store: AccountStore?
    private weak var settings: AppSettings?
    private var smartCopyTask: Task<Void, Never>?

    init(board: NSPasteboard = .general) {
        self.board = board
    }

    func attach(store: AccountStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    func cancelSmartCopy() {
        smartCopyTask?.cancel()
        smartCopyTask = nil
    }

    func copy(record: VaultRecord) -> Bool {
        cancelSmartCopy()
        guard let settings, settings.twoFAEnabled,
              !settings.touchIDRequired || settings.unlocked,
              let record = store?.live(record.id) else { return false }
        let now = Date().timeIntervalSince1970
        let displayedAt = OTPEngine.displayTime(kind: record.kind, period: record.period, at: now)
        let raw = OTPEngine.code(
            secret: record.secret, kind: record.kind, algorithm: record.algorithm,
            digits: record.digits, period: record.period, counter: record.counter, at: displayedAt
        )
        let plan = settings.smartCopyEnabled ? SmartCopyPlan(record: record, copiedAt: now) : nil
        // 智能复制时保留原码到补复制完成，避免旧的 30 秒清理任务先清空剪贴板。
        let clearAfter = plan.map { max(30, $0.expiresAt - now + 1) } ?? 30
        guard write(raw, clearAfter: clearAfter) else { return false }
        guard let plan else { return true }
        let changeCount = board.changeCount
        smartCopyTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, plan.expiresAt - Date().timeIntervalSince1970)))
            } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.smartCopyTask = nil
            guard let settings = self.settings,
                  settings.twoFAEnabled, settings.smartCopyEnabled,
                  !settings.touchIDRequired || settings.unlocked,
                  self.board.changeCount == changeCount,
                  self.board.string(forType: .string) == raw,
                  let current = self.store?.live(plan.record.id),
                  let refreshed = plan.refreshedCode(at: Date().timeIntervalSince1970, currentRecord: current)
            else { return }
            // 直接写入，不再次创建计划，保证每次手动复制最多补复制一次。
            _ = self.write(refreshed)
        }
        return true
    }

    private func write(_ raw: String, clearAfter: TimeInterval = 30) -> Bool {
        board.clearContents()
        guard board.setString(raw, forType: .string) else { return false }
        let changeCount = board.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + clearAfter) { [board] in
            guard board.changeCount == changeCount, board.string(forType: .string) == raw else { return }
            board.clearContents()
        }
        return true
    }
}
