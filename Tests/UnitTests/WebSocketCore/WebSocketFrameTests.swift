import XCTest
@testable import WebSocketCore

final class WebSocketFrameTests: XCTestCase {
    
    // MARK: - 基本帧创建测试
    
    func testBasicFrameCreation() throws {
        let payload = Data("Hello".utf8)
        
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .text,
            masked: true,
            payload: payload,
            maskingKey: 0x12345678
        )
        
        XCTAssertTrue(frame.fin)
        XCTAssertFalse(frame.rsv1)
        XCTAssertFalse(frame.rsv2)
        XCTAssertFalse(frame.rsv3)
        XCTAssertEqual(frame.opcode, .text)
        XCTAssertTrue(frame.masked)
        XCTAssertEqual(frame.payloadLength, 5)
        XCTAssertEqual(frame.maskingKey, 0x12345678)
        XCTAssertEqual(frame.payload, payload)
        XCTAssertTrue(frame.isComplete)
        XCTAssertTrue(frame.isDataFrame)
        XCTAssertFalse(frame.isControlFrame)
    }
    
    func testUnmaskedFrame() throws {
        let payload = Data("Server message".utf8)
        
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .text,
            masked: false,
            payload: payload
        )
        
        XCTAssertFalse(frame.masked)
        XCTAssertNil(frame.maskingKey)
        XCTAssertNil(frame.maskingKeyData)
    }
    
    func testControlFrame() throws {
        let pingData = Data("ping".utf8)
        
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .ping,
            masked: true,
            payload: pingData,
            maskingKey: 0xABCDEF00
        )
        
        XCTAssertTrue(frame.isControlFrame)
        XCTAssertFalse(frame.isDataFrame)
        XCTAssertEqual(frame.opcode, .ping)
    }
    
    func testMaskingKeyDataConversion() throws {
        let maskingKey: UInt32 = 0x12345678
        
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .binary,
            masked: true,
            payload: Data([1, 2, 3, 4]),
            maskingKey: maskingKey
        )
        
        let keyData = frame.maskingKeyData!
        XCTAssertEqual(keyData.count, 4)
        
        // 验证大端字节序转换
        let expectedBytes: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        XCTAssertEqual(Array(keyData), expectedBytes)
    }
    
    // MARK: - 帧验证测试
    
    func testMaskingValidation() {
        // 测试掩码帧必须有掩码密钥
        XCTAssertThrowsError(try WebSocketFrame(
            fin: true,
            opcode: .text,
            masked: true,
            payload: Data("test".utf8)
        )) { error in
            if case WebSocketProtocolError.maskingViolation = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected maskingViolation error")
            }
        }
        
        // 测试非掩码帧不能有掩码密钥
        XCTAssertThrowsError(try WebSocketFrame(
            fin: true,
            opcode: .text,
            masked: false,
            payload: Data("test".utf8),
            maskingKey: 0x12345678
        )) { error in
            if case WebSocketProtocolError.maskingViolation = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected maskingViolation error")
            }
        }
    }
    
    func testControlFrameValidation() {
        let longPayload = Data(repeating: 0x41, count: 126) // 126字节，超过控制帧限制
        
        // 控制帧负载不能超过125字节
        XCTAssertThrowsError(try WebSocketFrame(
            fin: true,
            opcode: .ping,
            masked: true,
            payload: longPayload,
            maskingKey: 0x12345678
        )) { error in
            if case WebSocketProtocolError.controlFrameTooLarge = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected controlFrameTooLarge error")
            }
        }
        
        // 控制帧不能分片
        XCTAssertThrowsError(try WebSocketFrame(
            fin: false, // FIN=0，分片帧
            opcode: .ping,
            masked: true,
            payload: Data("ping".utf8),
            maskingKey: 0x12345678
        )) { error in
            if case WebSocketProtocolError.fragmentationViolation = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected fragmentationViolation error")
            }
        }
    }
    
    func testReservedBitsValidation() {
        // 保留位设置应该报错
        XCTAssertThrowsError(try WebSocketFrame(
            fin: true,
            rsv1: true, // RSV1 设置为true
            opcode: .text,
            masked: true,
            payload: Data("test".utf8),
            maskingKey: 0x12345678
        )) { error in
            if case WebSocketProtocolError.reservedBitsSet = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected reservedBitsSet error")
            }
        }
    }
    
    func testReservedOpcodeValidation() {
        // 保留操作码应该报错
        XCTAssertThrowsError(try WebSocketFrame(
            fin: true,
            opcode: .reserved3,
            masked: true,
            payload: Data("test".utf8),
            maskingKey: 0x12345678
        )) { error in
            if case WebSocketProtocolError.unsupportedOpcode = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected unsupportedOpcode error")
            }
        }
    }
    
    // MARK: - 边界条件测试
    
    func testEmptyPayload() throws {
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .text,
            masked: true,
            payload: Data(),
            maskingKey: 0x12345678
        )
        
        XCTAssertEqual(frame.payloadLength, 0)
        XCTAssertTrue(frame.payload.isEmpty)
    }
    
    func testMaxControlFramePayload() throws {
        let maxPayload = Data(repeating: 0x41, count: 125) // 125字节，控制帧最大允许大小
        
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .close,
            masked: true,
            payload: maxPayload,
            maskingKey: 0x12345678
        )
        
        XCTAssertEqual(frame.payloadLength, 125)
        XCTAssertEqual(frame.payload.count, 125)
    }
    
    func testLargeDataFrame() throws {
        let largePayload = Data(repeating: 0x41, count: 70000) // 70KB数据
        
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .binary,
            masked: true,
            payload: largePayload,
            maskingKey: 0x12345678
        )
        
        XCTAssertEqual(frame.payloadLength, 70000)
        XCTAssertEqual(frame.payload.count, 70000)
    }
    
    // MARK: - 帧片段测试
    
    func testFragmentedFrame() throws {
        let frame = try WebSocketFrame(
            fin: false, // 非最终帧
            opcode: .text,
            masked: true,
            payload: Data("Part 1".utf8),
            maskingKey: 0x12345678
        )
        
        XCTAssertFalse(frame.fin)
        XCTAssertFalse(frame.isComplete)
        XCTAssertTrue(frame.isDataFrame)
    }
    
    func testContinuationFrame() throws {
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .continuation,
            masked: true,
            payload: Data(" Part 2".utf8),
            maskingKey: 0x87654321
        )
        
        XCTAssertEqual(frame.opcode, .continuation)
        XCTAssertTrue(frame.fin)
        XCTAssertTrue(frame.isComplete)
        XCTAssertTrue(frame.isDataFrame)
    }
}