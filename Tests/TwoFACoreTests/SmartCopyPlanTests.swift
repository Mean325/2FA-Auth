import XCTest
@testable import TwoFACore

final class SmartCopyPlanTests: XCTestCase {
    func testRefreshesAtExpiryAndOnlyWithinTheNextPeriod() throws {
        let record = makeRecord()
        let plan = try XCTUnwrap(SmartCopyPlan(record: record, copiedAt: 24))
        XCTAssertEqual(plan.expiresAt, 30)
        XCTAssertNil(plan.refreshedCode(at: 29.99, currentRecord: record))
        XCTAssertEqual(plan.refreshedCode(at: 30, currentRecord: record), "287082")
        XCTAssertEqual(plan.refreshedCode(at: 59.99, currentRecord: record), "287082")
        XCTAssertNil(plan.refreshedCode(at: 60, currentRecord: record))
    }

    func testPrefetchedCodeUsesItsOwnExpiry() throws {
        let record = makeRecord()
        for time in [25.0, 26.2, 29.99, 30.0] {
            let plan = try XCTUnwrap(SmartCopyPlan(record: record, copiedAt: time))
            XCTAssertEqual(plan.expiresAt, 60)
            XCTAssertNil(plan.refreshedCode(at: 30, currentRecord: record))
            XCTAssertEqual(plan.refreshedCode(at: 60, currentRecord: record), "359152")
        }
    }

    func testCustomPeriodAndSteam() throws {
        var record = makeRecord()
        record.period = 60
        XCTAssertEqual(SmartCopyPlan(record: record, copiedAt: 54)?.expiresAt, 60)
        XCTAssertEqual(SmartCopyPlan(record: record, copiedAt: 55)?.expiresAt, 120)
        record.kind = .steam
        record.period = 30
        let plan = try XCTUnwrap(SmartCopyPlan(record: record, copiedAt: 59))
        XCTAssertEqual(plan.expiresAt, 90)
        XCTAssertEqual(plan.refreshedCode(at: 90, currentRecord: record),
                       OTPEngine.code(secret: record.secret, kind: .steam, algorithm: .sha1,
                                      digits: 6, period: 30, counter: 0, at: 90))
    }

    func testDeletedOrChangedCredentialsDoNotRefresh() throws {
        let record = makeRecord()
        let plan = try XCTUnwrap(SmartCopyPlan(record: record, copiedAt: 10))
        var changed = record
        changed.deletedAt = Date()
        XCTAssertNil(plan.refreshedCode(at: 30, currentRecord: changed))
        changed = record
        changed.secret = Data("different secret".utf8)
        XCTAssertNil(plan.refreshedCode(at: 30, currentRecord: changed))
        changed = record
        changed.period = 60
        XCTAssertNil(plan.refreshedCode(at: 30, currentRecord: changed))
        changed = record
        changed.algorithm = .sha256
        XCTAssertNil(plan.refreshedCode(at: 30, currentRecord: changed))
        changed = record
        changed.digits = 8
        XCTAssertNil(plan.refreshedCode(at: 30, currentRecord: changed))
        changed = record
        changed.id = UUID()
        XCTAssertNil(plan.refreshedCode(at: 30, currentRecord: changed))
        changed = record
        changed.issuer = "Renamed"
        XCTAssertEqual(plan.refreshedCode(at: 30, currentRecord: changed), "287082")
    }

    func testHotpDeletedAndInvalidInputsHaveNoPlan() {
        var record = makeRecord()
        record.kind = .hotp
        XCTAssertNil(SmartCopyPlan(record: record, copiedAt: 10))
        record.kind = .totp
        record.deletedAt = Date()
        XCTAssertNil(SmartCopyPlan(record: record, copiedAt: 10))
        record.deletedAt = nil
        record.period = 0
        XCTAssertNil(SmartCopyPlan(record: record, copiedAt: 10))
        record.period = 30
        XCTAssertNil(SmartCopyPlan(record: record, copiedAt: .nan))
        XCTAssertNil(SmartCopyPlan(record: record, copiedAt: -1))
    }

    private func makeRecord() -> VaultRecord {
        VaultRecord(id: UUID(), issuer: "Example", account: "test@example.com",
                    secret: Data("12345678901234567890".utf8), kind: .totp, algorithm: .sha1,
                    digits: 6, period: 30, counter: 0, updatedAt: Date(), deletedAt: nil)
    }
}
