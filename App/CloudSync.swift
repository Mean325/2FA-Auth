import CloudKit
import Foundation
import Security
import TwoFACore

/// 账号和主题以 Base64 JSON 同步到 CloudKit 私有库。
@MainActor
final class CloudSync {
    static let settingsRecordName = "settings"
    private static let containerID = "iCloud.app.2famac"
    private static let zoneName = "VaultZone"
    private static let itemType = "VaultItem"
    private static let preferenceType = "Preference"
    private static let schemaVersion = 2
    private static let tokenKey = "sync.zoneToken.base64.v2"
    private static let pendingKey = "sync.pending"
    private static let initialPushKey = "sync.didInitialPush.base64.v2"
    private static let blockedKey = "sync.blocked"

    private var container: CKContainer?
    private let zoneID = CKRecordZone.ID(zoneName: CloudSync.zoneName, ownerName: CKCurrentUserDefaultName)
    private weak var store: AccountStore?
    private var task: Task<Void, Never>?
    private var syncing = false
    private var kickPending = false
    private var kickWaiter: ResumeOnce?

    private var database: CKDatabase? { container?.privateCloudDatabase }

    /// 未签名或没有 iCloud 权限时，CloudKit 会在创建容器时直接中断进程。先看权限，没有就只在本机用。
    private static func cloudKitEntitled() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        guard let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) else {
            return false
        }
        guard let services = value as? [String] else { return false }
        return services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
    }

    func bind(_ store: AccountStore) {
        self.store = store
        task?.cancel()
        task = Task { await self.loop() }
    }

    func note(_ identifier: String) {
        var ids = pendingIDs()
        ids.insert(identifier)
        savePending(ids)
        kick()
    }

    private func loop() async {
        guard Self.cloudKitEntitled() else {
            store?.syncStatus = .localOnly
            return
        }
        container = CKContainer(identifier: Self.containerID)
        var backoff: Double = 2
        while !Task.isCancelled {
            let result = await cycle()
            let seconds: Double
            switch result {
            case .retry:
                seconds = backoff
                backoff = min(backoff * 2, 300)
            case .idle:
                // 另一台 Mac 的修改不会推过来，空闲时也要再拉一次。
                seconds = 60
                backoff = 2
            }
            await pause(seconds)
        }
    }

    private func cycle() async -> CycleResult {
        guard let store, !syncing else { return .idle }
        syncing = true
        defer { syncing = false }
        let account = await accountStatus()
        switch account {
        case .available:
            break
        case .couldNotDetermine, .temporarilyUnavailable:
            store.syncStatus = .retrying
            return .retry
        default:
            store.syncStatus = .localOnly
            return .idle
        }

        if !UserDefaults.standard.bool(forKey: Self.initialPushKey) {
            enqueueEverything(store)
        }

        let pulled: PullBatch
        do {
            pulled = try await pull()
        } catch {
            if isZoneMissing(error) {
                do {
                    try await ensureZone()
                    pulled = try await pull()
                } catch {
                    store.syncStatus = .retrying
                    return .retry
                }
            } else {
                store.syncStatus = .retrying
                return .retry
            }
        }

        let outcome = apply(pulled, store: store)
        if outcome.needsRetry {
            clearToken()
            store.syncStatus = .retrying
            return .retry
        }
        let uploaded = await pushPending(store: store)
        if uploaded {
            if pendingIDs().isEmpty {
                UserDefaults.standard.set(true, forKey: Self.initialPushKey)
            }
            let blocked = blockedIDs().count
            store.syncStatus = blocked > 0 ? .unreadable(blocked) : .synced
            return .idle
        }
        store.syncStatus = .retrying
        return .retry
    }

    private func apply(_ batch: PullBatch, store: AccountStore) -> ApplyOutcome {
        var needsRetry = false
        for record in batch.records {
            let name = record.recordID.recordName
            if schemaVersion(record) != Self.schemaVersion {
                rememberBlocked(name)
                continue
            }
            if record.recordType == Self.preferenceType || name == Self.settingsRecordName {
                if applyTheme(record, store: store) {
                    forgetBlocked(name)
                } else {
                    rememberBlocked(name)
                }
                continue
            }
            guard let id = UUID(uuidString: name) else {
                rememberBlocked(name)
                continue
            }
            switch decodeAccount(record, id: id) {
            case .failure:
                rememberBlocked(name)
            case .success(let remote):
                let local = store.records.first { $0.id == id }
                let merged = local.map { VaultMerge.merge(local: $0, remote: remote) } ?? remote
                guard store.applyFromCloud(merged) else {
                    needsRetry = true
                    continue
                }
                forgetBlocked(name)
                if merged != remote {
                    note(id.uuidString.lowercased())
                } else {
                    removePending(id.uuidString.lowercased())
                }
            }
        }
        for deleted in batch.deleted {
            if deleted.recordName == Self.settingsRecordName {
                note(Self.settingsRecordName)
                continue
            }
            guard let id = UUID(uuidString: deleted.recordName),
                  store.records.contains(where: { $0.id == id }) else { continue }
            note(id.uuidString.lowercased())
        }
        return ApplyOutcome(needsRetry: needsRetry)
    }

    private func applyTheme(_ record: CKRecord, store: AccountStore) -> Bool {
        guard let payload = record["payload"] as? Data else { return false }
        guard let plain = try? decodedPayload(payload),
              let blob = try? JSONDecoder().decode(ThemeBlob.self, from: plain),
              let theme = ThemeID(rawValue: blob.theme) else { return false }
        let remoteDate = Date(timeIntervalSince1970: blob.updatedAt)
        let local = store.localTheme()
        if let localDate = local.updatedAt, localDate > remoteDate {
            note(Self.settingsRecordName)
            return true
        }
        store.applyRemoteTheme(theme, updatedAt: remoteDate)
        removePending(Self.settingsRecordName)
        return true
    }

    private func pushPending(store: AccountStore) async -> Bool {
        let ids = pendingIDs()
        guard !ids.isEmpty else { return true }
        do {
            try await ensureZone()
        } catch {
            return false
        }
        var recordIDs: [CKRecord.ID] = []
        for id in ids {
            recordIDs.append(CKRecord.ID(recordName: id, zoneID: zoneID))
        }
        guard let existing = await fetchRecords(recordIDs) else { return false }
        var saving: [CKRecord] = []
        for id in ids {
            let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
            let record = existing[recordID] ?? CKRecord(recordType: id == Self.settingsRecordName ? Self.preferenceType : Self.itemType, recordID: recordID)
            guard let payload = payload(for: id, store: store) else { continue }
            record["schemaVersion"] = NSNumber(value: Self.schemaVersion)
            record["payload"] = payload as NSData
            saving.append(record)
        }
        guard !saving.isEmpty else { return true }
        let saved = await save(saving)
        for id in saved {
            removePending(id)
        }
        return saved.count == saving.count
    }

    private func payload(for identifier: String, store: AccountStore) -> Data? {
        if identifier == Self.settingsRecordName {
            let local = store.localTheme()
            let stamp = local.updatedAt ?? Date()
            let blob = ThemeBlob(theme: local.id.rawValue, updatedAt: stamp.timeIntervalSince1970)
            guard let plain = try? JSONEncoder().encode(blob) else { return nil }
            return plain.base64EncodedData()
        }
        guard let id = UUID(uuidString: identifier),
              let record = store.records.first(where: { $0.id == id }) else { return nil }
        let blob = AccountBlob(record: record)
        guard let plain = try? JSONEncoder().encode(blob) else { return nil }
        return plain.base64EncodedData()
    }

    private func decodeAccount(_ record: CKRecord, id: UUID) -> Result<VaultRecord, Error> {
        guard let payload = record["payload"] as? Data else {
            return .failure(CocoaError(.fileReadCorruptFile))
        }
        do {
            let plain = try decodedPayload(payload)
            let blob = try JSONDecoder().decode(AccountBlob.self, from: plain)
            guard let decoded = blob.record(id: id) else { return .failure(CocoaError(.fileReadCorruptFile)) }
            return .success(decoded)
        } catch {
            return .failure(error)
        }
    }

    private func decodedPayload(_ payload: Data) throws -> Data {
        guard let json = Data(base64Encoded: payload) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return json
    }

    private func pull() async throws -> PullBatch {
        do {
            let batch = try await fetchChanges(token: loadToken())
            if let token = batch.token { storeToken(token) }
            return batch
        } catch {
            guard isTokenExpired(error) else { throw error }
            clearToken()
            let batch = try await fetchChanges(token: nil)
            if let token = batch.token { storeToken(token) }
            return batch
        }
    }

    private func enqueueEverything(_ store: AccountStore) {
        var ids = pendingIDs()
        for record in store.records {
            ids.insert(record.id.uuidString.lowercased())
        }
        ids.insert(Self.settingsRecordName)
        savePending(ids)
    }

    private func accountStatus() async -> CKAccountStatus {
        guard let container else { return .couldNotDetermine }
        return await withCheckedContinuation { continuation in
            container.accountStatus { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    private func ensureZone() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordZonesOperation(recordZonesToSave: [CKRecordZone(zoneID: zoneID)], recordZoneIDsToDelete: nil)
            let gate = ThrowOnce(continuation)
            operation.modifyRecordZonesResultBlock = { result in
                gate.resume(result)
            }
            guard let database else {
                gate.resume(.failure(CKError(.internalError)))
                return
            }
            database.add(operation)
        }
    }

    private func fetchChanges(token: CKServerChangeToken?) async throws -> PullBatch {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            configuration.previousServerChangeToken = token
            let operation = CKFetchRecordZoneChangesOperation()
            operation.recordZoneIDs = [zoneID]
            operation.configurationsByRecordZoneID = [zoneID: configuration]
            let buffer = PullBuffer(token: token)
            let gate = ThrowOnce(continuation)
            operation.recordWasChangedBlock = { _, result in
                if case .success(let record) = result { buffer.add(record) }
            }
            operation.recordWithIDWasDeletedBlock = { recordID, _ in
                buffer.delete(recordID)
            }
            operation.recordZoneFetchResultBlock = { _, result in
                switch result {
                case .success(let payload):
                    buffer.setToken(payload.serverChangeToken)
                case .failure(let error):
                    gate.resume(.failure(error))
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    gate.resume(.success(buffer.batch()))
                case .failure(let error):
                    gate.resume(.failure(error))
                }
            }
            guard let database else {
                gate.resume(.failure(CKError(.internalError)))
                return
            }
            database.add(operation)
        }
    }

    private func fetchRecords(_ ids: [CKRecord.ID]) async -> [CKRecord.ID: CKRecord]? {
        guard !ids.isEmpty else { return [:] }
        return await withCheckedContinuation { continuation in
            let operation = CKFetchRecordsOperation(recordIDs: ids)
            let found = RecordBuffer()
            operation.perRecordResultBlock = { _, result in
                switch result {
                case .success(let record): found.add(record)
                case .failure(let error):
                    if (error as? CKError)?.code != .unknownItem { found.markFailure() }
                }
            }
            operation.fetchRecordsResultBlock = { result in
                if case .failure(let error) = result {
                    let code = (error as? CKError)?.code
                    if code != .partialFailure && code != .unknownItem { found.markFailure() }
                }
                continuation.resume(returning: found.hasFailure ? nil : found.records)
            }
            guard let database else {
                continuation.resume(returning: nil)
                return
            }
            database.add(operation)
        }
    }

    private func save(_ records: [CKRecord]) async -> Set<String> {
        await withCheckedContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.isAtomic = false
            let saved = NameBuffer()
            operation.perRecordSaveBlock = { recordID, result in
                if case .success = result { saved.add(recordID.recordName) }
            }
            operation.modifyRecordsResultBlock = { _ in
                continuation.resume(returning: saved.names)
            }
            guard let database else {
                continuation.resume(returning: [])
                return
            }
            database.add(operation)
        }
    }

    private func schemaVersion(_ record: CKRecord) -> Int {
        (record["schemaVersion"] as? NSNumber)?.intValue ?? 0
    }

    private func isZoneMissing(_ error: Error) -> Bool {
        let code = (error as? CKError)?.code
        return code == .zoneNotFound || code == .userDeletedZone
    }

    private func isTokenExpired(_ error: Error) -> Bool {
        (error as? CKError)?.code == .changeTokenExpired
    }

    private func pendingIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.pendingKey) ?? [])
    }

    private func savePending(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: Self.pendingKey)
    }

    private func removePending(_ id: String) {
        var ids = pendingIDs()
        ids.remove(id)
        savePending(ids)
    }

    private func blockedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.blockedKey) ?? [])
    }

    private func rememberBlocked(_ id: String) {
        var ids = blockedIDs()
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: Self.blockedKey)
    }

    private func forgetBlocked(_ id: String) {
        var ids = blockedIDs()
        ids.remove(id)
        UserDefaults.standard.set(Array(ids), forKey: Self.blockedKey)
    }

    private func loadToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: Self.tokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func storeToken(_ token: CKServerChangeToken) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: Self.tokenKey)
    }

    private func clearToken() {
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
    }

    private func kick() {
        kickPending = true
        kickWaiter?.resume()
        kickWaiter = nil
    }

    private func pause(_ seconds: Double) async {
        if kickPending {
            kickPending = false
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if kickPending {
                kickPending = false
                continuation.resume()
                return
            }
            let waiter = ResumeOnce(continuation)
            kickWaiter = waiter
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                waiter.resume()
            }
        }
    }
}

private enum CycleResult {
    case retry
    case idle
}

private struct ApplyOutcome {
    var needsRetry: Bool
}

private struct PullBatch {
    var records: [CKRecord] = []
    var deleted: [CKRecord.ID] = []
    var token: CKServerChangeToken?
}

private struct AccountBlob: Codable {
    var issuer: String
    var account: String
    var secret: String
    var kind: String
    var algorithm: String
    var digits: Int
    var period: Int
    var counter: UInt64
    var sortOrder: Int?
    var updatedAt: TimeInterval
    var deletedAt: TimeInterval?

    init(record: VaultRecord) {
        issuer = record.issuer
        account = record.account
        secret = record.secret.base64EncodedString()
        kind = record.kind.rawValue
        algorithm = record.algorithm.rawValue
        digits = record.digits
        period = record.period
        counter = record.counter
        sortOrder = record.sortOrder
        updatedAt = record.updatedAt.timeIntervalSince1970
        deletedAt = record.deletedAt?.timeIntervalSince1970
    }

    func record(id: UUID) -> VaultRecord? {
        let secretData: Data
        if secret.isEmpty {
            secretData = Data()
        } else if let decoded = Data(base64Encoded: secret) {
            secretData = decoded
        } else {
            return nil
        }
        if deletedAt == nil && secretData.isEmpty { return nil }
        guard let kind = OTPKind(rawValue: kind),
              let algorithm = OTPAlgorithm(rawValue: algorithm) else { return nil }
        return VaultRecord(
            id: id,
            issuer: issuer,
            account: account,
            secret: deletedAt == nil ? secretData : Data(),
            kind: kind,
            algorithm: algorithm,
            digits: digits,
            period: period,
            counter: counter,
            sortOrder: sortOrder,
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            deletedAt: deletedAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

private struct ThemeBlob: Codable {
    var theme: String
    var updatedAt: TimeInterval
}

private final class PullBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [CKRecord] = []
    private var deleted: [CKRecord.ID] = []
    private var serverToken: CKServerChangeToken?

    init(token: CKServerChangeToken?) {
        serverToken = token
    }

    func add(_ record: CKRecord) {
        lock.lock()
        records.append(record)
        lock.unlock()
    }

    func delete(_ id: CKRecord.ID) {
        lock.lock()
        deleted.append(id)
        lock.unlock()
    }

    func setToken(_ token: CKServerChangeToken) {
        lock.lock()
        serverToken = token
        lock.unlock()
    }

    func batch() -> PullBatch {
        lock.lock()
        defer { lock.unlock() }
        return PullBatch(records: records, deleted: deleted, token: serverToken)
    }
}

private final class RecordBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var found: [CKRecord.ID: CKRecord] = [:]
    private var failed = false

    func markFailure() {
        lock.lock()
        failed = true
        lock.unlock()
    }

    var hasFailure: Bool {
        lock.lock()
        defer { lock.unlock() }
        return failed
    }

    func add(_ record: CKRecord) {
        lock.lock()
        found[record.recordID] = record
        lock.unlock()
    }

    var records: [CKRecord.ID: CKRecord] {
        lock.lock()
        defer { lock.unlock() }
        return found
    }
}

private final class NameBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var found: Set<String> = []

    func add(_ name: String) {
        lock.lock()
        found.insert(name)
        lock.unlock()
    }

    var names: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return found
    }
}

private final class ThrowOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}
