import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(CommonCrypto)
import CommonCrypto
#endif

/// WebSocket加密工具类
/// 提供WebSocket协议所需的加密和哈希功能
public struct CryptoUtilities {
    
    /// WebSocket魔术字符串
    public static let webSocketMagicString = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    
    public init() {}
    
    // MARK: - 密钥生成
    
    /// 生成WebSocket密钥
    /// - Returns: Base64编码的16字节随机密钥
    public static func generateWebSocketKey() -> String {
        let keyData = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        return keyData.base64EncodedString()
    }
    
    /// 生成指定长度的随机数据
    /// - Parameter length: 随机数据长度
    /// - Returns: 随机数据
    public static func generateRandomData(length: Int) -> Data {
        return Data((0..<length).map { _ in UInt8.random(in: 0...255) })
    }
    
    /// 生成掩码密钥（WebSocket帧掩码用）
    /// - Returns: 4字节掩码密钥
    public static func generateMaskingKey() -> Data {
        return generateRandomData(length: 4)
    }
    
    // MARK: - WebSocket Accept密钥计算
    
    /// 计算WebSocket Accept密钥
    /// - Parameter clientKey: 客户端密钥
    /// - Returns: 服务器应该返回的Accept密钥
    public static func computeWebSocketAccept(for clientKey: String) -> String {
        let combined = clientKey + webSocketMagicString
        let data = Data(combined.utf8)
        let hash = computeSHA1(data)
        return hash.base64EncodedString()
    }
    
    // MARK: - 哈希计算
    
    /// 计算SHA1哈希
    /// - Parameter data: 输入数据
    /// - Returns: SHA1哈希结果
    public static func computeSHA1(_ data: Data) -> Data {
        // 优先使用CryptoKit（iOS 13+）
        #if canImport(CryptoKit)
        if #available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *) {
            let hash = Insecure.SHA1.hash(data: data)
            return Data(hash)
        }
        #endif
        
        // 回退到CommonCrypto
        return computeSHA1WithCommonCrypto(data)
    }
    
    /// 使用CommonCrypto计算SHA1哈希
    /// - Parameter data: 输入数据
    /// - Returns: SHA1哈希结果
    private static func computeSHA1WithCommonCrypto(_ data: Data) -> Data {
        #if canImport(CommonCrypto)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.bindMemory(to: UInt8.self).baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
        #else
        // 如果CommonCrypto不可用，抛出错误
        fatalError("SHA1计算需要CryptoKit或CommonCrypto支持")
        #endif
    }
    
    // MARK: - Base64编码/解码
    
    /// Base64编码
    /// - Parameter data: 原始数据
    /// - Returns: Base64编码字符串
    public static func base64Encode(_ data: Data) -> String {
        return data.base64EncodedString()
    }
    
    /// Base64解码
    /// - Parameter string: Base64编码字符串
    /// - Returns: 解码后的数据，失败返回nil
    public static func base64Decode(_ string: String) -> Data? {
        return Data(base64Encoded: string)
    }
    
    // MARK: - 数据掩码处理
    
    /// 应用WebSocket掩码
    /// - Parameters:
    ///   - data: 原始数据
    ///   - maskingKey: 4字节掩码密钥
    /// - Returns: 掩码处理后的数据
    public static func applyMask(_ data: Data, maskingKey: Data) -> Data {
        guard maskingKey.count == 4 else {
            return data
        }
        
        var maskedData = Data(capacity: data.count)
        for (index, byte) in data.enumerated() {
            let maskByte = maskingKey[index % 4]
            maskedData.append(byte ^ maskByte)
        }
        
        return maskedData
    }
    
    /// 移除WebSocket掩码（解掩码）
    /// - Parameters:
    ///   - data: 掩码数据
    ///   - maskingKey: 4字节掩码密钥
    /// - Returns: 解掩码后的数据
    public static func removeMask(_ data: Data, maskingKey: Data) -> Data {
        // 掩码操作是对称的，应用掩码和移除掩码是同一个操作
        return applyMask(data, maskingKey: maskingKey)
    }
}

// MARK: - 数据扩展

public extension Data {
    /// 从十六进制字符串创建Data
    /// - Parameter hexString: 十六进制字符串
    init?(hexString: String) {
        let cleanHex = hexString.replacingOccurrences(of: " ", with: "")
        guard cleanHex.count % 2 == 0 else { return nil }
        
        var data = Data()
        var index = cleanHex.startIndex
        
        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2)
            let byteString = String(cleanHex[index..<nextIndex])
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
}

// MARK: - 字节序转换

public extension CryptoUtilities {
    
    /// 转换为大端字节序（网络字节序）
    /// - Parameter value: 原始值
    /// - Returns: 大端字节序数据
    static func toBigEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        let bigEndianValue = value.bigEndian
        return withUnsafeBytes(of: bigEndianValue) { Data($0) }
    }
    
    /// 从大端字节序转换
    /// - Parameters:
    ///   - data: 大端字节序数据
    ///   - type: 目标类型
    /// - Returns: 转换后的值
    static func fromBigEndian<T: FixedWidthInteger>(_ data: Data, as type: T.Type) -> T? {
        guard data.count == MemoryLayout<T>.size else { return nil }
        return data.withUnsafeBytes { bytes in
            guard let boundMemory = bytes.bindMemory(to: T.self).first else { return nil }
            return T(bigEndian: boundMemory)
        }
    }
} 