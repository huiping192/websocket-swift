import Foundation

// MARK: - 连接状态管理器

/// WebSocket连接状态管理器
/// 使用Actor模式确保线程安全的状态管理
public actor ConnectionStateManager: StateManagerProtocol {
    
    // MARK: - 属性
    
    /// 当前连接状态
    private var _currentState: WebSocketState = .closed
    
    /// 状态变化回调
    private var stateChangeHandlers: [(WebSocketState) -> Void] = []
    
    /// 状态变化历史记录（用于调试）
    private var stateHistory: [StateTransition] = []
    
    /// 最大历史记录数量
    private let maxHistoryCount: Int
    
    // MARK: - 初始化
    
    /// 初始化状态管理器
    /// - Parameter maxHistoryCount: 最大历史记录数量，默认100
    public init(maxHistoryCount: Int = 100) {
        self.maxHistoryCount = maxHistoryCount
        self._currentState = .closed
    }
    
    // MARK: - StateManagerProtocol实现
    
    /// 获取当前状态
    public var currentState: WebSocketState {
        return _currentState
    }
    
    /// 更新连接状态
    /// - Parameter newState: 新的状态
    public func updateState(_ newState: WebSocketState) {
        let oldState = _currentState
        
        // 验证状态转换是否合法
        guard isValidTransition(from: oldState, to: newState) else {
            print("⚠️ 无效的状态转换: \(oldState) -> \(newState)")
            return
        }
        
        // 更新状态
        _currentState = newState
        
        // 记录状态转换
        recordStateTransition(from: oldState, to: newState)
        
        // 通知状态变化
        notifyStateChange(newState)
        
        print("🔄 状态转换: \(oldState) -> \(newState)")
    }
    
    // MARK: - 状态查询方法
    
    /// 检查是否处于连接状态
    public var isConnected: Bool {
        return _currentState == .open
    }
    
    /// 检查是否处于连接中状态
    public var isConnecting: Bool {
        return _currentState == .connecting
    }
    
    /// 检查是否处于关闭状态
    public var isClosed: Bool {
        return _currentState == .closed
    }
    
    /// 检查是否处于关闭中状态
    public var isClosing: Bool {
        return _currentState == .closing
    }
    
    /// 检查是否可以发送消息
    public var canSendMessages: Bool {
        return _currentState == .open
    }
    
    /// 检查是否可以接收消息
    public var canReceiveMessages: Bool {
        return _currentState == .open
    }
    
    // MARK: - 状态变化监听
    
    /// 添加状态变化处理器
    /// - Parameter handler: 状态变化回调函数
    public func addStateChangeHandler(_ handler: @escaping (WebSocketState) -> Void) {
        stateChangeHandlers.append(handler)
    }
    
    /// 移除所有状态变化处理器
    public func removeAllStateChangeHandlers() {
        stateChangeHandlers.removeAll()
    }
    
    // MARK: - 状态历史和调试
    
    /// 获取状态变化历史
    public var stateTransitionHistory: [StateTransition] {
        return stateHistory
    }
    
    /// 清空状态历史
    public func clearStateHistory() {
        stateHistory.removeAll()
    }
    
    /// 等待状态变为指定值
    /// - Parameters:
    ///   - targetState: 目标状态
    ///   - timeout: 超时时间（秒），默认10秒
    /// - Returns: 是否在超时时间内达到目标状态
    public func waitForState(_ targetState: WebSocketState, timeout: TimeInterval = 10.0) async -> Bool {
        // 如果已经是目标状态，直接返回
        if _currentState == targetState {
            return true
        }
        
        // 创建等待任务
        return await withTaskGroup(of: Bool.self) { group in
            
            // 添加状态检查任务
            group.addTask { [weak self] in
                while true {
                    guard let self = self else { return false }
                    
                    let currentState = await self.currentState
                    if currentState == targetState {
                        return true
                    }
                    
                    // 每100毫秒检查一次
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            
            // 添加超时任务
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }
            
            // 返回第一个完成的结果
            if let result = await group.next() {
                group.cancelAll()
                return result
            }
            
            return false
        }
    }
    
    // MARK: - 私有方法
    
    /// 验证状态转换是否合法
    /// - Parameters:
    ///   - oldState: 原状态
    ///   - newState: 新状态
    /// - Returns: 是否为合法转换
    private func isValidTransition(from oldState: WebSocketState, to newState: WebSocketState) -> Bool {
        switch (oldState, newState) {
        case (.closed, .connecting):
            return true
        case (.connecting, .open):
            return true
        case (.connecting, .closed):
            return true // 连接失败
        case (.open, .closing):
            return true
        case (.open, .closed):
            return true // 异常断开
        case (.closing, .closed):
            return true
        default:
            // 同状态转换允许（幂等性）
            return oldState == newState
        }
    }
    
    /// 记录状态转换
    /// - Parameters:
    ///   - oldState: 原状态
    ///   - newState: 新状态
    private func recordStateTransition(from oldState: WebSocketState, to newState: WebSocketState) {
        let transition = StateTransition(
            fromState: oldState,
            toState: newState,
            timestamp: Date()
        )
        
        stateHistory.append(transition)
        
        // 限制历史记录数量
        if stateHistory.count > maxHistoryCount {
            stateHistory.removeFirst()
        }
    }
    
    /// 通知状态变化
    /// - Parameter newState: 新状态
    private func notifyStateChange(_ newState: WebSocketState) {
        let handlers = stateChangeHandlers
        // 在主队列上执行回调
        Task { @MainActor in
            for handler in handlers {
                handler(newState)
            }
        }
    }
}

// MARK: - 数据模型

/// 状态转换记录
public struct StateTransition {
    /// 原状态
    public let fromState: WebSocketState
    
    /// 新状态
    public let toState: WebSocketState
    
    /// 转换时间
    public let timestamp: Date
    
    /// 转换描述
    public var description: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timeString = formatter.string(from: timestamp)
        return "\(timeString): \(fromState) -> \(toState)"
    }
}

// MARK: - 扩展方法

extension ConnectionStateManager {
    
    /// 重置状态管理器
    /// 将状态重置为closed并清空历史记录
    public func reset() {
        _currentState = .closed
        stateHistory.removeAll()
        stateChangeHandlers.removeAll()
        print("🔄 状态管理器已重置")
    }
    
    /// 获取状态统计信息
    /// - Returns: 状态统计信息
    public func getStateStatistics() -> StateStatistics {
        let totalTransitions = stateHistory.count
        
        var stateCounts: [WebSocketState: Int] = [
            .connecting: 0,
            .open: 0,
            .closing: 0,
            .closed: 0
        ]
        
        for transition in stateHistory {
            stateCounts[transition.toState, default: 0] += 1
        }
        
        return StateStatistics(
            currentState: _currentState,
            totalTransitions: totalTransitions,
            stateCounts: stateCounts
        )
    }
}

// MARK: - 状态统计

/// 状态统计信息
public struct StateStatistics {
    /// 当前状态
    public let currentState: WebSocketState
    
    /// 总转换次数
    public let totalTransitions: Int
    
    /// 各状态计数
    public let stateCounts: [WebSocketState: Int]
    
    /// 统计描述
    public var description: String {
        return """
        状态统计:
        - 当前状态: \(currentState)
        - 总转换次数: \(totalTransitions)
        - 连接中: \(stateCounts[.connecting] ?? 0)次
        - 已开启: \(stateCounts[.open] ?? 0)次  
        - 关闭中: \(stateCounts[.closing] ?? 0)次
        - 已关闭: \(stateCounts[.closed] ?? 0)次
        """
    }
}