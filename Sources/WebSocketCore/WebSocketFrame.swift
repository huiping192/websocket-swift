import Foundation
import Utilities

/// WebSocket帧结构体
public struct WebSocketFrame {
    /// 最终帧标志 (FIN bit)
    public let fin: Bool
    
    /// 保留位1 (RSV1 bit) - 用于扩展
    public let rsv1: Bool
    
    /// 保留位2 (RSV2 bit) - 用于扩展  
    public let rsv2: Bool
    
    /// 保留位3 (RSV3 bit) - 用于扩展
    public let rsv3: Bool
    
    /// 操作码 (Opcode)
    public let opcode: FrameType
    
    /// 掩码标志 (MASK bit)
    public let masked: Bool
    
    /// 负载长度 (Payload Length)
    public let payloadLength: UInt64
    
    /// 掩码密钥 (Masking Key) - 仅当masked为true时存在，按照架构文档定义为UInt32
    public let maskingKey: UInt32?
    
    /// 负载数据 (Payload Data)
    public let payload: Data
    
    /// 初始化WebSocket帧
    public init(
        fin: Bool,
        rsv1: Bool = false,
        rsv2: Bool = false, 
        rsv3: Bool = false,
        opcode: FrameType,
        masked: Bool,
        payload: Data,
        maskingKey: UInt32? = nil
    ) throws {
        self.fin = fin
        self.rsv1 = rsv1
        self.rsv2 = rsv2
        self.rsv3 = rsv3
        self.opcode = opcode
        self.masked = masked
        self.payloadLength = UInt64(payload.count)
        self.payload = payload
        
        // 验证掩码密钥
        if masked && maskingKey == nil {
            throw WebSocketProtocolError.maskingViolation(description: "Masked frame must have masking key")
        }
        if !masked && maskingKey != nil {
            throw WebSocketProtocolError.maskingViolation(description: "Unmasked frame must not have masking key")
        }
        self.maskingKey = maskingKey
        
        // 验证控制帧约束
        if opcode.isControlFrame {
            if !fin {
                throw WebSocketProtocolError.fragmentationViolation(description: "Control frames must not be fragmented")
            }
            if payloadLength > 125 {
                throw WebSocketProtocolError.controlFrameTooLarge(size: payloadLength)
            }
        }
        
        // 验证保留位
        if (rsv1 || rsv2 || rsv3) {
            throw WebSocketProtocolError.reservedBitsSet
        }
        
        // 验证保留操作码
        if opcode.isReserved {
            throw WebSocketProtocolError.unsupportedOpcode(opcode.rawValue)
        }
    }
    
    /// 检查帧是否完整
    public var isComplete: Bool {
        return fin
    }
    
    /// 检查是否为数据帧
    public var isDataFrame: Bool {
        return opcode.isDataFrame
    }
    
    /// 检查是否为控制帧
    public var isControlFrame: Bool {
        return opcode.isControlFrame
    }
    
    /// 获取掩码密钥的Data表示（用于与CryptoUtilities兼容）
    public var maskingKeyData: Data? {
        guard let key = maskingKey else { return nil }
        return WebSocketMaskingKey.toData(key)
    }
}