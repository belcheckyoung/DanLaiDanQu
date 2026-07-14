// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DanmakuOverlay",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "DanmakuOverlay",
            path: "Sources/DanmakuOverlay",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .testTarget(
            name: "DanmakuOverlayTests",
            dependencies: ["DanmakuOverlay"]
        ),
    ]
)
