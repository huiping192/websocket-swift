import Foundation

/// WebSocket帧类型 - 严格按照RFC 6455定义
public enum FrameType: UInt8 {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA
    
    // 保留操作码 (0x3-0x7, 0xB-0xF)
    case reserved3 = 0x3
    case reserved4 = 0x4
    case reserved5 = 0x5
    case reserved6 = 0x6
    case reserved7 = 0x7
    case reservedB = 0xB
    case reservedC = 0xC
    case reservedD = 0xD
    case reservedE = 0xE
    case reservedF = 0xF
    
    /// 检查是否为数据帧
    public var isDataFrame: Bool {
        return self.rawValue <= 0x2
    }
    
    /// 检查是否为控制帧
    public var isControlFrame: Bool {
        return self.rawValue >= 0x8
    }
    
    /// 检查是否为保留操作码
    public var isReserved: Bool {
        switch self {
        case .reserved3, .reserved4, .reserved5, .reserved6, .reserved7,
             .reservedB, .reservedC, .reservedD, .reservedE, .reservedF:
            return true
        default:
            return false
        }
    }
    
    /// 从原始字节创建帧类型
    public init?(rawValue: UInt8) {
        switch rawValue {
        case 0x0: self = .continuation
        case 0x1: self = .text
        case 0x2: self = .binary
        case 0x8: self = .close
        case 0x9: self = .ping
        case 0xA: self = .pong
        case 0x3: self = .reserved3
        case 0x4: self = .reserved4
        case 0x5: self = .reserved5
        case 0x6: self = .reserved6
        case 0x7: self = .reserved7
        case 0xB: self = .reservedB
        case 0xC: self = .reservedC
        case 0xD: self = .reservedD
        case 0xE: self = .reservedE
        case 0xF: self = .reservedF
        default: return nil
        }
    }
}