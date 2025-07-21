import XCTest
@testable import WebSocketCore
@testable import NetworkTransport
@testable import HTTPUpgrade
@testable import Utilities

/// 单元测试
/// 测试各个模块的核心功能
final class UnitTests: XCTestCase {
    
    /// 测试工具类功能
    func testUtilities() {
        let testString = "Hello WebSocket"
        XCTAssertEqual(testString.utf8ByteCount, 15)
        
        let testData = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]) // "Hello"
        XCTAssertEqual(testData.hexString, "48656c6c6f")
    }
    
    /// 测试握手请求创建
    func testUpgradeRequest() {
        let request = UpgradeRequest(host: "example.com", path: "/test", protocols: ["chat"])
        
        XCTAssertEqual(request.host, "example.com")
        XCTAssertEqual(request.path, "/test")
        XCTAssertEqual(request.protocols, ["chat"])
        XCTAssertFalse(request.key.isEmpty)
    }
    
    /// 测试升级响应解析
    func testUpgradeResponse() {
        let headers = [
            "Sec-WebSocket-Accept": "test-accept-key",
            "Sec-WebSocket-Protocol": "chat"
        ]
        let response = UpgradeResponse(statusCode: 101, headers: headers)
        
        XCTAssertEqual(response.statusCode, 101)
        XCTAssertEqual(response.acceptKey, "test-accept-key")
    }
    
    /// 测试WebSocket消息类型
    func testWebSocketMessage() {
        let textMessage = WebSocketMessage.text("Hello")
        let binaryMessage = WebSocketMessage.binary(Data([1, 2, 3]))
        let pingMessage = WebSocketMessage.ping(nil)
        
        // 验证消息类型创建成功
        switch textMessage {
        case .text(let content):
            XCTAssertEqual(content, "Hello")
        default:
            XCTFail("应该是文本消息")
        }
    }
}