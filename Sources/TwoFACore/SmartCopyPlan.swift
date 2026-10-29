import Foundation

/// 手动复制的那条验证码到期后，只更新一次。提前展示的下一条码按其实际有效期计算。
public struct SmartCopyPlan: Sendable {
    public let record: VaultRecord
    public let expiresAt: TimeInterval

    public init?(record: VaultRecord, copiedAt: TimeInterval) {
        guard record.kind != .hotp, record.deletedAt == nil, record.period > 0,
              copiedAt.isFinite, copiedAt >= 0 else { return nil }
        self.record = record
        let step = TimeInterval(record.period)
        let displayedAt = OTPEngine.displayTime(kind: record.kind, period: record.period, at: copiedAt)
        expiresAt = (floor(displayedAt / step) + 1) * step
    }

    public func refreshedCode(at time: TimeInterval, currentRecord: VaultRecord) -> String? {
        guard time >= expiresAt, time < expiresAt + TimeInterval(record.period),
              currentRecord.deletedAt == nil,
              currentRecord.id == record.id,
              currentRecord.secret == record.secret,
              currentRecord.kind == record.kind,
              currentRecord.algorithm == record.algorithm,
              currentRecord.digits == record.digits,
              currentRecord.period == record.period else { return nil }
        return OTPEngine.code(
            secret: record.secret, kind: record.kind, algorithm: record.algorithm,
            digits: record.digits, period: record.period, counter: record.counter, at: time
        )
    }
}
