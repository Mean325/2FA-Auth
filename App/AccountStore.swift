import Foundation
import TwoFACore

enum SyncStatus: Equatable {
    case disabled, localOnly, retrying, synced
    case unreadable(Int)
}

struct RemoteThemeUpdate: Equatable {
    var id: ThemeID
    var updatedAt: TimeInterval
}

enum StoreWrite: Equatable {
    case saved, needName, failed
    case duplicate(UUID)
}

@MainActor
@Observable
final class AccountStore {
    private(set) var records: [VaultRecord] = []
    var syncStatus: SyncStatus = CloudSync.isEnabled ? .localOnly : .disabled
    var remoteThemeUpdate: RemoteThemeUpdate?
    private(set) var storageError: String?
    private(set) var storageReady = false
    private let file: LocalVaultFile
    private let cloudSync = CloudSync()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("app.2famac", isDirectory: true)
        file = LocalVaultFile(url: directory.appendingPathComponent("accounts.base64"))
        reload()
    }

    var blocksAdding: Bool { !storageReady }
    var storageMessageKey: String {
        storageError ?? L10nKey.storageReadFailed
    }

    func reload() {
        do {
            if file.exists {
                records = try file.load()
                storageReady = true
            } else {
                records = []
                storageReady = true
            }
            storageError = nil
            if storageReady { cloudSync.bind(self) }
        } catch {
            storageReady = false
            storageError = L10nKey.storageReadFailed
        }
    }

    func displayed(matching query: String) -> [VaultRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return VaultOrder.ordered(records).filter { record in
            needle.isEmpty
                || record.issuer.localizedStandardContains(needle)
                || record.account.localizedStandardContains(needle)
        }
    }

    func duplicateID(issuer: String, secret: Data, ignoring: UUID?) -> UUID? {
        let name = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        return records.first { record in
            record.deletedAt == nil
                && record.id != ignoring
                && record.issuer.trimmingCharacters(in: .whitespacesAndNewlines) == name
                && record.secret == secret
        }?.id
    }

    func commit(_ draft: DraftAccount, replacing: UUID?) -> StoreWrite {
        guard storageReady else { return .failed }
        let issuer = draft.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = draft.account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !issuer.isEmpty || !account.isEmpty else { return .needName }
        if replacing == nil, let existing = duplicateID(issuer: issuer, secret: draft.secret, ignoring: nil) {
            return .duplicate(existing)
        }
        let previous = replacing.flatMap { id in records.first { $0.id == id } }
        let record = VaultRecord(
            id: replacing ?? UUID(), issuer: issuer, account: account, secret: draft.secret,
            kind: draft.kind, algorithm: draft.kind == .steam ? .sha1 : draft.algorithm,
            digits: draft.kind == .steam ? 5 : draft.digits, period: draft.kind == .steam ? 30 : draft.period,
            counter: draft.kind == .steam ? 0 : draft.kind == .hotp ? draft.counter : previous?.counter ?? draft.counter,
            sortOrder: previous != nil ? previous?.sortOrder : VaultOrder.nextOrder(records),
            updatedAt: Date(), deletedAt: nil
        )
        guard write(record) else { return .failed }
        cloudSync.note(record.id.uuidString.lowercased())
        return .saved
    }

    /// 一次性保存完整顺序，隐藏在搜索结果外的账号也保留相对位置。
    func moveAccount(id: UUID, to target: UUID) -> Bool {
        guard let next = VaultOrder.moving(records, id: id, to: target, at: Date()),
              persist(next) else { return false }
        for record in next where record.deletedAt == nil {
            cloudSync.note(record.id.uuidString.lowercased())
        }
        return true
    }

    func advanceHotp(id: UUID) {
        guard var record = live(id), record.kind == .hotp, record.counter < UInt64.max else { return }
        record.counter += 1
        record.updatedAt = Date()
        if write(record) { cloudSync.note(id.uuidString.lowercased()) }
    }

    @discardableResult
    func tombstone(id: UUID) -> Bool {
        guard var record = live(id) else { return false }
        record.secret = Data()
        record.deletedAt = Date()
        record.updatedAt = record.deletedAt ?? Date()
        guard write(record) else { return false }
        cloudSync.note(id.uuidString.lowercased())
        return true
    }

    /// 用户改了主题。时间戳留给同步比较；云端更新不走这里。
    func noteLocalTheme(_ id: ThemeID) {
        UserDefaults.standard.set(id.rawValue, forKey: "appTheme")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "appThemeUpdatedAt")
        cloudSync.note(CloudSync.settingsRecordName)
    }

    func localTheme() -> (id: ThemeID, updatedAt: Date?) {
        let raw = UserDefaults.standard.string(forKey: "appTheme") ?? ""
        let id = ThemeID(rawValue: raw) ?? .system
        let stamp = UserDefaults.standard.double(forKey: "appThemeUpdatedAt")
        guard stamp > 0 else { return (id, nil) }
        return (id, Date(timeIntervalSince1970: stamp))
    }

    func applyRemoteTheme(_ id: ThemeID, updatedAt: Date) {
        UserDefaults.standard.set(id.rawValue, forKey: "appTheme")
        UserDefaults.standard.set(updatedAt.timeIntervalSince1970, forKey: "appThemeUpdatedAt")
        remoteThemeUpdate = RemoteThemeUpdate(id: id, updatedAt: updatedAt.timeIntervalSince1970)
    }

    func applyFromCloud(_ record: VaultRecord) -> Bool {
        var record = record
        if record.deletedAt != nil { record.secret = Data() }
        return write(record)
    }

    func live(_ id: UUID) -> VaultRecord? {
        records.first { $0.id == id && $0.deletedAt == nil }
    }

    /// 文件提交成功后才更新界面和上传队列，失败时保留上一版数据。
    private func write(_ record: VaultRecord) -> Bool {
        guard storageReady else { return false }
        var next = records
        if let index = next.firstIndex(where: { $0.id == record.id }) { next[index] = record }
        else { next.append(record) }
        return persist(next)
    }

    private func persist(_ next: [VaultRecord]) -> Bool {
        guard storageReady else { return false }
        do {
            try file.save(next)
            records = next
            storageError = nil
            return true
        } catch {
            storageError = L10nKey.storageWriteFailed
            return false
        }
    }
}
