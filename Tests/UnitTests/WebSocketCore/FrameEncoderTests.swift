import XCTest
@testable import WebSocketCore
@testable import Utilities

final class FrameEncoderTests: XCTestCase {
    
    var encoder: FrameEncoder!
    
    override func setUp() {
        super.setUp()
        encoder = FrameEncoder()
    }
    
    override func tearDown() {
        encoder = nil
        super.tearDown()
    }
    
    // MARK: - 基本消息编码测试
    
    func testTextMessageEncoding() throws {
        let message = WebSocketMessage.text("Hello")
        let frames = try encoder.encodeToFrames(message: message)
        
        XCTAssertEqual(frames.count, 1)
        let frame = frames[0]
        
        XCTAssertTrue(frame.fin)
        XCTAssertEqual(frame.opcode, .text)
        XCTAssertTrue(frame.masked)
        XCTAssertNotNil(frame.maskingKey)
        XCTAssertEqual(frame.payload, Data("Hello".utf8))
        XCTAssertEqual(frame.payloadLength, 5)
    }
    
    func testBinaryMessageEncoding() throws {
        let binaryData = Data([0x01, 0x02, 0x03, 0x04])
        let message = WebSocketMessage.binary(binaryData)
        let frames = try encoder.encodeToFrames(message: message)
        
        XCTAssertEqual(frames.count, 1)
        let frame = frames[0]
        
        XCTAssertTrue(frame.fin)
        XCTAssertEqual(frame.opcode, .binary)
        XCTAssertTrue(frame.masked)
        XCTAssertEqual(frame.payload, binaryData)
    }
    
    func testPingMessageEncoding() throws {
        let pingData = Data("ping".utf8)
        let message = WebSocketMessage.ping(pingData)
        let frames = try encoder.encodeToFrames(message: message)
        
        XCTAssertEqual(frames.count, 1)
        let frame = frames[0]
        
        XCTAssertTrue(frame.fin)
        XCTAssertEqual(frame.opcode, .ping)
        XCTAssertTrue(frame.masked)
        XCTAssertEqual(frame.payload, pingData)
    }
    
    func testPongMessageEncoding() throws {
        let pongData = Data("pong".utf8)
        let message = WebSocketMessage.pong(pongData)
        let frames = try encoder.encodeToFrames(message: message)
        
        XCTAssertEqual(frames.count, 1)
        let frame = frames[0]
        
        XCTAssertTrue(frame.fin)
        XCTAssertEqual(frame.opcode, .pong)
        XCTAssertTrue(frame.masked)
        XCTAssertEqual(frame.payload, pongData)
    }
    
    func testEmptyPingPongEncoding() throws {
        let pingMessage = WebSocketMessage.ping(nil)
        let pingFrames = try encoder.encodeToFrames(message: pingMessage)
        XCTAssertEqual(pingFrames[0].payload, Data())
        
        let pongMessage = WebSocketMessage.pong(nil)
        let pongFrames = try encoder.encodeToFrames(message: pongMessage)
        XCTAssertEqual(pongFrames[0].payload, Data())
    }
    
    // MARK: - 分片消息测试
    
    func testLargeMessageFragmentation() throws {
        let smallFrameEncoder = FrameEncoder(maxFrameSize: 10) // 10字节最大帧大小
        let longText = "This is a very long message that should be fragmented"
        let message = WebSocketMessage.text(longText)
        
        let frames = try smallFrameEncoder.encodeToFrames(message: message)
        
        // 应该被分片
        XCTAssertGreaterThan(frames.count, 1)
        
        // 检查分片结构
        let firstFrame = frames[0]
        XCTAssertFalse(firstFrame.fin) // 不是最终帧
        XCTAssertEqual(firstFrame.opcode, .text) // 首帧使用text操作码
        
        // 中间帧
        for i in 1..<(frames.count - 1) {
            let frame = frames[i]
            XCTAssertFalse(frame.fin)
            XCTAssertEqual(frame.opcode, .continuation)
        }
        
        // 最后一帧
        let lastFrame = frames.last!
        XCTAssertTrue(lastFrame.fin) // 最终帧
        XCTAssertEqual(lastFrame.opcode, .continuation)
        
        // 重组数据验证
        let reassembledData = frames.map { $0.payload }.reduce(Data()) { $0 + $1 }
        XCTAssertEqual(reassembledData, Data(longText.utf8))
    }
    
    func testExactFrameSizeMessage() throws {
        let frameSize = 100
        let exactSizeEncoder = FrameEncoder(maxFrameSize: frameSize)
        let exactData = Data(repeating: 0x41, count: frameSize) // 'A' * 100
        let message = WebSocketMessage.binary(exactData)
        
        let frames = try exactSizeEncoder.encodeToFrames(message: message)
        
        // 应该是单帧，不分片
        XCTAssertEqual(frames.count, 1)
        let frame = frames[0]
        
        XCTAssertTrue(frame.fin)
        XCTAssertEqual(frame.opcode, .binary)
        XCTAssertEqual(frame.payload, exactData)
    }
    
    func testEmptyMessageEncoding() throws {
        let textMessage = WebSocketMessage.text("")
        let textFrames = try encoder.encodeToFrames(message: textMessage)
        
        XCTAssertEqual(textFrames.count, 1)
        XCTAssertEqual(textFrames[0].payloadLength, 0)
        XCTAssertTrue(textFrames[0].payload.isEmpty)
        
        let binaryMessage = WebSocketMessage.binary(Data())
        let binaryFrames = try encoder.encodeToFrames(message: binaryMessage)
        
        XCTAssertEqual(binaryFrames.count, 1)
        XCTAssertEqual(binaryFrames[0].payloadLength, 0)
        XCTAssertTrue(binaryFrames[0].payload.isEmpty)
    }
    
    // MARK: - 帧二进制编码测试
    
    func testFrameBinaryEncoding() throws {
        let testMessage = "Test"
        let testData = Data(testMessage.utf8)
        
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .text,
            masked: true,
            payload: testData,
            maskingKey: 0x12345678
        )
        
        let encodedData = try encoder.encodeFrame(frame)
        
        // 验证帧头结构
        XCTAssertGreaterThanOrEqual(encodedData.count, 6) // 至少包含2字节头 + 4字节掩码密钥
        
        let firstByte = encodedData[0]
        let secondByte = encodedData[1]
        
        // 验证第一字节 (FIN + RSV + Opcode)
        XCTAssertEqual(firstByte & 0x80, 0x80) // FIN = 1
        XCTAssertEqual(firstByte & 0x70, 0x00) // RSV1,2,3 = 0
        XCTAssertEqual(firstByte & 0x0F, 0x01) // Opcode = text
        
        // 验证第二字节 (MASK + Payload Length)
        XCTAssertEqual(secondByte & 0x80, 0x80) // MASK = 1
        XCTAssertEqual(secondByte & 0x7F, UInt8(testData.count)) // Payload length
    }
    
    func testDifferentPayloadLengthEncodings() throws {
        // 测试不同长度编码
        let testCases = [
            (length: 125, headerSize: 6),     // 短长度 + 掩码密钥
            (length: 126, headerSize: 8),     // 中长度 + 掩码密钥
            (length: 70000, headerSize: 14)   // 长长度 + 掩码密钥
        ]
        
        for (length, expectedHeaderSize) in testCases {
            let payload = Data(repeating: 0x41, count: length)
            let frame = try WebSocketFrame(
                fin: true,
                opcode: .binary,
                masked: true,
                payload: payload,
                maskingKey: 0x12345678
            )
            
            let encoded = try encoder.encodeFrame(frame)
            
            // 验证总长度 = 头部 + 负载
            XCTAssertEqual(encoded.count, expectedHeaderSize + length)
        }
    }
    
    // MARK: - FrameCodecProtocol实现测试
    
    func testFrameCodecProtocolImplementation() throws {
        let codecEncoder = encoder as FrameCodecProtocol
        let message = WebSocketMessage.text("Protocol test")
        
        let encodedData = try codecEncoder.encode(message: message)
        
        // 应该产生有效的二进制数据
        XCTAssertGreaterThan(encodedData.count, 0)
        
        // 解码功能应该抛出错误
        XCTAssertThrowsError(try codecEncoder.decode(data: encodedData)) { error in
            if case WebSocketProtocolError.protocolViolation = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected protocolViolation error")
            }
        }
    }
    
    // MARK: - 控制帧限制测试
    
    func testControlFramePayloadLimit() throws {
        let maxPayload = Data(repeating: 0x41, count: 125) // 125字节，最大允许
        let oversizedPayload = Data(repeating: 0x41, count: 126) // 126字节，超出限制
        
        // 最大大小应该成功
        let validMessage = WebSocketMessage.ping(maxPayload)
        XCTAssertNoThrow(try encoder.encodeToFrames(message: validMessage))
        
        // 超出大小应该失败
        let invalidMessage = WebSocketMessage.ping(oversizedPayload)
        XCTAssertThrowsError(try encoder.encodeToFrames(message: invalidMessage)) { error in
            if case WebSocketProtocolError.controlFrameTooLarge = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected controlFrameTooLarge error")
            }
        }
    }
    
    // MARK: - 掩码生成测试
    
    func testMaskingKeyGeneration() throws {
        let message = WebSocketMessage.text("Test masking")
        let frames1 = try encoder.encodeToFrames(message: message)
        let frames2 = try encoder.encodeToFrames(message: message)
        
        // 不同次编码应该产生不同的掩码密钥
        XCTAssertNotEqual(frames1[0].maskingKey, frames2[0].maskingKey)
        
        // 所有帧都应该有掩码密钥
        for frame in frames1 {
            XCTAssertNotNil(frame.maskingKey)
            XCTAssertTrue(frame.masked)
        }
    }
}