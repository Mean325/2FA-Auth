import XCTest
@testable import TwoFACore

final class VaultMergeTests: XCTestCase {
    func testNewerTombstoneBeatsOlderEdit() {
        let older = sample(issuer: "旧", counter: 4, updatedAt: 10, deletedAt: nil)
        let tombstone = sample(issuer: "旧", counter: 1, updatedAt: 20, deletedAt: 20, secret: Data())
        let merged = VaultMerge.merge(local: older, remote: tombstone)
        XCTAssertEqual(merged.deletedAt, tombstone.deletedAt)
        XCTAssertEqual(merged.secret, Data())
        XCTAssertEqual(merged.counter, 1)
    }

    func testEqualTimestampPrefersTombstone() {
        let alive = sample(issuer: "还在", counter: 2, updatedAt: 10, deletedAt: nil)
        let tombstone = sample(issuer: "删了", counter: 0, updatedAt: 10, deletedAt: 10, secret: Data())
        XCTAssertEqual(VaultMerge.merge(local: alive, remote: tombstone).deletedAt, tombstone.deletedAt)
        XCTAssertEqual(VaultMerge.merge(local: tombstone, remote: alive).deletedAt, tombstone.deletedAt)
    }

    func testLiveRecordsKeepNewerFieldsAndLargerCounter() {
        let local = sample(issuer: "本机", counter: 8, updatedAt: 10, deletedAt: nil)
        let remote = sample(issuer: "另一台", counter: 3, updatedAt: 30, deletedAt: nil)
        let merged = VaultMerge.merge(local: local, remote: remote)
        XCTAssertEqual(merged.issuer, "另一台")
        XCTAssertEqual(merged.counter, 8)
        XCTAssertEqual(merged.updatedAt, date(30))
    }

    func testNewerOrderWinsWhileKeepingLargerHotpCounter() {
        var local = sample(issuer: "本机", counter: 8, updatedAt: 10, deletedAt: nil)
        local.sortOrder = 4
        var remote = sample(issuer: "另一台", counter: 3, updatedAt: 30, deletedAt: nil)
        remote.sortOrder = 0
        let merged = VaultMerge.merge(local: local, remote: remote)
        XCTAssertEqual(merged.sortOrder, 0)
        XCTAssertEqual(merged.counter, 8)
    }

    private func sample(
        issuer: String,
        counter: UInt64,
        updatedAt: TimeInterval,
        deletedAt: TimeInterval?,
        secret: Data = Data("secret".utf8)
    ) -> VaultRecord {
        VaultRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            issuer: issuer,
            account: "ada",
            secret: secret,
            kind: .hotp,
            algorithm: .sha1,
            digits: 6,
            period: 30,
            counter: counter,
            sortOrder: nil,
            updatedAt: date(updatedAt),
            deletedAt: deletedAt.map(date)
        )
    }

    private func date(_ time: TimeInterval) -> Date {
        Date(timeIntervalSince1970: time)
    }
}
