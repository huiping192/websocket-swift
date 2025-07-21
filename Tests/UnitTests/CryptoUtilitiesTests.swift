import XCTest
@testable import Utilities

/// CryptoUtilities单元测试
final class CryptoUtilitiesTests: XCTestCase {
    
    // MARK: - 密钥生成测试
    
    /// 测试WebSocket密钥生成
    func testWebSocketKeyGeneration() {
        let key1 = CryptoUtilities.generateWebSocketKey()
        let key2 = CryptoUtilities.generateWebSocketKey()
        
        // 密钥不应该相同（随机性）
        XCTAssertNotEqual(key1, key2)
        
        // 密钥应该是有效的Base64字符串，解码后长度为16字节
        let keyData1 = Data(base64Encoded: key1)
        let keyData2 = Data(base64Encoded: key2)
        
        XCTAssertNotNil(keyData1)
        XCTAssertNotNil(keyData2)
        XCTAssertEqual(keyData1?.count, 16)
        XCTAssertEqual(keyData2?.count, 16)
    }
    
    /// 测试随机数据生成
    func testRandomDataGeneration() {
        let data1 = CryptoUtilities.generateRandomData(length: 10)
        let data2 = CryptoUtilities.generateRandomData(length: 10)
        
        XCTAssertEqual(data1.count, 10)
        XCTAssertEqual(data2.count, 10)
        XCTAssertNotEqual(data1, data2) // 随机性检查
        
        // 测试边界情况
        let emptyData = CryptoUtilities.generateRandomData(length: 0)
        XCTAssertEqual(emptyData.count, 0)
        
        let largeData = CryptoUtilities.generateRandomData(length: 1000)
        XCTAssertEqual(largeData.count, 1000)
    }
    
    /// 测试掩码密钥生成
    func testMaskingKeyGeneration() {
        let maskingKey1 = CryptoUtilities.generateMaskingKey()
        let maskingKey2 = CryptoUtilities.generateMaskingKey()
        
        XCTAssertEqual(maskingKey1.count, 4)
        XCTAssertEqual(maskingKey2.count, 4)
        XCTAssertNotEqual(maskingKey1, maskingKey2) // 随机性检查
    }
    
    // MARK: - WebSocket Accept密钥计算测试
    
    /// 测试WebSocket Accept密钥计算
    func testWebSocketAcceptComputation() {
        // 使用RFC 6455示例中的测试向量
        let testKey = "dGhlIHNhbXBsZSBub25jZQ=="
        let expectedAccept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        
        let computedAccept = CryptoUtilities.computeWebSocketAccept(for: testKey)
        XCTAssertEqual(computedAccept, expectedAccept)
    }
    
    /// 测试不同输入的Accept密钥计算
    func testWebSocketAcceptComputationVariousInputs() {
        // 这些测试向量是通过标准WebSocket Accept计算得出的
        let testCases = [
            ("", "Kfh9QIsMVZcl6xEPYxPHzW8SZ8w="),
            ("test", "tNpbgC8ZQDOcSkHAWopKzQjJ1hI="),
            ("hello", "jzJp3eyq17jrlFXeK8QioU1Pyfo=")
        ]
        
        for (input, expected) in testCases {
            let result = CryptoUtilities.computeWebSocketAccept(for: input)
            XCTAssertEqual(result, expected, "Accept计算失败，输入: '\(input)'")
        }
    }
    
    // MARK: - SHA1哈希测试
    
    /// 测试SHA1哈希计算
    func testSHA1Computation() {
        // 测试已知的SHA1哈希
        let testCases = [
            ("hello", "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d"),
            ("", "da39a3ee5e6b4b0d3255bfef95601890afd80709"),
            ("abc", "a9993e364706816aba3e25717850c26c9cd0d89d"),
            ("The quick brown fox jumps over the lazy dog", "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12")
        ]
        
        for (input, expectedHex) in testCases {
            let inputData = Data(input.utf8)
            let hashData = CryptoUtilities.computeSHA1(inputData)
            let computedHex = hashData.hexString
            XCTAssertEqual(computedHex, expectedHex, "SHA1计算失败，输入: '\(input)'")
        }
    }
    
    // MARK: - Base64编码/解码测试
    
    /// 测试Base64编码
    func testBase64Encoding() {
        let testCases = [
            ("hello", "aGVsbG8="),
            ("", ""),
            ("f", "Zg=="),
            ("fo", "Zm8="),
            ("foo", "Zm9v"),
            ("foob", "Zm9vYg=="),
            ("fooba", "Zm9vYmE="),
            ("foobar", "Zm9vYmFy")
        ]
        
        for (input, expected) in testCases {
            let inputData = Data(input.utf8)
            let encoded = CryptoUtilities.base64Encode(inputData)
            XCTAssertEqual(encoded, expected, "Base64编码失败，输入: '\(input)'")
        }
    }
    
    /// 测试Base64解码
    func testBase64Decoding() {
        let testCases = [
            ("aGVsbG8=", "hello"),
            ("", ""),
            ("Zg==", "f"),
            ("Zm8=", "fo"),
            ("Zm9v", "foo"),
            ("Zm9vYg==", "foob"),
            ("Zm9vYmE=", "fooba"),
            ("Zm9vYmFy", "foobar")
        ]
        
        for (input, expected) in testCases {
            guard let decodedData = CryptoUtilities.base64Decode(input) else {
                XCTFail("Base64解码失败，输入: '\(input)'")
                continue
            }
            let decodedString = String(data: decodedData, encoding: .utf8)
            XCTAssertEqual(decodedString, expected, "Base64解码结果错误，输入: '\(input)'")
        }
    }
    
    /// 测试无效Base64字符串解码
    func testInvalidBase64Decoding() {
        let invalidInputs = ["!", "invalid", "Zm9!!!"]
        
        for input in invalidInputs {
            let result = CryptoUtilities.base64Decode(input)
            XCTAssertNil(result, "无效Base64字符串应该返回nil: '\(input)'")
        }
    }
    
    // MARK: - 数据掩码测试
    
    /// 测试数据掩码应用
    func testDataMasking() {
        let originalData = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]) // "Hello"
        let maskingKey = Data([0x37, 0xFA, 0x21, 0x3D])
        
        let maskedData = CryptoUtilities.applyMask(originalData, maskingKey: maskingKey)
        XCTAssertNotEqual(maskedData, originalData)
        XCTAssertEqual(maskedData.count, originalData.count)
        
        // 测试掩码操作的对称性
        let unmaskedData = CryptoUtilities.removeMask(maskedData, maskingKey: maskingKey)
        XCTAssertEqual(unmaskedData, originalData)
    }
    
    /// 测试空数据掩码
    func testEmptyDataMasking() {
        let emptyData = Data()
        let maskingKey = Data([0x37, 0xFA, 0x21, 0x3D])
        
        let maskedData = CryptoUtilities.applyMask(emptyData, maskingKey: maskingKey)
        XCTAssertEqual(maskedData, emptyData)
    }
    
    /// 测试无效掩码密钥
    func testInvalidMaskingKey() {
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])
        let invalidKey = Data([0x37, 0xFA]) // 只有2字节，应该是4字节
        
        let result = CryptoUtilities.applyMask(data, maskingKey: invalidKey)
        XCTAssertEqual(result, data) // 应该返回原始数据
    }
    
    // MARK: - 数据扩展测试
    
    /// 测试十六进制字符串创建Data
    func testDataFromHexString() {
        let testCases = [
            ("48656c6c6f", Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])), // "Hello"
            ("", Data()),
            ("00", Data([0x00])),
            ("ff", Data([0xFF])),
            ("48 65 6c 6c 6f", Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])) // 带空格
        ]
        
        for (hexString, expectedData) in testCases {
            let result = Data(hexString: hexString)
            XCTAssertEqual(result, expectedData, "十六进制字符串转Data失败: '\(hexString)'")
        }
    }
    
    /// 测试无效十六进制字符串
    func testInvalidHexString() {
        let invalidInputs = ["g", "48g", "4", "xyz"]
        
        for input in invalidInputs {
            let result = Data(hexString: input)
            XCTAssertNil(result, "无效十六进制字符串应该返回nil: '\(input)'")
        }
    }
    
    // MARK: - 字节序转换测试
    
    /// 测试大端字节序转换
    func testBigEndianConversion() {
        let value16: UInt16 = 0x1234
        let value32: UInt32 = 0x12345678
        let value64: UInt64 = 0x123456789ABCDEF0
        
        let data16 = CryptoUtilities.toBigEndian(value16)
        let data32 = CryptoUtilities.toBigEndian(value32)
        let data64 = CryptoUtilities.toBigEndian(value64)
        
        XCTAssertEqual(data16, Data([0x12, 0x34]))
        XCTAssertEqual(data32, Data([0x12, 0x34, 0x56, 0x78]))
        XCTAssertEqual(data64, Data([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0]))
    }
    
    /// 测试从大端字节序转换
    func testFromBigEndianConversion() {
        let data16 = Data([0x12, 0x34])
        let data32 = Data([0x12, 0x34, 0x56, 0x78])
        let data64 = Data([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0])
        
        let value16 = CryptoUtilities.fromBigEndian(data16, as: UInt16.self)
        let value32 = CryptoUtilities.fromBigEndian(data32, as: UInt32.self)
        let value64 = CryptoUtilities.fromBigEndian(data64, as: UInt64.self)
        
        XCTAssertEqual(value16, 0x1234)
        XCTAssertEqual(value32, 0x12345678)
        XCTAssertEqual(value64, 0x123456789ABCDEF0)
    }
    
    /// 测试字节序转换错误处理
    func testInvalidByteOrderConversion() {
        let shortData = Data([0x12])
        let result = CryptoUtilities.fromBigEndian(shortData, as: UInt16.self)
        XCTAssertNil(result, "数据长度不匹配应该返回nil")
    }
    
    // MARK: - 常量测试
    
    /// 测试魔术字符串常量
    func testMagicStringConstant() {
        XCTAssertEqual(CryptoUtilities.webSocketMagicString, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
    }
} 