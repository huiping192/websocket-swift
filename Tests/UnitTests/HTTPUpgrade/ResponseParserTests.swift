import XCTest
@testable import HTTPUpgrade

/// ResponseParser单元测试
final class ResponseParserTests: XCTestCase {
    
    var responseParser: ResponseParser!
    
    override func setUp() {
        super.setUp()
        responseParser = ResponseParser()
    }
    
    override func tearDown() {
        responseParser = nil
        super.tearDown()
    }
    
    /// 测试成功的握手响应解析
    func testSuccessfulHandshakeResponse() {
        let responseString = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r
        \r

        """
        
        let result = responseParser.parseResponse(responseString)
        
        XCTAssertTrue(result.isSuccess)
        
        guard let response = result.response else {
            XCTFail("应该解析成功")
            return
        }
        
        XCTAssertEqual(response.statusCode, 101)
        XCTAssertEqual(response.statusText, "Switching Protocols")
        XCTAssertEqual(response.headers["Upgrade"], "websocket")
        XCTAssertEqual(response.headers["Connection"], "Upgrade")
        XCTAssertEqual(response.headers["Sec-WebSocket-Accept"], "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }
    
    /// 测试带有额外头部的响应解析
    func testResponseWithAdditionalHeaders() {
        let responseString = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r
        Server: nginx/1.18.0\r
        Date: Tue, 19 Dec 2023 10:30:00 GMT\r
        Sec-WebSocket-Protocol: chat\r
        \r

        """
        
        let result = responseParser.parseResponse(responseString)
        
        XCTAssertTrue(result.isSuccess)
        
        guard let response = result.response else {
            XCTFail("应该解析成功")
            return
        }
        
        XCTAssertEqual(response.headers["Server"], "nginx/1.18.0")
        XCTAssertEqual(response.headers["Date"], "Tue, 19 Dec 2023 10:30:00 GMT")
        XCTAssertEqual(response.headers["Sec-WebSocket-Protocol"], "chat")
    }
    
    /// 测试错误状态码响应
    func testErrorStatusCodeResponse() {
        let responseString = """
        HTTP/1.1 400 Bad Request\r
        Content-Type: text/plain\r
        Content-Length: 11\r
        \r
        Bad Request
        """
        
        let result = responseParser.parseResponse(responseString)
        
        XCTAssertTrue(result.isSuccess)
        
        guard let response = result.response else {
            XCTFail("应该解析成功")
            return
        }
        
        XCTAssertEqual(response.statusCode, 400)
        XCTAssertEqual(response.statusText, "Bad Request")
        XCTAssertEqual(response.headers["Content-Type"], "text/plain")
    }
    
    /// 测试空响应
    func testEmptyResponse() {
        let result = responseParser.parseResponse("")
        
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.error, .emptyResponse)
    }
    
    /// 测试无效状态行
    func testInvalidStatusLine() {
        let responseString = """
        Invalid Status Line\r
        Upgrade: websocket\r
        \r

        """
        
        let result = responseParser.parseResponse(responseString)
        
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.error, .invalidStatusLine)
    }
    
    /// 测试不完整的状态行
    func testIncompleteStatusLine() {
        let responseString = """
        HTTP/1.1\r
        Upgrade: websocket\r
        \r

        """
        
        let result = responseParser.parseResponse(responseString)
        
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.error, .invalidStatusLine)
    }
    
    /// 测试有效握手响应验证
    func testValidHandshakeValidation() {
        let response = HTTPResponse(
            statusCode: 101,
            statusText: "Switching Protocols",
            headers: [
                "Upgrade": "websocket",
                "Connection": "Upgrade",
                "Sec-WebSocket-Accept": "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
            ]
        )
        
        let result = responseParser.validateHandshakeResponse(
            response,
            expectedAccept: "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        )
        
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.errorMessage)
    }
    
    /// 测试错误状态码验证
    func testInvalidStatusCodeValidation() {
        let response = HTTPResponse(
            statusCode: 400,
            statusText: "Bad Request",
            headers: [:]
        )
        
        let result = responseParser.validateHandshakeResponse(
            response,
            expectedAccept: "test"
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("状态码必须是101") == true)
    }
    
    /// 测试缺失Upgrade头部验证
    func testMissingUpgradeHeaderValidation() {
        let response = HTTPResponse(
            statusCode: 101,
            statusText: "Switching Protocols",
            headers: [
                "Connection": "Upgrade",
                "Sec-WebSocket-Accept": "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
            ]
        )
        
        let result = responseParser.validateHandshakeResponse(
            response,
            expectedAccept: "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("缺失必需头部") == true)
    }
    
    /// 测试错误的Upgrade头部值验证
    func testInvalidUpgradeHeaderValidation() {
        let response = HTTPResponse(
            statusCode: 101,
            statusText: "Switching Protocols",
            headers: [
                "Upgrade": "http",
                "Connection": "Upgrade",
                "Sec-WebSocket-Accept": "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
            ]
        )
        
        let result = responseParser.validateHandshakeResponse(
            response,
            expectedAccept: "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("Upgrade头部必须为websocket") == true)
    }
    
    /// 测试错误的Accept密钥验证
    func testInvalidAcceptKeyValidation() {
        let response = HTTPResponse(
            statusCode: 101,
            statusText: "Switching Protocols",
            headers: [
                "Upgrade": "websocket",
                "Connection": "Upgrade",
                "Sec-WebSocket-Accept": "wrong-accept-key"
            ]
        )
        
        let result = responseParser.validateHandshakeResponse(
            response,
            expectedAccept: "correct-accept-key"
        )
        
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errorMessage?.contains("Accept密钥验证失败") == true)
    }
    
    /// 测试从数据解析响应
    func testParseResponseFromData() {
        let responseString = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        \r

        """
        
        let data = responseString.data(using: .utf8)!
        let result = responseParser.parseResponse(from: data)
        
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.response?.statusCode, 101)
    }
    
    /// 测试从ASCII编码数据解析响应
    func testParseResponseFromASCIIData() {
        let responseString = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r
        \r

        """
        
        let data = responseString.data(using: .ascii)!
        let result = responseParser.parseResponse(from: data)
        
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.response?.statusCode, 101)
        XCTAssertEqual(result.response?.headers["Upgrade"], "websocket")
    }
    
    /// 测试从ISO Latin 1编码数据解析响应
    func testParseResponseFromISOLatin1Data() {
        let responseString = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Server: Apache/2.4.41\r
        \r

        """
        
        let data = responseString.data(using: .isoLatin1)!
        let result = responseParser.parseResponse(from: data)
        
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.response?.statusCode, 101)
        XCTAssertEqual(result.response?.headers["Server"], "Apache/2.4.41")
    }
    
    /// 测试从混合编码数据解析响应（UTF-8失败但ASCII成功）
    func testParseResponseFromMixedEncodingData() {
        // 创建一个ASCII HTTP响应，但包含一些高位字节
        var data = Data()
        let asciiPart = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        data.append(asciiPart.data(using: .ascii)!)
        // 添加一些非UTF-8字节但在ISO Latin 1中有效
        data.append(contentsOf: [0xE9]) // é in ISO Latin 1
        let endPart = "\r\n\r\n"
        data.append(endPart.data(using: .ascii)!)
        
        let result = responseParser.parseResponse(from: data)
        
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.response?.statusCode, 101)
    }
    
    /// 测试从完全无效数据解析响应
    func testParseResponseFromCompletelyInvalidData() {
        // 创建完全无法解码的数据
        let invalidData = Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD, 0xFC])
        let result = responseParser.parseResponse(from: invalidData)
        
        // 数据能够被解码（通过lossy转换），但由于不是有效的HTTP响应格式，状态行解析应该失败
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.error, .invalidStatusLine)
    }
    
    /// 测试UTF-8编码优先级
    func testUTF8EncodingPriority() {
        let responseString = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Content-Language: zh-CN\r
        \r

        """
        
        let utf8Data = responseString.data(using: .utf8)!
        let result = responseParser.parseResponse(from: utf8Data)
        
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.response?.statusCode, 101)
        XCTAssertEqual(result.response?.headers["Content-Language"], "zh-CN")
    }
    
    /// 测试多编码解析成功的握手验证
    func testMultiEncodingHandshakeValidation() {
        let clientKey = "dGhlIHNhbXBsZSBub25jZQ=="
        let expectedAccept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        
        let responseString = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(expectedAccept)\r
        \r

        """
        
        // 测试ASCII编码的完整验证
        let asciiData = responseString.data(using: .ascii)!
        let asciiResult = responseParser.validateHandshakeResponse(from: asciiData, clientKey: clientKey)
        XCTAssertTrue(asciiResult.isValid)
        
        // 测试ISO Latin 1编码的完整验证
        let latin1Data = responseString.data(using: .isoLatin1)!
        let latin1Result = responseParser.validateHandshakeResponse(from: latin1Data, clientKey: clientKey)
        XCTAssertTrue(latin1Result.isValid)
    }
    
    /// 测试完整握手响应验证
    func testCompleteHandshakeValidation() {
        let clientKey = "dGhlIHNhbXBsZSBub25jZQ=="
        let expectedAccept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        
        let responseString = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(expectedAccept)\r
        \r

        """
        
        let data = responseString.data(using: .utf8)!
        let result = responseParser.validateHandshakeResponse(from: data, clientKey: clientKey)
        
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.errorMessage)
    }
    
    /// 测试解析错误的本地化描述
    func testParseErrorDescriptions() {
        let errors: [ParseError] = [
            .emptyResponse,
            .invalidFormat("test"),
            .invalidStatusLine,
            .unsupportedHttpVersion
        ]
        
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty, "错误描述不应该为空: \(error)")
        }
    }
    
    /// 测试大小写不敏感的头部验证
    func testCaseInsensitiveHeaderValidation() {
        let response = HTTPResponse(
            statusCode: 101,
            statusText: "Switching Protocols",
            headers: [
                "upgrade": "WEBSOCKET",  // 小写键，大写值
                "connection": "upgrade",  // 小写键值
                "Sec-WebSocket-Accept": "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
            ]
        )
        
        let result = responseParser.validateHandshakeResponse(
            response,
            expectedAccept: "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        )
        
        XCTAssertTrue(result.isValid)
    }
    
    /// 测试Connection头部包含upgrade验证
    func testConnectionHeaderContainsUpgrade() {
        let response = HTTPResponse(
            statusCode: 101,
            statusText: "Switching Protocols",
            headers: [
                "Upgrade": "websocket",
                "Connection": "keep-alive, upgrade",  // 包含upgrade
                "Sec-WebSocket-Accept": "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
            ]
        )
        
        let result = responseParser.validateHandshakeResponse(
            response,
            expectedAccept: "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        )
        
        XCTAssertTrue(result.isValid)
    }
}