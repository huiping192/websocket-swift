// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftWebSocketLearning",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .watchOS(.v8),
        .tvOS(.v15)
    ],
    products: [
        // WebSocket核心库
        .library(
            name: "WebSocketCore",
            targets: ["WebSocketCore"]
        ),
        // 网络传输层
        .library(
            name: "NetworkTransport", 
            targets: ["NetworkTransport"]
        ),
        // HTTP升级握手
        .library(
            name: "HTTPUpgrade",
            targets: ["HTTPUpgrade"]
        ),
        // 工具类
        .library(
            name: "Utilities",
            targets: ["Utilities"]
        ),
        // 完整WebSocket库
        .library(
            name: "SwiftWebSocket",
            targets: ["WebSocketCore", "NetworkTransport", "HTTPUpgrade", "Utilities"]
        )
    ],
    dependencies: [
        // 目前无外部依赖，纯Swift实现
    ],
    targets: [
        // MARK: - 核心模块
        .target(
            name: "WebSocketCore",
            dependencies: ["NetworkTransport", "HTTPUpgrade", "Utilities"],
            path: "Sources/WebSocketCore"
        ),
        .target(
            name: "NetworkTransport", 
            dependencies: ["Utilities"],
            path: "Sources/NetworkTransport"
        ),
        .target(
            name: "HTTPUpgrade",
            dependencies: ["Utilities"],
            path: "Sources/HTTPUpgrade"
        ),
        .target(
            name: "Utilities",
            path: "Sources/Utilities"
        ),
        
        // MARK: - 示例应用
        .executableTarget(
            name: "WebSocketDemo",
            dependencies: ["WebSocketCore", "NetworkTransport", "HTTPUpgrade", "Utilities"],
            path: "Examples/WebSocketDemo-macOS"
        ),
        
        // MARK: - 测试
        .testTarget(
            name: "UnitTests",
            dependencies: ["WebSocketCore", "NetworkTransport", "HTTPUpgrade", "Utilities"],
            path: "Tests/UnitTests"
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["WebSocketCore", "NetworkTransport", "HTTPUpgrade", "Utilities"],
            path: "Tests/IntegrationTests"
        )
    ]
)