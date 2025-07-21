import Foundation
import Utilities

/// WebSocket帧解码器
/// 负责将二进制数据解码为WebSocket帧，支持流式处理和不完整帧
public final class FrameDecoder {
    
    /// 解码状态
    private enum DecodeState {
        case waitingForHeader
        case waitingForExtendedLength(header: FrameHeaderData, lengthIndicator: UInt8)
        case waitingForMaskingKey(header: FrameHeaderData, payloadLength: UInt64)
        case waitingForPayload(header: FrameHeaderData, payloadLength: UInt64, maskingKey: UInt32?)
    }
    
    /// 最大帧大小限制 (默认16MB)
    public static let defaultMaxFrameSize: UInt64 = 16 * 1024 * 1024
    
    /// 当前解码状态
    private var state: DecodeState = .waitingForHeader
    
    /// 数据缓冲区
    private var buffer = Data()
    
    /// 最大帧大小
    private let maxFrameSize: UInt64
    
    /// 初始化解码器
    /// - Parameter maxFrameSize: 最大允许的帧大小
    public init(maxFrameSize: UInt64 = defaultMaxFrameSize) {
        self.maxFrameSize = maxFrameSize
    }
    
    /// 解码数据流为WebSocket帧
    /// - Parameter data: 新接收的数据
    /// - Returns: 解码得到的完整帧数组
    /// - Throws: WebSocketProtocolError
    public func decode(data: Data) throws -> [WebSocketFrame] {
        buffer.append(data)
        var frames: [WebSocketFrame] = []
        
        // 逐个解析帧，使用更安全的方式
        while true {
            // 检查是否有足够数据解析下一个帧
            guard !buffer.isEmpty else { break }
            
            let originalBufferCount = buffer.count
            let result = try processBuffer()
            
            switch result {
            case .frame(let frame):
                frames.append(frame)
                
                // 确保状态完全重置
                state = .waitingForHeader
                
                // 安全检查：确保缓冲区真的被消费了
                if buffer.count >= originalBufferCount {
                    throw WebSocketProtocolError.protocolViolation(description: "Buffer not consumed after frame decode")
                }
                
            case .needMoreData:
                // 没有足够数据解析下一个完整帧，停止处理
                break
            }
        }
        
        return frames
    }
    
    /// 重置解码器状态
    public func reset() {
        state = .waitingForHeader
        buffer.removeAll()
    }
    
    // MARK: - Private Methods
    
    /// 处理结果
    private enum ProcessResult {
        case frame(WebSocketFrame)
        case needMoreData
    }
    
    /// 处理缓冲区数据
    private func processBuffer() throws -> ProcessResult {
        switch state {
        case .waitingForHeader:
            return try processHeader()
        case .waitingForExtendedLength(let header, let lengthIndicator):
            return try processExtendedLength(header: header, lengthIndicator: lengthIndicator)
        case .waitingForMaskingKey(let header, let payloadLength):
            return try processMaskingKey(header: header, payloadLength: payloadLength)
        case .waitingForPayload(let header, let payloadLength, let maskingKey):
            return try processPayload(header: header, payloadLength: payloadLength, maskingKey: maskingKey)
        }
    }
    
    /// 处理帧头
    private func processHeader() throws -> ProcessResult {
        guard buffer.count >= 2 else {
            return .needMoreData
        }
        
        let firstByte = buffer[0]
        let secondByte = buffer[1]
        
        // 解析基本头部信息
        let fin = (firstByte & 0x80) != 0
        let rsv1 = (firstByte & 0x40) != 0
        let rsv2 = (firstByte & 0x20) != 0
        let rsv3 = (firstByte & 0x10) != 0
        let opcodeValue = firstByte & 0x0F
        let masked = (secondByte & 0x80) != 0
        let payloadLengthIndicator = secondByte & 0x7F
        
        // 验证操作码
        guard let opcode = FrameType(rawValue: opcodeValue) else {
            throw WebSocketProtocolError.unsupportedOpcode(opcodeValue)
        }
        
        // 验证保留位
        if rsv1 || rsv2 || rsv3 {
            throw WebSocketProtocolError.reservedBitsSet
        }
        
        // 验证保留操作码
        if opcode.isReserved {
            throw WebSocketProtocolError.unsupportedOpcode(opcodeValue)
        }
        
        let headerData = FrameHeaderData(
            fin: fin,
            rsv1: rsv1,
            rsv2: rsv2,
            rsv3: rsv3,
            opcode: opcode,
            masked: masked
        )
        
        // 根据负载长度指示符决定下一步
        if payloadLengthIndicator <= 125 {
            let payloadLength = UInt64(payloadLengthIndicator)
            try validatePayloadLength(payloadLength, opcode: opcode)
            
            if masked {
                state = .waitingForMaskingKey(header: headerData, payloadLength: payloadLength)
            } else {
                state = .waitingForPayload(header: headerData, payloadLength: payloadLength, maskingKey: nil)
            }
            
            // 消费已处理的字节
            buffer.removeFirst(2)
            
        } else if payloadLengthIndicator == 126 {
            state = .waitingForExtendedLength(header: headerData, lengthIndicator: 126)
            buffer.removeFirst(2)
        } else { // payloadLengthIndicator == 127
            state = .waitingForExtendedLength(header: headerData, lengthIndicator: 127)
            buffer.removeFirst(2)
        }
        
        return try processBuffer()
    }
    
    /// 处理扩展长度
    private func processExtendedLength(header: FrameHeaderData, lengthIndicator: UInt8) throws -> ProcessResult {
        if lengthIndicator == 126 {
            // 16位长度
            guard buffer.count >= 2 else {
                return .needMoreData
            }
            
            let lengthData = buffer.prefix(2)
            guard let length = CryptoUtilities.fromBigEndian(lengthData, as: UInt16.self) else {
                throw WebSocketProtocolError.invalidFrameFormat(description: "Invalid 16-bit length encoding")
            }
            
            let payloadLength = UInt64(length)
            try validatePayloadLength(payloadLength, opcode: header.opcode)
            
            buffer.removeFirst(2)
            
            if header.masked {
                state = .waitingForMaskingKey(header: header, payloadLength: payloadLength)
            } else {
                state = .waitingForPayload(header: header, payloadLength: payloadLength, maskingKey: nil)
            }
            
        } else { // lengthIndicator == 127
            // 64位长度
            guard buffer.count >= 8 else {
                return .needMoreData
            }
            
            let lengthData = buffer.prefix(8)
            guard let length = CryptoUtilities.fromBigEndian(lengthData, as: UInt64.self) else {
                throw WebSocketProtocolError.invalidFrameFormat(description: "Invalid 64-bit length encoding")
            }
            
            // 验证最高位
            if length & 0x8000000000000000 != 0 {
                throw WebSocketProtocolError.invalidFrameFormat(description: "Invalid payload length - MSB set")
            }
            
            try validatePayloadLength(length, opcode: header.opcode)
            
            buffer.removeFirst(8)
            
            if header.masked {
                state = .waitingForMaskingKey(header: header, payloadLength: length)
            } else {
                state = .waitingForPayload(header: header, payloadLength: length, maskingKey: nil)
            }
        }
        
        return try processBuffer()
    }
    
    /// 处理掩码密钥
    private func processMaskingKey(header: FrameHeaderData, payloadLength: UInt64) throws -> ProcessResult {
        guard buffer.count >= 4 else {
            return .needMoreData
        }
        
        let maskingKeyData = buffer.prefix(4)
        guard let maskingKey = CryptoUtilities.fromBigEndian(maskingKeyData, as: UInt32.self) else {
            throw WebSocketProtocolError.invalidFrameFormat(description: "Invalid masking key")
        }
        
        buffer.removeFirst(4)
        state = .waitingForPayload(header: header, payloadLength: payloadLength, maskingKey: maskingKey)
        
        return try processBuffer()
    }
    
    /// 处理负载数据
    private func processPayload(header: FrameHeaderData, payloadLength: UInt64, maskingKey: UInt32?) throws -> ProcessResult {
        guard buffer.count >= payloadLength else {
            return .needMoreData
        }
        
        // 使用直接传入的header数据
        var payload = buffer.prefix(Int(payloadLength))
        
        // 如果有掩码，移除掩码
        if let maskingKey = maskingKey {
            let maskingKeyData = WebSocketMaskingKey.toData(maskingKey)
            payload = CryptoUtilities.removeMask(payload, maskingKey: maskingKeyData)
        }
        
        // 验证文本帧的UTF-8编码（只对文本帧进行验证，continuation帧的验证应该在MessageAssembler中进行）
        if header.opcode == .text {
            if String(data: payload, encoding: .utf8) == nil {
                throw WebSocketProtocolError.invalidUTF8Text
            }
        }
        
        let frame = try WebSocketFrame(
            fin: header.fin,
            rsv1: header.rsv1,
            rsv2: header.rsv2,
            rsv3: header.rsv3,
            opcode: header.opcode,
            masked: header.masked,
            payload: Data(payload),
            maskingKey: maskingKey
        )
        
        buffer.removeFirst(Int(payloadLength))
        
        return .frame(frame)
    }
    
    /// 验证负载长度
    private func validatePayloadLength(_ length: UInt64, opcode: FrameType) throws {
        // 检查帧大小限制
        if length > maxFrameSize {
            throw WebSocketProtocolError.payloadTooLarge(size: length, limit: maxFrameSize)
        }
        
        // 控制帧长度限制
        if opcode.isControlFrame && length > 125 {
            throw WebSocketProtocolError.controlFrameTooLarge(size: length)
        }
    }
    
    // MARK: - Helper Types and Methods
    
    /// 帧头部数据
    private struct FrameHeaderData {
        let fin: Bool
        let rsv1: Bool
        let rsv2: Bool
        let rsv3: Bool
        let opcode: FrameType
        let masked: Bool
    }
    
    /// 编码帧头数据
    private func encode(_ headerData: FrameHeaderData) throws -> Data {
        var data = Data(capacity: 2)
        
        let firstByte: UInt8 = (headerData.fin ? 0x80 : 0) |
                               (headerData.rsv1 ? 0x40 : 0) |
                               (headerData.rsv2 ? 0x20 : 0) |
                               (headerData.rsv3 ? 0x10 : 0) |
                               headerData.opcode.rawValue
        
        let secondByte: UInt8 = (headerData.masked ? 0x80 : 0) | 0x00 // 长度会在其他地方处理
        
        data.append(firstByte)
        data.append(secondByte)
        
        return data
    }
    
    /// 解码帧头数据
    private func decode(_ headerData: Data) throws -> FrameHeaderData {
        guard headerData.count >= 2 else {
            throw WebSocketProtocolError.invalidFrameFormat(description: "Incomplete header data")
        }
        
        let firstByte = headerData[0]
        let secondByte = headerData[1]
        
        let fin = (firstByte & 0x80) != 0
        let rsv1 = (firstByte & 0x40) != 0
        let rsv2 = (firstByte & 0x20) != 0
        let rsv3 = (firstByte & 0x10) != 0
        let opcodeValue = firstByte & 0x0F
        let masked = (secondByte & 0x80) != 0
        
        guard let opcode = FrameType(rawValue: opcodeValue) else {
            throw WebSocketProtocolError.unsupportedOpcode(opcodeValue)
        }
        
        return FrameHeaderData(
            fin: fin,
            rsv1: rsv1,
            rsv2: rsv2,
            rsv3: rsv3,
            opcode: opcode,
            masked: masked
        )
    }
}

// MARK: - FrameCodecProtocol Implementation

extension FrameDecoder: FrameCodecProtocol {
    /// FrameCodecProtocol的encode方法 - 解码器不实现编码
    public func encode(message: WebSocketMessage) throws -> Data {
        throw WebSocketProtocolError.protocolViolation(description: "FrameDecoder does not support encoding")
    }
}
