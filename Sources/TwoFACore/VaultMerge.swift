import Foundation

public struct VaultRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var issuer: String
    public var account: String
    public var secret: Data
    public var kind: OTPKind
    public var algorithm: OTPAlgorithm
    public var digits: Int
    public var period: Int
    public var counter: UInt64
    public var sortOrder: Int?
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID,
        issuer: String,
        account: String,
        secret: Data,
        kind: OTPKind,
        algorithm: OTPAlgorithm,
        digits: Int,
        period: Int,
        counter: UInt64,
        sortOrder: Int? = nil,
        updatedAt: Date,
        deletedAt: Date?
    ) {
        self.id = id
        self.issuer = issuer
        self.account = account
        self.secret = secret
        self.kind = kind
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.counter = counter
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// 只缺服务名时用账号名显示，两边都空的记录不应被保存。
    public var displayTitle: String {
        let name = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return account.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum VaultMerge {
    /// 合并两条同一账号的记录。
    /// 一边是墓碑时不比较计数器；更新时间相同则墓碑获胜。
    /// 两边都有效时，展示字段取较新的一条，HOTP 计数器取较大值。
    /// 调用方要在计数器被抬高后重新上传，否则另一台会停在较小值。
    public static func merge(local: VaultRecord, remote: VaultRecord) -> VaultRecord {
        let localDead = local.deletedAt != nil
        let remoteDead = remote.deletedAt != nil
        if localDead || remoteDead {
            if local.updatedAt == remote.updatedAt { return localDead ? local : remote }
            return local.updatedAt > remote.updatedAt ? local : remote
        }
        var winner = local.updatedAt >= remote.updatedAt ? local : remote
        winner.counter = max(local.counter, remote.counter)
        winner.updatedAt = max(local.updatedAt, remote.updatedAt)
        return winner
    }
}
