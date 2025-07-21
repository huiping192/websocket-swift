import Foundation

/// HTTP响应解析器
/// 负责解析WebSocket握手的HTTP响应
public struct ResponseParser {
    
    public init() {}
    
    /// 解析HTTP响应
    /// - Parameter responseString: 原始HTTP响应字符串
    /// - Returns: 解析结果
    public func parseResponse(_ responseString: String) -> ParseResult {
        guard !responseString.isEmpty else {
            return .failure(.emptyResponse)
        }
        
        let lines = responseString.components(separatedBy: "\r\n")
        
        guard !lines.isEmpty else {
            return .failure(.invalidFormat("响应格式无效"))
        }
        
        // 解析状态行
        guard let statusLine = parseStatusLine(lines[0]) else {
            return .failure(.invalidStatusLine)
        }
        
        // 解析头部
        let headers = parseHeaders(Array(lines.dropFirst()))
        
        let response = HTTPResponse(
            statusCode: statusLine.statusCode,
            statusText: statusLine.reasonPhrase,
            headers: headers
        )
        
        return .success(response)
    }
    
    /// 验证WebSocket握手响应
    /// - Parameters:
    ///   - response: 解析的HTTP响应
    ///   - expectedAccept: 期望的Accept密钥
    /// - Returns: 验证结果
    public func validateHandshakeResponse(
        _ response: HTTPResponse,
        expectedAccept: String
    ) -> HandshakeValidationResult {
        
        // 检查状态码
        guard response.statusCode == 101 else {
            return .invalid("状态码必须是101，实际是\(response.statusCode)")
        }
        
        // 检查必需的头部 (大小写不敏感)
        let requiredHeaders = ["upgrade", "connection", "sec-websocket-accept"]
        
        for headerName in requiredHeaders {
            guard getHeaderValue(response.headers, key: headerName) != nil else {
                return .invalid("缺失必需头部: \(headerName)")
            }
        }
        
        // 检查Upgrade头部
        guard let upgrade = getHeaderValue(response.headers, key: "upgrade"),
              upgrade.lowercased() == "websocket" else {
            return .invalid("Upgrade头部必须为websocket")
        }
        
        // 检查Connection头部
        guard let connection = getHeaderValue(response.headers, key: "connection"),
              connection.lowercased().contains("upgrade") else {
            return .invalid("Connection头部必须包含upgrade")
        }
        
        // 验证Accept密钥
        guard let accept = getHeaderValue(response.headers, key: "sec-websocket-accept"),
              accept == expectedAccept else {
            return .invalid("Sec-WebSocket-Accept密钥验证失败")
        }
        
        return .valid
    }
    
    // MARK: - 私有方法
    
    /// 解析HTTP状态行
    /// - Parameter statusLine: 状态行字符串
    /// - Returns: 解析的状态行信息
    private func parseStatusLine(_ statusLine: String) -> StatusLine? {
        let components = statusLine.components(separatedBy: " ")
        
        guard components.count >= 3,
              components[0].hasPrefix("HTTP/1.1"),
              let statusCode = Int(components[1]) else {
            return nil
        }
        
        let reasonPhrase = components.dropFirst(2).joined(separator: " ")
        
        return StatusLine(
            httpVersion: components[0],
            statusCode: statusCode,
            reasonPhrase: reasonPhrase
        )
    }
    
    /// 解析HTTP头部
    /// - Parameter lines: 头部行数组
    /// - Returns: 头部字典
    private func parseHeaders(_ lines: [String]) -> [String: String] {
        var headers: [String: String] = [:]
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // 空行表示头部结束
            if trimmedLine.isEmpty {
                break
            }
            
            // 解析头部行
            if let colonIndex = trimmedLine.firstIndex(of: ":") {
                let key = String(trimmedLine[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmedLine[trimmedLine.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        
        return headers
    }
    
    /// 大小写不敏感的头部值查找
    /// - Parameters:
    ///   - headers: 头部字典
    ///   - key: 头部名称（小写）
    /// - Returns: 头部值
    private func getHeaderValue(_ headers: [String: String], key: String) -> String? {
        // 首先尝试精确匹配
        if let value = headers[key] {
            return value
        }
        
        // 大小写不敏感查找
        let lowercaseKey = key.lowercased()
        for (headerKey, headerValue) in headers {
            if headerKey.lowercased() == lowercaseKey {
                return headerValue
            }
        }
        
        return nil
    }
}

// MARK: - 数据模型

/// HTTP响应
public struct HTTPResponse {
    /// 状态码
    public let statusCode: Int
    
    /// 状态文本
    public let statusText: String
    
    /// 头部字典
    public let headers: [String: String]
    
    public init(statusCode: Int, statusText: String, headers: [String: String]) {
        self.statusCode = statusCode
        self.statusText = statusText
        self.headers = headers
    }
}

/// 状态行
private struct StatusLine {
    let httpVersion: String
    let statusCode: Int
    let reasonPhrase: String
}

/// 解析结果
public enum ParseResult {
    case success(HTTPResponse)
    case failure(ParseError)
    
    /// 是否成功
    public var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
    
    /// 响应对象（如果成功）
    public var response: HTTPResponse? {
        if case .success(let response) = self {
            return response
        }
        return nil
    }
    
    /// 错误信息（如果失败）
    public var error: ParseError? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }
}

/// 解析错误
public enum ParseError: Error, Equatable {
    case emptyResponse
    case invalidFormat(String)
    case invalidStatusLine
    case unsupportedHttpVersion
    
    public var localizedDescription: String {
        switch self {
        case .emptyResponse:
            return "响应为空"
        case .invalidFormat(let reason):
            return "响应格式无效: \(reason)"
        case .invalidStatusLine:
            return "状态行格式无效"
        case .unsupportedHttpVersion:
            return "不支持的HTTP版本"
        }
    }
}

/// 握手验证结果
public enum HandshakeValidationResult {
    case valid
    case invalid(String)
    
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
}

// MARK: - 便利方法

extension ResponseParser {
    
    /// 从原始数据解析响应
    /// - Parameter data: 响应数据
    /// - Returns: 解析结果
    public func parseResponse(from data: Data) -> ParseResult {
        guard let responseString = String(data: data, encoding: .utf8) else {
            return .failure(.invalidFormat("无法解码为UTF-8字符串"))
        }
        
        return parseResponse(responseString)
    }
    
    /// 完整的握手响应验证
    /// - Parameters:
    ///   - data: 响应数据
    ///   - clientKey: 客户端密钥
    /// - Returns: 验证结果
    public func validateHandshakeResponse(
        from data: Data,
        clientKey: String
    ) -> HandshakeValidationResult {
        
        let parseResult = parseResponse(from: data)
        
        guard case .success(let response) = parseResult else {
            if let error = parseResult.error {
                return .invalid("解析失败: \(error.localizedDescription)")
            }
            return .invalid("未知解析错误")
        }
        
        // 计算期望的Accept密钥
        let requestBuilder = RequestBuilder()
        let expectedAccept = requestBuilder.computeWebSocketAccept(for: clientKey)
        
        return validateHandshakeResponse(response, expectedAccept: expectedAccept)
    }
}