import Foundation

/// 网络传输层模块
/// 负责TCP连接、TLS支持等底层网络操作
public struct NetworkTransport {
    
    /// 模块版本信息
    public static let version = "1.0.0"
    
    /// 初始化方法
    public init() {}
}

/// TCP连接状态
public enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case failed(Error)
}

/// 网络传输协议
public protocol NetworkTransportProtocol {
    func connect(to host: String, port: Int) async throws
    func disconnect() async
    func send(data: Data) async throws
    func receive() async throws -> Data
}