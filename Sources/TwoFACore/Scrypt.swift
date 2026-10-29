import CommonCrypto
import Foundation

public enum Scrypt {
    /// 备份口令派生。参数过大时直接放弃，避免一份坏文件把内存吃光。
    public static func derive(password: Data, salt: Data, n: Int, r: Int, p: Int, length: Int) -> Data? {
        guard n > 1, n & (n - 1) == 0, n <= 1 << 16 else { return nil }
        guard r >= 1, r <= 16, p >= 1, p <= 16, length > 0, length <= 64 else { return nil }
        let blockSize = 128 * r
        guard var blocks = pbkdf2(password: password, salt: salt, rounds: 1, length: blockSize * p) else { return nil }
        for index in 0..<p {
            let start = index * blockSize
            var chunk = Array(blocks[start..<(start + blockSize)])
            romix(&chunk, n: n, r: r)
            blocks.replaceSubrange(start..<(start + blockSize), with: chunk)
        }
        return pbkdf2(password: password, salt: blocks, rounds: 1, length: length)
    }

    private static func romix(_ block: inout [UInt8], n: Int, r: Int) {
        var v = [[UInt8]]()
        v.reserveCapacity(n)
        var x = block
        for _ in 0..<n {
            v.append(x)
            x = blockMix(x, r: r)
        }
        for _ in 0..<n {
            let j = integerify(x, r: r) % UInt64(n)
            x = blockMix(xorBytes(x, v[Int(j)]), r: r)
        }
        block = x
    }

    private static func blockMix(_ input: [UInt8], r: Int) -> [UInt8] {
        let chunks = 2 * r
        var x = Array(input[(chunks - 1) * 64..<chunks * 64])
        var y = [UInt8](repeating: 0, count: chunks * 64)
        for index in 0..<chunks {
            let piece = Array(input[index * 64..<(index + 1) * 64])
            var words = words(from: xorBytes(x, piece))
            salsa208(&words)
            x = bytes(from: words)
            y.replaceSubrange(index * 64..<(index + 1) * 64, with: x)
        }
        var output = [UInt8](repeating: 0, count: chunks * 64)
        var cursor = 0
        for index in stride(from: 0, to: chunks, by: 2) {
            output.replaceSubrange(cursor..<(cursor + 64), with: y[index * 64..<(index + 1) * 64])
            cursor += 64
        }
        for index in stride(from: 1, to: chunks, by: 2) {
            output.replaceSubrange(cursor..<(cursor + 64), with: y[index * 64..<(index + 1) * 64])
            cursor += 64
        }
        return output
    }

    private static func integerify(_ block: [UInt8], r: Int) -> UInt64 {
        let offset = (2 * r - 1) * 64
        return block[offset..<(offset + 8)].enumerated().reduce(UInt64(0)) { partial, item in
            partial | (UInt64(item.element) << (UInt64(item.offset) * 8))
        }
    }

    private static func salsa208(_ block: inout [UInt32]) {
        var x = block
        func rotl(_ value: UInt32, _ count: UInt32) -> UInt32 {
            (value << count) | (value >> (32 - count))
        }
        for _ in 0..<4 {
            x[4] ^= rotl(x[0] &+ x[12], 7); x[8] ^= rotl(x[4] &+ x[0], 9)
            x[12] ^= rotl(x[8] &+ x[4], 13); x[0] ^= rotl(x[12] &+ x[8], 18)
            x[9] ^= rotl(x[5] &+ x[1], 7); x[13] ^= rotl(x[9] &+ x[5], 9)
            x[1] ^= rotl(x[13] &+ x[9], 13); x[5] ^= rotl(x[1] &+ x[13], 18)
            x[14] ^= rotl(x[10] &+ x[6], 7); x[2] ^= rotl(x[14] &+ x[10], 9)
            x[6] ^= rotl(x[2] &+ x[14], 13); x[10] ^= rotl(x[6] &+ x[2], 18)
            x[3] ^= rotl(x[15] &+ x[11], 7); x[7] ^= rotl(x[3] &+ x[15], 9)
            x[11] ^= rotl(x[7] &+ x[3], 13); x[15] ^= rotl(x[11] &+ x[7], 18)
            x[1] ^= rotl(x[0] &+ x[3], 7); x[2] ^= rotl(x[1] &+ x[0], 9)
            x[3] ^= rotl(x[2] &+ x[1], 13); x[0] ^= rotl(x[3] &+ x[2], 18)
            x[6] ^= rotl(x[5] &+ x[4], 7); x[7] ^= rotl(x[6] &+ x[5], 9)
            x[4] ^= rotl(x[7] &+ x[6], 13); x[5] ^= rotl(x[4] &+ x[7], 18)
            x[11] ^= rotl(x[10] &+ x[9], 7); x[8] ^= rotl(x[11] &+ x[10], 9)
            x[9] ^= rotl(x[8] &+ x[11], 13); x[10] ^= rotl(x[9] &+ x[8], 18)
            x[12] ^= rotl(x[15] &+ x[14], 7); x[13] ^= rotl(x[12] &+ x[15], 9)
            x[14] ^= rotl(x[13] &+ x[12], 13); x[15] ^= rotl(x[14] &+ x[13], 18)
        }
        for index in 0..<16 { block[index] = block[index] &+ x[index] }
    }

    private static func words(from bytes: [UInt8]) -> [UInt32] {
        stride(from: 0, to: 64, by: 4).map { offset in
            let low = UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
            let high = (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
            return low | high
        }
    }

    private static func bytes(from words: [UInt32]) -> [UInt8] {
        words.flatMap { word in
            [UInt8(word & 0xff), UInt8((word >> 8) & 0xff), UInt8((word >> 16) & 0xff), UInt8((word >> 24) & 0xff)]
        }
    }

    private static func xorBytes(_ lhs: [UInt8], _ rhs: [UInt8]) -> [UInt8] {
        zip(lhs, rhs).map { $0 ^ $1 }
    }

    private static func pbkdf2(password: Data, salt: Data, rounds: Int, length: Int) -> Data? {
        var output = Data(count: length)
        let status: CCStatus = output.withUnsafeMutableBytes { outPtr in
            password.withUnsafeBytes { passPtr in
                salt.withUnsafeBytes { saltPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltPtr.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(rounds),
                        outPtr.bindMemory(to: UInt8.self).baseAddress,
                        length
                    )
                }
            }
        }
        return status == kCCSuccess ? output : nil
    }
}
