import Foundation
import Utilities

/// HTTP升级请求构建器
/// 负责构建WebSocket握手的HTTP请求
public struct RequestBuilder {
    
    /// WebSocket协议版本
    public static let webSocketVersion = "13"
    
    public init() {}
    
    /// 构建WebSocket升级请求
    /// - Parameters:
    ///   - url: 目标URL
    ///   - protocols: 支持的子协议列表
    ///   - extensions: 支持的扩展列表
    ///   - additionalHeaders: 额外的HTTP头部
    /// - Returns: 完整的HTTP请求字符串
    public func buildUpgradeRequest(
        for url: URL,
        protocols: [String] = [],
        extensions: [String] = [],
        additionalHeaders: [String: String] = [:]
    ) -> String {
        
        guard url.host != nil else {
            fatalError("URL必须包含主机名")
        }
        
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        let fullPath = path + query
        let key = CryptoUtilities.generateWebSocketKey()
        
        var request = "GET \(fullPath) HTTP/1.1\r\n"
        
        // 基本头部
        request += "Host: \(formatHostHeader(url))\r\n"
        request += "Upgrade: websocket\r\n"
        request += "Connection: Upgrade\r\n"
        request += "Sec-WebSocket-Key: \(key)\r\n"
        request += "Sec-WebSocket-Version: \(Self.webSocketVersion)\r\n"
        
        // 可选的Origin头部（浏览器环境需要）
        if let origin = additionalHeaders["Origin"] {
            request += "Origin: \(origin)\r\n"
        }
        
        // 子协议
        if !protocols.isEmpty {
            let protocolString = protocols.joined(separator: ", ")
            request += "Sec-WebSocket-Protocol: \(protocolString)\r\n"
        }
        
        // 扩展
        if !extensions.isEmpty {
            let extensionString = extensions.joined(separator: ", ")
            request += "Sec-WebSocket-Extensions: \(extensionString)\r\n"
        }
        
        // 额外头部（跳过已处理的头部）
        let skipHeaders = Set(["Host", "Upgrade", "Connection", "Sec-WebSocket-Key", 
                              "Sec-WebSocket-Version", "Origin", "Sec-WebSocket-Protocol", 
                              "Sec-WebSocket-Extensions"])
        for (key, value) in additionalHeaders {
            if !skipHeaders.contains(key) {
                request += "\(key): \(value)\r\n"
            }
        }
        
        // 结束头部
        request += "\r\n"
        
        return request
    }
    
    // MARK: - 私有方法
    
    /// 格式化Host头部
    /// - Parameter url: URL
    /// - Returns: 格式化的Host头部值
    private func formatHostHeader(_ url: URL) -> String {
        guard let host = url.host else {
            return ""
        }
        
        let port = url.port
        let scheme = url.scheme?.lowercased()
        
        // 对于标准端口，不显示端口号
        let shouldShowPort: Bool = {
            if let port = port {
                switch scheme {
                case "ws":
                    return port != 80
                case "wss":
                    return port != 443
                case "http":
                    return port != 80
                case "https":
                    return port != 443
                default:
                    return true
                }
            }
            return false
        }()
        
        if shouldShowPort, let port = port {
            return "\(host):\(port)"
        } else {
            return host
        }
    }
    

}

// MARK: - WebSocket请求验证

extension RequestBuilder {
    
    /// 验证WebSocket请求格式
    /// - Parameter request: HTTP请求字符串
    /// - Returns: 验证结果
    public static func validateWebSocketRequest(_ request: String) -> ValidationResult {
        guard !request.isEmpty else {
            return .invalid("请求为空")
        }
        
        let lines = request.components(separatedBy: "\r\n")
        
        guard !lines.isEmpty, !lines[0].isEmpty else {
            return .invalid("无效的请求行")
        }
        
        // 检查请求行
        let requestLine = lines[0]
        let requestParts = requestLine.components(separatedBy: " ")
        
        guard requestParts.count >= 3,
              requestParts[0] == "GET",
              requestParts[2].hasPrefix("HTTP/1.1") else {
            return .invalid("无效的请求行")
        }
        
        // 解析头部
        let headers = parseHeaders(lines)
        
        // 检查必需的头部
        let requiredHeaders = [
            "Host", "Upgrade", "Connection", 
            "Sec-WebSocket-Key", "Sec-WebSocket-Version"
        ]
        
        for header in requiredHeaders {
            guard headers[header] != nil else {
                return .invalid("缺失必需头部: \(header)")
            }
        }
        
        // 检查头部值
        guard headers["Upgrade"]?.lowercased() == "websocket" else {
            return .invalid("Upgrade头部必须为websocket")
        }
        
        guard headers["Connection"]?.lowercased().contains("upgrade") == true else {
            return .invalid("Connection头部必须包含Upgrade")
        }
        
        guard headers["Sec-WebSocket-Version"] == webSocketVersion else {
            return .invalid("不支持的WebSocket版本")
        }
        
        // 验证密钥格式
        if let key = headers["Sec-WebSocket-Key"],
           Data(base64Encoded: key)?.count != 16 {
            return .invalid("无效的WebSocket密钥格式")
        }
        
        return .valid(headers)
    }
    
    /// 解析HTTP头部
    /// - Parameter lines: HTTP请求行数组
    /// - Returns: 头部字典
    private static func parseHeaders(_ lines: [String]) -> [String: String] {
        var headers: [String: String] = [:]
        
        for i in 1..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            
            // 空行表示头部结束
            if line.isEmpty {
                break
            }
            
            // 解析头部行
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        
        return headers
    }
}

// MARK: - 验证结果

/// 请求验证结果
public enum ValidationResult {
    case valid([String: String])  // 有效，包含解析的头部
    case invalid(String)          // 无效，包含错误信息
    
    /// 是否有效
    public var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }
    
    /// 错误信息（如果无效）
    public var errorMessage: String? {
        if case .invalid(let message) = self {
            return message
        }
        return nil
    }
    
    /// 解析的头部（如果有效）
    public var headers: [String: String]? {
        if case .valid(let headers) = self {
            return headers
        }
        return nil
    }
}
