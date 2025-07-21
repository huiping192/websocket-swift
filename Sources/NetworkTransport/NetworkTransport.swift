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
public enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(Error)
    
    public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.failed, .failed):
            return true  // 简化处理，不比较具体错误
        default:
            return false
        }
    }
}

/// 网络传输协议
public protocol NetworkTransportProtocol {
    func connect(to host: String, port: Int, useTLS: Bool, tlsConfig: TLSConfiguration) async throws
    func disconnect() async
    func send(data: Data) async throws
    func receive() async throws -> Data
}