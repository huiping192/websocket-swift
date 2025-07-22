import Foundation
import Network

/// 连接生命周期管理器
/// 负责连接重试、保活、监控等功能
public final class ConnectionManager: @unchecked Sendable {
    
    // MARK: - 公共类型
    
    /// 重连策略协议
    public protocol ReconnectStrategy {
        func shouldReconnect(after error: Error, attemptCount: Int) -> Bool
        func delayBeforeReconnect(attemptCount: Int) -> TimeInterval
    }
    
    /// 连接事件
    public enum ConnectionEvent {
        case connected
        case disconnected(Error?)
        case reconnecting(attempt: Int)
        case reconnectFailed(Error)
        case dataReceived(Data)
        case error(Error)
    }
    
    // MARK: - 私有属性
    
    private let transport: BaseTransportProtocol
    private let reconnectStrategy: ReconnectStrategy
    private var connectionInfo: ConnectionInfo
    private var isManaging = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts: Int
    
    // 事件处理
    private var eventHandlers: [(ConnectionEvent) -> Void] = []
    private let eventQueue = DispatchQueue(label: "com.websocket.connection.events", qos: .utility)
    
    // 监控
    private var connectionStartTime: Date?
    private var lastDataReceivedTime: Date?
    private var totalBytesReceived: UInt64 = 0
    private var totalBytesSent: UInt64 = 0
    
    // 保活
    private var keepaliveTimer: Timer?
    private let keepaliveInterval: TimeInterval
    
    // MARK: - 初始化
    
    /// 初始化连接管理器
    /// - Parameters:
    ///   - transport: 底层传输协议实现
    ///   - reconnectStrategy: 重连策略
    ///   - maxReconnectAttempts: 最大重连次数，默认5次
    ///   - keepaliveInterval: 保活间隔，默认30秒
    public init(
        transport: BaseTransportProtocol,
        reconnectStrategy: ReconnectStrategy = ExponentialBackoffStrategy(),
        maxReconnectAttempts: Int = 5,
        keepaliveInterval: TimeInterval = 30.0
    ) {
        self.transport = transport
        self.reconnectStrategy = reconnectStrategy
        self.maxReconnectAttempts = maxReconnectAttempts
        self.keepaliveInterval = keepaliveInterval
        self.connectionInfo = ConnectionInfo(host: "", port: 0)
    }
    
    // MARK: - 公共方法
    
    /// 开始管理连接
    /// - Parameters:
    ///   - host: 主机名
    ///   - port: 端口号
    ///   - connectAction: 连接动作闭包
    public func startManaging(
        host: String,
        port: Int,
        connectAction: @escaping () async throws -> Void
    ) async throws {
        guard !isManaging else {
            throw NetworkError.invalidState("Already managing a connection")
        }
        
        connectionInfo = ConnectionInfo(host: host, port: port)
        isManaging = true
        reconnectAttempts = 0
        connectionStartTime = Date()
        
        try await performInitialConnection(connectAction: connectAction)
        startKeepalive()
        
        notifyEvent(.connected)
    }
    
    /// 停止管理连接
    public func stopManaging() async {
        guard isManaging else { return }
        
        isManaging = false
        stopKeepalive()
        await transport.disconnect()
        
        notifyEvent(.disconnected(nil))
        resetStatistics()
    }
    
    /// 发送数据（带统计）
    /// - Parameter data: 要发送的数据
    public func send(data: Data) async throws {
        try await transport.send(data: data)
        totalBytesSent += UInt64(data.count)
    }
    
    /// 接收数据（带统计）
    /// - Returns: 接收到的数据
    public func receive() async throws -> Data {
        let data = try await transport.receive()
        totalBytesReceived += UInt64(data.count)
        lastDataReceivedTime = Date()
        notifyEvent(.dataReceived(data))
        return data
    }
    
    /// 添加事件处理器
    /// - Parameter handler: 事件处理闭包
    public func addEventHandler(_ handler: @escaping (ConnectionEvent) -> Void) {
        eventQueue.async {
            self.eventHandlers.append(handler)
        }
    }
    
    /// 移除所有事件处理器
    public func removeAllEventHandlers() {
        eventQueue.async {
            self.eventHandlers.removeAll()
        }
    }
    
    /// 获取连接统计信息
    /// - Returns: 连接统计
    public func getConnectionStatistics() -> ConnectionStatistics {
        let uptime = connectionStartTime?.timeIntervalSinceNow ?? 0
        let lastActivity = lastDataReceivedTime?.timeIntervalSinceNow ?? 0
        
        return ConnectionStatistics(
            host: connectionInfo.host,
            port: connectionInfo.port,
            uptime: abs(uptime),
            totalBytesReceived: totalBytesReceived,
            totalBytesSent: totalBytesSent,
            lastActivityInterval: abs(lastActivity),
            reconnectAttempts: reconnectAttempts
        )
    }
    
    // MARK: - 私有方法
    
    /// 执行初始连接
    private func performInitialConnection(connectAction: @escaping () async throws -> Void) async throws {
        do {
            try await connectAction()
        } catch {
            if reconnectStrategy.shouldReconnect(after: error, attemptCount: 0) {
                try await attemptReconnection(connectAction: connectAction)
            } else {
                throw error
            }
        }
    }
    
    /// 尝试重连
    private func attemptReconnection(connectAction: @escaping () async throws -> Void) async throws {
        while isManaging && reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            
            let delay = reconnectStrategy.delayBeforeReconnect(attemptCount: reconnectAttempts)
            notifyEvent(.reconnecting(attempt: reconnectAttempts))
            
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            do {
                try await connectAction()
                notifyEvent(.connected)
                return
            } catch {
                notifyEvent(.reconnectFailed(error))
                
                if !reconnectStrategy.shouldReconnect(after: error, attemptCount: reconnectAttempts) {
                    throw error
                }
            }
        }
        
        throw NetworkError.connectionFailed(
            NSError(domain: "ConnectionManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "达到最大重连次数(\(maxReconnectAttempts))"
            ])
        )
    }
    
    /// 开始保活检测
    private func startKeepalive() {
        stopKeepalive()
        
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: keepaliveInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.performKeepalive()
            }
        }
    }
    
    /// 停止保活检测
    private func stopKeepalive() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
    }
    
    /// 执行保活检测
    private func performKeepalive() async {
        guard isManaging else { return }
        
        // 简单的保活检测：检查是否长时间没有数据传输
        if let lastActivity = lastDataReceivedTime,
           Date().timeIntervalSince(lastActivity) > keepaliveInterval * 2 {
            
            do {
                // 尝试发送一个空数据包作为保活
                let keepaliveData = Data([0x00])
                try await transport.send(data: keepaliveData)
            } catch {
                notifyEvent(.error(error))
                
                if isManaging {
                    // 保活失败，尝试重连
                    Task {
                        try? await attemptReconnection {
                            // 这里需要由外部提供重连逻辑
                        }
                    }
                }
            }
        }
    }
    
    /// 通知事件
    private func notifyEvent(_ event: ConnectionEvent) {
        eventQueue.async {
            for handler in self.eventHandlers {
                handler(event)
            }
        }
    }
    
    /// 重置统计信息
    private func resetStatistics() {
        connectionStartTime = nil
        lastDataReceivedTime = nil
        totalBytesReceived = 0
        totalBytesSent = 0
        reconnectAttempts = 0
    }
}

// MARK: - 数据模型

/// 连接信息
private struct ConnectionInfo {
    let host: String
    let port: Int
}

/// 连接统计信息
public struct ConnectionStatistics {
    public let host: String
    public let port: Int
    public let uptime: TimeInterval
    public let totalBytesReceived: UInt64
    public let totalBytesSent: UInt64
    public let lastActivityInterval: TimeInterval
    public let reconnectAttempts: Int
    
    /// 统计信息描述
    public var description: String {
        let formatter = ByteCountFormatter()
        let receivedSize = formatter.string(fromByteCount: Int64(totalBytesReceived))
        let sentSize = formatter.string(fromByteCount: Int64(totalBytesSent))
        
        return """
        连接统计:
        - 服务器: \(host):\(port)
        - 运行时间: \(String(format: "%.1f", uptime))秒
        - 接收数据: \(receivedSize)
        - 发送数据: \(sentSize)  
        - 最后活动: \(String(format: "%.1f", lastActivityInterval))秒前
        - 重连次数: \(reconnectAttempts)
        """
    }
}

// MARK: - 重连策略实现

/// 指数退避重连策略
public struct ExponentialBackoffStrategy: ConnectionManager.ReconnectStrategy {
    
    private let baseDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let maxAttempts: Int
    
    /// 初始化
    /// - Parameters:
    ///   - baseDelay: 基础延迟时间，默认1秒
    ///   - maxDelay: 最大延迟时间，默认30秒
    ///   - maxAttempts: 最大重试次数，默认5次
    public init(
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        maxAttempts: Int = 5
    ) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.maxAttempts = maxAttempts
    }
    
    public func shouldReconnect(after error: Error, attemptCount: Int) -> Bool {
        guard attemptCount < maxAttempts else { return false }
        
        // 检查是否是可恢复的错误
        if let networkError = error as? NetworkError {
            switch networkError {
            case .connectionTimeout, .connectionReset, .connectionFailed:
                return true
            case .hostUnreachable:
                return attemptCount < 2  // 主机不可达只重试一次
            default:
                return false
            }
        }
        
        return true
    }
    
    public func delayBeforeReconnect(attemptCount: Int) -> TimeInterval {
        let delay = baseDelay * pow(2.0, Double(attemptCount - 1))
        return min(delay, maxDelay)
    }
}

/// 固定间隔重连策略
public struct FixedIntervalStrategy: ConnectionManager.ReconnectStrategy {
    
    private let interval: TimeInterval
    private let maxAttempts: Int
    
    public init(interval: TimeInterval = 5.0, maxAttempts: Int = 3) {
        self.interval = interval
        self.maxAttempts = maxAttempts
    }
    
    public func shouldReconnect(after error: Error, attemptCount: Int) -> Bool {
        return attemptCount < maxAttempts
    }
    
    public func delayBeforeReconnect(attemptCount: Int) -> TimeInterval {
        return interval
    }
}