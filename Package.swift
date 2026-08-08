// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DoubaoWeTypeBridge",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "DoubaoWeTypeBridge", targets: ["DoubaoWeTypeBridge"])
    ],
    targets: [
        .target(
            name: "BridgeCore",
            path: "Sources/BridgeCore"
        ),
        .executableTarget(
            name: "DoubaoWeTypeBridge",
            dependencies: ["BridgeCore"],
            path: "Sources/DoubaoWeTypeBridge"
        ),
        .executableTarget(
            name: "BridgeSelfTests",
            dependencies: ["BridgeCore"],
            path: "Tests/BridgeSelfTests"
        ),
        .testTarget(
            name: "DoubaoWeTypeBridgeTests",
            dependencies: ["BridgeCore"],
            path: "Tests/DoubaoWeTypeBridgeTests"
        )
    ]
)
