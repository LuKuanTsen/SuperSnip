// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SuperSnip",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SuperSnip",
            path: "SuperSnip",
            exclude: ["Info.plist", "SuperSnip.entitlements"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon"),
            ]
        ),
    ]
)
