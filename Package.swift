// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AriaVoice",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AriaVoice",
            path: "Sources/AriaVoice",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
