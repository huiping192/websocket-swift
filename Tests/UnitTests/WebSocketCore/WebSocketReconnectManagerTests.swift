import XCTest
@testable import WebSocketCore
@testable import NetworkTransport

/// WebSocket重连管理器单元测试
final class WebSocketReconnectManagerTests: XCTestCase {
    
    // MARK: - 测试属性
    
    var reconnectManager: WebSocketReconnectManager!
    var mockConnectAction: MockConnectAction!
    
    // MARK: - 测试生命周期
    
    override func setUp() {
        super.setUp()
        mockConnectAction = MockConnectAction()
        
        // 使用快速策略进行测试
        let strategy = FixedIntervalReconnectStrategy(interval: 0.1, maxAttempts: 3)
        reconnectManager = WebSocketReconnectManager(strategy: strategy)
        
        Task {
            await reconnectManager.setConnectAction(mockConnectAction.connect)
        }
    }
    
    override func tearDown() {
        if let manager = reconnectManager {
            let expectation = expectation(description: "Stop reconnect")
            Task {
                await manager.stopReconnect()
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 1.0)
        }
        
        reconnectManager = nil
        mockConnectAction = nil
        super.tearDown()
    }
    
    // MARK: - 初始化测试
    
    func testInitialization() async {
        let manager = WebSocketReconnectManager()
        let state = await manager.currentState
        
        XCTAssertEqual(state, .idle)
        
        let stats = await manager.getStatistics()
        XCTAssertEqual(stats.totalAttempts, 0)
        XCTAssertEqual(stats.successfulReconnects, 0)
        XCTAssertEqual(stats.failedReconnects, 0)
    }
    
    func testInitializationWithCustomStrategy() async {
        let customStrategy = ExponentialBackoffReconnectStrategy(baseDelay: 2.0, maxAttempts: 10)
        let manager = WebSocketReconnectManager(strategy: customStrategy)
        
        let stats = await manager.getStatistics()
        XCTAssertTrue(stats.strategyDescription.contains("ExponentialBackoff"))
        XCTAssertTrue(stats.strategyDescription.contains("2.0"))
    }
    
    // MARK: - 连接回调测试
    
    func testSetConnectAction() async {
        var callCount = 0
        let connectAction = {
            callCount += 1
        }
        
        await reconnectManager.setConnectAction(connectAction)
        
        let success = await reconnectManager.reconnectImmediately()
        XCTAssertTrue(success)
        XCTAssertEqual(callCount, 1)
    }
    
    func testReconnectWithoutConnectAction() async {
        let manager = WebSocketReconnectManager()
        let success = await manager.reconnectImmediately()
        XCTAssertFalse(success)
    }
    
    // MARK: - 立即重连测试
    
    func testReconnectImmediatelySuccess() async {
        mockConnectAction.shouldSucceed = true
        
        let success = await reconnectManager.reconnectImmediately()
        XCTAssertTrue(success)
        XCTAssertEqual(mockConnectAction.connectCallCount, 1)
        
        let stats = await reconnectManager.getStatistics()
        XCTAssertEqual(stats.successfulReconnects, 1)
        XCTAssertEqual(stats.failedReconnects, 0)
    }
    
    func testReconnectImmediatelyFailure() async {
        mockConnectAction.shouldSucceed = false
        
        let success = await reconnectManager.reconnectImmediately()
        XCTAssertFalse(success)
        XCTAssertEqual(mockConnectAction.connectCallCount, 1)
        
        let stats = await reconnectManager.getStatistics()
        XCTAssertEqual(stats.successfulReconnects, 0)
        XCTAssertEqual(stats.failedReconnects, 1)
    }
    
    // MARK: - 自动重连测试
    
    func testStartReconnectSuccess() async {
        mockConnectAction.shouldSucceed = true
        mockConnectAction.delayBeforeSuccess = 0.05 // 50ms延迟
        
        let eventExpectation = expectation(description: "Reconnect events")
        eventExpectation.expectedFulfillmentCount = 2 // started + succeeded
        
        await reconnectManager.addEventHandler { event in
            switch event {
            case .reconnectStarted, .reconnectSucceeded:
                eventExpectation.fulfill()
            default:
                break
            }
        }
        
        await reconnectManager.startReconnect(after: NetworkError.connectionTimeout)
        
        await fulfillment(of: [eventExpectation], timeout: 2.0)
        
        // 等待重连完成
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        let stats = await reconnectManager.getStatistics()
        XCTAssertEqual(stats.successfulReconnects, 1)
        XCTAssertGreaterThan(stats.totalAttempts, 0)
        
        let state = await reconnectManager.currentState
        XCTAssertEqual(state, .idle)
    }
    
    func testStartReconnectFailure() async {
        mockConnectAction.shouldSucceed = false
        
        let eventExpectation = expectation(description: "Reconnect abandoned")
        
        await reconnectManager.addEventHandler { event in
            if case .reconnectAbandoned = event {
                eventExpectation.fulfill()
            }
        }
        
        await reconnectManager.startReconnect(after: NetworkError.connectionTimeout)
        
        await fulfillment(of: [eventExpectation], timeout: 2.0)
        
        let stats = await reconnectManager.getStatistics()
        XCTAssertEqual(stats.successfulReconnects, 0)
        XCTAssertGreaterThan(stats.failedReconnects, 0)
        XCTAssertEqual(stats.totalAttempts, 3) // 最大尝试次数
        
        let state = await reconnectManager.currentState
        XCTAssertEqual(state, .stopped)
    }
    
    func testStartReconnectWithNonRecoverableError() async {
        // 使用只重连可恢复错误的策略
        let strategy = ExponentialBackoffReconnectStrategy(maxAttempts: 3, onlyRecoverableErrors: true)
        let manager = WebSocketReconnectManager(strategy: strategy)
        
        await manager.setConnectAction(mockConnectAction.connect)
        
        // 不可恢复的错误
        let nonRecoverableError = WebSocketClientError.invalidURL("bad url")
        
        let eventExpectation = expectation(description: "Reconnect abandoned immediately")
        
        await manager.addEventHandler { event in
            if case .reconnectAbandoned(let error, let attempts) = event {
                XCTAssertEqual(attempts, 0)
                eventExpectation.fulfill()
            }
        }
        
        await manager.startReconnect(after: nonRecoverableError)
        
        await fulfillment(of: [eventExpectation], timeout: 1.0)
        
        let stats = await manager.getStatistics()
        XCTAssertEqual(stats.totalAttempts, 0)
    }
    
    // MARK: - 重连控制测试
    
    func testStopReconnect() async {
        mockConnectAction.shouldSucceed = false
        
        await reconnectManager.startReconnect(after: NetworkError.connectionTimeout)
        
        // 等待重连进入运行状态
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms，确保重连开始
        
        await reconnectManager.stopReconnect()
        
        // 再等一下确保停止操作完成
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        let state = await reconnectManager.currentState
        XCTAssertEqual(state, .stopped)
    }
    
    func testSetReconnectEnabled() async {
        await reconnectManager.setReconnectEnabled(false)
        await reconnectManager.startReconnect(after: NetworkError.connectionTimeout)
        
        // 禁用重连时不应该开始重连
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        let stats = await reconnectManager.getStatistics()
        XCTAssertEqual(stats.totalAttempts, 0)
    }
    
    func testMultipleStartReconnect() async {
        mockConnectAction.shouldSucceed = false
        
        // 开始第一次重连
        await reconnectManager.startReconnect(after: NetworkError.connectionTimeout)
        
        // 立即开始第二次重连（应该停止第一次）
        let connectionError = NetworkError.connectionFailed(NSError(domain: "Network", code: 1))
        await reconnectManager.startReconnect(after: connectionError)
        
        // 等待重连流程
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // 验证统计信息合理
        let stats = await reconnectManager.getStatistics()
        XCTAssertGreaterThan(stats.totalAttempts, 0)
    }
    
    // MARK: - 事件处理测试
    
    func testEventHandlers() async {
        var receivedEvents: [WebSocketReconnectEvent] = []
        
        await reconnectManager.addEventHandler { event in
            receivedEvents.append(event)
        }
        
        // 添加第二个处理器
        var secondHandlerCallCount = 0
        await reconnectManager.addEventHandler { _ in
            secondHandlerCallCount += 1
        }
        
        mockConnectAction.shouldSucceed = true
        await reconnectManager.startReconnect(after: NetworkError.connectionTimeout)
        
        // 等待事件
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        XCTAssertGreaterThan(receivedEvents.count, 0)
        XCTAssertGreaterThan(secondHandlerCallCount, 0)
        
        // 测试移除所有处理器
        await reconnectManager.removeAllEventHandlers()
        
        receivedEvents.removeAll()
        secondHandlerCallCount = 0
        
        await reconnectManager.reconnectImmediately()
        
        // 应该没有事件被接收
        XCTAssertEqual(receivedEvents.count, 0)
        XCTAssertEqual(secondHandlerCallCount, 0)
    }
    
    // MARK: - 统计信息测试
    
    func testStatisticsCollection() async {
        mockConnectAction.shouldSucceed = false
        
        let initialStats = await reconnectManager.getStatistics()
        XCTAssertEqual(initialStats.totalAttempts, 0)
        XCTAssertEqual(initialStats.successfulReconnects, 0)
        XCTAssertEqual(initialStats.failedReconnects, 0)
        XCTAssertEqual(initialStats.currentFailureStreak, 0)
        XCTAssertEqual(initialStats.totalReconnectTime, 0)
        XCTAssertEqual(initialStats.averageReconnectTime, 0)
        XCTAssertNil(initialStats.lastReconnectTime)
        XCTAssertEqual(initialStats.currentState, .idle)
        
        // 执行一些失败的重连
        await reconnectManager.startReconnect(after: NetworkError.connectionTimeout)
        
        // 等待重连完成
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        let finalStats = await reconnectManager.getStatistics()
        XCTAssertGreaterThan(finalStats.totalAttempts, 0)
        XCTAssertEqual(finalStats.successfulReconnects, 0)
        XCTAssertGreaterThan(finalStats.failedReconnects, 0)
        XCTAssertGreaterThan(finalStats.currentFailureStreak, 0)
    }
    
    func testResetStatistics() async {
        // 先执行一些操作产生统计数据
        mockConnectAction.shouldSucceed = false
        await reconnectManager.startReconnect(after: NetworkError.connectionTimeout)
        
        // 等待重连完成
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // 停止重连，确保状态稳定
        await reconnectManager.stopReconnect()
        
        let statsBeforeReset = await reconnectManager.getStatistics()
        XCTAssertGreaterThan(statsBeforeReset.totalAttempts, 0)
        
        // 重置统计信息
        await reconnectManager.resetStatistics()
        
        let statsAfterReset = await reconnectManager.getStatistics()
        XCTAssertEqual(statsAfterReset.totalAttempts, 0)
        XCTAssertEqual(statsAfterReset.successfulReconnects, 0)
        XCTAssertEqual(statsAfterReset.failedReconnects, 0)
        XCTAssertEqual(statsAfterReset.currentFailureStreak, 0)
        XCTAssertEqual(statsAfterReset.totalReconnectTime, 0)
        XCTAssertNil(statsAfterReset.lastReconnectTime)
        
        let history = await reconnectManager.getReconnectHistory()
        XCTAssertEqual(history.count, 0)
    }
    
    // MARK: - 历史记录测试
    
    func testReconnectHistory() async {
        mockConnectAction.shouldSucceed = false
        
        let initialHistory = await reconnectManager.getReconnectHistory()
        XCTAssertEqual(initialHistory.count, 0)
        
        // 执行重连
        await reconnectManager.startReconnect(after: NetworkError.connectionTimeout)
        
        // 等待重连完成
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        let finalHistory = await reconnectManager.getReconnectHistory()
        XCTAssertGreaterThan(finalHistory.count, 0)
        
        // 验证历史记录的格式
        for record in finalHistory {
            XCTAssertFalse(record.isSuccess)
            XCTAssertNotNil(record.error)
            XCTAssertGreaterThan(record.attemptNumber, 0)
            XCTAssertFalse(record.description.isEmpty)
        }
    }
    
    // MARK: - 便利方法测试
    
    func testConvenienceInitializers() {
        let exponential = WebSocketReconnectManager.exponentialBackoff(baseDelay: 2.0, maxAttempts: 10)
        let linear = WebSocketReconnectManager.linearBackoff(baseDelay: 1.0, maxAttempts: 15)
        let fixed = WebSocketReconnectManager.fixedInterval(interval: 3.0, maxAttempts: 8)
        let adaptive = WebSocketReconnectManager.adaptive(baseDelay: 1.5, maxAttempts: 12)
        let none = WebSocketReconnectManager.noReconnect()
        
        XCTAssertNotNil(exponential)
        XCTAssertNotNil(linear)
        XCTAssertNotNil(fixed)
        XCTAssertNotNil(adaptive)
        XCTAssertNotNil(none)
    }
    
    func testNoReconnectConvenienceInitializer() async {
        let manager = WebSocketReconnectManager.noReconnect()
        
        await manager.setConnectAction { }
        await manager.startReconnect(after: NetworkError.connectionTimeout)
        
        // 等待一小段时间
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        let stats = await manager.getStatistics()
        XCTAssertEqual(stats.totalAttempts, 0) // 不应该有重连尝试
    }
    
    // MARK: - 调试支持测试
    
    func testDetailedStatus() async {
        let status = await reconnectManager.getDetailedStatus()
        
        XCTAssertTrue(status.contains("WebSocket重连管理器状态"))
        XCTAssertTrue(status.contains("当前状态"))
        XCTAssertTrue(status.contains("使用策略"))
        XCTAssertTrue(status.contains("总尝试次数"))
    }
    
    func testExportStatistics() async {
        mockConnectAction.shouldSucceed = false
        
        await reconnectManager.startReconnect(after: NetworkError.connectionTimeout)
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        let exported = await reconnectManager.exportStatistics()
        
        XCTAssertNotNil(exported["currentState"])
        XCTAssertNotNil(exported["strategy"])
        XCTAssertNotNil(exported["totalAttempts"])
        XCTAssertNotNil(exported["successfulReconnects"])
        XCTAssertNotNil(exported["failedReconnects"])
        XCTAssertNotNil(exported["history"])
        
        if let history = exported["history"] as? [[String: Any]] {
            XCTAssertGreaterThan(history.count, 0)
        }
    }
}

// MARK: - Mock类

/// 模拟连接操作
class MockConnectAction {
    var shouldSucceed = true
    var delayBeforeSuccess: TimeInterval = 0
    var connectCallCount = 0
    
    func connect() async throws {
        connectCallCount += 1
        
        if delayBeforeSuccess > 0 {
            try await Task.sleep(nanoseconds: UInt64(delayBeforeSuccess * 1_000_000_000))
        }
        
        if !shouldSucceed {
            let underlyingError = NSError(domain: "TestError", code: 1, userInfo: nil)
            throw NetworkError.connectionFailed(underlyingError)
        }
    }
}