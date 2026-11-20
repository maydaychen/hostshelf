// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HostShelf",
    platforms: [.macOS(.v14)],
    products: [.library(name: "HostShelfCore", targets: ["HostShelfCore"])],
    targets: [
        .target(name: "HostShelfCore"),
        .testTarget(name: "HostShelfCoreTests", dependencies: ["HostShelfCore"])
    ]
)
