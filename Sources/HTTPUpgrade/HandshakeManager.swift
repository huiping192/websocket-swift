import Foundation
import NetworkTransport
import Utilities

/// WebSocket握手管理器
/// 负责完整的WebSocket握手流程
public final class HandshakeManager: HandshakeManagerProtocol {
    
    /// 握手超时时间（秒）
    public let handshakeTimeout: TimeInterval
    
    /// 请求构建器
    private let requestBuilder: RequestBuilder
    
    /// 响应解析器
    private let responseParser: ResponseParser
    
    /// 初始化握手管理器
    /// - Parameter handshakeTimeout: 握手超时时间，默认10秒
    public init(handshakeTimeout: TimeInterval = 10.0) {
        self.handshakeTimeout = handshakeTimeout
        self.requestBuilder = RequestBuilder()
        self.responseParser = ResponseParser()
    }
    
    /// 执行WebSocket握手
    /// - Parameters:
    ///   - url: WebSocket URL
    ///   - transport: 网络传输层
    ///   - protocols: 支持的子协议列表
    ///   - extensions: 支持的扩展列表
    ///   - additionalHeaders: 额外的HTTP头部
    /// - Returns: 握手结果
    public func performHandshake(
        url: URL,
        transport: NetworkTransportProtocol,
        protocols: [String] = [],
        extensions: [String] = [],
        additionalHeaders: [String: String] = [:]
    ) async throws -> HandshakeResult {
        
        // 1. 构建握手请求
        let request = requestBuilder.buildUpgradeRequest(
            for: url,
            protocols: protocols,
            extensions: extensions,
            additionalHeaders: additionalHeaders
        )
        
        // 提取客户端密钥用于后续验证
        let clientKey = extractClientKey(from: request)
        
        // 2. 发送握手请求
        guard let requestData = request.data(using: .utf8) else {
            throw HandshakeError.invalidRequest("无法编码请求为UTF-8")
        }
        
        try await transport.send(data: requestData)
        
        // 3. 接收握手响应（带超时）
        let responseData = try await withTimeout(handshakeTimeout) {
            try await transport.receive()
        }
        
        // 4. 解析和验证响应
        let validationResult = responseParser.validateHandshakeResponse(
            from: responseData,
            clientKey: clientKey
        )
        
        guard validationResult.isValid else {
            let errorMessage = validationResult.errorMessage ?? "未知验证错误"
            throw HandshakeError.validationFailed(errorMessage)
        }
        
        // 5. 解析响应以获取协商结果
        let parseResult = responseParser.parseResponse(from: responseData)
        
        guard case .success(let response) = parseResult else {
            let error = parseResult.error?.localizedDescription ?? "未知解析错误"
            throw HandshakeError.parseFailed(error)
        }
        
        // 6. 构建握手结果
        let negotiatedProtocol = response.headers["Sec-WebSocket-Protocol"]
        let negotiatedExtensions = parseExtensions(response.headers["Sec-WebSocket-Extensions"])
        
        return HandshakeResult(
            success: true,
            negotiatedProtocol: negotiatedProtocol,
            negotiatedExtensions: negotiatedExtensions,
            serverHeaders: response.headers
        )
    }
    
    // MARK: - 私有方法
    
    /// 从请求中提取客户端密钥
    /// - Parameter request: HTTP请求字符串
    /// - Returns: 客户端密钥
    private func extractClientKey(from request: String) -> String {
        let lines = request.components(separatedBy: "\r\n")
        
        for line in lines {
            if line.hasPrefix("Sec-WebSocket-Key:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        // 如果无法提取，生成一个新的密钥作为备用
        return CryptoUtilities.generateWebSocketKey()
    }
    
    /// 解析扩展字符串
    /// - Parameter extensionsString: 扩展字符串
    /// - Returns: 扩展数组
    private func parseExtensions(_ extensionsString: String?) -> [String] {
        guard let extensionsString = extensionsString else {
            return []
        }
        
        return extensionsString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    /// 超时包装器
    /// - Parameters:
    ///   - timeout: 超时时间
    ///   - operation: 异步操作
    /// - Returns: 操作结果
    private func withTimeout<T>(
        _ timeout: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        
        return try await withThrowingTaskGroup(of: T.self) { group in
            
            // 添加主要操作
            group.addTask {
                try await operation()
            }
            
            // 添加超时任务
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw HandshakeError.timeout
            }
            
            // 返回第一个完成的结果
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - 协议定义

/// 握手管理器协议
public protocol HandshakeManagerProtocol {
    
    /// 执行WebSocket握手
    /// - Parameters:
    ///   - url: WebSocket URL
    ///   - transport: 网络传输层
    ///   - protocols: 支持的子协议列表
    ///   - extensions: 支持的扩展列表
    ///   - additionalHeaders: 额外的HTTP头部
    /// - Returns: 握手结果
    func performHandshake(
        url: URL,
        transport: NetworkTransportProtocol,
        protocols: [String],
        extensions: [String],
        additionalHeaders: [String: String]
    ) async throws -> HandshakeResult
}

// MARK: - 数据模型

/// 握手结果
public struct HandshakeResult {
    /// 握手是否成功
    public let success: Bool
    
    /// 协商的子协议
    public let negotiatedProtocol: String?
    
    /// 协商的扩展
    public let negotiatedExtensions: [String]
    
    /// 服务器响应头部
    public let serverHeaders: [String: String]
    
    public init(
        success: Bool,
        negotiatedProtocol: String? = nil,
        negotiatedExtensions: [String] = [],
        serverHeaders: [String: String] = [:]
    ) {
        self.success = success
        self.negotiatedProtocol = negotiatedProtocol
        self.negotiatedExtensions = negotiatedExtensions
        self.serverHeaders = serverHeaders
    }
}

/// 握手错误
public enum HandshakeError: Error, LocalizedError {
    case invalidRequest(String)
    case timeout
    case validationFailed(String)
    case parseFailed(String)
    case networkError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason):
            return "无效的握手请求: \(reason)"
        case .timeout:
            return "握手超时"
        case .validationFailed(let reason):
            return "握手验证失败: \(reason)"
        case .parseFailed(let reason):
            return "响应解析失败: \(reason)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .invalidRequest:
            return "检查URL和请求参数是否正确"
        case .timeout:
            return "检查网络连接或增加超时时间"
        case .validationFailed:
            return "检查服务器响应是否符合WebSocket协议"
        case .parseFailed:
            return "检查服务器响应格式是否正确"
        case .networkError:
            return "检查网络连接状态"
        }
    }
}

// MARK: - 便利方法

extension HandshakeManager {
    
    /// 执行简单的WebSocket握手（无子协议和扩展）
    /// - Parameters:
    ///   - url: WebSocket URL
    ///   - transport: 网络传输层
    /// - Returns: 握手结果
    public func performSimpleHandshake(
        url: URL,
        transport: NetworkTransportProtocol
    ) async throws -> HandshakeResult {
        return try await performHandshake(
            url: url,
            transport: transport,
            protocols: [],
            extensions: [],
            additionalHeaders: [:]
        )
    }
    
    /// 执行带子协议的WebSocket握手
    /// - Parameters:
    ///   - url: WebSocket URL
    ///   - transport: 网络传输层
    ///   - protocols: 支持的子协议列表
    /// - Returns: 握手结果
    public func performHandshake(
        url: URL,
        transport: NetworkTransportProtocol,
        protocols: [String]
    ) async throws -> HandshakeResult {
        return try await performHandshake(
            url: url,
            transport: transport,
            protocols: protocols,
            extensions: [],
            additionalHeaders: [:]
        )
    }
}