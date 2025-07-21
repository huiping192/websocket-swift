import Foundation

/// WebSocket核心模块
/// 实现WebSocket协议的核心功能
public struct WebSocketCore {
    
    /// 模块版本信息
    public static let version = "1.0.0"
    
    /// 初始化方法
    public init() {}
}

/// WebSocket连接状态
public enum WebSocketState {
    case connecting
    case open
    case closing
    case closed
}

/// WebSocket消息类型
public enum WebSocketMessage {
    case text(String)
    case binary(Data)
    case ping(Data?)
    case pong(Data?)
}

/// WebSocket帧类型
public enum FrameType: UInt8 {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA
}

/// WebSocket客户端协议
public protocol WebSocketClientProtocol {
    func connect(to url: URL) async throws
    func send(message: WebSocketMessage) async throws
    func receive() async throws -> WebSocketMessage
    func close() async throws
}