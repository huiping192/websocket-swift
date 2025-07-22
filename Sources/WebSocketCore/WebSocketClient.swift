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
        
        /// 默认配置
        public static let `default` = Configuration(
            connectTimeout: 10.0,
            maxFrameSize: 65536,
            maxMessageSize: 16 * 1024 * 1024, // 16MB
            fragmentTimeout: 30.0,
            subprotocols: [],
            extensions: [],
            additionalHeaders: [:]
        )
        
        public init(
            connectTimeout: TimeInterval = 10.0,
            maxFrameSize: Int = 65536,
            maxMessageSize: UInt64 = 16 * 1024 * 1024,
            fragmentTimeout: TimeInterval = 30.0,
            subprotocols: [String] = [],
            extensions: [String] = [],
            additionalHeaders: [String: String] = [:]
        ) {
            self.connectTimeout = connectTimeout
            self.maxFrameSize = maxFrameSize
            self.maxMessageSize = maxMessageSize
            self.fragmentTimeout = fragmentTimeout
            self.subprotocols = subprotocols
            self.extensions = extensions
            self.additionalHeaders = additionalHeaders
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
            self.currentURL = url
            self.handshakeResult = handshakeResult
            
            // 5. 启动后台任务
            startBackgroundTasks()
            
            // 6. 更新状态为已连接
            await stateManager.updateState(.open)
            
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
        
        // 这里应该从接收缓冲区获取消息
        // 为了简化，这里抛出未实现错误
        // 实际应用中应该有专门的接收缓冲区
        throw WebSocketClientError.notImplemented("接收功能需要接收缓冲区支持")
    }
    
    /// 关闭连接
    public func close() async throws {
        let currentState = await stateManager.currentState
        
        // 如果已经关闭，直接返回
        if currentState == .closed {
            return
        }
        
        // 更新状态为关闭中
        await stateManager.updateState(.closing)
        
        do {
            // 发送关闭帧
            let closeMessage = WebSocketMessage.close(code: 1000, reason: "客户端主动关闭")
            
            // 编码关闭帧并发送
            let frameData = try frameEncoder.encode(message: closeMessage)
            try await transport.send(data: frameData)
            
            print("📤 已发送关闭帧")
            
            // 等待一段时间让服务器响应
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
            
        } catch {
            print("⚠️ 发送关闭帧失败: \(error)")
        }
        
        // 无论如何都要清理连接
        await cleanup()
        await stateManager.updateState(.closed)
        
        print("✅ WebSocket连接已关闭")
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
                print("❌ 接收数据失败: \(error)")
                
                // 网络错误，关闭连接
                await stateManager.updateState(.closed)
                await cleanup()
                break
            }
        }
        
        print("🔚 接收循环已结束")
    }
    
    /// 运行发送循环  
    private func runSendLoop() async {
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
                print("❌ 发送消息失败: \(error)")
                
                // 发送错误，根据错误类型决定是否关闭连接
                if error is NetworkError {
                    await stateManager.updateState(.closed)
                    await cleanup()
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
            
        case .pong(_):
            print("📥 收到Pong消息")
            // 可以用于心跳检测，这里暂时只记录
            
        case .text(let text):
            print("📥 收到文本消息: \(text)")
            // 应该将消息放入接收缓冲区供用户获取
            
        case .binary(let data):
            print("📥 收到二进制消息: \(data.count) bytes")
            // 应该将消息放入接收缓冲区供用户获取
        }
    }
    
    /// 清理资源
    private func cleanup() async {
        // 取消后台任务
        receiveTask?.cancel()
        sendTask?.cancel()
        receiveTask = nil
        sendTask = nil
        
        // 清空消息队列
        await messageQueue.clear()
        
        // 重置解码器和组装器状态
        frameDecoder.reset()
        messageAssembler.reset()
        
        // 断开网络连接
        await transport.disconnect()
        
        // 清理连接信息
        currentURL = nil
        handshakeResult = nil
        
        print("🧹 资源清理完成")
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
    case handshakeFailed(String)
    case networkError(Error)
    case protocolError(String)
    case notImplemented(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let reason):
            return "无效的URL: \(reason)"
        case .invalidState(let reason):
            return "无效的状态: \(reason)"
        case .connectionFailed(let error):
            return "连接失败: \(error.localizedDescription)"
        case .handshakeFailed(let reason):
            return "握手失败: \(reason)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .protocolError(let reason):
            return "协议错误: \(reason)"
        case .notImplemented(let reason):
            return "功能未实现: \(reason)"
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
}