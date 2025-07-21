import XCTest
@testable import HTTPUpgrade

/// RequestBuilder单元测试
final class RequestBuilderTests: XCTestCase {
    
    var requestBuilder: RequestBuilder!
    
    override func setUp() {
        super.setUp()
        requestBuilder = RequestBuilder()
    }
    
    override func tearDown() {
        requestBuilder = nil
        super.tearDown()
    }
    
    /// 测试基本的WebSocket升级请求构建
    func testBasicUpgradeRequest() {
        let url = URL(string: "ws://example.com/chat")!
        let request = requestBuilder.buildUpgradeRequest(for: url)
        
        XCTAssertTrue(request.contains("GET /chat HTTP/1.1"))
        XCTAssertTrue(request.contains("Host: example.com"))
        XCTAssertTrue(request.contains("Upgrade: websocket"))
        XCTAssertTrue(request.contains("Connection: Upgrade"))
        XCTAssertTrue(request.contains("Sec-WebSocket-Key:"))
        XCTAssertTrue(request.contains("Sec-WebSocket-Version: 13"))
        XCTAssertTrue(request.hasSuffix("\r\n\r\n"))
    }
    
    /// 测试带端口的WebSocket请求
    func testUpgradeRequestWithPort() {
        let url = URL(string: "ws://example.com:8080/ws")!
        let request = requestBuilder.buildUpgradeRequest(for: url)
        
        XCTAssertTrue(request.contains("Host: example.com:8080"))
        XCTAssertTrue(request.contains("GET /ws HTTP/1.1"))
    }
    
    /// 测试HTTPS默认端口不显示
    func testSecureUpgradeRequestDefaultPort() {
        let url = URL(string: "wss://example.com:443/secure")!
        let request = requestBuilder.buildUpgradeRequest(for: url)
        
        XCTAssertTrue(request.contains("Host: example.com"))
        XCTAssertFalse(request.contains("Host: example.com:443"))
    }
    
    /// 测试根路径处理
    func testRootPathHandling() {
        let url = URL(string: "ws://example.com")!
        let request = requestBuilder.buildUpgradeRequest(for: url)
        
        XCTAssertTrue(request.contains("GET / HTTP/1.1"))
    }
    
    /// 测试子协议
    func testSubProtocols() {
        let url = URL(string: "ws://example.com/chat")!
        let protocols = ["chat", "superchat"]
        let request = requestBuilder.buildUpgradeRequest(for: url, protocols: protocols)
        
        XCTAssertTrue(request.contains("Sec-WebSocket-Protocol: chat, superchat"))
    }
    
    /// 测试扩展
    func testExtensions() {
        let url = URL(string: "ws://example.com/chat")!
        let extensions = ["permessage-deflate", "x-webkit-deflate-frame"]
        let request = requestBuilder.buildUpgradeRequest(for: url, extensions: extensions)
        
        XCTAssertTrue(request.contains("Sec-WebSocket-Extensions: permessage-deflate, x-webkit-deflate-frame"))
    }
    
    /// 测试额外头部
    func testAdditionalHeaders() {
        let url = URL(string: "ws://example.com/chat")!
        let additionalHeaders = [
            "Origin": "https://example.com",
            "User-Agent": "TestAgent/1.0",
            "Authorization": "Bearer token123"
        ]
        let request = requestBuilder.buildUpgradeRequest(for: url, additionalHeaders: additionalHeaders)
        
        XCTAssertTrue(request.contains("Origin: https://example.com"))
        XCTAssertTrue(request.contains("User-Agent: TestAgent/1.0"))
        XCTAssertTrue(request.contains("Authorization: Bearer token123"))
    }
    
    /// 测试WebSocket密钥生成
    func testWebSocketKeyGeneration() {
        let key1 = requestBuilder.generateWebSocketKey()
        let key2 = requestBuilder.generateWebSocketKey()
        
        // 密钥不应该相同
        XCTAssertNotEqual(key1, key2)
        
        // 密钥应该是有效的Base64字符串，解码后长度为16字节
        let keyData1 = Data(base64Encoded: key1)
        let keyData2 = Data(base64Encoded: key2)
        
        XCTAssertNotNil(keyData1)
        XCTAssertNotNil(keyData2)
        XCTAssertEqual(keyData1?.count, 16)
        XCTAssertEqual(keyData2?.count, 16)
    }
    
    /// 测试WebSocket Accept密钥计算
    func testWebSocketAcceptComputation() {
        let testKey = "dGhlIHNhbXBsZSBub25jZQ=="
        let expectedAccept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        
        let computedAccept = requestBuilder.computeWebSocketAccept(for: testKey)
        XCTAssertEqual(computedAccept, expectedAccept)
    }
    
    /// 测试请求验证 - 有效请求
    func testValidRequestValidation() {
        let url = URL(string: "ws://example.com/chat")!
        let request = requestBuilder.buildUpgradeRequest(for: url)
        
        let result = RequestBuilder.validateWebSocketRequest(request)
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.errorMessage)
        XCTAssertNotNil(result.headers)
    }
    
    /// 测试请求验证 - 无效请求
    func testInvalidRequestValidation() {
        let invalidRequest = "POST /chat HTTP/1.1\r\nHost: example.com\r\n\r\n"
        
        let result = RequestBuilder.validateWebSocketRequest(invalidRequest)
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertNil(result.headers)
    }
    
    /// 测试空请求验证
    func testEmptyRequestValidation() {
        let result = RequestBuilder.validateWebSocketRequest("")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "请求为空")
    }
    
    /// 测试缺失头部的请求验证
    func testMissingHeaderValidation() {
        let incompleteRequest = """
        GET /chat HTTP/1.1\r
        Host: example.com\r
        Upgrade: websocket\r
        \r

        """
        
        let result = RequestBuilder.validateWebSocketRequest(incompleteRequest)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("缺失必需头部") == true)
    }
    
    /// 测试WebSocket版本常量
    func testWebSocketVersion() {
        XCTAssertEqual(RequestBuilder.webSocketVersion, "13")
    }
    
    /// 测试魔术字符串常量
    func testMagicString() {
        XCTAssertEqual(RequestBuilder.magicString, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
    }
    
    /// 测试复杂URL的处理
    func testComplexURLHandling() {
        let url = URL(string: "wss://subdomain.example.com:9443/path/to/websocket?param=value")!
        let request = requestBuilder.buildUpgradeRequest(for: url)
        
        XCTAssertTrue(request.contains("GET /path/to/websocket?param=value HTTP/1.1"))
        XCTAssertTrue(request.contains("Host: subdomain.example.com:9443"))
    }
}