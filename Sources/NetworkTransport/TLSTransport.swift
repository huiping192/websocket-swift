import Foundation
import Network

/// TLS传输实现
/// 使用Network.framework提供TLS加密连接功能，内部使用TCPTransport作为基础传输
public final class TLSTransport: TLSTransportProtocol, @unchecked Sendable {
    
    // MARK: - 私有属性
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.websocket.tls.transport", qos: .userInitiated)
    private var connectionState: ConnectionState = .disconnected
    private let maxReceiveSize: Int = 65536
    private let connectionTimeout: TimeInterval
    
    // MARK: - 状态管理
    private let stateQueue = DispatchQueue(label: "com.websocket.tls.state", qos: .utility)
    
    /// 初始化TLS传输
    /// - Parameter timeout: 连接超时时间（秒），默认30秒
    public init(timeout: TimeInterval = 30.0) {
        self.connectionTimeout = timeout
    }
    
    // MARK: - TLSTransportProtocol实现
    
    /// 连接到指定主机和端口（使用TLS加密）
    /// - Parameters:
    ///   - host: 主机名或IP地址
    ///   - port: 端口号
    ///   - tlsConfig: TLS配置选项
    public func connect(to host: String, port: Int, tlsConfig: TLSConfiguration = .secure) async throws {
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
                
                // 设置TLS连接参数
                let parameters = self.createTLSParameters(tlsConfig: tlsConfig)
                
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
    
    /// 创建TLS连接参数
    private func createTLSParameters(tlsConfig: TLSConfiguration) -> NWParameters {
        // TLS配置
        let tlsOptions = NWProtocolTLS.Options.from(tlsConfig)
        let parameters = NWParameters(tls: tlsOptions, tcp: .init())
        
        // 优化网络性能
        parameters.serviceClass = .responsiveData
        parameters.preferNoProxies = true
        parameters.multipathServiceType = .disabled
        
        // 配置TCP选项
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
                let networkError: NetworkError
                if (error as NSError).code == -9836 {
                    networkError = NetworkError.tlsHandshakeFailed(error)
                } else {
                    networkError = NetworkError.connectionFailed(error)
                }
                
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
                print("TLS Connection waiting: \(error)")
                
            case .preparing, .setup:
                break
                
            @unknown default:
                break
            }
        }
    }
}

// MARK: - 便利方法

extension TLSTransport {
    
    /// 连接到HTTPS服务器（使用标准443端口）
    /// - Parameter host: 主机名
    public func connectHTTPS(to host: String) async throws {
        try await connect(to: host, port: 443, tlsConfig: .webSocket)
    }
    
    /// 连接到WSS服务器（WebSocket over TLS）
    /// - Parameters:
    ///   - host: 主机名
    ///   - port: 端口号，默认443
    public func connectWSS(to host: String, port: Int = 443) async throws {
        try await connect(to: host, port: port, tlsConfig: .webSocket)
    }
    
    /// 连接到服务器（开发环境，跳过证书验证）
    /// - Parameters:
    ///   - host: 主机名
    ///   - port: 端口号
    public func connectDevelopment(to host: String, port: Int) async throws {
        try await connect(to: host, port: port, tlsConfig: .development)
    }
}