import Foundation

// MARK: - 心跳管理器

/// WebSocket心跳管理器
/// 负责发送Ping帧、处理Pong响应、检测连接超时
public actor HeartbeatManager {
    
    // MARK: - 配置参数
    
    /// 心跳间隔（秒）
    private let pingInterval: TimeInterval
    
    /// Pong响应超时时间（秒）
    private let pongTimeout: TimeInterval
    
    /// 最大连续超时次数
    private let maxTimeoutCount: Int
    
    // MARK: - 状态管理
    
    /// 心跳任务
    private var heartbeatTask: Task<Void, Never>?
    
    /// 最后收到Pong的时间
    private var lastPongTime: Date?
    
    /// 连续超时计数
    private var timeoutCount: Int = 0
    
    /// 待响应的Ping数据映射 (pingId -> sentTime)
    private var pendingPings: [UInt32: Date] = [:]
    
    /// Ping序列号生成器
    private var nextPingId: UInt32 = 0
    
    /// 往返时间统计
    private var rttHistory: [TimeInterval] = []
    
    /// 心跳状态回调
    private var onHeartbeatTimeout: (() -> Void)?
    private var onHeartbeatRestored: (() -> Void)?
    private var onRoundTripTimeUpdated: ((TimeInterval) -> Void)?
    
    // MARK: - 依赖引用
    
    /// WebSocket客户端弱引用
    private weak var client: WebSocketClientProtocol?
    
    // MARK: - 初始化
    
    /// 初始化心跳管理器
    /// - Parameters:
    ///   - client: WebSocket客户端
    ///   - pingInterval: Ping发送间隔（默认30秒）
    ///   - pongTimeout: Pong响应超时时间（默认10秒）
    ///   - maxTimeoutCount: 最大连续超时次数（默认3次）
    public init(
        client: WebSocketClientProtocol,
        pingInterval: TimeInterval = 30.0,
        pongTimeout: TimeInterval = 10.0,
        maxTimeoutCount: Int = 3
    ) {
        self.client = client
        self.pingInterval = pingInterval
        self.pongTimeout = pongTimeout
        self.maxTimeoutCount = maxTimeoutCount
    }
    
    // MARK: - 公共接口
    
    /// 启动心跳检测
    public func startHeartbeat() {
        // 停止现有心跳任务
        stopHeartbeat()
        
        // 重置状态
        resetHeartbeatState()
        
        // 启动新的心跳任务
        heartbeatTask = Task {
            await performHeartbeatLoop()
        }
    }
    
    /// 停止心跳检测
    public func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        resetHeartbeatState()
    }
    
    /// 处理收到的Pong帧
    /// - Parameter frame: Pong帧数据
    public func handlePong(_ frame: WebSocketFrame) {
        guard frame.opcode == .pong else { return }
        
        let now = Date()
        lastPongTime = now
        
        // 解析Ping ID（前4字节）
        if frame.payload.count >= 4 {
            let pingId = frame.payload.withUnsafeBytes { buffer in
                buffer.load(as: UInt32.self).bigEndian
            }
            
            // 计算往返时间
            if let sentTime = pendingPings.removeValue(forKey: pingId) {
                let rtt = now.timeIntervalSince(sentTime)
                updateRoundTripTime(rtt)
            }
        }
        
        // 重置超时计数
        if timeoutCount > 0 {
            timeoutCount = 0
            onHeartbeatRestored?()
        }
    }
    
    /// 获取当前往返时间统计
    /// - Returns: (平均值, 最小值, 最大值)
    public func getRoundTripTimeStats() -> (average: TimeInterval?, min: TimeInterval?, max: TimeInterval?) {
        guard !rttHistory.isEmpty else {
            return (average: nil, min: nil, max: nil)
        }
        
        let average = rttHistory.reduce(0, +) / Double(rttHistory.count)
        let min = rttHistory.min()
        let max = rttHistory.max()
        
        return (average: average, min: min, max: max)
    }
    
    /// 是否正在运行心跳检测
    public var isRunning: Bool {
        return heartbeatTask != nil && !(heartbeatTask?.isCancelled ?? true)
    }
    
    /// 设置心跳超时回调
    public func setOnHeartbeatTimeout(_ callback: @escaping () -> Void) {
        onHeartbeatTimeout = callback
    }
    
    /// 设置心跳恢复回调
    public func setOnHeartbeatRestored(_ callback: @escaping () -> Void) {
        onHeartbeatRestored = callback
    }
    
    /// 设置往返时间更新回调
    public func setOnRoundTripTimeUpdated(_ callback: @escaping (TimeInterval) -> Void) {
        onRoundTripTimeUpdated = callback
    }
    
    // MARK: - 私有方法
    
    /// 心跳循环主体
    private func performHeartbeatLoop() async {
        while !Task.isCancelled {
            do {
                // 发送Ping帧
                await sendPingFrame()
                
                // 等待Ping间隔
                try await Task.sleep(nanoseconds: UInt64(pingInterval * 1_000_000_000))
                
                // 检查超时
                await checkPongTimeout()
                
            } catch {
                // 任务被取消或出现错误，退出循环
                break
            }
        }
    }
    
    /// 发送Ping帧
    private func sendPingFrame() async {
        guard let client = client else { return }
        
        do {
            // 生成Ping ID和数据
            let pingId = generateNextPingId()
            let timestamp = Date()
            
            // 构造Ping数据：4字节ID + 8字节时间戳
            var pingData = Data()
            pingData.append(contentsOf: withUnsafeBytes(of: pingId.bigEndian) { Data($0) })
            pingData.append(contentsOf: withUnsafeBytes(of: timestamp.timeIntervalSince1970.bitPattern) { Data($0) })
            
            // 记录发送时间
            pendingPings[pingId] = timestamp
            
            // 发送Ping消息
            try await client.send(message: .ping(pingData))
            
        } catch {
            // Ping发送失败，增加超时计数
            timeoutCount += 1
            await handleHeartbeatFailure()
        }
    }
    
    /// 检查Pong响应超时
    private func checkPongTimeout() async {
        let now = Date()
        
        // 清理过期的Ping请求
        let expiredPings = pendingPings.filter { _, sentTime in
            now.timeIntervalSince(sentTime) > pongTimeout
        }
        
        if !expiredPings.isEmpty {
            // 移除过期的Ping请求
            for (pingId, _) in expiredPings {
                pendingPings.removeValue(forKey: pingId)
            }
            
            // 增加超时计数
            timeoutCount += expiredPings.count
            await handleHeartbeatFailure()
        }
    }
    
    /// 处理心跳失败
    private func handleHeartbeatFailure() async {
        if timeoutCount >= maxTimeoutCount {
            // 触发心跳超时回调
            onHeartbeatTimeout?()
            
            // 停止心跳检测
            stopHeartbeat()
        }
    }
    
    /// 更新往返时间统计
    /// - Parameter rtt: 往返时间
    private func updateRoundTripTime(_ rtt: TimeInterval) {
        rttHistory.append(rtt)
        
        // 保持历史记录大小在合理范围内
        if rttHistory.count > 100 {
            rttHistory.removeFirst()
        }
        
        // 触发RTT更新回调
        onRoundTripTimeUpdated?(rtt)
    }
    
    /// 生成下一个Ping ID
    /// - Returns: Ping ID
    private func generateNextPingId() -> UInt32 {
        defer { nextPingId = nextPingId.addingReportingOverflow(1).partialValue }
        return nextPingId
    }
    
    /// 重置心跳状态
    private func resetHeartbeatState() {
        lastPongTime = nil
        timeoutCount = 0
        pendingPings.removeAll()
        nextPingId = 0
        rttHistory.removeAll()
    }
}

// MARK: - 扩展：统计信息

public extension HeartbeatManager {
    
    /// 心跳统计信息
    struct Statistics {
        /// 当前往返时间（毫秒）
        public let currentRTT: TimeInterval?
        
        /// 平均往返时间（毫秒）
        public let averageRTT: TimeInterval?
        
        /// 最小往返时间（毫秒）
        public let minRTT: TimeInterval?
        
        /// 最大往返时间（毫秒）  
        public let maxRTT: TimeInterval?
        
        /// 连续超时次数
        public let timeoutCount: Int
        
        /// 待响应Ping数量
        public let pendingPingCount: Int
        
        /// 最后Pong时间
        public let lastPongTime: Date?
    }
    
    /// 获取心跳统计信息
    /// - Returns: 统计信息
    func getStatistics() -> Statistics {
        let rttStats = getRoundTripTimeStats()
        
        return Statistics(
            currentRTT: rttHistory.last,
            averageRTT: rttStats.average,
            minRTT: rttStats.min,
            maxRTT: rttStats.max,
            timeoutCount: timeoutCount,
            pendingPingCount: pendingPings.count,
            lastPongTime: lastPongTime
        )
    }
}