import Foundation
import NetworkTransport
import HTTPUpgrade
import Utilities

// MARK: - WebSocket客户端实现

/// WebSocket客户端
/// 整合所有底层组件，提供完整的WebSocket功能
public final class WebSocketClient: WebSocketClientProtocol {
    
    // MARK: - 依赖组件
    
    /// 网络传输层
    private let transport: NetworkTransportProtocol
    
    /// 握手管理器
    private let handshakeManager: HandshakeManagerProtocol
    
    /// 帧编码器
    private let frameEncoder: FrameEncoder
    
    /// 帧解码器
    private let frameDecoder: FrameDecoder
    
    /// 消息组装器
    private let messageAssembler: MessageAssembler
    
    /// 状态管理器
    private let stateManager: ConnectionStateManager
    
    /// 心跳管理器
    private var heartbeatManager: HeartbeatManager?
    
    /// 重连管理器
    private var reconnectManager: WebSocketReconnectManager?
    
    // MARK: - 配置参数
    
    /// WebSocket配置
    public struct Configuration {
        /// 连接超时时间（秒）
        public let connectTimeout: TimeInterval
        
        /// 最大帧大小（字节）
        public let maxFrameSize: Int
        
        /// 最大消息大小（字节）
        public let maxMessageSize: UInt64
        
        /// 分片超时时间（秒）
        public let fragmentTimeout: TimeInterval
        
        /// 支持的子协议列表
        public let subprotocols: [String]
        
        /// 支持的扩展列表
        public let extensions: [String]
        
        /// 额外的HTTP头部
        public let additionalHeaders: [String: String]
        
        /// 心跳配置
        public let heartbeatInterval: TimeInterval
        public let heartbeatTimeout: TimeInterval
        public let enableHeartbeat: Bool
        
        /// 重连配置
        public let enableAutoReconnect: Bool
        public let reconnectStrategy: WebSocketReconnectStrategy
        public let maxReconnectAttempts: Int
        public let reconnectTimeout: TimeInterval
        
        /// 默认配置
        public static let `default` = Configuration(
            connectTimeout: 10.0,
            maxFrameSize: 65536,
            maxMessageSize: 16 * 1024 * 1024, // 16MB
            fragmentTimeout: 30.0,
            subprotocols: [],
            extensions: [],
            additionalHeaders: [:],
            heartbeatInterval: 30.0,
            heartbeatTimeout: 10.0,
            enableHeartbeat: true,
            enableAutoReconnect: true,
            reconnectStrategy: ExponentialBackoffReconnectStrategy(),
            maxReconnectAttempts: 5,
            reconnectTimeout: 30.0
        )
        
        public init(
            connectTimeout: TimeInterval = 10.0,
            maxFrameSize: Int = 65536,
            maxMessageSize: UInt64 = 16 * 1024 * 1024,
            fragmentTimeout: TimeInterval = 30.0,
            subprotocols: [String] = [],
            extensions: [String] = [],
            additionalHeaders: [String: String] = [:],
            heartbeatInterval: TimeInterval = 30.0,
            heartbeatTimeout: TimeInterval = 10.0,
            enableHeartbeat: Bool = true,
            enableAutoReconnect: Bool = true,
            reconnectStrategy: WebSocketReconnectStrategy = ExponentialBackoffReconnectStrategy(),
            maxReconnectAttempts: Int = 5,
            reconnectTimeout: TimeInterval = 30.0
        ) {
            self.connectTimeout = connectTimeout
            self.maxFrameSize = maxFrameSize
            self.maxMessageSize = maxMessageSize
            self.fragmentTimeout = fragmentTimeout
            self.subprotocols = subprotocols
            self.extensions = extensions
            self.additionalHeaders = additionalHeaders
            self.heartbeatInterval = heartbeatInterval
            self.heartbeatTimeout = heartbeatTimeout
            self.enableHeartbeat = enableHeartbeat
            self.enableAutoReconnect = enableAutoReconnect
            self.reconnectStrategy = reconnectStrategy
            self.maxReconnectAttempts = maxReconnectAttempts
            self.reconnectTimeout = reconnectTimeout
        }
    }
    
    /// 客户端配置
    private let configuration: Configuration
    
    // MARK: - 运行时状态
    
    /// 当前连接的URL
    private var currentURL: URL?
    
    /// 接收任务
    private var receiveTask: Task<Void, Never>?
    
    /// 发送消息队列
    private let messageQueue = AsyncMessageQueue()
    
    /// 接收消息队列
    private let receiveQueue = AsyncMessageQueue()
    
    /// 发送任务
    private var sendTask: Task<Void, Never>?
    
    /// 握手结果
    private var handshakeResult: HandshakeResult?
    
    // MARK: - 初始化
    
    /// 初始化WebSocket客户端
    /// - Parameters:
    ///   - transport: 网络传输层，默认使用TCPTransport
    ///   - configuration: 客户端配置
    public init(
        transport: NetworkTransportProtocol? = nil,
        configuration: Configuration = .default
    ) {
        self.transport = transport ?? UnifiedNetworkTransport()
        self.configuration = configuration
        self.handshakeManager = HandshakeManager()
        self.frameEncoder = FrameEncoder()
        self.frameDecoder = FrameDecoder()
        self.messageAssembler = MessageAssembler(
            fragmentTimeout: configuration.fragmentTimeout,
            maxMessageSize: configuration.maxMessageSize
        )
        self.stateManager = ConnectionStateManager()
        
        // 创建心跳管理器
        if configuration.enableHeartbeat {
            self.heartbeatManager = HeartbeatManager(
                client: self,
                pingInterval: configuration.heartbeatInterval,
                pongTimeout: configuration.heartbeatTimeout
            )
            
            // 设置心跳超时回调
            Task {
                await self.heartbeatManager?.setOnHeartbeatTimeout { [weak self] in
                    Task {
                        await self?.handleHeartbeatTimeout() 
                    }
                }
            }
        }
        
        // 创建重连管理器
        if configuration.enableAutoReconnect {
            self.reconnectManager = WebSocketReconnectManager(strategy: configuration.reconnectStrategy)
            
            // 设置连接回调
            Task {
                await self.reconnectManager?.setConnectAction { [weak self] in
                    guard let self = self, let url = self.currentURL else {
                        throw WebSocketClientError.invalidState("没有可重连的URL")
                    }
                    
                    // 执行重连
                    try await self.performConnection(to: url)
                }
                
                // 设置重连事件回调
                await self.reconnectManager?.addEventHandler { [weak self] event in
                    Task {
                        await self?.handleReconnectEvent(event)
                    }
                }
            }
        }
    }
    
    // MARK: - WebSocketClientProtocol实现
    
    /// 连接到WebSocket服务器
    /// - Parameter url: WebSocket URL (ws:// 或 wss://)
    public func connect(to url: URL) async throws {
        // 验证URL
        guard let scheme = url.scheme, 
              ["ws", "wss"].contains(scheme.lowercased()) else {
            throw WebSocketClientError.invalidURL("不支持的协议：\(url.scheme ?? "nil")")
        }
        
        // 检查当前状态
        let currentState = await stateManager.currentState
        guard currentState == .closed else {
            throw WebSocketClientError.invalidState("当前状态不允许连接：\(currentState)")
        }
        
        // 保存URL用于重连
        self.currentURL = url
        
        do {
            // 尝试连接
            try await performConnection(to: url)
            
            // 连接成功，重置重连管理器
            await reconnectManager?.setReconnectEnabled(true)
            
        } catch {
            // 连接失败，检查是否需要重连
            if configuration.enableAutoReconnect {
                await reconnectManager?.startReconnect(after: error)
                
                // 等待重连完成或失败
                if let reconnectManager = reconnectManager {
                    let maxWaitTime = configuration.reconnectTimeout
                    let startTime = Date()
                    
                    while Date().timeIntervalSince(startTime) < maxWaitTime {
                        let state = await reconnectManager.currentState
                        
                        switch state {
                        case .idle:
                            // 重连成功
                            return
                        case .stopped:
                            // 重连失败
                            throw error
                        case .reconnecting, .waiting:
                            // 继续等待
                            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                            continue
                        }
                    }
                    
                    // 超时，停止重连
                    await reconnectManager.stopReconnect()
                    throw WebSocketClientError.connectionTimeout("重连超时")
                }
            }
            
            throw error
        }
    }
    
    /// 执行实际的连接操作（内部方法，用于初始连接和重连）
    /// - Parameter url: WebSocket URL
    private func performConnection(to url: URL) async throws {
        // 更新状态为连接中
        await stateManager.updateState(.connecting)
        
        do {
            // 1. 建立TCP连接
            let host = url.host ?? "localhost"
            let port = url.port ?? (url.scheme == "wss" ? 443 : 80)
            let useTLS = url.scheme == "wss"
            
            print("🔗 连接到 \(host):\(port) (TLS: \(useTLS))")
            
            try await transport.connect(
                to: host,
                port: port,
                useTLS: useTLS,
                tlsConfig: TLSConfiguration()
            )
            
            // 2. 执行WebSocket握手
            print("🤝 开始WebSocket握手...")
            
            let handshakeResult = try await handshakeManager.performHandshake(
                url: url,
                transport: transport,
                protocols: configuration.subprotocols,
                extensions: configuration.extensions,
                additionalHeaders: configuration.additionalHeaders
            )
            
            // 3. 验证握手结果
            guard handshakeResult.success else {
                throw WebSocketClientError.handshakeFailed("握手失败")
            }
            
            // 4. 保存连接信息
            self.handshakeResult = handshakeResult
            
            // 5. 启动后台任务
            startBackgroundTasks()
            
            // 6. 更新状态为已连接
            await stateManager.updateState(.open)
            
            // 7. 启动心跳管理器
            Task {
                await heartbeatManager?.startHeartbeat()
            }
            
            print("✅ WebSocket连接建立成功")
            
        } catch {
            // 连接失败，更新状态并清理
            await stateManager.updateState(.closed)
            await cleanup()
            
            if error is WebSocketClientError {
                throw error
            } else {
                throw WebSocketClientError.connectionFailed(error)
            }
        }
    }
    
    /// 发送消息
    /// - Parameter message: 要发送的消息
    public func send(message: WebSocketMessage) async throws {
        // 检查连接状态
        let isConnected = await stateManager.canSendMessages
        guard isConnected else {
            let currentState = await stateManager.currentState
            throw WebSocketClientError.invalidState("当前状态不允许发送消息：\(currentState)")
        }
        
        // 将消息加入发送队列
        await messageQueue.enqueue(message)
    }
    
    /// 接收消息
    /// - Returns: 接收到的消息
    public func receive() async throws -> WebSocketMessage {
        // 检查连接状态
        let canReceive = await stateManager.canReceiveMessages
        guard canReceive else {
            let currentState = await stateManager.currentState
            throw WebSocketClientError.invalidState("当前状态不允许接收消息：\(currentState)")
        }
        
        // 从接收队列获取消息
        while await stateManager.canReceiveMessages {
            if let message = await receiveQueue.dequeue() {
                return message
            }
            
            // 如果队列为空，等待一小段时间后重试
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
        
        // 连接已关闭
        let currentState = await stateManager.currentState
        throw WebSocketClientError.invalidState("连接已关闭：\(currentState)")
    }
    
    /// 关闭连接
    /// 关闭WebSocket连接（使用默认状态码）
    public func close() async throws {
        try await close(code: 1000, reason: "Normal closure")
    }
    
    /// 关闭WebSocket连接（指定状态码和原因）
    /// - Parameters:
    ///   - code: 关闭状态码 (RFC 6455)
    ///   - reason: 关闭原因
    public func close(code: UInt16, reason: String = "") async throws {
        let currentState = await stateManager.currentState
        
        // 如果已经关闭或正在关闭，直接返回
        if currentState == .closed || currentState == .closing {
            print("ℹ️ 连接已处于关闭状态: \(currentState)")
            return
        }
        
        print("🔌 开始关闭WebSocket连接...")
        
        // 停止重连管理器（用户主动关闭不应触发重连）
        await reconnectManager?.stopReconnect()
        await reconnectManager?.setReconnectEnabled(false)
        
        // 验证关闭状态码
        do {
            try validateCloseCode(code)
        } catch {
            print("⚠️ 关闭状态码验证失败: \(error)")
            // 即使状态码无效，仍继续关闭流程
        }
        
        // 更新状态为关闭中
        await stateManager.updateState(.closing)
        
        // 尝试发送关闭帧
        var closeFrameSent = false
        if await stateManager.canSendMessages || currentState == .open {
            do {
                try await sendCloseFrame(code: code, reason: reason)
                closeFrameSent = true
                
                // 等待服务器关闭帧响应或超时
                let gracefulClose = await waitForServerCloseResponse(timeout: 3.0)
                
                if gracefulClose {
                    print("✅ 优雅关闭完成")
                } else {
                    print("⚠️ 服务器未响应关闭帧，强制关闭")
                }
                
            } catch {
                print("⚠️ 发送关闭帧失败: \(error)")
            }
        } else {
            print("ℹ️ 连接状态不允许发送关闭帧，直接清理")
        }
        
        // 无论如何都要清理连接
        await cleanup()
        await stateManager.updateState(.closed)
        
        if closeFrameSent {
            print("✅ WebSocket连接已优雅关闭")
        } else {
            print("✅ WebSocket连接已强制关闭")
        }
    }
    
    // MARK: - 状态查询
    
    /// 获取当前连接状态
    public var connectionState: WebSocketState {
        get async {
            await stateManager.currentState
        }
    }
    
    /// 检查是否已连接
    public var isConnected: Bool {
        get async {
            await stateManager.isConnected
        }
    }
    
    /// 获取握手结果
    public var negotiatedProtocol: String? {
        handshakeResult?.negotiatedProtocol
    }
    
    /// 获取协商的扩展
    public var negotiatedExtensions: [String] {
        handshakeResult?.negotiatedExtensions ?? []
    }
    
    // MARK: - 重连管理
    
    /// 获取重连统计信息
    /// - Returns: 重连统计信息，如果未启用重连则返回nil
    public func getReconnectStatistics() async -> WebSocketReconnectManager.ReconnectStatistics? {
        return await reconnectManager?.getStatistics()
    }
    
    /// 获取重连历史记录
    /// - Returns: 重连历史记录
    public func getReconnectHistory() async -> [ReconnectRecord] {
        return await reconnectManager?.getReconnectHistory() ?? []
    }
    
    /// 手动触发重连
    /// - Returns: 重连是否成功
    @discardableResult
    public func reconnectManually() async -> Bool {
        guard configuration.enableAutoReconnect else {
            print("⚠️ 自动重连未启用，无法手动重连")
            return false
        }
        
        return await reconnectManager?.reconnectImmediately() ?? false
    }
    
    /// 设置重连启用状态
    /// - Parameter enabled: 是否启用重连
    public func setReconnectEnabled(_ enabled: Bool) async {
        await reconnectManager?.setReconnectEnabled(enabled)
    }
    
    /// 添加重连事件处理器
    /// - Parameter handler: 事件处理回调
    public func addReconnectEventHandler(_ handler: @escaping (WebSocketReconnectEvent) -> Void) async {
        await reconnectManager?.addEventHandler(handler)
    }
    
    /// 停止所有重连活动
    public func stopReconnect() async {
        await reconnectManager?.stopReconnect()
    }
    
    /// 重置重连统计信息
    public func resetReconnectStatistics() async {
        await reconnectManager?.resetStatistics()
    }
    
    // MARK: - 私有方法
    
    /// 启动后台任务
    private func startBackgroundTasks() {
        // 启动接收任务
        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop()
        }
        
        // 启动发送任务  
        sendTask = Task { [weak self] in
            await self?.runSendLoop()
        }
    }
    
    /// 运行接收循环
    private func runReceiveLoop() async {
        print("🔄 接收循环已启动")
        
        while await stateManager.canReceiveMessages {
            do {
                // 接收网络数据
                let data = try await transport.receive()
                
                // 解码WebSocket帧
                let frames = try frameDecoder.decode(data: data)
                
                // 处理每个帧
                for frame in frames {
                    try await processReceivedFrame(frame)
                }
                
            } catch {
                let currentState = await stateManager.currentState
                
                // 检查是否是由于连接正常关闭导致的错误
                if currentState == .closing || currentState == .closed {
                    print("ℹ️ 连接正在关闭，接收循环正常退出")
                    break
                }
                
                print("❌ 接收数据失败: \(error)")
                
                // 检查是否是取消错误（任务被取消）
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                    print("ℹ️ 接收任务已被取消")
                    break
                }
                
                // 网络错误，优雅关闭连接
                await stateManager.updateState(.closing)
                await cleanup()
                await stateManager.updateState(.closed)
                break
            }
        }
        
        print("🔚 接收循环已结束")
    }
    
    /// 运行发送循环  
    private func runSendLoop() async {
        print("🔄 发送循环已启动")
        
        while await stateManager.canSendMessages {
            do {
                // 从队列获取消息
                guard let message = await messageQueue.dequeue() else {
                    // 队列为空，等待一段时间
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    continue
                }
                
                // 编码消息为帧并发送
                let frameData = try frameEncoder.encode(message: message)
                try await transport.send(data: frameData)
                
                print("📤 已发送消息: \(message)")
                
            } catch {
                let currentState = await stateManager.currentState
                
                // 检查是否是由于连接正常关闭导致的错误
                if currentState == .closing || currentState == .closed {
                    print("ℹ️ 连接正在关闭，发送循环正常退出")
                    break
                }
                
                print("❌ 发送消息失败: \(error)")
                
                // 检查是否是取消错误（任务被取消）
                if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                    print("ℹ️ 发送任务已被取消")
                    break
                }
                
                // 发送错误，根据错误类型决定是否关闭连接
                if error is NetworkError {
                    await stateManager.updateState(.closing)
                    await cleanup()
                    await stateManager.updateState(.closed)
                    break
                }
            }
        }
        
        print("🔚 发送循环已结束")
    }
    
    /// 处理接收到的帧
    /// - Parameter frame: 接收到的帧
    private func processReceivedFrame(_ frame: WebSocketFrame) async throws {
        // 使用消息组装器处理帧
        if let message = try messageAssembler.process(frame: frame) {
            // 处理完整消息
            await handleReceivedMessage(message)
        }
    }
    
    /// 处理接收到的完整消息
    /// - Parameter message: 完整消息
    private func handleReceivedMessage(_ message: WebSocketMessage) async {
        switch message {
        case .ping(let data):
            print("📥 收到Ping消息")
            // 自动回复Pong
            let pongMessage = WebSocketMessage.pong(data)
            await messageQueue.enqueue(pongMessage)
            
        case .pong(let data):
            print("📥 收到Pong消息")
            // 将Pong帧传递给心跳管理器处理
            if let heartbeatManager = heartbeatManager {
                let payload = data ?? Data()
                Task {
                    do {
                        let pongFrame = try WebSocketFrame(
                            fin: true,
                            rsv1: false,
                            rsv2: false,
                            rsv3: false,
                            opcode: .pong,
                            masked: false,
                            payload: payload,
                            maskingKey: nil
                        )
                        await heartbeatManager.handlePong(pongFrame)
                    } catch {
                        print("❌ 创建Pong帧失败: \(error)")
                    }
                }
            }
            
        case .text(let text):
            print("📥 收到文本消息: \(text)")
            // 将用户消息放入接收队列
            await receiveQueue.enqueue(message)
            
        case .binary(let data):
            // 检查是否为关闭帧（通过MessageAssembler传递的关闭消息）
            // 关闭帧的二进制数据格式：前2字节为状态码，后续为UTF-8编码的原因
            if data.count >= 2 {
                // 尝试解析关闭状态码以确定是否为关闭帧
                let possibleCloseCode = data.withUnsafeBytes { buffer in
                    buffer.load(as: UInt16.self).bigEndian
                }
                
                // 常见的关闭状态码范围检查
                if (1000...1015).contains(possibleCloseCode) || (3000...4999).contains(possibleCloseCode) {
                    // 很可能是关闭帧，处理关闭逻辑
                    await handleCloseFrame(data: data)
                    return
                }
            }
            
            print("📥 收到二进制消息: \(data.count) bytes")
            // 将用户消息放入接收队列
            await receiveQueue.enqueue(message)
        }
    }
    
    /// 清理状态标志，防止重复清理
    private var isCleaningUp = false
    
    /// 清理资源（线程安全，防止重复清理）
    private func cleanup() async {
        // 防止重复清理
        guard !isCleaningUp else {
            print("⚠️ 清理已在进行中，跳过重复清理")
            return
        }
        
        isCleaningUp = true
        defer { isCleaningUp = false }
        
        print("🧹 开始清理资源...")
        
        // 停止心跳管理器
        if let heartbeatManager = heartbeatManager {
            await heartbeatManager.stopHeartbeat()
            print("✅ 心跳管理器已停止")
        }
        
        // 取消后台任务
        receiveTask?.cancel()
        sendTask?.cancel()
        receiveTask = nil
        sendTask = nil
        print("✅ 后台任务已取消")
        
        // 清空消息队列
        await messageQueue.clear()
        print("✅ 消息队列已清空")
        
        // 重置解码器和组装器状态
        frameDecoder.reset()
        messageAssembler.reset()
        print("✅ 解码器和组装器已重置")
        
        // 断开网络连接
        await transport.disconnect()
        print("✅ 网络连接已断开")
        
        // 清理连接信息
        currentURL = nil
        handshakeResult = nil
        
        print("🧹 资源清理完成")
    }
    
    /// 处理心跳超时
    private func handleHeartbeatTimeout() async {
        print("💔 心跳超时，检测连接断开")
        
        // 更新状态为关闭中
        await stateManager.updateState(.closing)
        
        // 清理资源
        await cleanup()
        
        // 更新状态为已关闭
        await stateManager.updateState(.closed)
        
        // 如果启用了自动重连，尝试重连
        if configuration.enableAutoReconnect, currentURL != nil {
            print("🔄 心跳超时触发自动重连")
            let timeoutError = WebSocketClientError.connectionTimeout("心跳超时")
            await reconnectManager?.startReconnect(after: timeoutError)
        }
    }
    
    /// 处理重连事件
    /// - Parameter event: 重连事件
    private func handleReconnectEvent(_ event: WebSocketReconnectEvent) async {
        switch event {
        case .reconnectStarted(let attempt, let delay):
            print("🔄 开始第\(attempt)次重连尝试，延迟\(delay)秒")
            
        case .reconnectFailed(let error, let attempt):
            print("❌ 第\(attempt)次重连失败: \(error.localizedDescription)")
            
        case .reconnectSucceeded(let attempt, let totalTime):
            print("✅ 第\(attempt)次重连成功，耗时\(String(format: "%.2f", totalTime))秒")
            
        case .reconnectAbandoned(let finalError, let totalAttempts):
            print("⏹️ 重连已放弃，共尝试\(totalAttempts)次，最终错误: \(finalError.localizedDescription)")
            
        case .reconnectStatusUpdate(let message):
            print("ℹ️ 重连状态: \(message)")
        }
    }
    
    // MARK: - 关闭处理辅助方法
    
    /// 验证关闭状态码
    /// - Parameter code: 关闭状态码
    private func validateCloseCode(_ code: UInt16) throws {
        switch code {
        case 1000...1003, 1007...1011, 3000...4999:
            // 有效状态码
            break
        case 1004, 1005, 1006:
            // 保留状态码，不应由客户端发送
            throw WebSocketClientError.invalidCloseCode(code, "保留状态码，不能主动发送")
        case 1012...1014:
            // 保留状态码
            throw WebSocketClientError.invalidCloseCode(code, "保留状态码")
        case 1015:
            // TLS握手失败，只能由服务器发送
            throw WebSocketClientError.invalidCloseCode(code, "TLS握手失败状态码，客户端不能发送")
        default:
            throw WebSocketClientError.invalidCloseCode(code, "未定义的状态码")
        }
    }
    
    /// 发送关闭帧
    /// - Parameters:
    ///   - code: 关闭状态码
    ///   - reason: 关闭原因
    private func sendCloseFrame(code: UInt16, reason: String) async throws {
        let closeMessage = WebSocketMessage.close(code: code, reason: reason)
        
        // 编码关闭帧并发送
        let frameData = try frameEncoder.encode(message: closeMessage)
        try await transport.send(data: frameData)
        
        print("📤 已发送关闭帧 - 状态码: \(code), 原因: \(reason)")
    }
    
    /// 等待服务器关闭帧响应
    /// - Parameter timeout: 超时时间（秒）
    /// - Returns: 是否收到服务器关闭帧
    private func waitForServerCloseResponse(timeout: TimeInterval) async -> Bool {
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < timeout {
            // 检查连接状态
            let currentState = await stateManager.currentState
            if currentState == .closed {
                return true
            }
            
            // 短暂休眠后继续检查
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        return false
    }
    
    /// 处理收到的关闭帧
    /// - Parameter closeFrame: 关闭帧数据
    private func handleCloseFrame(data: Data?) async {
        var code: UInt16 = 1005 // No Status Rcvd
        var reason = ""
        
        if let data = data, data.count >= 2 {
            // 解析关闭状态码（前2字节，大端序）
            code = data.withUnsafeBytes { buffer in
                buffer.load(as: UInt16.self).bigEndian
            }
            
            // 解析关闭原因（剩余字节，UTF-8编码）
            if data.count > 2 {
                let reasonData = data.dropFirst(2)
                reason = String(data: reasonData, encoding: .utf8) ?? ""
            }
        }
        
        print("📥 收到关闭帧 - 状态码: \(code), 原因: \(reason)")
        
        // 如果我们还在运行状态，需要回复关闭帧
        let currentState = await stateManager.currentState
        if currentState == .open {
            // 更新状态为关闭中
            await stateManager.updateState(.closing)
            
            // 回复关闭帧（相同状态码）
            do {
                try await sendCloseFrame(code: code, reason: "")
            } catch {
                print("⚠️ 回复关闭帧失败: \(error)")
            }
        }
        
        // 只更新状态为已关闭，不执行清理（清理由主关闭流程处理）
        await stateManager.updateState(.closed)
        print("✅ 服务器关闭帧已处理")
    }
}

// MARK: - 异步消息队列

/// 异步消息队列
private actor AsyncMessageQueue {
    private var messages: [WebSocketMessage] = []
    
    /// 入队消息
    func enqueue(_ message: WebSocketMessage) {
        messages.append(message)
    }
    
    /// 出队消息
    func dequeue() -> WebSocketMessage? {
        guard !messages.isEmpty else { return nil }
        return messages.removeFirst()
    }
    
    /// 清空队列
    func clear() {
        messages.removeAll()
    }
    
    /// 获取队列长度
    var count: Int {
        messages.count
    }
}

// MARK: - 错误定义

/// WebSocket客户端错误
public enum WebSocketClientError: Error, LocalizedError {
    case invalidURL(String)
    case invalidState(String)
    case connectionFailed(Error)
    case connectionTimeout(String)
    case handshakeFailed(String)
    case networkError(Error)
    case protocolError(String)
    case notImplemented(String)
    case invalidCloseCode(UInt16, String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let reason):
            return "无效的URL: \(reason)"
        case .invalidState(let reason):
            return "无效的状态: \(reason)"
        case .connectionFailed(let error):
            return "连接失败: \(error.localizedDescription)"
        case .connectionTimeout(let reason):
            return "连接超时: \(reason)"
        case .handshakeFailed(let reason):
            return "握手失败: \(reason)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .protocolError(let reason):
            return "协议错误: \(reason)"
        case .notImplemented(let reason):
            return "功能未实现: \(reason)"
        case .invalidCloseCode(let code, let reason):
            return "无效的关闭状态码 \(code): \(reason)"
        }
    }
}

// MARK: - 扩展：WebSocketMessage支持close消息

extension WebSocketMessage {
    /// 创建关闭消息
    /// - Parameters:
    ///   - code: 关闭状态码
    ///   - reason: 关闭原因
    /// - Returns: 关闭消息
    public static func close(code: UInt16, reason: String) -> WebSocketMessage {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: code.bigEndian) { Data($0) })
        if !reason.isEmpty {
            data.append(reason.data(using: .utf8) ?? Data())
        }
        return .binary(data)
    }
}

// MARK: - 便利方法

extension WebSocketClient {
    
    /// 发送文本消息
    /// - Parameter text: 文本内容
    public func send(text: String) async throws {
        try await send(message: .text(text))
    }
    
    /// 发送二进制数据
    /// - Parameter data: 二进制数据
    public func send(data: Data) async throws {
        try await send(message: .binary(data))
    }
    
    /// 发送Ping消息
    /// - Parameter data: Ping数据
    public func ping(data: Data? = nil) async throws {
        try await send(message: .ping(data))
    }
    
    /// 添加状态变化监听器
    /// - Parameter handler: 状态变化回调
    public func addStateChangeHandler(_ handler: @escaping (WebSocketState) -> Void) async {
        await stateManager.addStateChangeHandler(handler)
    }
    
    /// 等待连接建立
    /// - Parameter timeout: 超时时间
    /// - Returns: 是否成功连接
    public func waitForConnection(timeout: TimeInterval = 10.0) async -> Bool {
        return await stateManager.waitForState(.open, timeout: timeout)
    }
    
    /// 获取心跳统计信息
    /// - Returns: 心跳统计信息，如果心跳未启用则返回nil
    public func getHeartbeatStatistics() async -> HeartbeatManager.Statistics? {
        return await heartbeatManager?.getStatistics()
    }
    
    /// 设置心跳回调
    /// - Parameters:
    ///   - onTimeout: 心跳超时回调
    ///   - onRestored: 心跳恢复回调
    ///   - onRTTUpdated: 往返时间更新回调
    public func setHeartbeatCallbacks(
        onTimeout: (() -> Void)? = nil,
        onRestored: (() -> Void)? = nil,
        onRTTUpdated: ((TimeInterval) -> Void)? = nil
    ) async {
        if let heartbeatManager = heartbeatManager {
            if let onTimeout = onTimeout {
                await heartbeatManager.setOnHeartbeatTimeout(onTimeout)
            }
            if let onRestored = onRestored {
                await heartbeatManager.setOnHeartbeatRestored(onRestored)
            }
            if let onRTTUpdated = onRTTUpdated {
                await heartbeatManager.setOnRoundTripTimeUpdated(onRTTUpdated)
            }
        }
    }
}
