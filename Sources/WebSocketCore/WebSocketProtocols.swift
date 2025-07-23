import Foundation

// MARK: - 核心协议定义

/// WebSocket客户端协议 - 按照架构文档定义
public protocol WebSocketClientProtocol: AnyObject {
    func connect(to url: URL) async throws
    func send(message: WebSocketMessage) async throws
    func receive() async throws -> WebSocketMessage
    func close() async throws
}

/// 帧编解码器协议 - 按照架构文档定义
public protocol FrameCodecProtocol {
    func encode(message: WebSocketMessage) throws -> Data
    func decode(data: Data) throws -> [WebSocketFrame]
}

/// 状态管理器协议 - 按照架构文档定义
public protocol StateManagerProtocol {
    var currentState: WebSocketState { get async }
    func updateState(_ newState: WebSocketState) async
}