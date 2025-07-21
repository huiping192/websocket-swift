import Foundation
import WebSocketCore
import NetworkTransport
import HTTPUpgrade
import Utilities

/// WebSocket演示应用
/// 展示如何使用WebSocket库进行连接和消息传输
@main
struct WebSocketDemo {
    
    static func main() async {
        print("🚀 WebSocket学习库演示应用启动")
        print("📚 版本信息:")
        print("  - WebSocketCore: \(WebSocketCore.version)")
        print("  - NetworkTransport: \(NetworkTransport.version)")
        print("  - HTTPUpgrade: \(HTTPUpgrade.version)")
        print("  - Utilities: \(Utilities.version)")
        
        print("\n🔧 演示WebSocket基础功能...")
        
        // 演示握手请求创建
        let request = UpgradeRequest(
            host: "echo.websocket.org",
            path: "/",
            protocols: ["chat", "superchat"]
        )
        
        print("📤 创建握手请求:")
        print("  - Host: \(request.host)")
        print("  - Path: \(request.path)")
        print("  - Key: \(request.key)")
        print("  - Protocols: \(request.protocols)")
        
        // 演示工具函数
        let testData = "Hello WebSocket".data(using: .utf8)!
        print("\n🛠️  工具函数演示:")
        print("  - 文本: Hello WebSocket")
        print("  - UTF-8字节数: \("Hello WebSocket".utf8ByteCount)")
        print("  - 十六进制: \(testData.hexString)")
        
        print("\n✅ 演示完成!")
    }
}