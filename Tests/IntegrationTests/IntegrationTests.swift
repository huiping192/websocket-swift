import XCTest
@testable import WebSocketCore
@testable import NetworkTransport
@testable import HTTPUpgrade
@testable import Utilities

/// 集成测试
/// 测试模块间的协作和端到端功能
final class IntegrationTests: XCTestCase {
    
    /// 测试完整的握手流程
    func testCompleteHandshakeFlow() async {
        // 创建握手请求
        let request = UpgradeRequest(
            host: "echo.websocket.org",
            path: "/",
            protocols: ["echo-protocol"]
        )
        
        // 验证请求创建
        XCTAssertEqual(request.host, "echo.websocket.org")
        XCTAssertEqual(request.path, "/")
        XCTAssertEqual(request.protocols, ["echo-protocol"])
        XCTAssertFalse(request.key.isEmpty)
        
        // 模拟响应
        let responseHeaders = [
            "Upgrade": "websocket",
            "Connection": "Upgrade",
            "Sec-WebSocket-Accept": "test-accept-key",
            "Sec-WebSocket-Protocol": "echo-protocol"
        ]
        
        let response = UpgradeResponse(statusCode: 101, headers: responseHeaders)
        XCTAssertEqual(response.statusCode, 101)
        XCTAssertEqual(response.acceptKey, "test-accept-key")
    }
    
    /// 测试模块版本一致性
    func testModuleVersions() {
        XCTAssertEqual(WebSocketCore.version, "1.0.0")
        XCTAssertEqual(NetworkTransport.version, "1.0.0")
        XCTAssertEqual(HTTPUpgrade.version, "1.0.0")
        XCTAssertEqual(Utilities.version, "1.0.0")
    }
    
    /// 测试数据流转换
    func testDataFlowTransformation() {
        let originalText = "WebSocket测试消息"
        let data = originalText.data(using: .utf8)!
        
        // 验证数据转换
        XCTAssertEqual(originalText.utf8ByteCount, data.count)
        XCTAssertFalse(data.hexString.isEmpty)
        
        // 验证数据往返
        let recoveredText = String(data: data, encoding: .utf8)
        XCTAssertEqual(recoveredText, originalText)
    }
}