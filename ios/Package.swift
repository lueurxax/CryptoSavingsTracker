// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CryptoSavingsTracker",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .executable(name: "CryptoSavingsTracker", targets: ["CryptoSavingsTracker"])
    ],
    targets: [
        .executableTarget(
            name: "CryptoSavingsTracker",
            path: "CryptoSavingsTracker"
        )
    ]
)
