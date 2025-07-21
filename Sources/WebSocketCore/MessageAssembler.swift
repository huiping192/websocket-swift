import Foundation

/// WebSocket消息组装器
/// 负责处理分片消息重组、控制帧插入和消息完整性验证
public final class MessageAssembler {
    
    /// 分片消息超时时间 (默认30秒)
    public static let defaultFragmentTimeout: TimeInterval = 30.0
    
    /// 当前正在组装的部分消息
    private var currentMessage: PartialMessage?
    
    /// 分片超时时间
    private let fragmentTimeout: TimeInterval
    
    /// 最大消息大小 (默认64MB)
    private let maxMessageSize: UInt64
    
    /// 初始化消息组装器
    /// - Parameters:
    ///   - fragmentTimeout: 分片超时时间
    ///   - maxMessageSize: 最大消息大小
    public init(fragmentTimeout: TimeInterval = defaultFragmentTimeout, 
                maxMessageSize: UInt64 = 64 * 1024 * 1024) {
        self.fragmentTimeout = fragmentTimeout
        self.maxMessageSize = maxMessageSize
    }
    
    /// 处理WebSocket帧并组装完整消息
    /// - Parameter frame: 输入的WebSocket帧
    /// - Returns: 完整的WebSocket消息（如果有），或nil（需要更多帧）
    /// - Throws: WebSocketProtocolError
    public func process(frame: WebSocketFrame) throws -> WebSocketMessage? {
        // 清理超时的分片消息
        try cleanupExpiredFragments()
        
        // 处理控制帧（立即返回）
        if frame.isControlFrame {
            return try processControlFrame(frame)
        }
        
        // 处理数据帧
        return try processDataFrame(frame)
    }
    
    /// 重置组装器状态
    public func reset() {
        currentMessage = nil
    }
    
    /// 检查是否有未完成的分片消息
    public var hasIncompleteMessage: Bool {
        return currentMessage != nil
    }
    
    // MARK: - Private Methods
    
    /// 处理控制帧
    private func processControlFrame(_ frame: WebSocketFrame) throws -> WebSocketMessage {
        switch frame.opcode {
        case .ping:
            return .ping(frame.payload.isEmpty ? nil : frame.payload)
        case .pong:
            return .pong(frame.payload.isEmpty ? nil : frame.payload)
        case .close:
            return try parseCloseFrame(frame)
        default:
            throw WebSocketProtocolError.protocolViolation(description: "Invalid control frame opcode: \(frame.opcode)")
        }
    }
    
    /// 处理数据帧
    private func processDataFrame(_ frame: WebSocketFrame) throws -> WebSocketMessage? {
        switch frame.opcode {
        case .text, .binary:
            return try processFirstFrame(frame)
        case .continuation:
            return try processContinuationFrame(frame)
        default:
            throw WebSocketProtocolError.protocolViolation(description: "Invalid data frame opcode: \(frame.opcode)")
        }
    }
    
    /// 处理首个数据帧
    private func processFirstFrame(_ frame: WebSocketFrame) throws -> WebSocketMessage? {
        // 如果已经有未完成的消息，这是协议错误
        if currentMessage != nil {
            throw WebSocketProtocolError.unexpectedContinuation
        }
        
        if frame.fin {
            // 单帧消息，直接返回
            return try createMessage(from: frame.opcode, data: frame.payload)
        } else {
            // 分片消息的开始
            currentMessage = PartialMessage(
                type: frame.opcode,
                fragments: [frame.payload],
                startTime: Date(),
                totalSize: UInt64(frame.payload.count)
            )
            return nil
        }
    }
    
    /// 处理继续帧
    private func processContinuationFrame(_ frame: WebSocketFrame) throws -> WebSocketMessage? {
        guard var message = currentMessage else {
            throw WebSocketProtocolError.unexpectedContinuation
        }
        
        // 检查消息大小限制
        let newTotalSize = message.totalSize + UInt64(frame.payload.count)
        if newTotalSize > maxMessageSize {
            currentMessage = nil
            throw WebSocketProtocolError.payloadTooLarge(size: newTotalSize, limit: maxMessageSize)
        }
        
        // 添加分片
        message.fragments.append(frame.payload)
        message.totalSize = newTotalSize
        
        if frame.fin {
            // 消息完成
            currentMessage = nil
            let completeData = message.fragments.reduce(Data()) { $0 + $1 }
            return try createMessage(from: message.type, data: completeData)
        } else {
            // 继续等待更多分片
            currentMessage = message
            return nil
        }
    }
    
    /// 创建WebSocket消息
    private func createMessage(from opcode: FrameType, data: Data) throws -> WebSocketMessage {
        switch opcode {
        case .text:
            guard let text = String(data: data, encoding: .utf8) else {
                throw WebSocketProtocolError.invalidUTF8Text
            }
            return .text(text)
        case .binary:
            return .binary(data)
        default:
            throw WebSocketProtocolError.protocolViolation(description: "Invalid message opcode: \(opcode)")
        }
    }
    
    /// 解析关闭帧
    private func parseCloseFrame(_ frame: WebSocketFrame) throws -> WebSocketMessage {
        let payload = frame.payload
        
        if payload.isEmpty {
            // 无状态码和原因的关闭帧
            return createCloseMessage(code: 1005, reason: "") // 1005 = No Status Rcvd
        }
        
        if payload.count == 1 {
            throw WebSocketProtocolError.invalidFrameFormat(description: "Invalid close frame payload length")
        }
        
        if payload.count >= 2 {
            // 解析状态码
            let statusCode = payload.withUnsafeBytes { bytes in
                UInt16(bigEndian: bytes.load(as: UInt16.self))
            }
            
            // 解析关闭原因
            var reason = ""
            if payload.count > 2 {
                let reasonData = payload.dropFirst(2)
                guard let reasonString = String(data: reasonData, encoding: .utf8) else {
                    throw WebSocketProtocolError.invalidUTF8Text
                }
                reason = reasonString
            }
            
            return createCloseMessage(code: statusCode, reason: reason)
        }
        
        throw WebSocketProtocolError.invalidFrameFormat(description: "Invalid close frame format")
    }
    
    /// 创建关闭消息
    private func createCloseMessage(code: UInt16, reason: String) -> WebSocketMessage {
        var closeData = Data()
        closeData.append(contentsOf: withUnsafeBytes(of: code.bigEndian) { Data($0) })
        if !reason.isEmpty {
            closeData.append(Data(reason.utf8))
        }
        return .binary(closeData) // 暂时使用binary表示close消息
    }
    
    /// 清理过期的分片消息
    private func cleanupExpiredFragments() throws {
        guard let message = currentMessage else { return }
        
        let elapsed = Date().timeIntervalSince(message.startTime)
        if elapsed > fragmentTimeout {
            currentMessage = nil
            throw WebSocketProtocolError.protocolViolation(description: "Fragment timeout exceeded")
        }
    }
}

// MARK: - Supporting Types

/// 部分消息（正在组装的分片消息）
private struct PartialMessage {
    /// 消息类型
    let type: FrameType
    
    /// 分片数据数组
    var fragments: [Data]
    
    /// 消息开始时间
    let startTime: Date
    
    /// 总大小
    var totalSize: UInt64
}