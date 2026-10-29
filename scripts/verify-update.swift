import CryptoKit
import Foundation

// Verify with the public key embedded in the shipped app, not the CI signing key.
guard CommandLine.arguments.count == 4,
      let publicKey = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[2]) else {
    fatalError("Usage: verify-update.swift PUBLIC_KEY SIGNATURE ARCHIVE")
}
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
guard key.isValidSignature(signature, for: archive) else {
    fputs("Update signature does not match the app's public key.\n", stderr)
    exit(1)
}
print("Update signature verified against the app's public key.")
