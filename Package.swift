// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Mobi2EpubTransfer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Mobi2EpubTransfer", targets: ["Mobi2EpubTransfer"]),
        .library(name: "Mobi2EpubTransferCore", targets: ["Mobi2EpubTransferCore"])
    ],
    targets: [
        .target(
            name: "Mobi2EpubTransferCore"
        ),
        .executableTarget(
            name: "Mobi2EpubTransfer",
            dependencies: ["Mobi2EpubTransferCore"]
        ),
        .testTarget(
            name: "Mobi2EpubTransferCoreTests",
            dependencies: ["Mobi2EpubTransferCore"]
        )
    ]
)
