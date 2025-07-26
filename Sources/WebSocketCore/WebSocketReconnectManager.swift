import Foundation

// MARK: - WebSocket重连管理器

/// WebSocket重连管理器
/// 负责管理WebSocket连接的自动重连逻辑
public actor WebSocketReconnectManager {
    
    // MARK: - 公共类型
    
    /// 重连状态
    public enum ReconnectState: Equatable {
        /// 未启动
        case idle
        /// 正在重连中
        case reconnecting(attempt: Int)
        /// 重连暂停（等待延迟时间）
        case waiting(nextAttempt: Int, resumeTime: Date)
        /// 重连已停止
        case stopped
    }
    
    /// 重连统计信息
    public struct ReconnectStatistics {
        /// 总重连尝试次数
        public let totalAttempts: Int
        
        /// 成功重连次数
        public let successfulReconnects: Int
        
        /// 失败重连次数
        public let failedReconnects: Int
        
        /// 当前连续失败次数
        public let currentFailureStreak: Int
        
        /// 总重连耗时（秒）
        public let totalReconnectTime: TimeInterval
        
        /// 平均重连时间（秒）
        public let averageReconnectTime: TimeInterval
        
        /// 上次重连时间
        public let lastReconnectTime: Date?
        
        /// 当前重连状态
        public let currentState: ReconnectState
        
        /// 使用的重连策略描述
        public let strategyDescription: String
    }
    
    // MARK: - 属性
    
    /// 重连策略
    private let strategy: WebSocketReconnectStrategy
    
    /// 连接回调（用于执行实际的连接操作）
    private var connectAction: (() async throws -> Void)?
    
    /// 重连事件回调
    private var eventHandlers: [(WebSocketReconnectEvent) -> Void] = []
    
    /// 当前重连状态
    private var _currentState: ReconnectState = .idle
    
    /// 重连任务
    private var reconnectTask: Task<Void, Never>?
    
    /// 统计信息
    private var totalAttempts: Int = 0
    private var successfulReconnects: Int = 0
    private var failedReconnects: Int = 0
    private var currentFailureStreak: Int = 0
    private var reconnectStartTime: Date?
    private var totalReconnectTime: TimeInterval = 0
    private var lastReconnectTime: Date?
    
    /// 重连历史记录（用于调试）
    private var reconnectHistory: [ReconnectRecord] = []
    private let maxHistoryCount: Int = 50
    
    /// 是否启用重连
    private var isReconnectEnabled: Bool = true
    
    // MARK: - 初始化
    
    /// 初始化重连管理器
    /// - Parameter strategy: 重连策略，默认使用指数退避策略
    public init(strategy: WebSocketReconnectStrategy = ExponentialBackoffReconnectStrategy()) {
        self.strategy = strategy
    }
    
    // MARK: - 公共接口
    
    /// 当前重连状态
    public var currentState: ReconnectState {
        return _currentState
    }
    
    /// 设置连接回调
    /// - Parameter connectAction: 连接操作的回调函数
    public func setConnectAction(_ connectAction: @escaping () async throws -> Void) {
        self.connectAction = connectAction
    }
    
    /// 添加重连事件处理器
    /// - Parameter handler: 事件处理回调
    public func addEventHandler(_ handler: @escaping (WebSocketReconnectEvent) -> Void) {
        eventHandlers.append(handler)
    }
    
    /// 移除所有事件处理器
    public func removeAllEventHandlers() {
        eventHandlers.removeAll()
    }
    
    /// 启用或禁用自动重连
    /// - Parameter enabled: 是否启用重连
    public func setReconnectEnabled(_ enabled: Bool) {
        isReconnectEnabled = enabled
        
        if !enabled {
            stopReconnect()
        }
    }
    
    /// 开始重连流程
    /// - Parameter initialError: 触发重连的初始错误
    public func startReconnect(after initialError: Error) {
        guard isReconnectEnabled else {
            notifyEvent(.reconnectStatusUpdate(message: "自动重连已禁用"))
            return
        }
        
        // 停止现有的重连任务
        stopReconnect()
        
        // 重置策略状态
        strategy.reset()
        
        // 启动重连任务
        reconnectTask = Task {
            await performReconnectLoop(initialError: initialError)
        }
    }
    
    /// 停止重连流程
    public func stopReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        
        if case .reconnecting = _currentState {
            _currentState = .stopped
            notifyEvent(.reconnectStatusUpdate(message: "重连已停止"))
        }
    }
    
    /// 手动触发立即重连
    /// - Returns: 重连是否成功
    @discardableResult
    public func reconnectImmediately() async -> Bool {
        guard let connectAction = connectAction else {
            notifyEvent(.reconnectStatusUpdate(message: "未设置连接回调，无法重连"))
            return false
        }
        
        do {
            notifyEvent(.reconnectStatusUpdate(message: "执行立即重连"))
            try await connectAction()
            
            // 重连成功
            recordReconnectSuccess()
            strategy.reset()
            
            notifyEvent(.reconnectSucceeded(attempt: 1, totalTime: 0))
            return true
            
        } catch {
            // 重连失败
            recordReconnectFailure(error: error)
            notifyEvent(.reconnectFailed(error: error, attempt: 1))
            return false
        }
    }
    
    /// 获取重连统计信息
    /// - Returns: 重连统计信息
    public func getStatistics() -> ReconnectStatistics {
        let averageTime = successfulReconnects > 0 ? totalReconnectTime / Double(successfulReconnects) : 0
        
        return ReconnectStatistics(
            totalAttempts: totalAttempts,
            successfulReconnects: successfulReconnects,
            failedReconnects: failedReconnects,
            currentFailureStreak: currentFailureStreak,
            totalReconnectTime: totalReconnectTime,
            averageReconnectTime: averageTime,
            lastReconnectTime: lastReconnectTime,
            currentState: _currentState,
            strategyDescription: strategy.description
        )
    }
    
    /// 获取重连历史记录
    /// - Returns: 重连历史记录
    public func getReconnectHistory() -> [ReconnectRecord] {
        return reconnectHistory
    }
    
    /// 重置统计信息
    public func resetStatistics() {
        totalAttempts = 0
        successfulReconnects = 0
        failedReconnects = 0
        currentFailureStreak = 0
        totalReconnectTime = 0
        lastReconnectTime = nil
        reconnectHistory.removeAll()
        
        notifyEvent(.reconnectStatusUpdate(message: "重连统计信息已重置"))
    }
    
    // MARK: - 私有方法
    
    /// 执行重连循环
    /// - Parameter initialError: 初始错误
    private func performReconnectLoop(initialError: Error) async {
        guard let connectAction = connectAction else {
            notifyEvent(.reconnectStatusUpdate(message: "未设置连接回调，无法重连"))
            return
        }
        
        var attemptCount = 0
        var lastError = initialError
        reconnectStartTime = Date()
        
        // 检查初始错误是否应该重连
        guard strategy.shouldReconnect(after: initialError, attemptCount: 0) else {
            recordReconnectFailure(error: initialError)
            notifyEvent(.reconnectAbandoned(finalError: initialError, totalAttempts: 0))
            _currentState = .stopped
            return
        }
        
        while !Task.isCancelled && isReconnectEnabled {
            attemptCount += 1
            totalAttempts += 1
            
            // 检查是否应该继续重连
            guard strategy.shouldReconnect(after: lastError, attemptCount: attemptCount) else {
                recordReconnectFailure(error: lastError)
                notifyEvent(.reconnectAbandoned(finalError: lastError, totalAttempts: attemptCount))
                _currentState = .stopped
                break
            }
            
            // 计算延迟时间
            let delay = strategy.delayBeforeReconnect(attemptCount: attemptCount)
            let resumeTime = Date().addingTimeInterval(delay)
            
            _currentState = .waiting(nextAttempt: attemptCount, resumeTime: resumeTime)
            notifyEvent(.reconnectStarted(attempt: attemptCount, delay: delay))
            
            // 等待延迟时间
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    // 任务被取消
                    _currentState = .stopped
                    break
                }
            }
            
            // 检查任务是否被取消
            guard !Task.isCancelled && isReconnectEnabled else {
                _currentState = .stopped
                break
            }
            
            // 尝试重连
            _currentState = .reconnecting(attempt: attemptCount)
            
            do {
                // 执行连接操作
                try await connectAction()
                
                // 重连成功
                let reconnectTime = reconnectStartTime?.timeIntervalSinceNow ?? 0
                recordReconnectSuccess()
                strategy.reset()
                
                _currentState = .idle
                lastReconnectTime = Date()
                totalReconnectTime += abs(reconnectTime)
                
                notifyEvent(.reconnectSucceeded(attempt: attemptCount, totalTime: abs(reconnectTime)))
                break
                
            } catch {
                // 重连失败
                lastError = error
                recordReconnectFailure(error: error)
                notifyEvent(.reconnectFailed(error: error, attempt: attemptCount))
                
                // 继续下一次重连尝试
                continue
            }
        }
    }
    
    /// 记录重连成功
    private func recordReconnectSuccess() {
        successfulReconnects += 1
        currentFailureStreak = 0
        
        let record = ReconnectRecord(
            timestamp: Date(),
            attemptNumber: totalAttempts,
            isSuccess: true,
            error: nil,
            delay: 0
        )
        addReconnectRecord(record)
    }
    
    /// 记录重连失败
    /// - Parameter error: 失败的错误
    private func recordReconnectFailure(error: Error) {
        failedReconnects += 1
        currentFailureStreak += 1
        
        let record = ReconnectRecord(
            timestamp: Date(),
            attemptNumber: totalAttempts,
            isSuccess: false,
            error: error,
            delay: 0
        )
        addReconnectRecord(record)
    }
    
    /// 添加重连记录
    /// - Parameter record: 重连记录
    private func addReconnectRecord(_ record: ReconnectRecord) {
        reconnectHistory.append(record)
        
        // 限制历史记录数量
        if reconnectHistory.count > maxHistoryCount {
            reconnectHistory.removeFirst()
        }
    }
    
    /// 通知事件
    /// - Parameter event: 重连事件
    private func notifyEvent(_ event: WebSocketReconnectEvent) {
        for handler in eventHandlers {
            handler(event)
        }
    }
}

// MARK: - 重连记录

/// 重连记录
public struct ReconnectRecord {
    /// 记录时间戳
    public let timestamp: Date
    
    /// 尝试次数
    public let attemptNumber: Int
    
    /// 是否成功
    public let isSuccess: Bool
    
    /// 错误信息（失败时）
    public let error: Error?
    
    /// 延迟时间（秒）
    public let delay: TimeInterval
    
    /// 描述信息
    public var description: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        
        let timeString = formatter.string(from: timestamp)
        let status = isSuccess ? "✅ 成功" : "❌ 失败"
        let errorInfo = error?.localizedDescription ?? ""
        
        return "[\(timeString)] 尝试 #\(attemptNumber): \(status) \(errorInfo)"
    }
}

// MARK: - 扩展：便利方法

public extension WebSocketReconnectManager {
    
    /// 创建带有指数退避策略的重连管理器
    /// - Parameters:
    ///   - baseDelay: 基础延迟时间，默认1秒
    ///   - maxDelay: 最大延迟时间，默认60秒
    ///   - maxAttempts: 最大重连尝试次数，默认5次
    /// - Returns: 配置好的重连管理器
    static func exponentialBackoff(
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        maxAttempts: Int = 5
    ) -> WebSocketReconnectManager {
        let strategy = ExponentialBackoffReconnectStrategy(
            baseDelay: baseDelay,
            maxDelay: maxDelay,
            maxAttempts: maxAttempts
        )
        return WebSocketReconnectManager(strategy: strategy)
    }
    
    /// 创建带有线性退避策略的重连管理器
    /// - Parameters:
    ///   - baseDelay: 基础延迟时间，默认1秒
    ///   - increment: 延迟增量，默认1秒
    ///   - maxDelay: 最大延迟时间，默认30秒
    ///   - maxAttempts: 最大重连尝试次数，默认10次
    /// - Returns: 配置好的重连管理器
    static func linearBackoff(
        baseDelay: TimeInterval = 1.0,
        increment: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        maxAttempts: Int = 10
    ) -> WebSocketReconnectManager {
        let strategy = LinearBackoffReconnectStrategy(
            baseDelay: baseDelay,
            increment: increment,
            maxDelay: maxDelay,
            maxAttempts: maxAttempts
        )
        return WebSocketReconnectManager(strategy: strategy)
    }
    
    /// 创建带有固定间隔策略的重连管理器
    /// - Parameters:
    ///   - interval: 固定延迟时间，默认5秒
    ///   - maxAttempts: 最大重连尝试次数，默认10次
    /// - Returns: 配置好的重连管理器
    static func fixedInterval(
        interval: TimeInterval = 5.0,
        maxAttempts: Int = 10
    ) -> WebSocketReconnectManager {
        let strategy = FixedIntervalReconnectStrategy(
            interval: interval,
            maxAttempts: maxAttempts
        )
        return WebSocketReconnectManager(strategy: strategy)
    }
    
    /// 创建带有自适应策略的重连管理器
    /// - Parameters:
    ///   - baseDelay: 基础延迟时间，默认2秒
    ///   - maxDelay: 最大延迟时间，默认120秒
    ///   - maxAttempts: 最大重连尝试次数，默认8次
    /// - Returns: 配置好的重连管理器
    static func adaptive(
        baseDelay: TimeInterval = 2.0,
        maxDelay: TimeInterval = 120.0,
        maxAttempts: Int = 8
    ) -> WebSocketReconnectManager {
        let strategy = AdaptiveReconnectStrategy(
            baseDelay: baseDelay,
            maxDelay: maxDelay,
            maxAttempts: maxAttempts
        )
        return WebSocketReconnectManager(strategy: strategy)
    }
    
    /// 创建禁用重连的管理器
    /// - Returns: 禁用重连的管理器
    static func noReconnect() -> WebSocketReconnectManager {
        let strategy = NoReconnectStrategy()
        let manager = WebSocketReconnectManager(strategy: strategy)
        Task {
            await manager.setReconnectEnabled(false)
        }
        return manager
    }
}

// MARK: - 扩展：调试支持

public extension WebSocketReconnectManager {
    
    /// 获取详细的状态描述
    /// - Returns: 状态描述字符串
    func getDetailedStatus() async -> String {
        let stats = await getStatistics()
        let history = await getReconnectHistory()
        
        var status = """
        WebSocket重连管理器状态:
        - 当前状态: \(stats.currentState)
        - 使用策略: \(stats.strategyDescription)
        - 总尝试次数: \(stats.totalAttempts)
        - 成功重连: \(stats.successfulReconnects)
        - 失败重连: \(stats.failedReconnects)
        - 连续失败: \(stats.currentFailureStreak)
        - 平均重连时间: \(String(format: "%.2f", stats.averageReconnectTime))秒
        """
        
        if let lastTime = stats.lastReconnectTime {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            status += "\n- 上次重连: \(formatter.string(from: lastTime))"
        }
        
        if !history.isEmpty {
            status += "\n\n最近的重连记录:"
            for record in history.suffix(5) {
                status += "\n  \(record.description)"
            }
        }
        
        return status
    }
    
    /// 导出重连统计数据（用于分析）
    /// - Returns: JSON格式的统计数据
    func exportStatistics() async -> [String: Any] {
        let stats = await getStatistics()
        let history = await getReconnectHistory()
        
        return [
            "currentState": String(describing: stats.currentState),
            "strategy": stats.strategyDescription,
            "totalAttempts": stats.totalAttempts,
            "successfulReconnects": stats.successfulReconnects,
            "failedReconnects": stats.failedReconnects,
            "currentFailureStreak": stats.currentFailureStreak,
            "totalReconnectTime": stats.totalReconnectTime,
            "averageReconnectTime": stats.averageReconnectTime,
            "lastReconnectTime": stats.lastReconnectTime?.timeIntervalSince1970 ?? 0,
            "history": history.map { record in
                [
                    "timestamp": record.timestamp.timeIntervalSince1970,
                    "attemptNumber": record.attemptNumber,
                    "isSuccess": record.isSuccess,
                    "error": record.error?.localizedDescription ?? "",
                    "delay": record.delay
                ]
            }
        ]
    }
}