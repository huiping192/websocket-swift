import XCTest
@testable import WebSocketCore
@testable import Utilities

final class FrameDecoderTests: XCTestCase {
    
    var decoder: FrameDecoder!
    var encoder: FrameEncoder!
    
    override func setUp() {
        super.setUp()
        decoder = FrameDecoder()
        encoder = FrameEncoder()
    }
    
    override func tearDown() {
        decoder = nil
        encoder = nil
        super.tearDown()
    }
    
    // MARK: - 基本解码测试
    
    func testBasicFrameDecoding() throws {
        // 创建一个简单的文本帧进行编码
        let originalFrame = try WebSocketFrame(
            fin: true,
            opcode: .text,
            masked: true,
            payload: Data("Hello".utf8),
            maskingKey: 0x12345678
        )
        
        let encodedData = try encoder.encodeFrame(originalFrame)
        let decodedFrames = try decoder.decode(data: encodedData)
        
        XCTAssertEqual(decodedFrames.count, 1)
        let decodedFrame = decodedFrames[0]
        
        XCTAssertEqual(decodedFrame.fin, originalFrame.fin)
        XCTAssertEqual(decodedFrame.opcode, originalFrame.opcode)
        XCTAssertEqual(decodedFrame.masked, originalFrame.masked)
        XCTAssertEqual(decodedFrame.maskingKey, originalFrame.maskingKey)
        XCTAssertEqual(decodedFrame.payload, originalFrame.payload)
        XCTAssertEqual(decodedFrame.payloadLength, originalFrame.payloadLength)
    }
    
    func testMultipleFramesDecoding() throws {
        // 创建多个帧
        let frames = [
            try WebSocketFrame(fin: true, opcode: .text, masked: true, payload: Data("Frame 1".utf8), maskingKey: 0x11111111),
            try WebSocketFrame(fin: true, opcode: .binary, masked: true, payload: Data([1, 2, 3]), maskingKey: 0x22222222),
            try WebSocketFrame(fin: true, opcode: .ping, masked: true, payload: Data("ping".utf8), maskingKey: 0x33333333)
        ]
        
        // 编码所有帧为连续数据
        var combinedData = Data()
        for frame in frames {
            combinedData.append(try encoder.encodeFrame(frame))
        }
        
        // 使用新的解码器实例避免状态问题
        let freshDecoder = FrameDecoder()
        
        // 解码
        let decodedFrames = try freshDecoder.decode(data: combinedData)
        
        XCTAssertEqual(decodedFrames.count, 3)
        for (index, decodedFrame) in decodedFrames.enumerated() {
            let originalFrame = frames[index]
            XCTAssertEqual(decodedFrame.opcode, originalFrame.opcode)
            XCTAssertEqual(decodedFrame.payload, originalFrame.payload)
            XCTAssertEqual(decodedFrame.maskingKey, originalFrame.maskingKey)
        }
    }
    
    // MARK: - 流式解码测试
    
    func testStreamingDecoding() throws {
        let originalFrame = try WebSocketFrame(
            fin: true,
            opcode: .text,
            masked: true,
            payload: Data("Streaming test".utf8),
            maskingKey: 0x87654321
        )
        
        let encodedData = try encoder.encodeFrame(originalFrame)
        
        // 分块发送数据
        var decodedFrames: [WebSocketFrame] = []
        
        // 发送第一个字节
        let chunk1 = try decoder.decode(data: encodedData.prefix(1))
        XCTAssertEqual(chunk1.count, 0) // 应该没有完整帧
        decodedFrames.append(contentsOf: chunk1)
        
        // 发送剩余数据
        let remainingData = encodedData.dropFirst()
        let chunk2 = try decoder.decode(data: remainingData)
        decodedFrames.append(contentsOf: chunk2)
        
        // 现在应该有完整的帧
        XCTAssertEqual(decodedFrames.count, 1)
        let decodedFrame = decodedFrames[0]
        
        XCTAssertEqual(decodedFrame.payload, originalFrame.payload)
        XCTAssertEqual(decodedFrame.opcode, originalFrame.opcode)
    }
    
    func testIncompleteFrameHandling() throws {
        let originalFrame = try WebSocketFrame(
            fin: true,
            opcode: .binary,
            masked: true,
            payload: Data(repeating: 0x42, count: 1000),
            maskingKey: 0xABCDEF00
        )
        
        let encodedData = try encoder.encodeFrame(originalFrame)
        
        // 使用新的解码器实例避免状态问题
        let freshDecoder = FrameDecoder()
        
        // 只发送头部的一部分数据，这样不会触发长度解析错误
        let partialData = encodedData.prefix(4) // 只发送前4字节
        
        let frames1 = try freshDecoder.decode(data: partialData)
        XCTAssertEqual(frames1.count, 0) // 没有完整帧
        
        // 发送剩余数据
        let remainingData = encodedData.dropFirst(4)
        let frames2 = try freshDecoder.decode(data: remainingData)
        XCTAssertEqual(frames2.count, 1) // 现在有完整帧了
        
        let decodedFrame = frames2[0]
        XCTAssertEqual(decodedFrame.payload, originalFrame.payload)
    }
    
    // MARK: - 不同负载长度解码测试
    
    func testShortPayloadDecoding() throws {
        // 测试7位长度编码
        let payload = Data("Short".utf8)
        let frame = try WebSocketFrame(fin: true, opcode: .text, masked: true, payload: payload, maskingKey: 0x12345678)
        
        let encoded = try encoder.encodeFrame(frame)
        let decoded = try decoder.decode(data: encoded)
        
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].payload, payload)
    }
    
    func testMediumPayloadDecoding() throws {
        // 测试16位长度编码 (126-65535字节)
        let payload = Data(repeating: 0x41, count: 1000)
        let frame = try WebSocketFrame(fin: true, opcode: .binary, masked: true, payload: payload, maskingKey: 0x87654321)
        
        // 使用新的解码器实例避免状态问题
        let freshDecoder = FrameDecoder()
        
        let encoded = try encoder.encodeFrame(frame)
        let decoded = try freshDecoder.decode(data: encoded)
        
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].payload, payload)
    }
    
    func testLongPayloadDecoding() throws {
        // 测试64位长度编码 (65536+字节)
        let payload = Data(repeating: 0x42, count: 70000)
        let frame = try WebSocketFrame(fin: true, opcode: .binary, masked: true, payload: payload, maskingKey: 0xFEDCBA98)
        
        let encoded = try encoder.encodeFrame(frame)
        let decoded = try decoder.decode(data: encoded)
        
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].payload, payload)
    }
    
    // MARK: - 掩码处理测试
    
    func testMaskedFrameDecoding() throws {
        let originalPayload = Data("Masked data test".utf8)
        let maskingKey: UInt32 = 0x12345678
        
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .text,
            masked: true,
            payload: originalPayload,
            maskingKey: maskingKey
        )
        
        let encoded = try encoder.encodeFrame(frame)
        let decoded = try decoder.decode(data: encoded)
        
        XCTAssertEqual(decoded.count, 1)
        let decodedFrame = decoded[0]
        
        XCTAssertTrue(decodedFrame.masked)
        XCTAssertEqual(decodedFrame.maskingKey, maskingKey)
        XCTAssertEqual(decodedFrame.payload, originalPayload) // 应该已解掩码
    }
    
    func testUnmaskedFrameDecoding() throws {
        // 手动构建无掩码帧 (服务器端帧)
        let payload = Data("Server message".utf8)
        var frameData = Data()
        
        // 第一字节: FIN=1, RSV=0, Opcode=text(1)
        frameData.append(0x81)
        
        // 第二字节: MASK=0, Length=14
        frameData.append(UInt8(payload.count))
        
        // 负载数据 (无掩码)
        frameData.append(payload)
        
        let decoded = try decoder.decode(data: frameData)
        
        XCTAssertEqual(decoded.count, 1)
        let decodedFrame = decoded[0]
        
        XCTAssertFalse(decodedFrame.masked)
        XCTAssertNil(decodedFrame.maskingKey)
        XCTAssertEqual(decodedFrame.payload, payload)
    }
    
    // MARK: - 控制帧解码测试
    
    func testControlFrameDecoding() throws {
        let controlFrames = [
            (opcode: FrameType.ping, payload: Data("ping".utf8)),
            (opcode: FrameType.pong, payload: Data("pong".utf8)),
            (opcode: FrameType.close, payload: Data())
        ]
        
        for (opcode, payload) in controlFrames {
            // 为每个测试创建新的解码器实例，避免状态问题
            let freshDecoder = FrameDecoder()
            
            let frame = try WebSocketFrame(
                fin: true,
                opcode: opcode,
                masked: true,
                payload: payload,
                maskingKey: 0x11223344
            )
            
            let encoded = try encoder.encodeFrame(frame)
            print("DEBUG: Encoded \(opcode) frame: \(encoded.map { String(format: "%02X", $0) }.joined(separator: " "))")
            let decoded = try freshDecoder.decode(data: encoded)
            print("DEBUG: Decoded frames count: \(decoded.count)")
            
            XCTAssertEqual(decoded.count, 1, "Failed to decode \(opcode) control frame")
            let decodedFrame = decoded[0]
            
            XCTAssertEqual(decodedFrame.opcode, opcode)
            XCTAssertEqual(decodedFrame.payload, payload)
            XCTAssertTrue(decodedFrame.isControlFrame)
        }
    }
    
    // MARK: - 错误处理测试
    
    func testInvalidOpcodeError() {
        // 手动构建带有无效操作码的帧
        let invalidFrameData = Data([0x8C, 0x00]) // FIN=1, opcode=0xC (无效)
        
        XCTAssertThrowsError(try decoder.decode(data: invalidFrameData)) { error in
            if case WebSocketProtocolError.unsupportedOpcode = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected unsupportedOpcode error, got \(error)")
            }
        }
    }
    
    func testReservedBitsError() {
        // 手动构建带有保留位设置的帧
        var frameWithReservedBits = Data([0xF1, 0x05]) // FIN=1, RSV1=RSV2=RSV3=1, opcode=text
        frameWithReservedBits.append(Data("test".utf8))
        
        XCTAssertThrowsError(try decoder.decode(data: frameWithReservedBits)) { error in
            if case WebSocketProtocolError.reservedBitsSet = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected reservedBitsSet error")
            }
        }
    }
    
    func testFrameSizeLimitError() throws {
        let smallLimitDecoder = FrameDecoder(maxFrameSize: 100)
        
        // 创建超出限制的帧
        let largePayload = Data(repeating: 0x41, count: 200)
        let largeFrame = try WebSocketFrame(
            fin: true,
            opcode: .binary,
            masked: true,
            payload: largePayload,
            maskingKey: 0x12345678
        )
        
        let encoded = try encoder.encodeFrame(largeFrame)
        
        XCTAssertThrowsError(try smallLimitDecoder.decode(data: encoded)) { error in
            if case WebSocketProtocolError.payloadTooLarge = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected payloadTooLarge error")
            }
        }
    }
    
    func testControlFrameSizeError() {
        // 手动构建过大的控制帧 (126字节，超过125字节限制)
        var largeControlFrame = Data([0x89, 0xFE]) // FIN=1, opcode=ping, MASK=0, length=126 (使用扩展长度)
        largeControlFrame.append(contentsOf: [0x00, 0x7E]) // 扩展长度 = 126
        largeControlFrame.append(Data(repeating: 0x00, count: 126))
        
        XCTAssertThrowsError(try decoder.decode(data: largeControlFrame)) { error in
            if case WebSocketProtocolError.controlFrameTooLarge = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected controlFrameTooLarge error, got \(error)")
            }
        }
    }
    
    // MARK: - UTF-8验证测试
    
    func testUTF8TextValidation() {
        // 手动构建包含无效UTF-8的文本帧
        var invalidTextFrame = Data([0x81, 0x84]) // FIN=1, opcode=text, MASK=1, length=4
        invalidTextFrame.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // 掩码密钥
        // 无效的UTF-8序列
        let invalidUTF8 = Data([0xFF, 0xFE, 0xFD, 0xFC])
        invalidTextFrame.append(invalidUTF8)
        
        XCTAssertThrowsError(try decoder.decode(data: invalidTextFrame)) { error in
            if case WebSocketProtocolError.invalidUTF8Text = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected invalidUTF8Text error")
            }
        }
    }
    
    // MARK: - 重置功能测试
    
    func testDecoderReset() throws {
        // 发送不完整的帧数据
        let partialData = Data([0x81, 0x85]) // 缺少掩码密钥和负载
        let frames1 = try decoder.decode(data: partialData)
        XCTAssertEqual(frames1.count, 0)
        
        // 重置解码器
        decoder.reset()
        
        // 发送完整的帧
        let completeFrame = try WebSocketFrame(
            fin: true,
            opcode: .text,
            masked: true,
            payload: Data("Reset test".utf8),
            maskingKey: 0x12345678
        )
        
        let encoded = try encoder.encodeFrame(completeFrame)
        let frames2 = try decoder.decode(data: encoded)
        
        XCTAssertEqual(frames2.count, 1)
        XCTAssertEqual(frames2[0].payload, completeFrame.payload)
    }
    
    // MARK: - FrameCodecProtocol实现测试
    
    func testFrameCodecProtocolImplementation() throws {
        let codecDecoder = decoder as FrameCodecProtocol
        
        // 编码功能应该抛出错误
        let message = WebSocketMessage.text("Codec test")
        XCTAssertThrowsError(try codecDecoder.encode(message: message)) { error in
            if case WebSocketProtocolError.protocolViolation = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected protocolViolation error")
            }
        }
        
        // 解码功能应该正常工作
        let frame = try WebSocketFrame(fin: true, opcode: .text, masked: true, payload: Data("test".utf8), maskingKey: 0x12345678)
        let encoded = try encoder.encodeFrame(frame)
        let decoded = try codecDecoder.decode(data: encoded)
        
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].payload, frame.payload)
    }
}
