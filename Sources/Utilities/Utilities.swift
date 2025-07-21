import Foundation

/// WebSocket工具类模块
/// 提供通用的工具函数和扩展
public struct Utilities {
    
    /// 模块版本信息
    public static let version = "1.0.0"
    
    /// 初始化方法
    public init() {}
}

// MARK: - 字符串扩展
public extension String {
    /// 计算UTF-8字节数
    var utf8ByteCount: Int {
        return self.utf8.count
    }
}

// MARK: - Data扩展  
public extension Data {
    /// 转换为十六进制字符串
    var hexString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}