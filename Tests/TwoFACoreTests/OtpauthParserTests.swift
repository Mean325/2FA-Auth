import XCTest
@testable import TwoFACore

final class OtpauthParserTests: XCTestCase {
    func testGitHubLink() throws {
        let raw = "otpauth://totp/GitHub:ada?secret=JBSWY3DPEHPK3PXP"
        let draft = try XCTUnwrap(try? OtpauthParser.parse(raw).get())
        XCTAssertEqual(draft.issuer, "GitHub")
        XCTAssertEqual(draft.account, "ada")
        XCTAssertEqual(draft.kind, .totp)
        XCTAssertEqual(draft.algorithm, .sha1)
        XCTAssertEqual(draft.digits, 6)
        XCTAssertEqual(draft.period, 30)
        XCTAssertEqual(draft.secret, Data("Hello!".utf8) + Data([0xde, 0xad, 0xbe, 0xef]))
    }

    func testSteamIssuerOverridesTotp() throws {
        let raw = "otpauth://totp/Steam:player?secret=JBSWY3DPEHPK3PXP&issuer=Steam"
        let draft = try XCTUnwrap(try? OtpauthParser.parse(raw).get())
        XCTAssertEqual(draft.kind, .steam)
        XCTAssertEqual(draft.digits, 5)
        XCTAssertEqual(draft.period, 30)
        XCTAssertEqual(draft.algorithm, .sha1)
    }

    func testBase32IgnoresPaddingCaseAndSeparators() {
        let expected = Data("foobar".utf8)
        XCTAssertEqual(SecretCodec.base32("MZXW6YTBOI======"), expected)
        XCTAssertEqual(SecretCodec.base32("mzxw6ytboi"), expected)
        XCTAssertEqual(SecretCodec.base32("MZ XW6-YTBOI"), expected)
    }

    func testSteamManualHexThenBase32ThenBase64() {
        let hex = "3132333435363738393031323334353637383930"
        XCTAssertEqual(SecretCodec.steamManual(hex), Data("12345678901234567890".utf8))
        XCTAssertEqual(SecretCodec.steamManual("MZXW6YTBOI"), Data("foobar".utf8))
        XCTAssertEqual(SecretCodec.steamManual("Zm9vYmFy"), Data("foobar".utf8))
    }

    func testHotpCounterDefaultsToZero() throws {
        let draft = try XCTUnwrap(try? OtpauthParser.parse("otpauth://hotp/Site:bob?secret=JBSWY3DPEHPK3PXP").get())
        XCTAssertEqual(draft.kind, .hotp)
        XCTAssertEqual(draft.counter, 0)
    }

    func testRejectsUnknownAlgorithm() {
        let raw = "otpauth://totp/A:b?secret=JBSWY3DPEHPK3PXP&algorithm=MD5"
        XCTAssertEqual(OtpauthParser.parse(raw), .failure(.algorithm))
    }
}
