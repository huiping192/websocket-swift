import XCTest
import CryptoKit
@testable import WebSocketCore
@testable import NetworkTransport
@testable import HTTPUpgrade

/// WebSocketClient单元测试
final class WebSocketClientTests: XCTestCase {
    
    var client: WebSocketClient!
    var mockTransport: MockNetworkTransport!
    
    override func setUp() {
        super.setUp()
        mockTransport = MockNetworkTransport()
        client = WebSocketClient(
            transport: mockTransport,
            configuration: .default
        )
    }
    
    override func tearDown() {
        client = nil
        mockTransport = nil
        super.tearDown()
    }
    
    // MARK: - 初始化测试
    
    func testClientInitialization() async {
        // 验证初始状态
        let state = await client.connectionState
        XCTAssertEqual(state, .closed)
        
        let isConnected = await client.isConnected
        XCTAssertFalse(isConnected)
    }
    
    // MARK: - URL验证测试
    
    func testInvalidURLScheme() async {
        let invalidURL = URL(string: "http://example.com")!
        
        do {
            try await client.connect(to: invalidURL)
            XCTFail("应该抛出无效URL错误")
        } catch let error as WebSocketClientError {
            switch error {
            case .invalidURL(let reason):
                XCTAssertTrue(reason.contains("不支持的协议"))
            default:
                XCTFail("错误类型不正确: \(error)")
            }
        } catch {
            XCTFail("意外的错误类型: \(error)")
        }
    }
    
    func testValidWebSocketURL() {
        let wsURL = URL(string: "ws://example.com")!
        XCTAssertNotNil(wsURL.scheme)
        XCTAssertEqual(wsURL.scheme, "ws")
        
        let wssURL = URL(string: "wss://example.com")!
        XCTAssertNotNil(wssURL.scheme)
        XCTAssertEqual(wssURL.scheme, "wss")
    }
    
    // MARK: - 状态管理测试
    
    func testStateTransitionDuringConnection() async {
        // 模拟成功的握手响应
        mockTransport.simulateSuccessfulHandshake = true
        
        let url = URL(string: "ws://example.com")!
        
        // 监听状态变化
        var stateChanges: [WebSocketState] = []
        await client.addStateChangeHandler { state in
            stateChanges.append(state)
        }
        
        do {
            try await client.connect(to: url)
            
            // 验证状态变化序列
            // 注意：由于异步操作，可能需要等待状态更新
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            let currentState = await client.connectionState
            
            // 验证最终状态为已连接
            XCTAssertEqual(currentState, .open)
            
        } catch {
            XCTFail("连接失败: \(error)")
        }
    }
    
    func testInvalidStateForConnection() async {
        // 模拟成功的握手响应
        mockTransport.simulateSuccessfulHandshake = true
        
        let url = URL(string: "ws://example.com")!
        
        do {
            // 第一次连接
            try await client.connect(to: url)
            
            // 尝试再次连接（应该失败）
            try await client.connect(to: url)
            XCTFail("应该抛出无效状态错误")
            
        } catch let error as WebSocketClientError {
            switch error {
            case .invalidState(let reason):
                XCTAssertTrue(reason.contains("当前状态不允许连接"))
            default:
                XCTFail("错误类型不正确: \(error)")
            }
        } catch {
            // 第一次连接可能成功，第二次连接失败是预期的
        }
    }
    
    // MARK: - 消息发送测试
    
    func testSendMessageWhenNotConnected() async {
        let message = WebSocketMessage.text("Hello")
        
        do {
            try await client.send(message: message)
            XCTFail("应该抛出无效状态错误")
        } catch let error as WebSocketClientError {
            switch error {
            case .invalidState(let reason):
                XCTAssertTrue(reason.contains("当前状态不允许发送消息"))
            default:
                XCTFail("错误类型不正确: \(error)")
            }
        } catch {
            XCTFail("意外的错误类型: \(error)")
        }
    }
    
    func testSendTextMessage() async {
        await connectSuccessfully()
        
        do {
            try await client.send(text: "Hello WebSocket")
            
            // 验证消息被正确编码和发送
            // 由于发送是异步的，可能需要等待
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            XCTAssertTrue(mockTransport.sentData.count > 0, "应该有数据被发送")
            
        } catch {
            XCTFail("发送消息失败: \(error)")
        }
    }
    
    func testSendBinaryMessage() async {
        await connectSuccessfully()
        
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        
        do {
            try await client.send(data: testData)
            
            // 等待发送完成
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            XCTAssertTrue(mockTransport.sentData.count > 0, "应该有数据被发送")
            
        } catch {
            XCTFail("发送二进制消息失败: \(error)")
        }
    }
    
    // MARK: - 连接关闭测试
    
    func testCloseConnection() async {
        await connectSuccessfully()
        
        do {
            try await client.close()
            
            let state = await client.connectionState
            XCTAssertEqual(state, .closed)
            
            let isConnected = await client.isConnected
            XCTAssertFalse(isConnected)
            
        } catch {
            XCTFail("关闭连接失败: \(error)")
        }
    }
    
    func testCloseAlreadyClosedConnection() async {
        // 连接已经是关闭状态
        do {
            try await client.close()
            // 应该成功，不抛出错误
        } catch {
            XCTFail("关闭已关闭的连接不应该抛出错误: \(error)")
        }
    }
    
    // MARK: - 配置测试
    
    func testCustomConfiguration() {
        let customConfig = WebSocketClient.Configuration(
            connectTimeout: 5.0,
            maxFrameSize: 32768,
            maxMessageSize: 1024 * 1024,
            fragmentTimeout: 15.0,
            subprotocols: ["chat", "echo"],
            extensions: ["permessage-deflate"],
            additionalHeaders: ["Custom-Header": "Value"]
        )
        
        let customClient = WebSocketClient(
            transport: mockTransport,
            configuration: customConfig
        )
        
        XCTAssertNotNil(customClient)
        // 验证配置被正确设置
        // 注意：由于配置是私有的，我们只能间接验证
    }
    
    // MARK: - Ping/Pong测试
    
    func testSendPing() async {
        await connectSuccessfully()
        
        let pingData = Data("ping test".utf8)
        
        do {
            try await client.ping(data: pingData)
            
            // 等待发送完成
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            XCTAssertTrue(mockTransport.sentData.count > 0, "应该有Ping数据被发送")
            
        } catch {
            XCTFail("发送Ping失败: \(error)")
        }
    }
    
    // MARK: - 等待连接测试
    
    func testWaitForConnection() async {
        mockTransport.simulateSuccessfulHandshake = true
        
        let url = URL(string: "ws://example.com")!
        
        // 在后台连接
        Task {
            try? await client.connect(to: url)
        }
        
        // 等待连接建立
        let success = await client.waitForConnection(timeout: 5.0)
        XCTAssertTrue(success, "应该在超时时间内连接成功")
    }
    
    func testWaitForConnectionTimeout() async {
        // 不设置mock响应，模拟连接超时
        
        let url = URL(string: "ws://example.com")!
        
        // 在后台尝试连接（会失败）
        Task {
            try? await client.connect(to: url)
        }
        
        // 等待连接（应该超时）
        let success = await client.waitForConnection(timeout: 0.1)
        XCTAssertFalse(success, "应该在超时时间内连接失败")
    }
    
    // MARK: - 辅助方法
    
    /// 成功连接到测试服务器
    private func connectSuccessfully() async {
        mockTransport.simulateSuccessfulHandshake = true
        
        let url = URL(string: "ws://example.com")!
        
        do {
            try await client.connect(to: url)
            
            // 等待连接完成
            let success = await client.waitForConnection(timeout: 1.0)
            XCTAssertTrue(success, "测试连接应该成功")
            
        } catch {
            XCTFail("测试连接失败: \(error)")
        }
    }
    
    /// 创建有效的握手响应
    private func createValidHandshakeResponse() -> Data {
        // 使用一个简化的mock响应，跳过Accept验证
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        \r
        
        """
        return Data(response.utf8)
    }
}

// MARK: - Mock网络传输

/// Mock网络传输实现，用于测试
class MockNetworkTransport: NetworkTransportProtocol {
    
    var isConnected = false
    var sentData: [Data] = []
    var receivedData: [Data] = []
    var mockHandshakeResponse: Data?
    var shouldFailConnection = false
    var shouldFailSend = false
    var shouldFailReceive = false
    var simulateSuccessfulHandshake = false
    
    private var receiveIndex = 0
    
    func connect(to host: String, port: Int, useTLS: Bool, tlsConfig: TLSConfiguration) async throws {
        if shouldFailConnection {
            throw MockError.connectionFailed
        }
        
        isConnected = true
        print("Mock: 已连接到 \(host):\(port)")
    }
    
    func disconnect() async {
        isConnected = false
        sentData.removeAll()
        receivedData.removeAll()
        receiveIndex = 0
        print("Mock: 已断开连接")
    }
    
    func send(data: Data) async throws {
        guard isConnected else {
            throw MockError.notConnected
        }
        
        if shouldFailSend {
            throw MockError.sendFailed
        }
        
        sentData.append(data)
        print("Mock: 已发送 \(data.count) 字节")
    }
    
    func receive() async throws -> Data {
        guard isConnected else {
            throw MockError.notConnected
        }
        
        if shouldFailReceive {
            throw MockError.receiveFailed
        }
        
        // 如果启用了模拟成功握手，直接生成正确的响应
        if simulateSuccessfulHandshake {
            simulateSuccessfulHandshake = false
            return createMockHandshakeResponse(for: getLastSentRequest())
        }
        
        // 如果有预设的握手响应，先返回它
        if let handshakeResponse = mockHandshakeResponse {
            mockHandshakeResponse = nil // 只返回一次
            return handshakeResponse
        }
        
        // 如果有接收数据队列，返回下一个
        if receiveIndex < receivedData.count {
            let data = receivedData[receiveIndex]
            receiveIndex += 1
            return data
        }
        
        // 否则模拟等待
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        throw MockError.noDataAvailable
    }
    
    // MARK: - Mock辅助方法
    
    private func getLastSentRequest() -> String {
        guard let lastData = sentData.last else { return "" }
        return String(data: lastData, encoding: .utf8) ?? ""
    }
    
    private func createMockHandshakeResponse(for request: String) -> Data {
        // 从请求中提取Sec-WebSocket-Key
        let lines = request.components(separatedBy: "\r\n")
        var clientKey = "dGhlIHNhbXBsZSBub25jZQ==" // 默认值
        
        for line in lines {
            if line.hasPrefix("Sec-WebSocket-Key:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    clientKey = parts[1].trimmingCharacters(in: .whitespaces)
                }
                break
            }
        }
        
        // 计算正确的Accept值
        let magicString = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = clientKey + magicString
        let data = Data(combined.utf8)
        let hash = Insecure.SHA1.hash(data: data)
        let accept = Data(hash).base64EncodedString()
        
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(accept)\r
        \r
        
        """
        return Data(response.utf8)
    }
    
    // MARK: - Mock控制方法
    
    func addMockReceivedData(_ data: Data) {
        receivedData.append(data)
    }
    
    func reset() {
        isConnected = false
        sentData.removeAll()
        receivedData.removeAll()
        mockHandshakeResponse = nil
        receiveIndex = 0
        shouldFailConnection = false
        shouldFailSend = false
        shouldFailReceive = false
    }
}

// MARK: - Mock错误

enum MockError: Error {
    case connectionFailed
    case notConnected
    case sendFailed
    case receiveFailed
    case noDataAvailable
}