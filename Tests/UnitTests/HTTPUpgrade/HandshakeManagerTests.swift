import XCTest
@testable import HTTPUpgrade
@testable import NetworkTransport
@testable import Utilities

/// HandshakeManager单元测试
final class HandshakeManagerTests: XCTestCase {
    
    var handshakeManager: HandshakeManager!
    var mockTransport: MockTransport!
    
    override func setUp() {
        super.setUp()
        handshakeManager = HandshakeManager(handshakeTimeout: 5.0)
        mockTransport = MockTransport()
    }
    
    override func tearDown() {
        handshakeManager = nil
        mockTransport = nil
        super.tearDown()
    }
    
    /// 测试成功的握手流程
    func testSuccessfulHandshake() async throws {
        let url = URL(string: "ws://example.com/chat")!
        
        // 使用智能Mock Transport，它会自动处理密钥验证
        let smartTransport = SmartMockTransport()
        
        let result = try await handshakeManager.performSimpleHandshake(
            url: url,
            transport: smartTransport
        )
        
        XCTAssertTrue(result.success)
        XCTAssertNil(result.negotiatedProtocol)  
        XCTAssertTrue(result.negotiatedExtensions.isEmpty)
        XCTAssertNotNil(smartTransport.lastSentData)
    }
    
    /// 从请求字符串中提取客户端密钥
    private func extractClientKeyFromRequest(_ request: String) -> String {
        let lines = request.components(separatedBy: "\r\n")
        
        for line in lines {
            if line.hasPrefix("Sec-WebSocket-Key:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        return "dGhlIHNhbXBsZSBub25jZQ==" // 默认值
    }
    
    /// 获取测试用的客户端密钥
    private func getClientKeyForTest(
        url: URL,
        protocols: [String] = [],
        extensions: [String] = [],
        additionalHeaders: [String: String] = [:]
    ) async throws -> String {
        let tempResponse = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: placeholder\r
        \r

        """
        
        mockTransport.nextReceiveData = tempResponse.data(using: .utf8)!
        
        // 执行握手来获取发送的请求
        do {
            _ = try await handshakeManager.performHandshake(
                url: url,
                transport: mockTransport,
                protocols: protocols,
                extensions: extensions,
                additionalHeaders: additionalHeaders
            )
        } catch {
            // 忽略验证失败，我们只需要获取发送的请求
        }
        
        // 从发送的请求中提取客户端密钥
        guard let sentData = mockTransport.lastSentData,
              let sentRequest = String(data: sentData, encoding: .utf8) else {
            throw XCTestError(.failureWhileWaiting)
        }
        
        return extractClientKeyFromRequest(sentRequest)
    }
    
    /// 测试带子协议的握手
    func testHandshakeWithProtocols() async throws {
        let url = URL(string: "ws://example.com/chat")!
        let protocols = ["chat", "superchat"]
        
        // 使用智能Mock Transport，设置协商chat协议
        let smartTransport = SmartMockTransport(protocolToNegotiate: "chat")
        
        let result = try await handshakeManager.performHandshake(
            url: url,
            transport: smartTransport,
            protocols: protocols
        )
        
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.negotiatedProtocol, "chat")
        
        // 验证请求包含子协议
        if let sentData = smartTransport.lastSentData,
           let sentRequest = String(data: sentData, encoding: .utf8) {
            XCTAssertTrue(sentRequest.contains("Sec-WebSocket-Protocol: chat, superchat"))
        } else {
            XCTFail("应该发送请求数据")
        }
    }
    
    /// 测试带扩展的握手
    func testHandshakeWithExtensions() async throws {
        let url = URL(string: "ws://example.com/chat")!
        let extensions = ["permessage-deflate"]
        
        // 使用智能Mock Transport，设置协商permessage-deflate扩展
        let smartTransport = SmartMockTransport(extensionsToNegotiate: ["permessage-deflate"])
        
        let result = try await handshakeManager.performHandshake(
            url: url,
            transport: smartTransport,
            protocols: [],
            extensions: extensions,
            additionalHeaders: [:]
        )
        
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.negotiatedExtensions, ["permessage-deflate"])
    }
    
    /// 测试握手超时
    func testHandshakeTimeout() async {
        let url = URL(string: "ws://example.com/chat")!
        let shortTimeoutManager = HandshakeManager(handshakeTimeout: 0.1)
        
        // 不设置响应数据，模拟超时
        mockTransport.simulateTimeout = true
        
        do {
            _ = try await shortTimeoutManager.performSimpleHandshake(
                url: url,
                transport: mockTransport
            )
            XCTFail("应该抛出超时错误")
        } catch HandshakeError.timeout {
            // 预期的错误
        } catch {
            XCTFail("意外的错误: \(error)")
        }
    }
    
    /// 测试服务器拒绝握手
    func testServerRejectsHandshake() async {
        let url = URL(string: "ws://example.com/chat")!
        
        // 模拟服务器拒绝响应
        let rejectResponse = """
        HTTP/1.1 400 Bad Request\r
        Content-Type: text/plain\r
        Content-Length: 11\r
        \r
        Bad Request
        """
        
        mockTransport.nextReceiveData = rejectResponse.data(using: .utf8)!
        
        do {
            _ = try await handshakeManager.performSimpleHandshake(
                url: url,
                transport: mockTransport
            )
            XCTFail("应该抛出验证错误")
        } catch HandshakeError.validationFailed(let reason) {
            XCTAssertTrue(reason.contains("状态码必须是101"))
        } catch {
            XCTFail("意外的错误: \(error)")
        }
    }
    
    /// 测试无效的Accept密钥
    func testInvalidAcceptKey() async {
        let url = URL(string: "ws://example.com/chat")!
        
        // 模拟错误的Accept密钥响应
        let invalidAcceptResponse = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: wrong-accept-key\r
        \r

        """
        
        mockTransport.nextReceiveData = invalidAcceptResponse.data(using: .utf8)!
        
        do {
            _ = try await handshakeManager.performSimpleHandshake(
                url: url,
                transport: mockTransport
            )
            XCTFail("应该抛出验证错误")
        } catch HandshakeError.validationFailed(let reason) {
            XCTAssertTrue(reason.contains("Accept密钥验证失败"))
        } catch {
            XCTFail("意外的错误: \(error)")
        }
    }
    
    /// 测试网络发送错误
    func testNetworkSendError() async {
        let url = URL(string: "ws://example.com/chat")!
        
        mockTransport.shouldFailSend = true
        
        do {
            _ = try await handshakeManager.performSimpleHandshake(
                url: url,
                transport: mockTransport
            )
            XCTFail("应该抛出网络错误")
        } catch {
            // 应该是网络错误
            XCTAssertTrue(error is NetworkError)
        }
    }
    
    /// 测试握手错误的本地化描述
    func testHandshakeErrorDescriptions() {
        let errors: [HandshakeError] = [
            .invalidRequest("test"),
            .timeout,
            .validationFailed("test"),
            .parseFailed("test"),
            .networkError(NetworkError.connectionTimeout)
        ]
        
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "错误描述不应该为空: \(error)")
            XCTAssertFalse(error.recoverySuggestion?.isEmpty ?? true, "恢复建议不应该为空: \(error)")
        }
    }
    
    /// 测试握手结果模型
    func testHandshakeResultModel() {
        let result1 = HandshakeResult(success: true)
        let result2 = HandshakeResult(
            success: true,
            negotiatedProtocol: "chat",
            negotiatedExtensions: ["deflate"],
            serverHeaders: ["Server": "nginx"]
        )
        
        XCTAssertTrue(result1.success)
        XCTAssertNil(result1.negotiatedProtocol)
        XCTAssertTrue(result1.negotiatedExtensions.isEmpty)
        XCTAssertTrue(result1.serverHeaders.isEmpty)
        
        XCTAssertTrue(result2.success)
        XCTAssertEqual(result2.negotiatedProtocol, "chat")
        XCTAssertEqual(result2.negotiatedExtensions, ["deflate"])
        XCTAssertEqual(result2.serverHeaders["Server"], "nginx")
    }
    
    /// 测试额外头部处理
    func testAdditionalHeaders() async throws {
        let url = URL(string: "ws://example.com/chat")!
        let additionalHeaders = [
            "Authorization": "Bearer token123",
            "User-Agent": "TestClient/1.0"
        ]
        
        // 使用智能Mock Transport
        let smartTransport = SmartMockTransport()
        
        let result = try await handshakeManager.performHandshake(
            url: url,
            transport: smartTransport,
            protocols: [],
            extensions: [],
            additionalHeaders: additionalHeaders
        )
        
        XCTAssertTrue(result.success)
        
        // 验证请求包含额外头部
        if let sentData = smartTransport.lastSentData,
           let sentRequest = String(data: sentData, encoding: .utf8) {
            XCTAssertTrue(sentRequest.contains("Authorization: Bearer token123"))
            XCTAssertTrue(sentRequest.contains("User-Agent: TestClient/1.0"))
        } else {
            XCTFail("应该发送请求数据")
        }
    }
    
    /// 测试复杂扩展解析
    func testComplexExtensionParsing() async throws {
        let url = URL(string: "ws://example.com/chat")!
        
        // 使用智能Mock Transport，设置多个扩展
        let smartTransport = SmartMockTransport(
            extensionsToNegotiate: ["permessage-deflate", "x-webkit-deflate-frame"]
        )
        
        let result = try await handshakeManager.performSimpleHandshake(
            url: url,
            transport: smartTransport
        )
        
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.negotiatedExtensions.count, 2)
        XCTAssertTrue(result.negotiatedExtensions.contains("permessage-deflate"))
        XCTAssertTrue(result.negotiatedExtensions.contains("x-webkit-deflate-frame"))
    }
}

// MARK: - Mock Transport

/// 密钥提取Mock传输层，用于获取客户端密钥
class KeyExtractionMockTransport: NetworkTransportProtocol {
    var lastSentData: Data?
    var extractedClientKey: String?
    
    func connect(to host: String, port: Int, useTLS: Bool, tlsConfig: TLSConfiguration = .secure) async throws {
        // Mock实现，不做任何操作
    }
    
    func send(data: Data) async throws {
        lastSentData = data
        
        // 提取客户端密钥
        if let request = String(data: data, encoding: .utf8) {
            extractedClientKey = extractClientKeyFromRequest(request)
        }
    }
    
    func receive() async throws -> Data {
        // 返回一个无效响应，让握手失败
        let invalidResponse = "HTTP/1.1 500 Internal Server Error\r\n\r\n"
        return invalidResponse.data(using: .utf8)!
    }
    
    func disconnect() async {
        // Mock实现，不做任何操作
    }
    
    /// 从请求中提取客户端密钥
    private func extractClientKeyFromRequest(_ request: String) -> String {
        let lines = request.components(separatedBy: "\r\n")
        
        for line in lines {
            if line.hasPrefix("Sec-WebSocket-Key:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        return "dGhlIHNhbXBsZSBub25jZQ==" // 默认值
    }
}

/// Mock网络传输层用于测试
class MockTransport: NetworkTransportProtocol {
    var lastSentData: Data?
    var nextReceiveData: Data?
    var shouldFailSend = false
    var simulateTimeout = false
    
    func connect(to host: String, port: Int, useTLS: Bool, tlsConfig: TLSConfiguration = .secure) async throws {
        // Mock实现，不做任何操作
    }
    
    func send(data: Data) async throws {
        if shouldFailSend {
            throw NetworkError.connectionReset
        }
        lastSentData = data
    }
    
    func receive() async throws -> Data {
        if simulateTimeout {
            // 模拟长时间等待
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
        }
        
        guard let data = nextReceiveData else {
            throw NetworkError.connectionReset
        }
        
        return data
    }
    
    func disconnect() async {
        // Mock实现，不做任何操作
    }
}

/// 智能Mock传输层，自动处理WebSocket握手响应
class SmartMockTransport: NetworkTransportProtocol {
    var lastSentData: Data?
    var shouldFailSend = false
    var simulateTimeout = false
    var protocolToNegotiate: String?
    var extensionsToNegotiate: [String] = []
    
    init(protocolToNegotiate: String? = nil, extensionsToNegotiate: [String] = []) {
        self.protocolToNegotiate = protocolToNegotiate
        self.extensionsToNegotiate = extensionsToNegotiate
    }
    
    func connect(to host: String, port: Int, useTLS: Bool, tlsConfig: TLSConfiguration = .secure) async throws {
        // Mock实现，不做任何操作
    }
    
    func send(data: Data) async throws {
        if shouldFailSend {
            throw NetworkError.connectionReset
        }
        lastSentData = data
    }
    
    func receive() async throws -> Data {
        if simulateTimeout {
            // 模拟长时间等待
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
        }
        
        // 从发送的请求中提取客户端密钥
        guard let sentData = lastSentData,
              let request = String(data: sentData, encoding: .utf8) else {
            throw NetworkError.connectionReset
        }
        
        let clientKey = extractClientKeyFromRequest(request)
        let acceptKey = CryptoUtilities.computeWebSocketAccept(for: clientKey)
        
        // 构建响应
        var response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(acceptKey)\r

        """
        
        // 添加协议协商
        if let protocolName = protocolToNegotiate {
            response += "Sec-WebSocket-Protocol: \(protocolName)\r\n"
        }
        
        // 添加扩展协商
        if !extensionsToNegotiate.isEmpty {
            let extensionsString = extensionsToNegotiate.joined(separator: ", ")
            response += "Sec-WebSocket-Extensions: \(extensionsString)\r\n"
        }
        
        response += "\r\n"
        
        return response.data(using: .utf8)!
    }
    
    func disconnect() async {
        // Mock实现，不做任何操作
    }
    
    /// 从请求中提取客户端密钥
    private func extractClientKeyFromRequest(_ request: String) -> String {
        let lines = request.components(separatedBy: "\r\n")
        
        for line in lines {
            if line.hasPrefix("Sec-WebSocket-Key:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        return "dGhlIHNhbXBsZSBub25jZQ==" // 默认值
    }
}

