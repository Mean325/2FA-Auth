import XCTest
@testable import TwoFACore

final class ScryptTests: XCTestCase {
    /// RFC 7914 §12: ensures byte-to-word decoding retains little-endian order.
    func testRFC7914Vector() throws {
        let result = try XCTUnwrap(Scrypt.derive(
            password: Data(), salt: Data(), n: 16, r: 1, p: 1, length: 64
        ))
        let expected = "77d6576238657b203b19ca42c18a0497"
            + "f16b4844e3074ae8dfdffa3fede21442"
            + "fcd0069ded0948f8326a753a0fc81f17"
            + "e8d3e0fb2e0d3628cf35e20c38d18906"
        XCTAssertEqual(result.map { String(format: "%02x", $0) }.joined(), expected)
    }
}
