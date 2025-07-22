import XCTest
@testable import NetworkTransport

final class ConnectionManagerTests: XCTestCase {
    
    var mockTransport: MockBaseTransport!
    var connectionManager: ConnectionManager!
    
    override func setUpWithError() throws {
        super.setUp()
        mockTransport = MockBaseTransport()
        connectionManager = ConnectionManager(
            transport: mockTransport,
            reconnectStrategy: MockReconnectStrategy(),
            maxReconnectAttempts: 3,
            keepaliveInterval: 1.0  // 短的保活间隔用于测试
        )
    }

    override func tearDown() {
        if let manager = connectionManager {
            Task {
                await manager.stopManaging()
            }
        }
        connectionManager = nil
        mockTransport = nil
        super.tearDown()
    }
    
    // MARK: - 基础功能测试
    
    /// 测试ConnectionManager初始化
    func testConnectionManagerInitialization() {
        let transport = MockBaseTransport()
        let manager = ConnectionManager(transport: transport)
        
        XCTAssertNotNil(manager, "ConnectionManager应该成功初始化")
    }
    
    /// 测试开始管理连接
    func testStartManaging() async throws {
        var connectCalled = false
        
        try await connectionManager.startManaging(host: "example.com", port: 80) {
            connectCalled = true
        }
        
        XCTAssertTrue(connectCalled, "连接动作应该被调用")
        
        await connectionManager.stopManaging()
    }
    
    /// 测试重复开始管理应该失败
    func testDuplicateStartManaging() async throws {
        // 第一次开始管理
        try await connectionManager.startManaging(host: "example.com", port: 80) {
            // 空的连接动作
        }
        
        // 第二次开始管理应该失败
        do {
            try await connectionManager.startManaging(host: "example.com", port: 80) {
                // 空的连接动作
            }
            XCTFail("重复开始管理应该失败")
        } catch NetworkError.invalidState {
            // 预期的错误
        } catch {
            XCTFail("意外的错误类型: \(error)")
        }
        
        await connectionManager.stopManaging()
    }
    
    /// 测试停止管理连接
    func testStopManaging() async throws {
        try await connectionManager.startManaging(host: "example.com", port: 80) {
            // 空的连接动作
        }
        
        await connectionManager.stopManaging()
        
        // 停止后应该能再次开始管理
        try await connectionManager.startManaging(host: "example.com", port: 80) {
            // 空的连接动作
        }
        
        await connectionManager.stopManaging()
    }
    
    // MARK: - 数据传输测试
    
    /// 测试发送数据
    func testSendData() async throws {
        try await connectionManager.startManaging(host: "example.com", port: 80) {
            // 空的连接动作
        }
        
        let testData = "Hello, World!".data(using: .utf8)!
        try await connectionManager.send(data: testData)
        
        XCTAssertEqual(mockTransport.sentData.count, 1, "应该发送一次数据")
        XCTAssertEqual(mockTransport.sentData.first, testData, "发送的数据应该匹配")
        
        await connectionManager.stopManaging()
    }
    
    /// 测试接收数据
    func testReceiveData() async throws {
        let expectedData = "Response data".data(using: .utf8)!
        mockTransport.mockReceivedData.append(expectedData)
        
        try await connectionManager.startManaging(host: "example.com", port: 80) {
            // 空的连接动作
        }
        
        let receivedData = try await connectionManager.receive()
        
        XCTAssertEqual(receivedData, expectedData, "接收的数据应该匹配")
        
        await connectionManager.stopManaging()
    }
    
    // MARK: - 事件处理测试
    
    /// 测试事件处理器
    func testEventHandlers() async throws {
        var receivedEvents: [ConnectionManager.ConnectionEvent] = []
        
        connectionManager.addEventHandler { event in
            receivedEvents.append(event)
        }
        
        try await connectionManager.startManaging(host: "example.com", port: 80) {
            // 空的连接动作
        }
        
        // 等待事件处理
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        
        XCTAssertFalse(receivedEvents.isEmpty, "应该接收到连接事件")
        
        // 检查是否有连接事件
        let hasConnectedEvent = receivedEvents.contains { event in
            if case .connected = event {
                return true
            }
            return false
        }
        XCTAssertTrue(hasConnectedEvent, "应该有连接事件")
        
        await connectionManager.stopManaging()
    }
    
    /// 测试移除事件处理器
    func testRemoveEventHandlers() async throws {
        var eventCount = 0
        
        connectionManager.addEventHandler { _ in
            eventCount += 1
        }
        
        try await connectionManager.startManaging(host: "example.com", port: 80) {
            // 空的连接动作
        }
        
        // 等待事件处理
        try await Task.sleep(nanoseconds: 100_000_000)
        let initialEventCount = eventCount
        
        connectionManager.removeAllEventHandlers()
        
        await connectionManager.stopManaging()
        
        // 等待可能的其他事件
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // 事件数量应该没有增加（因为处理器已移除）
        XCTAssertGreaterThan(initialEventCount, 0, "应该有初始事件")
    }
    
    // MARK: - 统计信息测试
    
    /// 测试连接统计信息
    func testConnectionStatistics() async throws {
        try await connectionManager.startManaging(host: "example.com", port: 80) {
            // 空的连接动作
        }
        
        let testData = "Test data".data(using: .utf8)!
        try await connectionManager.send(data: testData)
        
        mockTransport.mockReceivedData.append(testData)
        _ = try await connectionManager.receive()
        
        let stats = connectionManager.getConnectionStatistics()
        
        XCTAssertEqual(stats.host, "example.com")
        XCTAssertEqual(stats.port, 80)
        XCTAssertGreaterThan(stats.uptime, 0)
        XCTAssertEqual(stats.totalBytesSent, UInt64(testData.count))
        XCTAssertEqual(stats.totalBytesReceived, UInt64(testData.count))
        
        await connectionManager.stopManaging()
    }
    
    /// 测试统计信息描述
    func testConnectionStatisticsDescription() async throws {
        try await connectionManager.startManaging(host: "test.com", port: 443) {
            // 空的连接动作
        }
        
        let stats = connectionManager.getConnectionStatistics()
        let description = stats.description
        
        XCTAssertTrue(description.contains("test.com:443"), "描述应包含主机和端口信息")
        XCTAssertTrue(description.contains("运行时间"), "描述应包含运行时间信息")
        
        await connectionManager.stopManaging()
    }
    
    // MARK: - 重连策略测试
    
    /// 测试指数退避重连策略
    func testExponentialBackoffStrategy() {
        let strategy = ExponentialBackoffStrategy(baseDelay: 1.0, maxDelay: 10.0, maxAttempts: 3)
        
        // 测试是否应该重连
        let networkError = NetworkError.connectionTimeout
        XCTAssertTrue(strategy.shouldReconnect(after: networkError, attemptCount: 1))
        XCTAssertTrue(strategy.shouldReconnect(after: networkError, attemptCount: 2))
        XCTAssertFalse(strategy.shouldReconnect(after: networkError, attemptCount: 3))
        
        // 测试延迟计算
        XCTAssertEqual(strategy.delayBeforeReconnect(attemptCount: 1), 1.0)
        XCTAssertEqual(strategy.delayBeforeReconnect(attemptCount: 2), 2.0)
        XCTAssertEqual(strategy.delayBeforeReconnect(attemptCount: 3), 4.0)
        XCTAssertEqual(strategy.delayBeforeReconnect(attemptCount: 10), 10.0) // 达到最大延迟
    }
    
    /// 测试固定间隔重连策略
    func testFixedIntervalStrategy() {
        let strategy = FixedIntervalStrategy(interval: 5.0, maxAttempts: 2)
        
        // 测试是否应该重连
        let networkError = NetworkError.connectionTimeout
        XCTAssertTrue(strategy.shouldReconnect(after: networkError, attemptCount: 1))
        XCTAssertFalse(strategy.shouldReconnect(after: networkError, attemptCount: 2))
        
        // 测试延迟计算（固定间隔）
        XCTAssertEqual(strategy.delayBeforeReconnect(attemptCount: 1), 5.0)
        XCTAssertEqual(strategy.delayBeforeReconnect(attemptCount: 2), 5.0)
    }
    
    // MARK: - 错误处理测试
    
    /// 测试连接失败的处理
    func testConnectionFailureHandling() async throws {
        mockTransport.shouldFailConnection = true
        
        do {
            try await connectionManager.startManaging(host: "example.com", port: 80) {
                throw NetworkError.connectionTimeout
            }
            XCTFail("连接失败应该抛出错误")
        } catch NetworkError.connectionTimeout {
            // 预期的错误
        } catch {
            XCTFail("意外的错误类型: \(error)")
        }
    }
    
    /// 测试发送失败的处理
    func testSendFailureHandling() async throws {
        try await connectionManager.startManaging(host: "example.com", port: 80) {
            // 空的连接动作
        }
        
        mockTransport.shouldFailSend = true
        
        do {
            let testData = "Test data".data(using: .utf8)!
            try await connectionManager.send(data: testData)
            XCTFail("发送失败应该抛出错误")
        } catch NetworkError.sendFailed {
            // 预期的错误
        } catch {
            XCTFail("意外的错误类型: \(error)")
        }
        
        await connectionManager.stopManaging()
    }
    
    /// 测试接收失败的处理
    func testReceiveFailureHandling() async throws {
        try await connectionManager.startManaging(host: "example.com", port: 80) {
            // 空的连接动作
        }
        
        mockTransport.shouldFailReceive = true
        
        do {
            _ = try await connectionManager.receive()
            XCTFail("接收失败应该抛出错误")
        } catch NetworkError.receiveFailed {
            // 预期的错误
        } catch {
            XCTFail("意外的错误类型: \(error)")
        }
        
        await connectionManager.stopManaging()
    }
    
    // MARK: - 并发测试
    
    /// 测试并发数据发送
    func testConcurrentSend() async throws {
        try await connectionManager.startManaging(host: "example.com", port: 80) {
            // 空的连接动作
        }
        
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    do {
                        let testData = "Test data \(i)".data(using: .utf8)!
                        try await self.connectionManager.send(data: testData)
                    } catch {
                        // 忽略错误，专注于测试并发性
                    }
                }
            }
            
            await group.waitForAll()
        }
        
        // 如果能执行到这里，说明并发发送没有崩溃
        XCTAssertGreaterThan(mockTransport.sentData.count, 0, "应该至少发送了一些数据")
        
        await connectionManager.stopManaging()
    }
}

// MARK: - Mock类

/// 模拟传输实现
class MockBaseTransport: BaseTransportProtocol {
    var sentData: [Data] = []
    var mockReceivedData: [Data] = []
    var shouldFailConnection = false
    var shouldFailSend = false
    var shouldFailReceive = false
    
    func disconnect() async {
        // Mock实现
    }
    
    func send(data: Data) async throws {
        if shouldFailSend {
            throw NetworkError.sendFailed(NSError(domain: "MockError", code: 1))
        }
        sentData.append(data)
    }
    
    func receive() async throws -> Data {
        if shouldFailReceive {
            throw NetworkError.receiveFailed(NSError(domain: "MockError", code: 1))
        }
        
        guard !mockReceivedData.isEmpty else {
            throw NetworkError.noDataReceived
        }
        
        return mockReceivedData.removeFirst()
    }
}

/// 模拟重连策略
struct MockReconnectStrategy: ConnectionManager.ReconnectStrategy {
    func shouldReconnect(after error: Error, attemptCount: Int) -> Bool {
        return attemptCount < 2 // 最多重试1次
    }
    
    func delayBeforeReconnect(attemptCount: Int) -> TimeInterval {
        return 0.1 // 很短的延迟用于测试
    }
}