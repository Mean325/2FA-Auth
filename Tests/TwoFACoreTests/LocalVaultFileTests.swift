import XCTest
@testable import TwoFACore

final class LocalVaultFileTests: XCTestCase {
    func testBase64ContainsReadableJSONAndPreservesOTPAfterRestart() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = LocalVaultFile(url: folder.appendingPathComponent("accounts.base64"))
        var records = [sample(.totp), sample(.hotp), sample(.steam)]
        records[1].counter = 19
        records[2].digits = 5
        try file.save(records)
        let data = try Data(contentsOf: file.url)
        let json = try XCTUnwrap(Data(base64Encoded: data))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let stored = try XCTUnwrap(object["records"] as? [[String: Any]])
        XCTAssertEqual(stored.first?["secret"] as? String, records[0].secret.base64EncodedString())
        let reopened = try LocalVaultFile(url: file.url).load()
        XCTAssertEqual(reopened, records)
        for (original, restored) in zip(records, reopened) {
            XCTAssertEqual(code(original), code(restored))
        }
        let permissions = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testDeletedRecordsDiscardSecretsOnSave() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = LocalVaultFile(url: folder.appendingPathComponent("accounts.base64"))
        var tombstone = sample(.totp)
        tombstone.deletedAt = Date(timeIntervalSinceReferenceDate: 1234.56789)
        try file.save([tombstone])
        let restored = try XCTUnwrap(file.load().first)
        XCTAssertTrue(restored.secret.isEmpty)
        XCTAssertEqual(restored.id, tombstone.id)
        XCTAssertEqual(restored.deletedAt, tombstone.deletedAt)
    }

    func testInvalidDataAndDuplicateIDsAreRejectedWithoutOverwriting() throws {
        XCTAssertThrowsError(try LocalVaultFile.decode(Data("broken".utf8)))
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = LocalVaultFile(url: folder.appendingPathComponent("accounts.base64"))
        let record = sample(.totp)
        try file.save([record])
        let original = try Data(contentsOf: file.url)
        XCTAssertThrowsError(try file.save([record, record]))
        var empty = record
        empty.secret = Data()
        XCTAssertThrowsError(try file.save([empty]))
        XCTAssertEqual(try Data(contentsOf: file.url), original)
    }

    func testUnknownVersionIsRejected() throws {
        let json = try XCTUnwrap(Data(base64Encoded: LocalVaultFile.encode([sample(.totp)])))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        object["version"] = 99
        let future = try JSONSerialization.data(withJSONObject: object).base64EncodedData()
        XCTAssertThrowsError(try LocalVaultFile.decode(future))
    }

    func testFailedAtomicReplacementPreservesDestinationAndCleansTemporaryFile() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent("accounts.base64")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let sentinel = destination.appendingPathComponent("original")
        try Data("keep".utf8).write(to: sentinel)
        XCTAssertThrowsError(try LocalVaultFile(url: destination).save([sample(.totp)]))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["accounts.base64"])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sample(_ kind: OTPKind) -> VaultRecord {
        VaultRecord(id: UUID(), issuer: "测试服务", account: "test@example.com",
            secret: Data("12345678901234567890".utf8), kind: kind, algorithm: .sha1,
            digits: 6, period: 30, counter: 0, sortOrder: nil,
            updatedAt: Date(timeIntervalSinceReferenceDate: 800_000_000.123456), deletedAt: nil)
    }

    private func code(_ record: VaultRecord) -> String {
        OTPEngine.code(secret: record.secret, kind: record.kind, algorithm: record.algorithm,
            digits: record.digits, period: record.period, counter: record.counter, at: 59)
    }
}
