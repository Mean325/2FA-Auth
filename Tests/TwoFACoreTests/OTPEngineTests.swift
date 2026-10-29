import XCTest
@testable import TwoFACore

final class OTPEngineTests: XCTestCase {
    private let sha1Seed = Data("12345678901234567890".utf8)
    private let sha256Seed = Data("12345678901234567890123456789012".utf8)
    private let sha512Seed = Data(String(repeating: "1234567890", count: 7).prefix(64).utf8)

    func testHotpAppendixD() {
        let expected = [
            "755224", "287082", "359152", "969429", "338314",
            "254676", "287922", "162583", "399871", "520489"
        ]
        for (counter, code) in expected.enumerated() {
            XCTAssertEqual(
                OTPEngine.code(secret: sha1Seed, kind: .hotp, algorithm: .sha1, digits: 6, period: 30, counter: UInt64(counter), at: 0),
                code,
                "counter \(counter)"
            )
        }
    }

    func testTotpAppendixB() {
        let rows: [(TimeInterval, String, String, String)] = [
            (59, "94287082", "46119246", "90693936"),
            (1_111_111_109, "07081804", "68084774", "25091201"),
            (1_111_111_111, "14050471", "67062674", "99943326"),
            (1_234_567_890, "89005924", "91819424", "93441116"),
            (2_000_000_000, "69279037", "90698825", "38618901"),
            (20_000_000_000, "65353130", "77737706", "47863826")
        ]
        for row in rows {
            XCTAssertEqual(otp(algorithm: .sha1, secret: sha1Seed, at: row.0), row.1, "sha1 \(row.0)")
            XCTAssertEqual(otp(algorithm: .sha256, secret: sha256Seed, at: row.0), row.2, "sha256 \(row.0)")
            XCTAssertEqual(otp(algorithm: .sha512, secret: sha512Seed, at: row.0), row.3, "sha512 \(row.0)")
        }
        XCTAssertEqual(
            OTPEngine.code(secret: sha1Seed, kind: .totp, algorithm: .sha1, digits: 6, period: 30, counter: 0, at: 59),
            "287082"
        )
    }

    func testSteamAt59Seconds() {
        XCTAssertEqual(
            OTPEngine.code(secret: sha1Seed, kind: .steam, algorithm: .sha1, digits: 5, period: 30, counter: 0, at: 59),
            "PV9M4"
        )
    }

    func testDisplayTimeUsesNextSlotAtFiveSeconds() {
        XCTAssertEqual(OTPEngine.displayTime(kind: .totp, period: 30, at: 26.2), 30)
        XCTAssertEqual(OTPEngine.displayTime(kind: .totp, period: 30, at: 25), 30)
        XCTAssertEqual(OTPEngine.displayTime(kind: .totp, period: 30, at: 24), 24)
        XCTAssertEqual(OTPEngine.displayTime(kind: .hotp, period: 30, at: 26), 26)
        XCTAssertEqual(OTPEngine.remaining(period: 30, at: 26.2), 3.8, accuracy: 0.001)
    }

    private func otp(algorithm: OTPAlgorithm, secret: Data, at time: TimeInterval) -> String {
        OTPEngine.code(secret: secret, kind: .totp, algorithm: algorithm, digits: 8, period: 30, counter: 0, at: time)
    }
}
