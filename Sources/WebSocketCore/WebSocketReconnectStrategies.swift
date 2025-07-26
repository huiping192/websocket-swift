import Foundation
import NetworkTransport

// MARK: - 重连策略协议

/// WebSocket重连策略协议
/// 定义了重连行为的核心接口
public protocol WebSocketReconnectStrategy {
    /// 判断是否应该进行重连
    /// - Parameters:
    ///   - error: 导致连接断开的错误
    ///   - attemptCount: 当前重连尝试次数
    /// - Returns: true表示应该重连，false表示不应该重连
    func shouldReconnect(after error: Error, attemptCount: Int) -> Bool
    
    /// 计算重连前的延迟时间
    /// - Parameter attemptCount: 当前重连尝试次数
    /// - Returns: 延迟时间（秒）
    func delayBeforeReconnect(attemptCount: Int) -> TimeInterval
    
    /// 重置策略状态（连接成功后调用）
    func reset()
    
    /// 获取策略的描述信息
    var description: String { get }
}

// MARK: - 重连事件

/// WebSocket重连事件
public enum WebSocketReconnectEvent {
    /// 开始重连尝试
    case reconnectStarted(attempt: Int, delay: TimeInterval)
    
    /// 重连失败
    case reconnectFailed(error: Error, attempt: Int)
    
    /// 重连成功
    case reconnectSucceeded(attempt: Int, totalTime: TimeInterval)
    
    /// 放弃重连
    case reconnectAbandoned(finalError: Error, totalAttempts: Int)
    
    /// 重连过程中的状态更新
    case reconnectStatusUpdate(message: String)
}

// MARK: - 错误分类器

/// WebSocket错误分类器
/// 用于判断错误是否可以重连
public struct WebSocketErrorClassifier {
    
    /// 判断错误是否为可重连的错误
    /// - Parameter error: 要判断的错误
    /// - Returns: true表示可以重连，false表示不可重连
    public static func isRecoverableError(_ error: Error) -> Bool {
        // NetworkError类型错误
        if let networkError = error as? NetworkError {
            switch networkError {
            case .connectionTimeout, .hostUnreachable, .connectionFailed, 
                 .connectionReset, .connectionCancelled, .noDataReceived:
                return true // 网络相关错误可以重连
            case .invalidState, .notConnected, .sendFailed, .receiveFailed, .tlsHandshakeFailed:
                return false // 配置或协议错误不可重连
            }
        }
        
        // WebSocket客户端错误
        if let clientError = error as? WebSocketClientError {
            switch clientError {
            case .networkError, .connectionFailed, .connectionTimeout:
                return true // 网络相关错误可以重连
            case .invalidURL, .invalidState, .handshakeFailed, .protocolError, .notImplemented, .invalidCloseCode:
                return false // 配置或协议错误不可重连
            }
        }
        
        // WebSocket协议错误 - 通常不可重连
        if error is WebSocketProtocolError {
            return false
        }
        
        // 其他系统错误
        if let nsError = error as NSError? {
            switch nsError.domain {
            case NSURLErrorDomain:
                switch nsError.code {
                case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost,
                     NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
                    return true
                default:
                    return false
                }
            case NSPOSIXErrorDomain:
                // POSIX错误，如ECONNREFUSED, EHOSTUNREACH等
                return nsError.code == ECONNREFUSED || nsError.code == EHOSTUNREACH
            default:
                return false
            }
        }
        
        // 默认情况：检查错误描述中的关键词
        let errorDescription = error.localizedDescription.lowercased()
        let recoverableKeywords = ["timeout", "connection", "network", "unreachable", "refused"]
        let nonRecoverableKeywords = ["unauthorized", "forbidden", "invalid", "protocol", "handshake"]
        
        for keyword in nonRecoverableKeywords {
            if errorDescription.contains(keyword) {
                return false
            }
        }
        
        for keyword in recoverableKeywords {
            if errorDescription.contains(keyword) {
                return true
            }
        }
        
        // 默认不可重连
        return false
    }
    
    /// 获取错误的严重程度
    /// - Parameter error: 要评估的错误
    /// - Returns: 错误严重程度（0-10，10最严重）
    public static func getErrorSeverity(_ error: Error) -> Int {
        // NetworkError类型错误
        if let networkError = error as? NetworkError {
            switch networkError {
            case .connectionTimeout, .noDataReceived:
                return 3 // 轻度，超时类问题
            case .hostUnreachable, .connectionFailed, .connectionReset, .connectionCancelled:
                return 4 // 中等，网络连接问题
            case .invalidState, .notConnected:
                return 6 // 较高，状态相关问题
            case .sendFailed, .receiveFailed:
                return 5 // 中等，数据传输失败
            case .tlsHandshakeFailed:
                return 8 // 高，TLS握手失败
            }
        }
        
        if let clientError = error as? WebSocketClientError {
            switch clientError {
            case .networkError, .connectionFailed, .connectionTimeout:
                return 4 // 中等，网络相关问题
            case .invalidURL, .invalidState:
                return 7 // 较高，配置或状态问题
            case .handshakeFailed:
                return 8 // 高，握手失败可能是认证或协议问题
            case .protocolError:
                return 9 // 很高，协议错误
            case .notImplemented:
                return 6 // 较高，功能未实现
            case .invalidCloseCode:
                return 5 // 中等，关闭状态码问题
            }
        }
        
        if error is WebSocketProtocolError {
            return 9 // 很高，协议错误通常很严重
        }
        
        // 根据错误描述评估
        let errorDescription = error.localizedDescription.lowercased()
        if errorDescription.contains("timeout") {
            return 3
        } else if errorDescription.contains("connection") {
            return 4
        } else if errorDescription.contains("unauthorized") || errorDescription.contains("forbidden") {
            return 8
        } else if errorDescription.contains("invalid") || errorDescription.contains("protocol") {
            return 7
        }
        
        // 默认中等严重程度
        return 5
    }
}

// MARK: - 指数退避策略

/// 指数退避重连策略
/// 重连间隔按指数增长：baseDelay * (2^attemptCount)
public struct ExponentialBackoffReconnectStrategy: WebSocketReconnectStrategy {
    
    // MARK: - 属性
    
    /// 基础延迟时间（秒）
    private let baseDelay: TimeInterval
    
    /// 最大延迟时间（秒）
    private let maxDelay: TimeInterval
    
    /// 最大重连尝试次数
    private let maxAttempts: Int
    
    /// 随机化范围（避免惊群效应）
    private let jitterRange: ClosedRange<Double>
    
    /// 只对可恢复错误进行重连
    private let onlyRecoverableErrors: Bool
    
    // MARK: - 初始化
    
    /// 初始化指数退避重连策略
    /// - Parameters:
    ///   - baseDelay: 基础延迟时间，默认1秒
    ///   - maxDelay: 最大延迟时间，默认60秒
    ///   - maxAttempts: 最大重连尝试次数，默认5次
    ///   - jitterRange: 随机化范围，默认0.8...1.2
    ///   - onlyRecoverableErrors: 是否只对可恢复错误重连，默认true
    public init(
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        maxAttempts: Int = 5,
        jitterRange: ClosedRange<Double> = 0.8...1.2,
        onlyRecoverableErrors: Bool = true
    ) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
        self.jitterRange = jitterRange
        self.onlyRecoverableErrors = onlyRecoverableErrors
    }
    
    // MARK: - WebSocketReconnectStrategy实现
    
    public func shouldReconnect(after error: Error, attemptCount: Int) -> Bool {
        // 超过最大尝试次数
        guard attemptCount < maxAttempts else { return false }
        
        // 检查是否为可恢复错误
        if onlyRecoverableErrors {
            return WebSocketErrorClassifier.isRecoverableError(error)
        }
        
        return true
    }
    
    public func delayBeforeReconnect(attemptCount: Int) -> TimeInterval {
        // 计算指数退避延迟
        let exponentialDelay = baseDelay * pow(2.0, Double(attemptCount - 1))
        
        // 限制最大延迟
        let clampedDelay = min(exponentialDelay, maxDelay)
        
        // 添加随机化，避免多个连接同时重连（惊群效应）
        let jitter = Double.random(in: jitterRange)
        
        return clampedDelay * jitter
    }
    
    public func reset() {
        // 指数退避策略无需重置状态
    }
    
    public var description: String {
        return "ExponentialBackoff(base: \(baseDelay)s, max: \(maxDelay)s, attempts: \(maxAttempts))"
    }
}

// MARK: - 线性退避策略

/// 线性退避重连策略
/// 重连间隔线性增长：baseDelay + (increment * attemptCount)
public struct LinearBackoffReconnectStrategy: WebSocketReconnectStrategy {
    
    // MARK: - 属性
    
    /// 基础延迟时间（秒）
    private let baseDelay: TimeInterval
    
    /// 每次重连的延迟增量（秒）
    private let increment: TimeInterval
    
    /// 最大延迟时间（秒）
    private let maxDelay: TimeInterval
    
    /// 最大重连尝试次数
    private let maxAttempts: Int
    
    /// 只对可恢复错误进行重连
    private let onlyRecoverableErrors: Bool
    
    // MARK: - 初始化
    
    /// 初始化线性退避重连策略
    /// - Parameters:
    ///   - baseDelay: 基础延迟时间，默认1秒
    ///   - increment: 延迟增量，默认1秒
    ///   - maxDelay: 最大延迟时间，默认30秒
    ///   - maxAttempts: 最大重连尝试次数，默认10次
    ///   - onlyRecoverableErrors: 是否只对可恢复错误重连，默认true
    public init(
        baseDelay: TimeInterval = 1.0,
        increment: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        maxAttempts: Int = 10,
        onlyRecoverableErrors: Bool = true
    ) {
        self.baseDelay = baseDelay
        self.increment = increment
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
        self.onlyRecoverableErrors = onlyRecoverableErrors
    }
    
    // MARK: - WebSocketReconnectStrategy实现
    
    public func shouldReconnect(after error: Error, attemptCount: Int) -> Bool {
        // 超过最大尝试次数
        guard attemptCount < maxAttempts else { return false }
        
        // 检查是否为可恢复错误
        if onlyRecoverableErrors {
            return WebSocketErrorClassifier.isRecoverableError(error)
        }
        
        return true
    }
    
    public func delayBeforeReconnect(attemptCount: Int) -> TimeInterval {
        // 计算线性增长延迟
        let linearDelay = baseDelay + (increment * Double(attemptCount - 1))
        
        // 限制最大延迟
        return min(linearDelay, maxDelay)
    }
    
    public func reset() {
        // 线性退避策略无需重置状态
    }
    
    public var description: String {
        return "LinearBackoff(base: \(baseDelay)s, increment: \(increment)s, max: \(maxDelay)s, attempts: \(maxAttempts))"
    }
}

// MARK: - 固定间隔策略

/// 固定间隔重连策略
/// 每次重连都使用相同的延迟时间
public struct FixedIntervalReconnectStrategy: WebSocketReconnectStrategy {
    
    // MARK: - 属性
    
    /// 固定延迟时间（秒）
    private let interval: TimeInterval
    
    /// 最大重连尝试次数
    private let maxAttempts: Int
    
    /// 只对可恢复错误进行重连
    private let onlyRecoverableErrors: Bool
    
    // MARK: - 初始化
    
    /// 初始化固定间隔重连策略
    /// - Parameters:
    ///   - interval: 固定延迟时间，默认5秒
    ///   - maxAttempts: 最大重连尝试次数，默认10次
    ///   - onlyRecoverableErrors: 是否只对可恢复错误重连，默认true
    public init(
        interval: TimeInterval = 5.0,
        maxAttempts: Int = 10,
        onlyRecoverableErrors: Bool = true
    ) {
        self.interval = interval
        self.maxAttempts = maxAttempts
        self.onlyRecoverableErrors = onlyRecoverableErrors
    }
    
    // MARK: - WebSocketReconnectStrategy实现
    
    public func shouldReconnect(after error: Error, attemptCount: Int) -> Bool {
        // 超过最大尝试次数
        guard attemptCount < maxAttempts else { return false }
        
        // 检查是否为可恢复错误
        if onlyRecoverableErrors {
            return WebSocketErrorClassifier.isRecoverableError(error)
        }
        
        return true
    }
    
    public func delayBeforeReconnect(attemptCount: Int) -> TimeInterval {
        return interval
    }
    
    public func reset() {
        // 固定间隔策略无需重置状态
    }
    
    public var description: String {
        return "FixedInterval(interval: \(interval)s, attempts: \(maxAttempts))"
    }
}

// MARK: - 自适应策略

/// 自适应重连策略
/// 根据连接质量和错误类型动态调整重连行为
public class AdaptiveReconnectStrategy: WebSocketReconnectStrategy {
    
    // MARK: - 属性
    
    /// 基础延迟时间（秒）
    private let baseDelay: TimeInterval
    
    /// 最大延迟时间（秒）
    private let maxDelay: TimeInterval
    
    /// 最大重连尝试次数
    private let maxAttempts: Int
    
    /// 连接成功历史记录（用于计算连接质量）
    private var connectionHistory: [ConnectionRecord] = []
    
    /// 最大历史记录数量
    private let maxHistoryCount: Int
    
    /// 当前连接质量分数（0-1，1表示最好）
    private var connectionQuality: Double = 1.0
    
    // MARK: - 初始化
    
    /// 初始化自适应重连策略
    /// - Parameters:
    ///   - baseDelay: 基础延迟时间，默认2秒
    ///   - maxDelay: 最大延迟时间，默认120秒
    ///   - maxAttempts: 最大重连尝试次数，默认8次
    ///   - maxHistoryCount: 最大历史记录数量，默认20
    public init(
        baseDelay: TimeInterval = 2.0,
        maxDelay: TimeInterval = 120.0,
        maxAttempts: Int = 8,
        maxHistoryCount: Int = 20
    ) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
        self.maxHistoryCount = maxHistoryCount
    }
    
    // MARK: - WebSocketReconnectStrategy实现
    
    public func shouldReconnect(after error: Error, attemptCount: Int) -> Bool {
        // 超过最大尝试次数
        guard attemptCount < maxAttempts else { return false }
        
        // 记录连接失败
        recordConnectionFailure(error: error)
        
        // 更新连接质量
        updateConnectionQuality()
        
        // 检查是否为可恢复错误
        let isRecoverable = WebSocketErrorClassifier.isRecoverableError(error)
        
        // 根据连接质量和错误严重程度决定是否重连
        let errorSeverity = WebSocketErrorClassifier.getErrorSeverity(error)
        let shouldReconnectBasedOnQuality = connectionQuality > 0.1 || errorSeverity <= 5
        
        return isRecoverable && shouldReconnectBasedOnQuality
    }
    
    public func delayBeforeReconnect(attemptCount: Int) -> TimeInterval {
        // 基于连接质量调整延迟
        let qualityMultiplier = 2.0 - connectionQuality // 质量越差，延迟越长
        
        // 指数退避 + 质量调整
        let exponentialDelay = baseDelay * pow(1.5, Double(attemptCount - 1)) * qualityMultiplier
        
        // 限制最大延迟
        return min(exponentialDelay, maxDelay)
    }
    
    public func reset() {
        // 记录连接成功
        recordConnectionSuccess()
        updateConnectionQuality()
    }
    
    public var description: String {
        return "Adaptive(quality: \(String(format: "%.2f", connectionQuality)), base: \(baseDelay)s, max: \(maxDelay)s)"
    }
    
    // MARK: - 私有方法
    
    /// 记录连接成功
    private func recordConnectionSuccess() {
        let record = ConnectionRecord(
            timestamp: Date(),
            isSuccess: true,
            error: nil
        )
        addConnectionRecord(record)
    }
    
    /// 记录连接失败
    /// - Parameter error: 连接失败的错误
    private func recordConnectionFailure(error: Error) {
        let record = ConnectionRecord(
            timestamp: Date(),
            isSuccess: false,
            error: error
        )
        addConnectionRecord(record)
    }
    
    /// 添加连接记录
    /// - Parameter record: 连接记录
    private func addConnectionRecord(_ record: ConnectionRecord) {
        connectionHistory.append(record)
        
        // 限制历史记录数量
        if connectionHistory.count > maxHistoryCount {
            connectionHistory.removeFirst()
        }
    }
    
    /// 更新连接质量分数
    private func updateConnectionQuality() {
        guard !connectionHistory.isEmpty else {
            connectionQuality = 1.0
            return
        }
        
        // 最近的记录权重更高
        var totalWeight = 0.0
        var weightedSuccess = 0.0
        
        for (index, record) in connectionHistory.enumerated() {
            let weight = 1.0 + Double(index) / Double(connectionHistory.count) // 越新权重越高
            totalWeight += weight
            
            if record.isSuccess {
                weightedSuccess += weight
            }
        }
        
        connectionQuality = weightedSuccess / totalWeight
    }
    
    // MARK: - 内部类型
    
    /// 连接记录
    private struct ConnectionRecord {
        let timestamp: Date
        let isSuccess: Bool
        let error: Error?
    }
}

// MARK: - 无重连策略

/// 无重连策略
/// 永不重连，用于禁用自动重连功能
public struct NoReconnectStrategy: WebSocketReconnectStrategy {
    
    public init() {}
    
    public func shouldReconnect(after error: Error, attemptCount: Int) -> Bool {
        return false
    }
    
    public func delayBeforeReconnect(attemptCount: Int) -> TimeInterval {
        return 0
    }
    
    public func reset() {
        // 无需重置
    }
    
    public var description: String {
        return "NoReconnect"
    }
}