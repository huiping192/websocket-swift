import Foundation
import Network

/// TCP传输实现
/// 使用Network.framework提供TCP连接功能
public final class TCPTransport: NetworkTransportProtocol, @unchecked Sendable {
    
    // MARK: - 私有属性
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.websocket.tcp.transport", qos: .userInitiated)
    private var connectionState: ConnectionState = .disconnected
    private let maxReceiveSize: Int = 65536
    private let connectionTimeout: TimeInterval = 30.0
    
    // MARK: - 状态管理
    private let stateQueue = DispatchQueue(label: "com.websocket.tcp.state", qos: .utility)
    
    public init() {}
    
    // MARK: - 便利方法
    
    /// 便利方法：连接到指定主机和端口（不使用TLS）
    /// - Parameters:
    ///   - host: 主机名或IP地址
    ///   - port: 端口号
    public func connect(to host: String, port: Int) async throws {
        try await connect(to: host, port: port, useTLS: false, tlsConfig: .secure)
    }
    
    /// 便利方法：连接到指定主机和端口（使用默认TLS配置）
    /// - Parameters:
    ///   - host: 主机名或IP地址
    ///   - port: 端口号
    public func connectSecure(to host: String, port: Int) async throws {
        try await connect(to: host, port: port, useTLS: true, tlsConfig: .secure)
    }
    
    // MARK: - NetworkTransportProtocol实现
    
    /// 连接到指定主机和端口
    /// - Parameters:
    ///   - host: 主机名或IP地址
    ///   - port: 端口号
    ///   - useTLS: 是否使用TLS加密
    ///   - tlsConfig: TLS配置（当useTLS为true时使用）
    public func connect(to host: String, port: Int, useTLS: Bool, tlsConfig: TLSConfiguration = .secure) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stateQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NetworkError.connectionReset)
                    return
                }
                
                // 检查当前状态
                guard self.connectionState == .disconnected else {
                    continuation.resume(throwing: NetworkError.invalidState("Connection already exists"))
                    return
                }
                
                // 设置连接参数
                let parameters = self.createConnectionParameters(useTLS: useTLS, tlsConfig: tlsConfig)
                
                // 创建连接
                let endpoint = NWEndpoint.hostPort(
                    host: NWEndpoint.Host(host),
                    port: NWEndpoint.Port(integerLiteral: UInt16(port))
                )
                
                let connection = NWConnection(to: endpoint, using: parameters)
                self.connection = connection
                self.connectionState = .connecting
                
                // 设置状态更新处理
                connection.stateUpdateHandler = { [weak self] state in
                    self?.handleConnectionStateUpdate(state, continuation: continuation)
                }
                
                // 启动连接
                connection.start(queue: self.queue)
                
                // 设置超时
                DispatchQueue.global().asyncAfter(deadline: .now() + self.connectionTimeout) { [weak self] in
                    self?.stateQueue.async {
                        if self?.connectionState == .connecting {
                            self?.connectionState = .failed(NetworkError.connectionTimeout)
                            connection.cancel()
                            continuation.resume(throwing: NetworkError.connectionTimeout)
                        }
                    }
                }
            }
        }
    }
    
    /// 断开连接
    public func disconnect() async {
        await withCheckedContinuation { continuation in
            stateQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                if let connection = self.connection {
                    connection.cancel()
                    self.connection = nil
                }
                
                self.connectionState = .disconnected
                continuation.resume()
            }
        }
    }
    
    /// 发送数据
    /// - Parameter data: 要发送的数据
    public func send(data: Data) async throws {
        guard let connection = self.connection else {
            throw NetworkError.notConnected
        }
        
        guard connectionState == .connected else {
            throw NetworkError.invalidState("Connection not ready")
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: NetworkError.sendFailed(error))
                } else {
                    continuation.resume()
                }
            })
        }
    }
    
    /// 接收数据
    /// - Returns: 接收到的数据
    public func receive() async throws -> Data {
        guard let connection = self.connection else {
            throw NetworkError.notConnected
        }
        
        guard connectionState == .connected else {
            throw NetworkError.invalidState("Connection not ready")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maxReceiveSize) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: NetworkError.receiveFailed(error))
                    return
                }
                
                if isComplete {
                    continuation.resume(throwing: NetworkError.connectionReset)
                    return
                }
                
                guard let data = data, !data.isEmpty else {
                    continuation.resume(throwing: NetworkError.noDataReceived)
                    return
                }
                
                continuation.resume(returning: data)
            }
        }
    }
    
    // MARK: - 私有方法
    
    /// 创建连接参数
    private func createConnectionParameters(useTLS: Bool, tlsConfig: TLSConfiguration = .secure) -> NWParameters {
        let parameters: NWParameters
        
        if useTLS {
            // TLS配置
            let tlsOptions = NWProtocolTLS.Options.from(tlsConfig)
            parameters = NWParameters(tls: tlsOptions, tcp: .init())
        } else {
            // 普通TCP配置
            parameters = NWParameters.tcp
        }
        
        // 优化网络性能
        parameters.serviceClass = .responsiveData
        parameters.preferNoProxies = true
        parameters.multipathServiceType = .disabled
        
        // 禁用Nagle算法以降低延迟
        if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.noDelay = true
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 60  // 60秒开始发送keepalive
            tcpOptions.keepaliveInterval = 30  // 每30秒发送一次
            tcpOptions.keepaliveCount = 3  // 最多发送3次
        }
        
        return parameters
    }
    
    /// 处理连接状态更新
    private func handleConnectionStateUpdate(_ state: NWConnection.State, continuation: CheckedContinuation<Void, Error>) {
        stateQueue.async { [weak self] in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                if self.connectionState == .connecting {
                    self.connectionState = .connected
                    continuation.resume()
                }
                
            case .failed(let error):
                let networkError = NetworkError.connectionFailed(error)
                self.connectionState = .failed(networkError)
                if self.connectionState == .connecting {
                    continuation.resume(throwing: networkError)
                }
                
            case .cancelled:
                self.connectionState = .disconnected
                if self.connectionState == .connecting {
                    continuation.resume(throwing: NetworkError.connectionCancelled)
                }
                
            case .waiting(let error):
                print("Connection waiting: \(error)")
                // 继续等待，不改变状态
                
            case .preparing, .setup:
                // 准备阶段，保持connecting状态
                break
                
            @unknown default:
                break
            }
        }
    }
}

// MARK: - 网络错误定义

/// 网络传输错误
public enum NetworkError: Error, LocalizedError {
    case connectionTimeout
    case hostUnreachable
    case connectionFailed(Error)
    case connectionReset
    case connectionCancelled
    case invalidState(String)
    case notConnected
    case sendFailed(Error)
    case receiveFailed(Error)
    case noDataReceived
    case tlsHandshakeFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .connectionTimeout:
            return "连接超时"
        case .hostUnreachable:
            return "主机不可达"
        case .connectionFailed(let error):
            return "连接失败: \(error.localizedDescription)"
        case .connectionReset:
            return "连接被重置"
        case .connectionCancelled:
            return "连接被取消"
        case .invalidState(let message):
            return "无效状态: \(message)"
        case .notConnected:
            return "未连接"
        case .sendFailed(let error):
            return "发送失败: \(error.localizedDescription)"
        case .receiveFailed(let error):
            return "接收失败: \(error.localizedDescription)"
        case .noDataReceived:
            return "未接收到数据"
        case .tlsHandshakeFailed(let error):
            return "TLS握手失败: \(error.localizedDescription)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .connectionTimeout:
            return "请检查网络连接，确认服务器地址正确"
        case .hostUnreachable:
            return "请检查主机名或IP地址是否正确"
        case .connectionFailed, .connectionReset:
            return "请稍后重试，或检查网络连接"
        case .notConnected:
            return "请先建立连接"
        case .tlsHandshakeFailed:
            return "请检查TLS配置或证书"
        default:
            return "请重试或联系技术支持"
        }
    }
}