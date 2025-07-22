import Foundation

/// 统一网络传输实现
/// 组合TCP和TLS传输，提供向后兼容的NetworkTransportProtocol接口
public final class UnifiedNetworkTransport: NetworkTransportProtocol, @unchecked Sendable {
    
    private var tcpTransport: TCPTransport?
    private var tlsTransport: TLSTransport?
    private let connectionTimeout: TimeInterval
    
    /// 初始化统一网络传输
    /// - Parameter timeout: 连接超时时间（秒），默认30秒
    public init(timeout: TimeInterval = 30.0) {
        self.connectionTimeout = timeout
    }
    
    /// 连接到指定主机和端口
    /// - Parameters:
    ///   - host: 主机名或IP地址
    ///   - port: 端口号
    ///   - useTLS: 是否使用TLS加密
    ///   - tlsConfig: TLS配置（当useTLS为true时使用）
    public func connect(to host: String, port: Int, useTLS: Bool, tlsConfig: TLSConfiguration = .secure) async throws {
        // 清理之前的连接
        await disconnect()
        
        if useTLS {
            // 使用TLS传输
            let transport = TLSTransport(timeout: connectionTimeout)
            try await transport.connect(to: host, port: port, tlsConfig: tlsConfig)
            tlsTransport = transport
        } else {
            // 使用TCP传输
            let transport = TCPTransport(timeout: connectionTimeout)
            try await transport.connect(to: host, port: port)
            tcpTransport = transport
        }
    }
    
    /// 断开连接
    public func disconnect() async {
        if let tcp = tcpTransport {
            await tcp.disconnect()
            tcpTransport = nil
        }
        if let tls = tlsTransport {
            await tls.disconnect()
            tlsTransport = nil
        }
    }
    
    /// 发送数据
    /// - Parameter data: 要发送的数据
    public func send(data: Data) async throws {
        if let tcp = tcpTransport {
            try await tcp.send(data: data)
        } else if let tls = tlsTransport {
            try await tls.send(data: data)
        } else {
            throw NetworkError.notConnected
        }
    }
    
    /// 接收数据
    /// - Returns: 接收到的数据
    public func receive() async throws -> Data {
        if let tcp = tcpTransport {
            return try await tcp.receive()
        } else if let tls = tlsTransport {
            return try await tls.receive()
        } else {
            throw NetworkError.notConnected
        }
    }
}