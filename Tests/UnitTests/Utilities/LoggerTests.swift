import XCTest
@testable import Utilities

/// Logger单元测试
final class LoggerTests: XCTestCase {
    
    var logger: WebSocketLogger!
    var testHandler: TestLogHandler!
    
    override func setUp() {
        super.setUp()
        logger = WebSocketLogger.shared
        testHandler = TestLogHandler()
        
        // 重置日志器设置
        logger.isEnabled = true
        logger.logLevel = .debug
        logger.logNetworkData = true
        logger.outputHandlers = [testHandler]
        logger.metrics.reset()
    }
    
    override func tearDown() {
        // 恢复默认设置
        logger.outputHandlers = [ConsoleLogHandler()]
        logger.logLevel = .info
        logger.logNetworkData = false
        testHandler = nil
        super.tearDown()
    }
    
    /// 测试基本日志记录
    func testBasicLogging() {
        logger.info("Test message")
        
        // 等待异步处理
        wait(for: testHandler, expectedCount: 1)
        
        XCTAssertEqual(testHandler.entries.count, 1)
        let entry = testHandler.entries[0]
        XCTAssertEqual(entry.level, .info)
        XCTAssertEqual(entry.message, "Test message")
        XCTAssertEqual(entry.category, .general)
    }
    
    /// 测试日志级别过滤
    func testLogLevelFiltering() {
        logger.logLevel = .warning
        
        logger.debug("Debug message")
        logger.info("Info message")
        logger.warning("Warning message")
        logger.error("Error message")
        
        wait(for: testHandler, expectedCount: 2)
        
        XCTAssertEqual(testHandler.entries.count, 2)
        XCTAssertEqual(testHandler.entries[0].level, .warning)
        XCTAssertEqual(testHandler.entries[1].level, .error)
    }
    
    /// 测试日志分类
    func testLogCategories() {
        logger.info("Network message", category: .network)
        logger.info("Handshake message", category: .handshake)
        logger.info("Message data", category: .message)
        
        wait(for: testHandler, expectedCount: 3)
        
        XCTAssertEqual(testHandler.entries.count, 3)
        XCTAssertEqual(testHandler.entries[0].category, .network)
        XCTAssertEqual(testHandler.entries[1].category, .handshake)
        XCTAssertEqual(testHandler.entries[2].category, .message)
    }
    
    /// 测试上下文信息
    func testContextLogging() {
        let context = ["userId": "123", "sessionId": "abc"]
        logger.info("User action", context: context)
        
        wait(for: testHandler, expectedCount: 1)
        
        XCTAssertEqual(testHandler.entries.count, 1)
        let entry = testHandler.entries[0]
        XCTAssertEqual(entry.context["userId"] as? String, "123")
        XCTAssertEqual(entry.context["sessionId"] as? String, "abc")
    }
    
    /// 测试网络数据包记录
    func testNetworkPacketLogging() {
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        
        logger.logNetworkPacket(direction: .outgoing, data: testData)
        logger.logNetworkPacket(direction: .incoming, data: testData)
        
        wait(for: testHandler, expectedCount: 2)
        
        XCTAssertEqual(testHandler.entries.count, 2)
        
        let outgoingEntry = testHandler.entries[0]
        XCTAssertEqual(outgoingEntry.category, .network)
        XCTAssertTrue(outgoingEntry.message.contains("→"))
        XCTAssertEqual(outgoingEntry.context["direction"] as? String, "outgoing")
        XCTAssertEqual(outgoingEntry.context["size"] as? Int, 4)
        
        let incomingEntry = testHandler.entries[1]
        XCTAssertTrue(incomingEntry.message.contains("←"))
        XCTAssertEqual(incomingEntry.context["direction"] as? String, "incoming")
    }
    
    /// 测试性能指标记录
    func testPerformanceMetricLogging() {
        logger.logPerformanceMetric("connection_time", value: 1.5, unit: "s")
        logger.logPerformanceMetric("throughput", value: 1024.0, unit: "KB/s")
        
        wait(for: testHandler, expectedCount: 2)
        
        XCTAssertEqual(testHandler.entries.count, 2)
        
        let entries = testHandler.entries
        XCTAssertTrue(entries.allSatisfy { $0.category == .performance })
        XCTAssertTrue(entries.allSatisfy { $0.level == .info })
        
        // 检查指标是否记录到metrics中
        let customMetrics = logger.metrics.getCustomMetrics()
        XCTAssertEqual(customMetrics["connection_time"]?.first, 1.5)
        XCTAssertEqual(customMetrics["throughput"]?.first, 1024.0)
    }
    
    /// 测试日志启用/禁用
    func testLoggingEnableDisable() {
        logger.isEnabled = false
        logger.info("This should not be logged")
        
        wait(for: testHandler, expectedCount: 0, timeout: 0.5)
        
        XCTAssertEqual(testHandler.entries.count, 0)
        
        logger.isEnabled = true
        logger.info("This should be logged")
        
        wait(for: testHandler, expectedCount: 1)
        
        XCTAssertEqual(testHandler.entries.count, 1)
    }
    
    /// 测试网络数据记录开关
    func testNetworkDataLoggingToggle() {
        logger.logNetworkData = false
        let testData = Data([0x01, 0x02])
        
        logger.logNetworkPacket(direction: .outgoing, data: testData)
        
        wait(for: testHandler, expectedCount: 0, timeout: 0.5)
        
        XCTAssertEqual(testHandler.entries.count, 0)
        
        logger.logNetworkData = true
        logger.logNetworkPacket(direction: .outgoing, data: testData)
        
        wait(for: testHandler, expectedCount: 1)
        
        XCTAssertEqual(testHandler.entries.count, 1)
    }
    
    /// 测试便利日志方法
    func testConvenienceMethods() {
        logger.debug("Debug test")
        logger.info("Info test")
        logger.warning("Warning test")
        logger.error("Error test")
        logger.critical("Critical test")
        
        wait(for: testHandler, expectedCount: 5)
        
        XCTAssertEqual(testHandler.entries.count, 5)
        
        let levels = testHandler.entries.map { $0.level }
        XCTAssertEqual(levels, [.debug, .info, .warning, .error, .critical])
    }
    
    /// 测试日志级别比较
    func testLogLevelComparison() {
        XCTAssertTrue(WebSocketLogger.Level.debug < .info)
        XCTAssertTrue(WebSocketLogger.Level.info < .warning)
        XCTAssertTrue(WebSocketLogger.Level.warning < .error)
        XCTAssertTrue(WebSocketLogger.Level.error < .critical)
        
        XCTAssertFalse(WebSocketLogger.Level.critical < .error)
    }
    
    /// 测试性能指标统计
    func testPerformanceMetrics() {
        // 记录不同级别的日志
        logger.debug("Debug")
        logger.info("Info")
        logger.warning("Warning")
        logger.error("Error")
        
        // 记录不同分类的日志
        logger.info("Network", category: .network)
        logger.info("Handshake", category: .handshake)
        
        wait(for: testHandler, expectedCount: 6)
        
        let levelCounts = logger.metrics.getLogLevelCounts()
        XCTAssertEqual(levelCounts[.debug], 1)
        XCTAssertEqual(levelCounts[.info], 3) // info + network + handshake
        XCTAssertEqual(levelCounts[.warning], 1)
        XCTAssertEqual(levelCounts[.error], 1)
        
        let categoryCounts = logger.metrics.getCategoryCounts()
        XCTAssertEqual(categoryCounts[.general], 4)
        XCTAssertEqual(categoryCounts[.network], 1)
        XCTAssertEqual(categoryCounts[.handshake], 1)
    }
    
    /// 测试全局日志函数
    func testGlobalLogFunctions() {
        wsDebug("Global debug")
        wsInfo("Global info")
        wsWarning("Global warning")
        wsError("Global error")
        wsCritical("Global critical")
        
        wait(for: testHandler, expectedCount: 5)
        
        XCTAssertEqual(testHandler.entries.count, 5)
        
        let messages = testHandler.entries.map { $0.message }
        let expectedMessages = ["Global debug", "Global info", "Global warning", "Global error", "Global critical"]
        XCTAssertEqual(messages, expectedMessages)
    }
    
    /// 测试日志条目格式化
    func testLogEntryFormatting() {
        logger.info("Test message")
        
        wait(for: testHandler, expectedCount: 1)
        
        let entry = testHandler.entries[0]
        
        // 检查时间戳格式
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let formattedTime = formatter.string(from: entry.timestamp)
        XCTAssertEqual(entry.formattedTimestamp, formattedTime)
        
        // 检查文件名提取
        XCTAssertEqual(entry.file, "LoggerTests.swift")
        XCTAssertEqual(entry.function, "testLogEntryFormatting()")
    }
    
    /// 测试大数据网络包的截断
    func testLargeNetworkPacketTruncation() {
        // 创建超过64字节的数据
        let largeData = Data(repeating: 0xFF, count: 100)
        
        logger.logNetworkPacket(direction: .outgoing, data: largeData)
        
        wait(for: testHandler, expectedCount: 1)
        
        let entry = testHandler.entries[0]
        XCTAssertTrue(entry.message.contains("..."))
        XCTAssertTrue(entry.message.contains("100 bytes"))
    }
    
    // MARK: - 辅助方法
    
    private func wait(for handler: TestLogHandler, expectedCount: Int, timeout: TimeInterval = 1.0) {
        let expectation = XCTestExpectation(description: "Log entries")
        
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if handler.entries.count >= expectedCount {
                expectation.fulfill()
            }
        }
        
        // 给异步日志处理一些时间
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            if handler.entries.count >= expectedCount {
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: timeout + 1.0)
    }
}

// MARK: - 测试用的日志处理器

class TestLogHandler: LogOutputHandler {
    private(set) var entries: [LogEntry] = []
    private let queue = DispatchQueue(label: "test.log.handler", qos: .utility)
    
    func output(_ entry: LogEntry) {
        queue.async {
            self.entries.append(entry)
        }
    }
}