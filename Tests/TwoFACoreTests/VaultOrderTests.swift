import XCTest
@testable import TwoFACore

final class VaultOrderTests: XCTestCase {
    func testMoveUpAndDownPreservesEveryAccount() throws {
        let records = samples()
        let movedUp = try XCTUnwrap(VaultOrder.moving(records, id: records[2].id, to: records[0].id, at: Date()))
        XCTAssertEqual(VaultOrder.ordered(movedUp).map(\.id), [records[2].id, records[0].id, records[1].id])
        let movedDown = try XCTUnwrap(VaultOrder.moving(records, id: records[0].id, to: records[2].id, at: Date()))
        XCTAssertEqual(VaultOrder.ordered(movedDown).map(\.id), [records[1].id, records[2].id, records[0].id])
        XCTAssertEqual(Set(movedDown.map(\.id)), Set(records.map(\.id)))
        XCTAssertEqual(movedDown.map(\.secret), records.map(\.secret))
    }

    func testOrderSurvivesFileEncodingAndNewAccountAppends() throws {
        let records = samples()
        let moved = try XCTUnwrap(VaultOrder.moving(records, id: records[2].id, to: records[0].id, at: Date()))
        var reopened = try LocalVaultFile.decode(LocalVaultFile.encode(moved))
        let new = sample(order: VaultOrder.nextOrder(reopened))
        reopened.append(new)
        XCTAssertEqual(VaultOrder.ordered(reopened).map(\.id), [records[2].id, records[0].id, records[1].id, new.id])
    }

    func testMovingSearchResultsKeepsUnshownAccountsAndTombstones() throws {
        let records = samples()
        var deleted = sample(order: 10)
        deleted.deletedAt = Date(timeIntervalSince1970: 10)
        deleted.secret = Data()
        let all = records + [deleted]
        let moved = try XCTUnwrap(VaultOrder.moving(all, id: records[2].id, to: records[0].id, at: Date()))
        XCTAssertEqual(VaultOrder.ordered(moved).map(\.id), [records[2].id, records[0].id, records[1].id])
        XCTAssertEqual(moved.last, deleted)
    }

    func testOnlyChangedPositionsReceiveNewTimestamps() throws {
        let records = samples()
        let now = Date(timeIntervalSince1970: 50)
        let moved = try XCTUnwrap(VaultOrder.moving(records, id: records[1].id, to: records[2].id, at: now))
        XCTAssertEqual(moved[0], records[0])
        XCTAssertEqual(moved[1].updatedAt, now)
        XCTAssertEqual(moved[2].updatedAt, now)
    }

    func testInvalidOrSameTargetDoesNotChangeOrder() {
        let records = samples()
        XCTAssertNil(VaultOrder.moving(records, id: UUID(), to: records[0].id, at: Date()))
        XCTAssertNil(VaultOrder.moving(records, id: records[0].id, to: UUID(), at: Date()))
        XCTAssertNil(VaultOrder.moving(records, id: records[0].id, to: records[0].id, at: Date()))
    }

    private func samples() -> [VaultRecord] { (0..<3).map { sample(order: $0) } }
    private func sample(order: Int) -> VaultRecord {
        VaultRecord(id: UUID(), issuer: "Demo", account: "demo@example.com",
            secret: Data("12345678901234567890".utf8), kind: .hotp, algorithm: .sha1,
            digits: 6, period: 30, counter: 4, sortOrder: order,
            updatedAt: Date(timeIntervalSince1970: 10), deletedAt: nil)
    }
}
