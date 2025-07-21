import Foundation
import os.log

/// WebSocket日志系统
/// 提供结构化日志记录功能
public final class WebSocketLogger {
    
    /// 日志级别
    public enum Level: Int, CaseIterable, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
        case critical = 4
        
        public static func < (lhs: Level, rhs: Level) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
        var description: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .warning: return "WARNING"
            case .error: return "ERROR"
            case .critical: return "CRITICAL"
            }
        }
        
        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            case .critical: return "🔥"
            }
        }
    }
    
    /// 日志分类
    public enum Category: String, CaseIterable {
        case network = "network"
        case handshake = "handshake"
        case message = "message"
        case frame = "frame"
        case security = "security"
        case performance = "performance"
        case connection = "connection"
        case general = "general"
    }
    
    /// 单例实例
    public static let shared = WebSocketLogger()
    
    /// 当前日志级别
    public var logLevel: Level = .info
    
    /// 是否启用日志
    public var isEnabled: Bool = true
    
    /// 是否记录网络数据包
    public var logNetworkData: Bool = false
    
    /// 日志输出处理器
    public var outputHandlers: [LogOutputHandler] = [ConsoleLogHandler()]
    
    /// 性能指标
    public private(set) var metrics = PerformanceMetrics()
    
    private let queue = DispatchQueue(label: "com.websocket.logger", qos: .utility)
    private let osLog: OSLog
    
    private init() {
        self.osLog = OSLog(subsystem: "com.websocket.swift", category: "WebSocket")
    }
    
    /// 记录日志
    /// - Parameters:
    ///   - level: 日志级别
    ///   - message: 日志消息
    ///   - category: 日志分类
    ///   - file: 文件名
    ///   - function: 函数名
    ///   - line: 行号
    ///   - context: 额外上下文
    public func log(
        _ level: Level,
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        context: [String: Any] = [:]
    ) {
        guard isEnabled && level >= logLevel else { return }
        
        queue.async { [weak self] in
            self?.processLog(
                level: level,
                message: message,
                category: category,
                file: file,
                function: function,
                line: line,
                context: context
            )
        }
    }
    
    /// 记录网络数据包
    /// - Parameters:
    ///   - direction: 数据方向（发送/接收）
    ///   - data: 数据内容
    ///   - context: 额外上下文
    public func logNetworkPacket(
        direction: NetworkDirection,
        data: Data,
        context: [String: Any] = [:]
    ) {
        guard isEnabled && logNetworkData else { return }
        
        let message = formatNetworkData(direction: direction, data: data)
        var fullContext = context
        fullContext["direction"] = direction.rawValue
        fullContext["size"] = data.count
        
        log(.debug, message, category: .network, context: fullContext)
    }
    
    /// 记录性能指标
    /// - Parameters:
    ///   - metric: 指标名称
    ///   - value: 指标值
    ///   - unit: 单位
    public func logPerformanceMetric(
        _ metric: String,
        value: Double,
        unit: String = ""
    ) {
        metrics.record(metric: metric, value: value, unit: unit)
        
        let message = "\(metric): \(value)\(unit)"
        log(.info, message, category: .performance, context: [
            "metric": metric,
            "value": value,
            "unit": unit
        ])
    }
    
    // MARK: - 便利方法
    
    public func debug(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        context: [String: Any] = [:]
    ) {
        log(.debug, message, category: category, file: file, function: function, line: line, context: context)
    }
    
    public func info(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        context: [String: Any] = [:]
    ) {
        log(.info, message, category: category, file: file, function: function, line: line, context: context)
    }
    
    public func warning(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        context: [String: Any] = [:]
    ) {
        log(.warning, message, category: category, file: file, function: function, line: line, context: context)
    }
    
    public func error(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        context: [String: Any] = [:]
    ) {
        log(.error, message, category: category, file: file, function: function, line: line, context: context)
    }
    
    public func critical(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        context: [String: Any] = [:]
    ) {
        log(.critical, message, category: category, file: file, function: function, line: line, context: context)
    }
    
    // MARK: - 私有方法
    
    private func processLog(
        level: Level,
        message: String,
        category: Category,
        file: String,
        function: String,
        line: Int,
        context: [String: Any]
    ) {
        let logEntry = LogEntry(
            timestamp: Date(),
            level: level,
            message: message,
            category: category,
            file: URL(fileURLWithPath: file).lastPathComponent,
            function: function,
            line: line,
            context: context
        )
        
        // 输出到所有处理器
        outputHandlers.forEach { handler in
            handler.output(logEntry)
        }
        
        // 输出到系统日志
        outputToOSLog(logEntry)
        
        // 更新统计
        metrics.incrementLogCount(level: level, category: category)
    }
    
    private func outputToOSLog(_ entry: LogEntry) {
        let formattedMessage = "[\(entry.category.rawValue)] \(entry.message)"
        
        switch entry.level {
        case .debug:
            os_log(.debug, log: osLog, "%{public}@", formattedMessage)
        case .info:
            os_log(.info, log: osLog, "%{public}@", formattedMessage)
        case .warning:
            os_log(.error, log: osLog, "%{public}@", formattedMessage)
        case .error:
            os_log(.error, log: osLog, "%{public}@", formattedMessage)
        case .critical:
            os_log(.fault, log: osLog, "%{public}@", formattedMessage)
        }
    }
    
    private func formatNetworkData(direction: NetworkDirection, data: Data) -> String {
        let directionIndicator = direction == .outgoing ? "→" : "←"
        let hexData = data.prefix(64).map { String(format: "%02x", $0) }.joined(separator: " ")
        let truncated = data.count > 64 ? "..." : ""
        
        return "\(directionIndicator) \(data.count) bytes: \(hexData)\(truncated)"
    }
}

// MARK: - 数据模型

/// 日志条目
public struct LogEntry {
    public let timestamp: Date
    public let level: WebSocketLogger.Level
    public let message: String
    public let category: WebSocketLogger.Category
    public let file: String
    public let function: String
    public let line: Int
    public let context: [String: Any]
    
    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

/// 网络数据方向
public enum NetworkDirection: String {
    case incoming = "incoming"
    case outgoing = "outgoing"
}

/// 日志输出处理器协议
public protocol LogOutputHandler {
    func output(_ entry: LogEntry)
}

/// 控制台日志处理器
public class ConsoleLogHandler: LogOutputHandler {
    public init() {}
    
    public func output(_ entry: LogEntry) {
        let levelText = "\(entry.level.emoji) \(entry.level.description)"
        let location = "\(entry.file):\(entry.line) \(entry.function)"
        let contextText = entry.context.isEmpty ? "" : " \(entry.context)"
        
        print("[\(entry.formattedTimestamp)] [\(levelText)] [\(entry.category.rawValue)] \(entry.message) (\(location))\(contextText)")
    }
}

/// 文件日志处理器
public class FileLogHandler: LogOutputHandler {
    private let fileURL: URL
    private let fileHandle: FileHandle?
    
    public init(fileURL: URL) {
        self.fileURL = fileURL
        
        // 创建文件（如果不存在）
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        
        self.fileHandle = try? FileHandle(forWritingTo: fileURL)
        fileHandle?.seekToEndOfFile()
    }
    
    deinit {
        fileHandle?.closeFile()
    }
    
    public func output(_ entry: LogEntry) {
        let levelText = entry.level.description
        let location = "\(entry.file):\(entry.line) \(entry.function)"
        let contextText = entry.context.isEmpty ? "" : " \(entry.context)"
        
        let logLine = "[\(entry.formattedTimestamp)] [\(levelText)] [\(entry.category.rawValue)] \(entry.message) (\(location))\(contextText)\n"
        
        if let data = logLine.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }
}

/// 性能指标收集器
public class PerformanceMetrics {
    private var logCounts: [WebSocketLogger.Level: Int] = [:]
    private var categoryCounts: [WebSocketLogger.Category: Int] = [:]
    private var customMetrics: [String: [Double]] = [:]
    private let queue = DispatchQueue(label: "com.websocket.metrics", qos: .utility)
    
    public init() {
        // 初始化计数器
        WebSocketLogger.Level.allCases.forEach { logCounts[$0] = 0 }
        WebSocketLogger.Category.allCases.forEach { categoryCounts[$0] = 0 }
    }
    
    internal func incrementLogCount(level: WebSocketLogger.Level, category: WebSocketLogger.Category) {
        queue.async {
            self.logCounts[level, default: 0] += 1
            self.categoryCounts[category, default: 0] += 1
        }
    }
    
    internal func record(metric: String, value: Double, unit: String) {
        queue.async {
            self.customMetrics[metric, default: []].append(value)
        }
    }
    
    /// 获取日志级别统计
    public func getLogLevelCounts() -> [WebSocketLogger.Level: Int] {
        return queue.sync { logCounts }
    }
    
    /// 获取分类统计
    public func getCategoryCounts() -> [WebSocketLogger.Category: Int] {
        return queue.sync { categoryCounts }
    }
    
    /// 获取自定义指标
    public func getCustomMetrics() -> [String: [Double]] {
        return queue.sync { customMetrics }
    }
    
    /// 重置所有指标
    public func reset() {
        queue.async {
            self.logCounts.removeAll()
            self.categoryCounts.removeAll()
            self.customMetrics.removeAll()
            
            WebSocketLogger.Level.allCases.forEach { self.logCounts[$0] = 0 }
            WebSocketLogger.Category.allCases.forEach { self.categoryCounts[$0] = 0 }
        }
    }
}

// MARK: - 全局便利函数

/// 全局日志函数
public func wsLog(
    _ level: WebSocketLogger.Level,
    _ message: String,
    category: WebSocketLogger.Category = .general,
    file: String = #file,
    function: String = #function,
    line: Int = #line,
    context: [String: Any] = [:]
) {
    WebSocketLogger.shared.log(
        level,
        message,
        category: category,
        file: file,
        function: function,
        line: line,
        context: context
    )
}

/// 全局调试日志
public func wsDebug(
    _ message: String,
    category: WebSocketLogger.Category = .general,
    file: String = #file,
    function: String = #function,
    line: Int = #line,
    context: [String: Any] = [:]
) {
    WebSocketLogger.shared.debug(message, category: category, file: file, function: function, line: line, context: context)
}

/// 全局信息日志
public func wsInfo(
    _ message: String,
    category: WebSocketLogger.Category = .general,
    file: String = #file,
    function: String = #function,
    line: Int = #line,
    context: [String: Any] = [:]
) {
    WebSocketLogger.shared.info(message, category: category, file: file, function: function, line: line, context: context)
}

/// 全局警告日志
public func wsWarning(
    _ message: String,
    category: WebSocketLogger.Category = .general,
    file: String = #file,
    function: String = #function,
    line: Int = #line,
    context: [String: Any] = [:]
) {
    WebSocketLogger.shared.warning(message, category: category, file: file, function: function, line: line, context: context)
}

/// 全局错误日志
public func wsError(
    _ message: String,
    category: WebSocketLogger.Category = .general,
    file: String = #file,
    function: String = #function,
    line: Int = #line,
    context: [String: Any] = [:]
) {
    WebSocketLogger.shared.error(message, category: category, file: file, function: function, line: line, context: context)
}

/// 全局关键错误日志
public func wsCritical(
    _ message: String,
    category: WebSocketLogger.Category = .general,
    file: String = #file,
    function: String = #function,
    line: Int = #line,
    context: [String: Any] = [:]
) {
    WebSocketLogger.shared.critical(message, category: category, file: file, function: function, line: line, context: context)
}