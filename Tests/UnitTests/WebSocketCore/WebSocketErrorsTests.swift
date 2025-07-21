import XCTest
@testable import WebSocketCore

final class WebSocketErrorsTests: XCTestCase {
    
    // TODO: 添加WebSocket错误处理相关测试
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testProtocolErrorCreation() throws {
        let error = WebSocketProtocolError.invalidFrameFormat(description: "Test error")
        XCTAssertNotNil(error)
    }
    
    func testProtocolViolationError() throws {
        let error = WebSocketProtocolError.protocolViolation(description: "Test protocol violation")
        XCTAssertNotNil(error)
    }
}