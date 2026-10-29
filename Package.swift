// swift-tools-version: 6.0
import PackageDescription

// 核心计算不依赖 SwiftUI，方便用 swift build 单独校验，界面工程再链接这个库。
let package = Package(
    name: "TwoFA",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TwoFACore", targets: ["TwoFACore"])
    ],
    targets: [
        .target(name: "TwoFACore"),
        .testTarget(name: "TwoFACoreTests", dependencies: ["TwoFACore"])
    ]
)
