import CryptoKit
import Foundation

public enum OTPKind: String, Codable, Sendable {
    case totp, hotp, steam
}

public enum OTPAlgorithm: String, Codable, Sendable {
    case sha1, sha256, sha512
}

public enum OTPEngine {
    /// Steam 字符表。先取出的余数对应验证码第一位。
    public static let steamAlphabet = Array("23456789BCDFGHJKMNPQRTVWXY")

    /// 计算一条验证码。HOTP 只用 counter；TOTP 和 Steam 用 unixTime 对周期取整。
    public static func code(
        secret: Data,
        kind: OTPKind,
        algorithm: OTPAlgorithm,
        digits: Int,
        period: Int,
        counter: UInt64,
        at unixTime: TimeInterval
    ) -> String {
        let moving: UInt64
        switch kind {
        case .hotp:
            moving = counter
        case .totp, .steam:
            let step = UInt64(max(period, 1))
            let seconds = unixTime > 0 ? UInt64(unixTime) : 0
            moving = seconds / step
        }
        let binary = truncated(hmac(algorithm, key: secret, counter: moving))
        if kind == .steam { return steam(binary) }
        return decimal(binary, digits: max(digits, 1))
    }

    /// 剩余小于等于 5 秒时，返回下一条码开始的时刻。界面用它出码，并标「即将生效」。
    /// 用周期序号加一，避免把剩余秒数加回去时浮点误差仍落在当前周期。HOTP 没有下一条。
    public static func displayTime(kind: OTPKind, period: Int, at unixTime: TimeInterval) -> TimeInterval {
        guard kind != .hotp else { return unixTime }
        let step = TimeInterval(max(period, 1))
        guard remaining(period: period, at: unixTime) <= 5 else { return unixTime }
        let index = floor(unixTime / step)
        return (index + 1) * step
    }

    /// 当前这条码还剩多少秒。正好踩在周期边界上时，视为新周期刚开始。
    /// 即将生效时圆环继续用这个剩余值，不重置成满周期。
    public static func remaining(period: Int, at unixTime: TimeInterval) -> TimeInterval {
        let step = TimeInterval(max(period, 1))
        let into = unixTime.truncatingRemainder(dividingBy: step)
        if into == 0 { return step }
        return step - into
    }

    private static func hmac(_ algorithm: OTPAlgorithm, key: Data, counter: UInt64) -> Data {
        let message = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        let symmetric = SymmetricKey(data: key)
        switch algorithm {
        case .sha1:
            return Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symmetric))
        case .sha256:
            return Data(HMAC<SHA256>.authenticationCode(for: message, using: symmetric))
        case .sha512:
            return Data(HMAC<SHA512>.authenticationCode(for: message, using: symmetric))
        }
    }

    /// 动态截断。偏移越界时返回 0，避免坏摘要把界面打崩。
    private static func truncated(_ hmac: Data) -> UInt32 {
        guard hmac.count >= 4 else { return 0 }
        let offset = Int(hmac[hmac.count - 1] & 0x0f)
        guard offset + 4 <= hmac.count else { return 0 }
        let slice = hmac.subdata(in: offset..<(offset + 4))
        let value = slice.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return value & 0x7fff_ffff
    }

    private static func steam(_ value: UInt32) -> String {
        var rest = Int(value)
        let count = steamAlphabet.count
        return String((0..<5).map { _ in
            let index = rest % count
            rest /= count
            return steamAlphabet[index]
        })
    }

    private static func decimal(_ value: UInt32, digits: Int) -> String {
        var modulus: UInt32 = 1
        for _ in 0..<digits {
            guard modulus <= UInt32.max / 10 else { break }
            modulus *= 10
        }
        let number = value % modulus
        let raw = String(number)
        if raw.count >= digits { return raw }
        return String(repeating: "0", count: digits - raw.count) + raw
    }
}
