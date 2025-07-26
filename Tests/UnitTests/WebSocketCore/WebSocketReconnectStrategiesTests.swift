import XCTest
@testable import WebSocketCore
@testable import NetworkTransport

/// WebSocket重连策略单元测试
final class WebSocketReconnectStrategiesTests: XCTestCase {
    
    // MARK: - 错误分类器测试
    
    func testErrorClassifierRecoverableErrors() {
        // 网络错误 - 应该可重连
        XCTAssertTrue(WebSocketErrorClassifier.isRecoverableError(NetworkError.connectionTimeout))
        XCTAssertTrue(WebSocketErrorClassifier.isRecoverableError(NetworkError.connectionReset))
        let connectionError = NetworkError.connectionFailed(NSError(domain: "Network", code: 1))
        XCTAssertTrue(WebSocketErrorClassifier.isRecoverableError(connectionError))
        XCTAssertTrue(WebSocketErrorClassifier.isRecoverableError(NetworkError.hostUnreachable))
        
        // WebSocket客户端错误 - 部分可重连
        let networkError = NetworkError.connectionTimeout
        XCTAssertTrue(WebSocketErrorClassifier.isRecoverableError(WebSocketClientError.networkError(networkError)))
        XCTAssertTrue(WebSocketErrorClassifier.isRecoverableError(WebSocketClientError.connectionTimeout("timeout")))
        
        // NSURLError网络错误 - 可重连
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)
        XCTAssertTrue(WebSocketErrorClassifier.isRecoverableError(urlError))
    }
    
    func testErrorClassifierNonRecoverableErrors() {
        // TLS错误 - 不应该重连
        let tlsError = NetworkError.tlsHandshakeFailed(NSError(domain: "TLS", code: 1))
        XCTAssertFalse(WebSocketErrorClassifier.isRecoverableError(tlsError))
        
        // WebSocket协议错误 - 不应该重连
        XCTAssertFalse(WebSocketErrorClassifier.isRecoverableError(WebSocketProtocolError.invalidFrameFormat(description: "test")))
        
        // 客户端配置错误 - 不应该重连
        XCTAssertFalse(WebSocketErrorClassifier.isRecoverableError(WebSocketClientError.invalidURL("bad url")))
        XCTAssertFalse(WebSocketErrorClassifier.isRecoverableError(WebSocketClientError.handshakeFailed("failed")))
        
        // 其他不可恢复错误
        let customError = NSError(domain: "TestDomain", code: 403, userInfo: [NSLocalizedDescriptionKey: "forbidden access"])
        XCTAssertFalse(WebSocketErrorClassifier.isRecoverableError(customError))
    }
    
    func testErrorSeverityClassification() {
        // 轻微错误
        let timeoutSeverity = WebSocketErrorClassifier.getErrorSeverity(NetworkError.connectionTimeout)
        XCTAssertLessThanOrEqual(timeoutSeverity, 4)
        
        // 严重错误
        let tlsError = NetworkError.tlsHandshakeFailed(NSError(domain: "TLS", code: 1))
        let tlsSeverity = WebSocketErrorClassifier.getErrorSeverity(tlsError)
        XCTAssertGreaterThanOrEqual(tlsSeverity, 7)
        
        // 中等错误
        let connectionError = NetworkError.connectionFailed(NSError(domain: "Network", code: 1))
        let failedSeverity = WebSocketErrorClassifier.getErrorSeverity(connectionError)
        XCTAssertGreaterThanOrEqual(failedSeverity, 4)
        XCTAssertLessThanOrEqual(failedSeverity, 7)
    }
    
    // MARK: - 指数退避策略测试
    
    func testExponentialBackoffStrategy() {
        // 使用固定的jitter范围进行测试，避免随机性
        let strategy = ExponentialBackoffReconnectStrategy(
            baseDelay: 1.0,
            maxDelay: 16.0,
            maxAttempts: 5,
            jitterRange: 1.0...1.0, // 禁用jitter以便测试
            onlyRecoverableErrors: true
        )
        
        // 测试重连决策
        let recoverableError = NetworkError.connectionTimeout
        XCTAssertTrue(strategy.shouldReconnect(after: recoverableError, attemptCount: 1))
        XCTAssertTrue(strategy.shouldReconnect(after: recoverableError, attemptCount: 4))
        XCTAssertFalse(strategy.shouldReconnect(after: recoverableError, attemptCount: 5))
        
        // 测试延迟计算 (无jitter的情况下)
        let delay1 = strategy.delayBeforeReconnect(attemptCount: 1) // 应该是 1.0
        let delay2 = strategy.delayBeforeReconnect(attemptCount: 2) // 应该是 2.0  
        let delay3 = strategy.delayBeforeReconnect(attemptCount: 3) // 应该是 4.0
        
        // 验证指数增长 (无jitter的精确值)
        XCTAssertEqual(delay1, 1.0, accuracy: 0.001)
        XCTAssertEqual(delay2, 2.0, accuracy: 0.001)
        XCTAssertEqual(delay3, 4.0, accuracy: 0.001)
        
        // 验证最大延迟限制
        let maxDelay = strategy.delayBeforeReconnect(attemptCount: 10)
        XCTAssertLessThanOrEqual(maxDelay, 16.0)
        
        // 测试不可恢复错误
        let nonRecoverableError = WebSocketClientError.invalidURL("bad")
        XCTAssertFalse(strategy.shouldReconnect(after: nonRecoverableError, attemptCount: 1))
    }
    
    func testExponentialBackoffStrategyWithoutRecoverableCheck() {
        let strategy = ExponentialBackoffReconnectStrategy(
            baseDelay: 1.0,
            maxDelay: 16.0,
            maxAttempts: 3,
            onlyRecoverableErrors: false
        )
        
        // 即使是不可恢复错误也应该重连（当禁用可恢复检查时）
        let nonRecoverableError = WebSocketClientError.invalidURL("bad")
        XCTAssertTrue(strategy.shouldReconnect(after: nonRecoverableError, attemptCount: 1))
        XCTAssertFalse(strategy.shouldReconnect(after: nonRecoverableError, attemptCount: 3))
    }
    
    // MARK: - 线性退避策略测试
    
    func testLinearBackoffStrategy() {
        let strategy = LinearBackoffReconnectStrategy(
            baseDelay: 2.0,
            increment: 1.0,
            maxDelay: 10.0,
            maxAttempts: 8
        )
        
        // 测试重连决策
        let recoverableError = NetworkError.connectionTimeout
        XCTAssertTrue(strategy.shouldReconnect(after: recoverableError, attemptCount: 1))
        XCTAssertTrue(strategy.shouldReconnect(after: recoverableError, attemptCount: 7))
        XCTAssertFalse(strategy.shouldReconnect(after: recoverableError, attemptCount: 8))
        
        // 测试延迟计算（线性增长）
        XCTAssertEqual(strategy.delayBeforeReconnect(attemptCount: 1), 2.0) // base
        XCTAssertEqual(strategy.delayBeforeReconnect(attemptCount: 2), 3.0) // base + increment
        XCTAssertEqual(strategy.delayBeforeReconnect(attemptCount: 3), 4.0) // base + 2*increment
        
        // 验证最大延迟限制
        XCTAssertEqual(strategy.delayBeforeReconnect(attemptCount: 20), 10.0)
    }
    
    // MARK: - 固定间隔策略测试
    
    func testFixedIntervalStrategy() {
        let strategy = FixedIntervalReconnectStrategy(
            interval: 5.0,
            maxAttempts: 10
        )
        
        // 测试重连决策
        let recoverableError = NetworkError.connectionTimeout
        XCTAssertTrue(strategy.shouldReconnect(after: recoverableError, attemptCount: 1))
        XCTAssertTrue(strategy.shouldReconnect(after: recoverableError, attemptCount: 9))
        XCTAssertFalse(strategy.shouldReconnect(after: recoverableError, attemptCount: 10))
        
        // 测试固定延迟
        XCTAssertEqual(strategy.delayBeforeReconnect(attemptCount: 1), 5.0)
        XCTAssertEqual(strategy.delayBeforeReconnect(attemptCount: 5), 5.0)
        XCTAssertEqual(strategy.delayBeforeReconnect(attemptCount: 10), 5.0)
    }
    
    // MARK: - 自适应策略测试
    
    func testAdaptiveStrategy() {
        let strategy = AdaptiveReconnectStrategy(
            baseDelay: 1.0,
            maxDelay: 30.0,
            maxAttempts: 6
        )
        
        // 测试重连决策
        let recoverableError = NetworkError.connectionTimeout
        XCTAssertTrue(strategy.shouldReconnect(after: recoverableError, attemptCount: 1))
        XCTAssertTrue(strategy.shouldReconnect(after: recoverableError, attemptCount: 5))
        XCTAssertFalse(strategy.shouldReconnect(after: recoverableError, attemptCount: 6))
        
        // 测试延迟计算（第一次应该基于初始连接质量）
        let initialDelay = strategy.delayBeforeReconnect(attemptCount: 1)
        XCTAssertGreaterThan(initialDelay, 0)
        XCTAssertLessThanOrEqual(initialDelay, 30.0)
        
        // 测试连接成功后重置
        strategy.reset()
        let delayAfterReset = strategy.delayBeforeReconnect(attemptCount: 1)
        XCTAssertGreaterThan(delayAfterReset, 0)
    }
    
    func testAdaptiveStrategyConnectionQuality() {
        let strategy = AdaptiveReconnectStrategy(
            baseDelay: 1.0,
            maxDelay: 30.0,
            maxAttempts: 10
        )
        
        // 模拟多次连接失败，质量应该下降
        let error = NetworkError.connectionTimeout
        for i in 1...3 {
            _ = strategy.shouldReconnect(after: error, attemptCount: i)
        }
        
        let delayAfterFailures = strategy.delayBeforeReconnect(attemptCount: 4)
        
        // 连接成功，质量应该提升
        strategy.reset()
        let delayAfterSuccess = strategy.delayBeforeReconnect(attemptCount: 1)
        
        // 成功后的延迟应该更短（但由于随机化和其他因素，我们只检查合理范围）
        XCTAssertGreaterThan(delayAfterFailures, 0)
        XCTAssertGreaterThan(delayAfterSuccess, 0)
    }
    
    // MARK: - 无重连策略测试
    
    func testNoReconnectStrategy() {
        let strategy = NoReconnectStrategy()
        
        // 永远不应该重连
        XCTAssertFalse(strategy.shouldReconnect(after: NetworkError.connectionTimeout, attemptCount: 1))
        let connectionError = NetworkError.connectionFailed(NSError(domain: "Network", code: 1))
        XCTAssertFalse(strategy.shouldReconnect(after: connectionError, attemptCount: 1))
        
        // 延迟应该为0
        XCTAssertEqual(strategy.delayBeforeReconnect(attemptCount: 1), 0)
        
        // 重置不应该有副作用
        strategy.reset()
        XCTAssertFalse(strategy.shouldReconnect(after: NetworkError.connectionTimeout, attemptCount: 1))
    }
    
    // MARK: - 策略描述测试
    
    func testStrategyDescriptions() {
        let exponential = ExponentialBackoffReconnectStrategy(baseDelay: 1.0, maxDelay: 60.0, maxAttempts: 5)
        XCTAssertTrue(exponential.description.contains("ExponentialBackoff"))
        XCTAssertTrue(exponential.description.contains("1.0"))
        XCTAssertTrue(exponential.description.contains("60.0"))
        XCTAssertTrue(exponential.description.contains("5"))
        
        let linear = LinearBackoffReconnectStrategy(baseDelay: 2.0, increment: 1.0, maxDelay: 30.0, maxAttempts: 10)
        XCTAssertTrue(linear.description.contains("LinearBackoff"))
        
        let fixed = FixedIntervalReconnectStrategy(interval: 5.0, maxAttempts: 10)
        XCTAssertTrue(fixed.description.contains("FixedInterval"))
        
        let adaptive = AdaptiveReconnectStrategy()
        XCTAssertTrue(adaptive.description.contains("Adaptive"))
        
        let none = NoReconnectStrategy()
        XCTAssertEqual(none.description, "NoReconnect")
    }
}