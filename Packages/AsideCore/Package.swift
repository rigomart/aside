// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AsideCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AsideCore", targets: ["AsideCore"]),
    ],
    targets: [
        .target(name: "AsideCore"),
        .testTarget(name: "AsideCoreTests", dependencies: ["AsideCore"]),
    ]
)
