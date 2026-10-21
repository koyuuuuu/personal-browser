// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrowserCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "BrowserCore", targets: ["BrowserCore"])],
    targets: [
        .target(name: "BrowserCore"),
        .testTarget(name: "BrowserCoreTests", dependencies: ["BrowserCore"])
    ]
)
