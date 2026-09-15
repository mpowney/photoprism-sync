// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PhotoPrismSyncCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "PhotoPrismSyncCore",
            targets: ["PhotoPrismSyncCore"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "PhotoPrismSyncCore"
        ),
        .testTarget(
            name: "PhotoPrismSyncCoreTests",
            dependencies: ["PhotoPrismSyncCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
