import XCTest
@testable import WebSocketCore

final class MessageAssemblerTests: XCTestCase {
    
    var assembler: MessageAssembler!
    
    override func setUp() {
        super.setUp()
        assembler = MessageAssembler()
    }
    
    override func tearDown() {
        assembler = nil
        super.tearDown()
    }
    
    // MARK: - 单帧消息测试
    
    func testSingleTextFrameAssembly() throws {
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .text,
            masked: false,
            payload: Data("Hello World".utf8)
        )
        
        let message = try assembler.process(frame: frame)
        
        XCTAssertNotNil(message)
        if case .text(let text) = message! {
            XCTAssertEqual(text, "Hello World")
        } else {
            XCTFail("Expected text message")
        }
        
        XCTAssertFalse(assembler.hasIncompleteMessage)
    }
    
    func testSingleBinaryFrameAssembly() throws {
        let binaryData = Data([0x01, 0x02, 0x03, 0x04])
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .binary,
            masked: false,
            payload: binaryData
        )
        
        let message = try assembler.process(frame: frame)
        
        XCTAssertNotNil(message)
        if case .binary(let data) = message! {
            XCTAssertEqual(data, binaryData)
        } else {
            XCTFail("Expected binary message")
        }
    }
    
    func testEmptyTextFrame() throws {
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .text,
            masked: false,
            payload: Data()
        )
        
        let message = try assembler.process(frame: frame)
        
        XCTAssertNotNil(message)
        if case .text(let text) = message! {
            XCTAssertEqual(text, "")
        } else {
            XCTFail("Expected empty text message")
        }
    }
    
    // MARK: - 分片消息测试
    
    func testFragmentedTextMessage() throws {
        let fullMessage = "This is a fragmented text message"
        let part1 = "This is a "
        let part2 = "fragmented "
        let part3 = "text message"
        
        // 第一个分片 (开始)
        let frame1 = try WebSocketFrame(
            fin: false,
            opcode: .text,
            masked: false,
            payload: Data(part1.utf8)
        )
        
        let message1 = try assembler.process(frame: frame1)
        XCTAssertNil(message1) // 未完成的消息
        XCTAssertTrue(assembler.hasIncompleteMessage)
        
        // 第二个分片 (中间)
        let frame2 = try WebSocketFrame(
            fin: false,
            opcode: .continuation,
            masked: false,
            payload: Data(part2.utf8)
        )
        
        let message2 = try assembler.process(frame: frame2)
        XCTAssertNil(message2) // 仍未完成
        XCTAssertTrue(assembler.hasIncompleteMessage)
        
        // 第三个分片 (结束)
        let frame3 = try WebSocketFrame(
            fin: true,
            opcode: .continuation,
            masked: false,
            payload: Data(part3.utf8)
        )
        
        let message3 = try assembler.process(frame: frame3)
        XCTAssertNotNil(message3)
        XCTAssertFalse(assembler.hasIncompleteMessage)
        
        if case .text(let text) = message3! {
            XCTAssertEqual(text, fullMessage)
        } else {
            XCTFail("Expected text message")
        }
    }
    
    func testFragmentedBinaryMessage() throws {
        let part1 = Data([0x01, 0x02])
        let part2 = Data([0x03, 0x04])
        let part3 = Data([0x05, 0x06])
        let fullData = part1 + part2 + part3
        
        // 第一个分片
        let frame1 = try WebSocketFrame(fin: false, opcode: .binary, masked: false, payload: part1)
        let message1 = try assembler.process(frame: frame1)
        XCTAssertNil(message1)
        
        // 第二个分片
        let frame2 = try WebSocketFrame(fin: false, opcode: .continuation, masked: false, payload: part2)
        let message2 = try assembler.process(frame: frame2)
        XCTAssertNil(message2)
        
        // 最后分片
        let frame3 = try WebSocketFrame(fin: true, opcode: .continuation, masked: false, payload: part3)
        let message3 = try assembler.process(frame: frame3)
        
        XCTAssertNotNil(message3)
        if case .binary(let data) = message3! {
            XCTAssertEqual(data, fullData)
        } else {
            XCTFail("Expected binary message")
        }
    }
    
    func testTwoFragmentMessage() throws {
        // 测试最简单的分片情况：两个分片
        let part1 = "Hello "
        let part2 = "World!"
        
        let frame1 = try WebSocketFrame(fin: false, opcode: .text, masked: false, payload: Data(part1.utf8))
        let frame2 = try WebSocketFrame(fin: true, opcode: .continuation, masked: false, payload: Data(part2.utf8))
        
        let message1 = try assembler.process(frame: frame1)
        XCTAssertNil(message1)
        
        let message2 = try assembler.process(frame: frame2)
        XCTAssertNotNil(message2)
        
        if case .text(let text) = message2! {
            XCTAssertEqual(text, "Hello World!")
        } else {
            XCTFail("Expected text message")
        }
    }
    
    // MARK: - 控制帧测试
    
    func testPingFrameProcessing() throws {
        let pingData = Data("ping payload".utf8)
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .ping,
            masked: false,
            payload: pingData
        )
        
        let message = try assembler.process(frame: frame)
        
        XCTAssertNotNil(message)
        if case .ping(let data) = message! {
            XCTAssertEqual(data, pingData)
        } else {
            XCTFail("Expected ping message")
        }
    }
    
    func testPongFrameProcessing() throws {
        let pongData = Data("pong payload".utf8)
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .pong,
            masked: false,
            payload: pongData
        )
        
        let message = try assembler.process(frame: frame)
        
        XCTAssertNotNil(message)
        if case .pong(let data) = message! {
            XCTAssertEqual(data, pongData)
        } else {
            XCTFail("Expected pong message")
        }
    }
    
    func testEmptyPingPong() throws {
        // 空的ping帧
        let pingFrame = try WebSocketFrame(fin: true, opcode: .ping, masked: false, payload: Data())
        let pingMessage = try assembler.process(frame: pingFrame)
        
        if case .ping(let data) = pingMessage! {
            XCTAssertNil(data)
        } else {
            XCTFail("Expected ping message with nil data")
        }
        
        // 空的pong帧
        let pongFrame = try WebSocketFrame(fin: true, opcode: .pong, masked: false, payload: Data())
        let pongMessage = try assembler.process(frame: pongFrame)
        
        if case .pong(let data) = pongMessage! {
            XCTAssertNil(data)
        } else {
            XCTFail("Expected pong message with nil data")
        }
    }
    
    func testCloseFrameProcessing() throws {
        // 创建带状态码和原因的关闭帧
        var closePayload = Data()
        let statusCode: UInt16 = 1000 // 正常关闭
        closePayload.append(contentsOf: withUnsafeBytes(of: statusCode.bigEndian) { Data($0) })
        closePayload.append(Data("Normal closure".utf8))
        
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .close,
            masked: false,
            payload: closePayload
        )
        
        let message = try assembler.process(frame: frame)
        
        XCTAssertNotNil(message)
        // 关闭消息当前被表示为binary消息
        if case .binary(let data) = message! {
            XCTAssertEqual(data, closePayload)
        } else {
            XCTFail("Expected binary message representing close frame")
        }
    }
    
    func testEmptyCloseFrame() throws {
        let frame = try WebSocketFrame(fin: true, opcode: .close, masked: false, payload: Data())
        let message = try assembler.process(frame: frame)
        
        XCTAssertNotNil(message)
        // 空关闭帧应该产生包含状态码1005的消息
        if case .binary(let data) = message! {
            XCTAssertEqual(data.count, 2) // 只有状态码，没有原因
        } else {
            XCTFail("Expected binary message for empty close frame")
        }
    }
    
    // MARK: - 控制帧与分片消息交错测试
    
    func testControlFramesDuringFragmentation() throws {
        // 开始分片消息
        let frame1 = try WebSocketFrame(fin: false, opcode: .text, masked: false, payload: Data("Hello ".utf8))
        let message1 = try assembler.process(frame: frame1)
        XCTAssertNil(message1)
        XCTAssertTrue(assembler.hasIncompleteMessage)
        
        // 插入ping帧
        let pingFrame = try WebSocketFrame(fin: true, opcode: .ping, masked: false, payload: Data("ping".utf8))
        let pingMessage = try assembler.process(frame: pingFrame)
        XCTAssertNotNil(pingMessage)
        if case .ping = pingMessage! {
            // 正确
        } else {
            XCTFail("Expected ping message")
        }
        
        // 分片消息状态应该保持
        XCTAssertTrue(assembler.hasIncompleteMessage)
        
        // 完成分片消息
        let frame2 = try WebSocketFrame(fin: true, opcode: .continuation, masked: false, payload: Data("World!".utf8))
        let message2 = try assembler.process(frame: frame2)
        XCTAssertNotNil(message2)
        XCTAssertFalse(assembler.hasIncompleteMessage)
        
        if case .text(let text) = message2! {
            XCTAssertEqual(text, "Hello World!")
        } else {
            XCTFail("Expected text message")
        }
    }
    
    // MARK: - 错误处理测试
    
    func testUnexpectedContinuation() {
        // 没有开始帧就发送continuation帧
        XCTAssertThrowsError(try assembler.process(frame: WebSocketFrame(
            fin: true,
            opcode: .continuation,
            masked: false,
            payload: Data("unexpected".utf8)
        ))) { error in
            if case WebSocketProtocolError.unexpectedContinuation = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected unexpectedContinuation error")
            }
        }
    }
    
    func testMultipleStartFrames() throws {
        // 发送第一个开始帧
        let frame1 = try WebSocketFrame(fin: false, opcode: .text, masked: false, payload: Data("start1".utf8))
        let message1 = try assembler.process(frame: frame1)
        XCTAssertNil(message1)
        
        // 在没有完成第一个消息的情况下发送另一个开始帧
        let frame2 = try WebSocketFrame(fin: false, opcode: .text, masked: false, payload: Data("start2".utf8))
        
        XCTAssertThrowsError(try assembler.process(frame: frame2)) { error in
            if case WebSocketProtocolError.unexpectedContinuation = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected unexpectedContinuation error")
            }
        }
    }
    
    func testInvalidUTF8InFragmentedMessage() throws {
        // 开始文本分片
        let frame1 = try WebSocketFrame(fin: false, opcode: .text, masked: false, payload: Data("Valid start".utf8))
        let message1 = try assembler.process(frame: frame1)
        XCTAssertNil(message1)
        
        // 发送包含无效UTF-8的结束分片
        let invalidUTF8 = Data([0xFF, 0xFE])
        let frame2 = try WebSocketFrame(fin: true, opcode: .continuation, masked: false, payload: invalidUTF8)
        
        XCTAssertThrowsError(try assembler.process(frame: frame2)) { error in
            if case WebSocketProtocolError.invalidUTF8Text = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected invalidUTF8Text error")
            }
        }
    }
    
    func testMessageSizeLimit() throws {
        let smallLimitAssembler = MessageAssembler(maxMessageSize: 100)
        
        // 开始一个分片消息
        let frame1 = try WebSocketFrame(fin: false, opcode: .text, masked: false, payload: Data(repeating: 0x41, count: 50))
        let message1 = try smallLimitAssembler.process(frame: frame1)
        XCTAssertNil(message1)
        
        // 发送超出大小限制的续分片
        let frame2 = try WebSocketFrame(fin: true, opcode: .continuation, masked: false, payload: Data(repeating: 0x42, count: 60))
        
        XCTAssertThrowsError(try smallLimitAssembler.process(frame: frame2)) { error in
            if case WebSocketProtocolError.payloadTooLarge = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected payloadTooLarge error")
            }
        }
    }
    
    func testInvalidCloseFrame() {
        // 创建只有1字节负载的无效关闭帧
        let invalidClosePayload = Data([0x01])
        
        XCTAssertThrowsError(try assembler.process(frame: WebSocketFrame(
            fin: true,
            opcode: .close,
            masked: false,
            payload: invalidClosePayload
        ))) { error in
            if case WebSocketProtocolError.invalidFrameFormat = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected invalidFrameFormat error")
            }
        }
    }
    
    func testInvalidCloseFrameUTF8() throws {
        // 创建带有无效UTF-8原因的关闭帧
        var invalidClosePayload = Data()
        let statusCode: UInt16 = 1000
        invalidClosePayload.append(contentsOf: withUnsafeBytes(of: statusCode.bigEndian) { Data($0) })
        invalidClosePayload.append(Data([0xFF, 0xFE])) // 无效UTF-8
        
        XCTAssertThrowsError(try assembler.process(frame: WebSocketFrame(
            fin: true,
            opcode: .close,
            masked: false,
            payload: invalidClosePayload
        ))) { error in
            if case WebSocketProtocolError.invalidUTF8Text = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected invalidUTF8Text error")
            }
        }
    }
    
    // MARK: - 重置功能测试
    
    func testAssemblerReset() throws {
        // 开始分片消息
        let frame1 = try WebSocketFrame(fin: false, opcode: .text, masked: false, payload: Data("incomplete".utf8))
        let message1 = try assembler.process(frame: frame1)
        XCTAssertNil(message1)
        XCTAssertTrue(assembler.hasIncompleteMessage)
        
        // 重置组装器
        assembler.reset()
        XCTAssertFalse(assembler.hasIncompleteMessage)
        
        // 发送新的完整消息
        let frame2 = try WebSocketFrame(fin: true, opcode: .text, masked: false, payload: Data("new message".utf8))
        let message2 = try assembler.process(frame: frame2)
        
        XCTAssertNotNil(message2)
        if case .text(let text) = message2! {
            XCTAssertEqual(text, "new message")
        } else {
            XCTFail("Expected text message")
        }
    }
    
    // MARK: - 超时测试 (模拟)
    
    func testFragmentTimeout() throws {
        // 使用非常短的超时时间进行测试
        let shortTimeoutAssembler = MessageAssembler(fragmentTimeout: 0.001) // 1毫秒
        
        // 开始分片消息
        let frame1 = try WebSocketFrame(fin: false, opcode: .text, masked: false, payload: Data("start".utf8))
        let message1 = try shortTimeoutAssembler.process(frame: frame1)
        XCTAssertNil(message1)
        
        // 等待超时
        Thread.sleep(forTimeInterval: 0.01) // 等待10毫秒
        
        // 尝试处理另一个帧，应该触发超时清理
        let frame2 = try WebSocketFrame(fin: true, opcode: .ping, masked: false, payload: Data())
        
        XCTAssertThrowsError(try shortTimeoutAssembler.process(frame: frame2)) { error in
            if case WebSocketProtocolError.protocolViolation = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected protocolViolation error for timeout")
            }
        }
    }
}