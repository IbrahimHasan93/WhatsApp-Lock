// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WhatsAppLock",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "WhatsAppLock",
            path: "Sources/WhatsAppLock"
        )
    ]
)
