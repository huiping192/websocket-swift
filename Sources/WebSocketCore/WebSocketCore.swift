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