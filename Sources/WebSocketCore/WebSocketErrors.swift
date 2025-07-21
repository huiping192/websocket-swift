import Foundation

/// WebSocket协议错误类型
public enum WebSocketProtocolError: Error {
    case invalidFrameFormat(description: String)
    case unsupportedOpcode(UInt8)
    case fragmentationViolation(description: String)
    case controlFrameTooLarge(size: UInt64)
    case invalidUTF8Text
    case maskingViolation(description: String)
    case payloadTooLarge(size: UInt64, limit: UInt64)
    case protocolViolation(description: String)
    case reservedBitsSet
    case unexpectedContinuation
    case incompleteFrame
    case bufferOverflow
}