import XCTest
@testable import WebSocketCore
@testable import Utilities

final class WebSocketUtilitiesTests: XCTestCase {
    
    // MARK: - 掩码密钥生成测试
    
    func testMaskingKeyGeneration() {
        let key1 = WebSocketMaskingKey.generate()
        let key2 = WebSocketMaskingKey.generate()
        
        // 生成的密钥应该不同
        XCTAssertNotEqual(key1, key2)
    }
    
    func testMaskingKeyConversion() {
        let originalKey: UInt32 = 0x12345678
        let keyData = WebSocketMaskingKey.toData(originalKey)
        
        XCTAssertEqual(keyData.count, 4)
        
        // 验证大端字节序
        let expectedBytes: [UInt8] = [0x12, 0x34, 0x56, 0x78]
        XCTAssertEqual(Array(keyData), expectedBytes)
        
        // 验证往返转换
        let convertedKey = keyData.withUnsafeBytes { bytes in
            UInt32(bigEndian: bytes.load(as: UInt32.self))
        }
        XCTAssertEqual(convertedKey, originalKey)
    }
    
    // MARK: - 负载长度编码测试
    
    func testShortPayloadLengthEncoding() {
        // 测试7位长度编码 (0-125)
        for length in [0, 1, 125] {
            let encoded = WebSocketPayloadLength.encode(UInt64(length))
            XCTAssertEqual(encoded.count, 1)
            XCTAssertEqual(encoded[0], UInt8(length))
        }
    }
    
    func testMediumPayloadLengthEncoding() {
        // 测试16位长度编码 (126-65535)
        let testCases: [UInt64] = [126, 1000, 65535]
        
        for length in testCases {
            let encoded = WebSocketPayloadLength.encode(length)
            XCTAssertEqual(encoded.count, 3)
            XCTAssertEqual(encoded[0], 126)
            
            // 验证16位大端编码
            let lengthBytes = encoded.dropFirst()
            let decodedLength = CryptoUtilities.fromBigEndian(lengthBytes, as: UInt16.self)!
            XCTAssertEqual(UInt64(decodedLength), length)
        }
    }
    
    func testLongPayloadLengthEncoding() {
        // 测试64位长度编码 (65536及以上)
        let testCases: [UInt64] = [65536, 1000000, UInt64.max >> 1] // 最高位不能为1
        
        for length in testCases {
            let encoded = WebSocketPayloadLength.encode(length)
            XCTAssertEqual(encoded.count, 9)
            XCTAssertEqual(encoded[0], 127)
            
            // 验证64位大端编码
            let lengthBytes = encoded.dropFirst()
            let decodedLength = CryptoUtilities.fromBigEndian(lengthBytes, as: UInt64.self)!
            XCTAssertEqual(decodedLength, length)
        }
    }
    
    // MARK: - 负载长度解码测试
    
    func testShortPayloadLengthDecoding() throws {
        // 测试7位长度解码
        for length in [0, 1, 125] {
            let data = Data([UInt8(length)])
            let result = try WebSocketPayloadLength.decode(from: data, at: 0)
            XCTAssertEqual(result.length, UInt64(length))
            XCTAssertEqual(result.bytesConsumed, 1)
        }
    }
    
    func testMediumPayloadLengthDecoding() throws {
        // 测试16位长度解码
        let testCases: [UInt16] = [126, 1000, 65535]
        
        for length in testCases {
            var data = Data([126])
            data.append(contentsOf: CryptoUtilities.toBigEndian(length))
            
            let result = try WebSocketPayloadLength.decode(from: data, at: 0)
            XCTAssertEqual(result.length, UInt64(length))
            XCTAssertEqual(result.bytesConsumed, 3)
        }
    }
    
    func testLongPayloadLengthDecoding() throws {
        // 测试64位长度解码
        let testCases: [UInt64] = [65536, 1000000, UInt64.max >> 1]
        
        for length in testCases {
            var data = Data([127])
            data.append(contentsOf: CryptoUtilities.toBigEndian(length))
            
            let result = try WebSocketPayloadLength.decode(from: data, at: 0)
            XCTAssertEqual(result.length, length)
            XCTAssertEqual(result.bytesConsumed, 9)
        }
    }
    
    func testPayloadLengthDecodingErrors() {
        // 测试不完整数据
        XCTAssertThrowsError(try WebSocketPayloadLength.decode(from: Data(), at: 0)) { error in
            XCTAssertTrue(error is WebSocketProtocolError)
        }
        
        // 测试16位长度不完整
        XCTAssertThrowsError(try WebSocketPayloadLength.decode(from: Data([126, 0x12]), at: 0)) { error in
            XCTAssertTrue(error is WebSocketProtocolError)
        }
        
        // 测试64位长度不完整
        let incompleteData = Data([127, 0x00, 0x00, 0x00, 0x01])
        XCTAssertThrowsError(try WebSocketPayloadLength.decode(from: incompleteData, at: 0)) { error in
            XCTAssertTrue(error is WebSocketProtocolError)
        }
        
        // 测试64位长度的MSB设置错误
        var invalidData = Data([127])
        let invalidLength: UInt64 = 0x8000000000000001 // MSB设置为1
        invalidData.append(contentsOf: CryptoUtilities.toBigEndian(invalidLength))
        
        XCTAssertThrowsError(try WebSocketPayloadLength.decode(from: invalidData, at: 0)) { error in
            if case WebSocketProtocolError.invalidFrameFormat = error {
                // 正确的错误类型
            } else {
                XCTFail("Expected invalidFrameFormat error")
            }
        }
    }
    
    // MARK: - 往返编码测试
    
    func testPayloadLengthRoundTrip() throws {
        let testCases: [UInt64] = [
            0, 1, 125,              // 7位编码
            126, 1000, 65535,       // 16位编码
            65536, 1000000,         // 64位编码
            UInt64.max >> 1         // 最大有效值
        ]
        
        for originalLength in testCases {
            let encoded = WebSocketPayloadLength.encode(originalLength)
            let result = try WebSocketPayloadLength.decode(from: encoded, at: 0)
            
            XCTAssertEqual(result.length, originalLength, "Round trip failed for length \(originalLength)")
            XCTAssertEqual(result.bytesConsumed, encoded.count)
        }
    }
    
    // MARK: - 偏移量解码测试
    
    func testPayloadLengthDecodingWithOffset() throws {
        // 测试在数据中间解码
        let prefix = Data([0xFF, 0xAA, 0xBB])
        let lengthData = WebSocketPayloadLength.encode(1000)
        let suffix = Data([0xCC, 0xDD])
        
        var testData = prefix
        testData.append(lengthData)
        testData.append(suffix)
        
        let result = try WebSocketPayloadLength.decode(from: testData, at: prefix.count)
        XCTAssertEqual(result.length, 1000)
        XCTAssertEqual(result.bytesConsumed, lengthData.count)
    }
    
    func testDecodingBeyondDataBounds() {
        let data = Data([126, 0x03, 0xE8]) // length = 1000
        
        // 测试offset超出数据范围
        XCTAssertThrowsError(try WebSocketPayloadLength.decode(from: data, at: data.count)) { error in
            XCTAssertTrue(error is WebSocketProtocolError)
        }
        
        XCTAssertThrowsError(try WebSocketPayloadLength.decode(from: data, at: 100)) { error in
            XCTAssertTrue(error is WebSocketProtocolError)
        }
    }
}