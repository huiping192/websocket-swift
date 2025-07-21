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
    
    /// 测试从无效数据解析响应
    func testParseResponseFromInvalidData() {
        // 创建无效的UTF-8数据
        let invalidData = Data([0xFF, 0xFE, 0xFD])
        let result = responseParser.parseResponse(from: invalidData)
        
        XCTAssertFalse(result.isSuccess)
        if case .failure(.invalidFormat(let reason)) = result {
            XCTAssertTrue(reason.contains("无法解码为UTF-8字符串"))
        } else {
            XCTFail("应该返回格式错误")
        }
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