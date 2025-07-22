import Foundation
import Network
@preconcurrency import Security

/// TLS配置选项
public struct TLSConfiguration: Sendable {
    
    /// 证书验证策略
    public enum CertificateVerification: Sendable, Equatable {
        case `default`           // 默认系统验证
        case disabled           // 禁用验证（仅用于开发）
        case pinned([SecCertificate])  // 证书固定
        // 注意：自定义验证闭包暂时移除以支持Sendable
        
        public static func == (lhs: CertificateVerification, rhs: CertificateVerification) -> Bool {
            switch (lhs, rhs) {
            case (.default, .default), (.disabled, .disabled):
                return true
            case (.pinned, .pinned):
                return true  // 简化处理，不比较具体证书
            default:
                return false
            }
        }
    }
    
    /// 支持的TLS版本
    public enum TLSVersion: Sendable, Equatable {
        case tls12
        case tls13
        case any
    }
    
    // MARK: - 配置属性
    
    /// 最低TLS版本
    public let minimumTLSVersion: TLSVersion
    
    /// 最高TLS版本
    public let maximumTLSVersion: TLSVersion
    
    /// 证书验证策略
    public let certificateVerification: CertificateVerification
    
    /// 是否验证主机名
    public let verifyHostname: Bool
    
    /// 支持的加密套件（nil表示使用系统默认）
    public let cipherSuites: [UInt16]?
    
    /// ALPN协议列表
    public let applicationProtocols: [String]
    
    // MARK: - 初始化
    
    public init(
        minimumTLSVersion: TLSVersion = .tls12,
        maximumTLSVersion: TLSVersion = .any,
        certificateVerification: CertificateVerification = .default,
        verifyHostname: Bool = true,
        cipherSuites: [UInt16]? = nil,
        applicationProtocols: [String] = []
    ) {
        self.minimumTLSVersion = minimumTLSVersion
        self.maximumTLSVersion = maximumTLSVersion
        self.certificateVerification = certificateVerification
        self.verifyHostname = verifyHostname
        self.cipherSuites = cipherSuites
        self.applicationProtocols = applicationProtocols
    }
    
    // MARK: - 预定义配置
    
    /// 默认安全配置
    public static let secure = TLSConfiguration()
    
    /// 开发环境配置（跳过证书验证）
    public static let development = TLSConfiguration(
        certificateVerification: .disabled,
        verifyHostname: false
    )
    
    /// WebSocket安全配置
    public static let webSocket = TLSConfiguration(
        minimumTLSVersion: .tls12,
        applicationProtocols: ["http/1.1"]
    )
}

// MARK: - NWProtocolTLS.Options扩展

extension NWProtocolTLS.Options {
    
    /// 从TLSConfiguration创建TLS选项
    /// - Parameter config: TLS配置
    /// - Returns: 配置好的TLS选项
    static func from(_ config: TLSConfiguration) -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        
        // 设置证书验证策略
        switch config.certificateVerification {
        case .default:
            // 使用默认验证
            break
            
        case .disabled:
            // 禁用证书验证（仅开发环境）
            sec_protocol_options_set_verify_block(
                options.securityProtocolOptions,
                { _, _, sec_protocol_verify_complete in
                    sec_protocol_verify_complete(true)
                },
                DispatchQueue.global()
            )
            
        case .pinned:
            // 证书固定验证暂时使用默认验证
            // 完整实现需要更复杂的证书链验证逻辑
            break
        }
        
        return options
    }
}

// MARK: - TLS错误

extension NetworkError {
    
    /// TLS握手超时
    static let tlsHandshakeTimeout = NetworkError.tlsHandshakeFailed(
        NSError(domain: "TLSError", code: -1001, userInfo: [
            NSLocalizedDescriptionKey: "TLS握手超时"
        ])
    )
    
    /// 证书验证失败
    static func certificateValidationFailed(_ reason: String) -> NetworkError {
        return .tlsHandshakeFailed(
            NSError(domain: "TLSError", code: -1002, userInfo: [
                NSLocalizedDescriptionKey: "证书验证失败: \(reason)"
            ])
        )
    }
    
    /// 不支持的TLS版本
    static let unsupportedTLSVersion = NetworkError.tlsHandshakeFailed(
        NSError(domain: "TLSError", code: -1003, userInfo: [
            NSLocalizedDescriptionKey: "不支持的TLS版本"
        ])
    )
}