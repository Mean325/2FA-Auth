import Foundation

public enum SecretCodec {
    /// RFC 4648 Base32。忽略空格和连字符，不区分大小写，填充可有可无。
    public static func base32(_ raw: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        let values = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })
        let cleaned = raw.uppercased().filter { $0 != "=" && !isIgnored($0) }
        guard !cleaned.isEmpty else { return nil }
        var buffer = 0
        var bits = 0
        var output = Data()
        for character in cleaned {
            guard let value = values[character] else { return nil }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((buffer >> bits) & 0xff))
            }
        }
        return output
    }

    /// 编辑框要展示原始字节。用户当初的空格和大小写不会保留。
    public static func base32Encode(_ data: Data) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var buffer = 0
        var bits = 0
        var output = ""
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(buffer >> bits) & 0x1f])
            }
        }
        if bits > 0 {
            output.append(alphabet[(buffer << (5 - bits)) & 0x1f])
        }
        return output
    }

    public static func hex(_ raw: String) -> Data? {
        let cleaned = raw.filter { !isIgnored($0) }
        guard !cleaned.isEmpty, cleaned.count.isMultiple(of: 2) else { return nil }
        var output = Data()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            output.append(byte)
            index = next
        }
        return output
    }

    public static func base64(_ raw: String) -> Data? {
        let cleaned = raw.filter { !$0.isWhitespace }
        guard !cleaned.isEmpty else { return nil }
        return Data(base64Encoded: cleaned)
    }

    /// 手动添加 Steam：整段 40 位十六进制按十六进制，否则先 Base32，再 Base64。
    /// otpauth 和备份里已经解出的字节不要再走这里。
    public static func steamManual(_ raw: String) -> Data? {
        let compact = raw.filter { !isIgnored($0) }
        if compact.count == 40, compact.allSatisfy(isASCIIHex) {
            return hex(compact)
        }
        if let decoded = base32(raw) { return decoded }
        return base64(raw)
    }

    private static func isIgnored(_ character: Character) -> Bool {
        character.isWhitespace || character == "-"
    }

    private static func isASCIIHex(_ character: Character) -> Bool {
        guard let value = character.asciiValue else { return false }
        return (value >= 48 && value <= 57) || (value >= 65 && value <= 70) || (value >= 97 && value <= 102)
    }
}
