import Foundation

/// HTTP升级握手模块
/// 负责WebSocket握手协议的实现
public struct HTTPUpgrade {
    
    /// 模块版本信息
    public static let version = "1.0.0"
    
    /// 初始化方法
    public init() {}
}

/// WebSocket握手状态
public enum HandshakeState {
    case initial
    case requestSent
    case responseReceived
    case completed
    case failed(Error)
}

/// HTTP升级请求
public struct UpgradeRequest {
    public let host: String
    public let path: String
    public let key: String
    public let protocols: [String]
    
    public init(host: String, path: String = "/", protocols: [String] = []) {
        self.host = host
        self.path = path
        self.key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        self.protocols = protocols
    }
}

/// HTTP升级响应
public struct UpgradeResponse {
    public let statusCode: Int
    public let headers: [String: String]
    public let acceptKey: String?
    
    public init(statusCode: Int, headers: [String: String]) {
        self.statusCode = statusCode
        self.headers = headers
        self.acceptKey = headers["Sec-WebSocket-Accept"]
    }
}