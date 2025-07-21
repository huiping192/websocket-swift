import Foundation
import Utilities

// MARK: - WebSocket掩码密钥工具

/// WebSocket掩码密钥生成工具
public struct WebSocketMaskingKey {
    
    /// 生成掩码密钥 - 兼容CryptoUtilities和架构设计
    public static func generate() -> UInt32 {
        let keyData = CryptoUtilities.generateMaskingKey()
        return CryptoUtilities.fromBigEndian(keyData, as: UInt32.self) ?? 0
    }
    
    /// 将UInt32掩码密钥转换为Data（用于CryptoUtilities）
    public static func toData(_ key: UInt32) -> Data {
        return CryptoUtilities.toBigEndian(key)
    }
}

// MARK: - 负载长度编码工具

/// WebSocket负载长度编码工具类
public struct WebSocketPayloadLength {
    
    /// 编码负载长度为字节数组
    public static func encode(_ length: UInt64) -> Data {
        var data = Data()
        
        if length <= 125 {
            // 7位长度
            data.append(UInt8(length))
        } else if length <= 65535 {
            // 7+16位长度
            data.append(126)
            data.append(contentsOf: CryptoUtilities.toBigEndian(UInt16(length)))
        } else {
            // 7+64位长度
            data.append(127)
            data.append(contentsOf: CryptoUtilities.toBigEndian(length))
        }
        
        return data
    }
    
    /// 从字节数组解码负载长度
    public static func decode(from data: Data, at offset: Int) throws -> (length: UInt64, bytesConsumed: Int) {
        guard offset < data.count else {
            throw WebSocketProtocolError.incompleteFrame
        }
        
        let firstByte = data[offset]
        let baseLength = firstByte & 0x7F
        
        if baseLength <= 125 {
            return (UInt64(baseLength), 1)
        } else if baseLength == 126 {
            // 16位扩展长度
            guard offset + 3 <= data.count else {
                throw WebSocketProtocolError.incompleteFrame
            }
            let lengthData = data.subdata(in: (offset + 1)..<(offset + 3))
            guard let length = CryptoUtilities.fromBigEndian(lengthData, as: UInt16.self) else {
                throw WebSocketProtocolError.invalidFrameFormat(description: "Invalid 16-bit length encoding")
            }
            return (UInt64(length), 3)
        } else if baseLength == 127 {
            // 64位扩展长度
            guard offset + 9 <= data.count else {
                throw WebSocketProtocolError.incompleteFrame
            }
            let lengthData = data.subdata(in: (offset + 1)..<(offset + 9))
            guard let length = CryptoUtilities.fromBigEndian(lengthData, as: UInt64.self) else {
                throw WebSocketProtocolError.invalidFrameFormat(description: "Invalid 64-bit length encoding")
            }
            // RFC 6455: 最高位必须为0
            if length & 0x8000000000000000 != 0 {
                throw WebSocketProtocolError.invalidFrameFormat(description: "Invalid payload length - MSB set")
            }
            return (length, 9)
        } else {
            throw WebSocketProtocolError.invalidFrameFormat(description: "Invalid payload length indicator")
        }
    }
}