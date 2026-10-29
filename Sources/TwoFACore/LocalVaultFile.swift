import Darwin
import Foundation

/// Base64 编码的 JSON 文件；没有应用层加密，也不依赖钥匙串。
public struct LocalVaultFile: Sendable {
    public enum Failure: Error {
        case invalidEncoding, unsupportedVersion, invalidRecords
    }

    private struct Envelope: Codable {
        var version: Int
        var records: [VaultRecord]
    }

    public let url: URL
    public init(url: URL) { self.url = url }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    public static func encode(_ records: [VaultRecord]) throws -> Data {
        let records = try validated(records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Envelope(version: 1, records: records)).base64EncodedData()
    }

    public static func decode(_ encoded: Data) throws -> [VaultRecord] {
        guard let json = Data(base64Encoded: encoded) else { throw Failure.invalidEncoding }
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(Envelope.self, from: json)
        guard envelope.version == 1 else { throw Failure.unsupportedVersion }
        return try validated(envelope.records)
    }

    public func load() throws -> [VaultRecord] {
        try Self.decode(Data(contentsOf: url))
    }

    public func save(_ records: [VaultRecord]) throws {
        let data = try Self.encode(records)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 原子替换保留原文件直到新文件完整写入；文件仅当前用户可读写。
        let temporary = directory.appendingPathComponent(".vault-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        try handle.synchronize()
        guard rename(temporary.path, url.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private static func validated(_ records: [VaultRecord]) throws -> [VaultRecord] {
        guard Set(records.map(\.id)).count == records.count,
              records.allSatisfy({ $0.deletedAt != nil || !$0.secret.isEmpty }) else {
            throw Failure.invalidRecords
        }
        return records.map { record in
            var record = record
            if record.deletedAt != nil { record.secret = Data() }
            return record
        }
    }
}
