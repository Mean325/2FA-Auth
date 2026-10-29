import CryptoKit
import Foundation
import TwoFACore

private enum ParsedRow {
    case ok(DraftAccount)
    case bad(String)
}

enum TextRead: Equatable {
    case accounts([DraftAccount])
    case secret(Data)
    case issue(ImportIssue)
}

enum BackupRead {
    case accounts([DraftAccount], rejected: [(name: String, reason: String)])
    case needsPassword
    case badPassword
    case unsupported
}

enum Importers {
    static func message(for issue: ImportIssue) -> String {
        switch issue {
        case .secret: return L10n.text(L10nKey.addBadSecret)
        case .algorithm: return L10n.text(L10nKey.addBadAlgorithm)
        case .digits: return L10n.text(L10nKey.addBadDigits)
        case .period: return L10n.text(L10nKey.addBadPeriod)
        case .url: return L10n.text(L10nKey.importBadItem)
        }
    }

    static func readText(_ raw: String) -> TextRead {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("otpauth-migration://") {
            let drafts = migrationAccounts(trimmed)
            return drafts.isEmpty ? .issue(.secret) : .accounts(drafts)
        }
        if trimmed.lowercased().hasPrefix("otpauth://") {
            switch OtpauthParser.parse(trimmed) {
            case .success(let draft): return .accounts([draft])
            case .failure(let issue): return .issue(issue)
            }
        }
        if let secret = SecretCodec.base32(trimmed) ?? SecretCodec.steamManual(trimmed) {
            return .secret(secret)
        }
        return .issue(.secret)
    }

    static func readBackup(_ data: Data, password: String?) -> BackupRead {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unsupported
        }
        if json["services"] != nil || json["servicesEncrypted"] != nil {
            return read2FAS(json, password: password)
        }
        if json["db"] != nil || json["header"] != nil {
            return readAegis(json, password: password)
        }
        return .unsupported
    }

    private static func read2FAS(_ json: [String: Any], password: String?) -> BackupRead {
        if let encrypted = json["servicesEncrypted"] as? String, !encrypted.isEmpty {
            guard let password, !password.isEmpty else { return .needsPassword }
            guard let blob = Data(base64Encoded: encrypted),
                  let plain = decrypt2FAS(password: password, blob: blob),
                  let services = try? JSONSerialization.jsonObject(with: plain) as? [[String: Any]]
            else { return .badPassword }
            return split(services.map(service2FAS))
        }
        guard let services = json["services"] as? [[String: Any]] else { return .unsupported }
        return split(services.map(service2FAS))
    }

    /// 2FAS 加密备份用密码的 SHA-256 当 AES-GCM 钥匙，密文是组合格式。密码不对就不写入。
    private static func decrypt2FAS(password: String, blob: Data) -> Data? {
        let key = SymmetricKey(data: Data(SHA256.hash(data: Data(password.utf8))))
        guard let box = try? AES.GCM.SealedBox(combined: blob) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    private static func service2FAS(_ item: [String: Any]) -> ParsedRow {
        let otp = item["otp"] as? [String: Any] ?? [:]
        let name = (item["name"] as? String) ?? (otp["issuer"] as? String) ?? ""
        guard let secretText = item["secret"] as? String, let secret = SecretCodec.base32(secretText) else {
            return .bad(name)
        }
        let token = (otp["tokenType"] as? String)?.uppercased() ?? "TOTP"
        let kind: OTPKind = token == "HOTP" ? .hotp : (token == "STEAM" ? .steam : .totp)
        return .ok(makeDraft(
            issuer: (otp["issuer"] as? String) ?? name,
            account: (otp["account"] as? String) ?? "",
            secret: secret,
            kind: kind,
            algorithm: algorithm(otp["algorithm"] as? String),
            digits: otp["digits"] as? Int ?? 6,
            period: otp["period"] as? Int ?? 30,
            counter: UInt64(otp["counter"] as? Int ?? 0)
        ))
    }

    private static func readAegis(_ json: [String: Any], password: String?) -> BackupRead {
        if let db = json["db"] as? [String: Any] {
            let entries = db["entries"] as? [[String: Any]] ?? []
            return split(entries.map(serviceAegis))
        }
        guard json["db"] is String else { return .unsupported }
        guard let password, !password.isEmpty else { return .needsPassword }
        guard let plain = decryptAegis(json, password: password),
              let decoded = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let entries = decoded["entries"] as? [[String: Any]]
        else { return .badPassword }
        return split(entries.map(serviceAegis))
    }

    /// Aegis 的主钥匙放在 scrypt 槽里。认证失败时整份都不写入。
    private static func decryptAegis(_ json: [String: Any], password: String) -> Data? {
        guard let header = json["header"] as? [String: Any],
              let slots = header["slots"] as? [[String: Any]],
              let params = header["params"] as? [String: Any],
              let dbText = json["db"] as? String,
              let slot = slots.first(where: { ($0["type"] as? Int) == 1 }),
              let salt = base64(slot["salt"] as? String),
              let n = slot["n"] as? Int,
              let r = slot["r"] as? Int,
              let p = slot["p"] as? Int,
              let keyParams = slot["key_params"] as? [String: Any],
              let wrapped = base64(slot["key"] as? String),
              let slotNonce = base64(keyParams["nonce"] as? String),
              let slotTag = base64(keyParams["tag"] as? String),
              let dbNonce = base64(params["nonce"] as? String),
              let dbTag = base64(params["tag"] as? String),
              let dbCipher = base64(dbText),
              let derived = Scrypt.derive(password: Data(password.utf8), salt: salt, n: n, r: r, p: p, length: 32),
              let master = openGCM(cipher: wrapped, nonce: slotNonce, tag: slotTag, key: derived),
              let plain = openGCM(cipher: dbCipher, nonce: dbNonce, tag: dbTag, key: master)
        else { return nil }
        return plain
    }

    private static func serviceAegis(_ item: [String: Any]) -> ParsedRow {
        let info = item["info"] as? [String: Any] ?? [:]
        let name = (item["issuer"] as? String) ?? (item["name"] as? String) ?? ""
        guard let secretText = info["secret"] as? String, let secret = SecretCodec.base32(secretText) else {
            return .bad(name)
        }
        let token = (item["type"] as? String)?.lowercased() ?? "totp"
        let kind: OTPKind = token == "hotp" ? .hotp : (token == "steam" ? .steam : .totp)
        return .ok(makeDraft(
            issuer: name,
            account: (item["name"] as? String) ?? "",
            secret: secret,
            kind: kind,
            algorithm: algorithm(info["algo"] as? String),
            digits: info["digits"] as? Int ?? 6,
            period: info["period"] as? Int ?? 30,
            counter: UInt64(info["counter"] as? Int ?? 0)
        ))
    }

    private static func split(_ rows: [ParsedRow]) -> BackupRead {
        var ready: [DraftAccount] = []
        var rejected: [(name: String, reason: String)] = []
        for row in rows {
            switch row {
            case .ok(let draft): ready.append(draft)
            case .bad(let name): rejected.append((name, L10n.text(L10nKey.importBadItem)))
            }
        }
        if ready.isEmpty && rejected.isEmpty { return .unsupported }
        return .accounts(ready, rejected: rejected)
    }

    private static func makeDraft(
        issuer: String,
        account: String,
        secret: Data,
        kind: OTPKind,
        algorithm: OTPAlgorithm?,
        digits: Int,
        period: Int,
        counter: UInt64
    ) -> DraftAccount {
        let steam = kind == .steam || issuer.caseInsensitiveCompare("Steam") == .orderedSame
        return DraftAccount(
            issuer: issuer,
            account: account,
            secret: secret,
            kind: steam ? .steam : kind,
            algorithm: steam ? .sha1 : (algorithm ?? .sha1),
            digits: steam ? 5 : (digits == 8 ? 8 : 6),
            period: steam ? 30 : (period == 60 ? 60 : 30),
            counter: steam ? 0 : counter
        )
    }

    private static func algorithm(_ raw: String?) -> OTPAlgorithm? {
        switch raw?.uppercased() {
        case "SHA1", "SHA-1": return .sha1
        case "SHA256", "SHA-256": return .sha256
        case "SHA512", "SHA-512": return .sha512
        case nil: return nil
        default: return nil
        }
    }

    private static func migrationAccounts(_ raw: String) -> [DraftAccount] {
        guard let components = URLComponents(string: raw),
              let dataText = components.queryItems?.first(where: { $0.name == "data" })?.value,
              let payload = base64(dataText)
        else { return [] }
        var scanner = ProtoScanner(payload)
        var drafts: [DraftAccount] = []
        while let field = scanner.next() {
            if field.number == 1, case .bytes(let nested) = field.value {
                if let draft = otpParameters(nested) { drafts.append(draft) }
            }
        }
        return drafts
    }

    private static func otpParameters(_ data: Data) -> DraftAccount? {
        var scanner = ProtoScanner(data)
        var secret = Data()
        var name = ""
        var issuer = ""
        var algorithm = OTPAlgorithm.sha1
        var digits = 6
        var kind = OTPKind.totp
        var counter: UInt64 = 0
        while let field = scanner.next() {
            switch (field.number, field.value) {
            case (1, .bytes(let value)): secret = value
            case (2, .bytes(let value)): name = String(data: value, encoding: .utf8) ?? ""
            case (3, .bytes(let value)): issuer = String(data: value, encoding: .utf8) ?? ""
            case (4, .varint(let value)):
                algorithm = value == 2 ? .sha256 : (value == 3 ? .sha512 : .sha1)
            case (5, .varint(let value)):
                digits = value == 2 ? 8 : 6
            case (6, .varint(let value)):
                kind = value == 1 ? .hotp : .totp
            case (7, .varint(let value)):
                counter = value
            default:
                break
            }
        }
        guard !secret.isEmpty else { return nil }
        let account = name
        return makeDraft(issuer: issuer.isEmpty ? name : issuer, account: issuer.isEmpty ? "" : account, secret: secret, kind: kind, algorithm: algorithm, digits: digits, period: 30, counter: counter)
    }

    private static func base64(_ raw: String?) -> Data? {
        guard var text = raw?.replacingOccurrences(of: " ", with: "+") else { return nil }
        text = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = text.count % 4
        if remainder != 0 { text += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: text)
    }

    private static func openGCM(cipher: Data, nonce: Data, tag: Data, key: Data) -> Data? {
        guard let gcmNonce = try? AES.GCM.Nonce(data: nonce),
              let box = try? AES.GCM.SealedBox(nonce: gcmNonce, ciphertext: cipher, tag: tag)
        else { return nil }
        return try? AES.GCM.open(box, using: SymmetricKey(data: key))
    }
}

private struct ProtoField {
    var number: Int
    var value: ProtoValue
}

private enum ProtoValue {
    case varint(UInt64)
    case bytes(Data)
}

private struct ProtoScanner {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func next() -> ProtoField? {
        guard let key = varint() else { return nil }
        let number = Int(key >> 3)
        switch key & 0x7 {
        case 0:
            guard let value = varint() else { return nil }
            return ProtoField(number: number, value: .varint(value))
        case 2:
            guard let length = varint(), index + Int(length) <= bytes.count else { return nil }
            let end = index + Int(length)
            let data = Data(bytes[index..<end])
            index = end
            return ProtoField(number: number, value: .bytes(data))
        case 1:
            guard index + 8 <= bytes.count else { return nil }
            index += 8
            return ProtoField(number: number, value: .varint(0))
        case 5:
            guard index + 4 <= bytes.count else { return nil }
            index += 4
            return ProtoField(number: number, value: .varint(0))
        default:
            return nil
        }
    }

    private mutating func varint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }
}
