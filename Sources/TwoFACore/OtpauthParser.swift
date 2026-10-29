import Foundation

public struct DraftAccount: Equatable, Sendable {
    public var issuer: String
    public var account: String
    public var secret: Data
    public var kind: OTPKind
    public var algorithm: OTPAlgorithm
    public var digits: Int
    public var period: Int
    public var counter: UInt64

    public init(
        issuer: String,
        account: String,
        secret: Data,
        kind: OTPKind,
        algorithm: OTPAlgorithm,
        digits: Int,
        period: Int,
        counter: UInt64
    ) {
        self.issuer = issuer
        self.account = account
        self.secret = secret
        self.kind = kind
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.counter = counter
    }
}

public enum ImportIssue: Equatable, Error, Sendable {
    case url
    case secret
    case algorithm
    case digits
    case period
}

public enum OtpauthParser {
    /// 解析 otpauth://。缺省算法 SHA1、位数 6、周期 30、HOTP 计数器 0。
    /// 发行者是 Steam（不区分大小写）或类型本身是 steam 时，锁定为 5 位 Steam 码。
    public static func parse(_ raw: String) -> Result<DraftAccount, ImportIssue> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "otpauth",
              let host = components.host?.lowercased()
        else { return .failure(.url) }

        let kind: OTPKind
        switch host {
        case "totp": kind = .totp
        case "hotp": kind = .hotp
        case "steam": kind = .steam
        default: return .failure(.url)
        }

        let items = components.queryItems ?? []
        func query(_ name: String) -> String? {
            items.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        guard let secretText = query("secret"), let secret = SecretCodec.base32(secretText) else {
            return .failure(.secret)
        }

        let label = decodedLabel(components.percentEncodedPath)
        var issuer = ""
        var account = label
        if let colon = label.firstIndex(of: ":") {
            issuer = String(label[..<colon])
            account = String(label[label.index(after: colon)...])
        }
        if let queryIssuer = query("issuer")?.removingPercentEncoding ?? query("issuer"), !queryIssuer.isEmpty {
            issuer = queryIssuer
        }
        issuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        account = account.trimmingCharacters(in: .whitespacesAndNewlines)

        let steam = kind == .steam || issuer.caseInsensitiveCompare("Steam") == .orderedSame
        if steam {
            // 链接里写错的位数或算法不再拦截，Steam 码的参数是固定的。
            return .success(DraftAccount(
                issuer: issuer.isEmpty ? "Steam" : issuer,
                account: account,
                secret: secret,
                kind: .steam,
                algorithm: .sha1,
                digits: 5,
                period: 30,
                counter: 0
            ))
        }

        let algorithm: OTPAlgorithm
        if let rawAlgorithm = query("algorithm") {
            switch rawAlgorithm.uppercased() {
            case "SHA1": algorithm = .sha1
            case "SHA256": algorithm = .sha256
            case "SHA512": algorithm = .sha512
            default: return .failure(.algorithm)
            }
        } else {
            algorithm = .sha1
        }

        let digits: Int
        if let rawDigits = query("digits") {
            guard let value = Int(rawDigits), value == 6 || value == 8 else { return .failure(.digits) }
            digits = value
        } else {
            digits = 6
        }

        let period: Int
        if let rawPeriod = query("period") {
            guard let value = Int(rawPeriod), value == 30 || value == 60 else { return .failure(.period) }
            period = value
        } else {
            period = 30
        }

        let counter: UInt64
        if kind == .hotp, let rawCounter = query("counter") {
            guard let value = UInt64(rawCounter) else { return .failure(.url) }
            counter = value
        } else {
            counter = 0
        }

        return .success(DraftAccount(
            issuer: issuer,
            account: account,
            secret: secret,
            kind: kind,
            algorithm: algorithm,
            digits: digits,
            period: period,
            counter: counter
        ))
    }

    private static func decodedLabel(_ path: String) -> String {
        let stripped = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return stripped.removingPercentEncoding ?? stripped
    }
}
