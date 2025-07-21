import Foundation
import Utilities

/// WebSocket帧编码器
/// 负责将WebSocket消息编码为符合RFC 6455标准的二进制帧数据
public final class FrameEncoder {
    
    /// 默认最大帧大小 (64KB)
    public static let defaultMaxFrameSize = 65536
    
    /// 最大帧大小
    private let maxFrameSize: Int
    
    /// 初始化编码器
    /// - Parameter maxFrameSize: 最大帧大小，用于大消息分片
    public init(maxFrameSize: Int = defaultMaxFrameSize) {
        self.maxFrameSize = maxFrameSize
    }
    
    /// 编码WebSocket消息为帧序列
    /// - Parameter message: 要编码的WebSocket消息
    /// - Returns: 编码后的帧序列
    /// - Throws: WebSocketProtocolError
    public func encodeToFrames(message: WebSocketMessage) throws -> [WebSocketFrame] {
        switch message {
        case .text(let text):
            let data = Data(text.utf8)
            return try encodeDataMessage(data: data, opcode: .text)
            
        case .binary(let data):
            return try encodeDataMessage(data: data, opcode: .binary)
            
        case .ping(let data):
            return [try encodeControlFrame(opcode: .ping, payload: data ?? Data())]
            
        case .pong(let data):
            return [try encodeControlFrame(opcode: .pong, payload: data ?? Data())]
        }
    }
    
    /// 编码单个帧为二进制数据
    /// - Parameter frame: 要编码的WebSocket帧
    /// - Returns: 编码后的二进制数据
    /// - Throws: WebSocketProtocolError
    public func encodeFrame(_ frame: WebSocketFrame) throws -> Data {
        var data = Data()
        
        // 1. 构建帧头
        data.append(contentsOf: try buildFrameHeader(frame))
        
        // 2. 添加负载数据（如果有掩码，需要先掩码处理）
        if frame.masked, let maskingKey = frame.maskingKey {
            let maskingKeyData = WebSocketMaskingKey.toData(maskingKey)
            let maskedPayload = CryptoUtilities.applyMask(frame.payload, maskingKey: maskingKeyData)
            data.append(maskedPayload)
        } else {
            data.append(frame.payload)
        }
        
        return data
    }
    
    // MARK: - Private Methods
    
    /// 编码数据消息（支持分片）
    private func encodeDataMessage(data: Data, opcode: FrameType) throws -> [WebSocketFrame] {
        guard !data.isEmpty || opcode == .text || opcode == .binary else {
            throw WebSocketProtocolError.invalidFrameFormat(description: "Data frames cannot be empty except for text/binary")
        }
        
        // 如果数据小于最大帧大小，发送单帧
        if data.count <= maxFrameSize {
            let frame = try WebSocketFrame(
                fin: true,
                opcode: opcode,
                masked: true,
                payload: data,
                maskingKey: WebSocketMaskingKey.generate()
            )
            return [frame]
        }
        
        // 大消息需要分片
        return try createFragmentedFrames(data: data, opcode: opcode)
    }
    
    /// 编码控制帧
    private func encodeControlFrame(opcode: FrameType, payload: Data) throws -> WebSocketFrame {
        // 控制帧负载不能超过125字节
        guard payload.count <= 125 else {
            throw WebSocketProtocolError.controlFrameTooLarge(size: UInt64(payload.count))
        }
        
        return try WebSocketFrame(
            fin: true,
            opcode: opcode,
            masked: true,
            payload: payload,
            maskingKey: WebSocketMaskingKey.generate()
        )
    }
    
    /// 创建分片帧序列
    private func createFragmentedFrames(data: Data, opcode: FrameType) throws -> [WebSocketFrame] {
        var frames: [WebSocketFrame] = []
        var offset = 0
        let totalSize = data.count
        
        while offset < totalSize {
            let chunkSize = min(maxFrameSize, totalSize - offset)
            let chunk = data.subdata(in: offset..<(offset + chunkSize))
            let isFirst = offset == 0
            let isLast = (offset + chunkSize) >= totalSize
            
            let frame = try WebSocketFrame(
                fin: isLast,
                opcode: isFirst ? opcode : .continuation,
                masked: true,
                payload: chunk,
                maskingKey: WebSocketMaskingKey.generate()
            )
            
            frames.append(frame)
            offset += chunkSize
        }
        
        return frames
    }
    
    /// 构建WebSocket帧头
    private func buildFrameHeader(_ frame: WebSocketFrame) throws -> Data {
        var header = Data()
        
        // 第一字节: FIN + RSV + Opcode
        let firstByte: UInt8 = (frame.fin ? 0x80 : 0) |
                              (frame.rsv1 ? 0x40 : 0) |
                              (frame.rsv2 ? 0x20 : 0) |
                              (frame.rsv3 ? 0x10 : 0) |
                              frame.opcode.rawValue
        header.append(firstByte)
        
        // 第二字节及后续: MASK + Payload Length
        let payloadLength = frame.payloadLength
        if payloadLength <= 125 {
            let secondByte: UInt8 = (frame.masked ? 0x80 : 0) | UInt8(payloadLength)
            header.append(secondByte)
        } else if payloadLength <= 65535 {
            let secondByte: UInt8 = (frame.masked ? 0x80 : 0) | 126
            header.append(secondByte)
            header.append(contentsOf: CryptoUtilities.toBigEndian(UInt16(payloadLength)))
        } else {
            let secondByte: UInt8 = (frame.masked ? 0x80 : 0) | 127
            header.append(secondByte)
            header.append(contentsOf: CryptoUtilities.toBigEndian(payloadLength))
        }
        
        // 掩码密钥（如果需要）
        if frame.masked, let maskingKey = frame.maskingKey {
            header.append(contentsOf: CryptoUtilities.toBigEndian(maskingKey))
        }
        
        return header
    }
}

// MARK: - FrameCodecProtocol Implementation

extension FrameEncoder: FrameCodecProtocol {
    /// 实现FrameCodecProtocol的encode方法
    public func encode(message: WebSocketMessage) throws -> Data {
        let frames = try encodeToFrames(message: message)
        var data = Data()
        
        for frame in frames {
            data.append(try encodeFrame(frame))
        }
        
        return data
    }
    
    /// FrameCodecProtocol的decode方法 - 编码器不实现解码
    public func decode(data: Data) throws -> [WebSocketFrame] {
        throw WebSocketProtocolError.protocolViolation(description: "FrameEncoder does not support decoding")
    }
}