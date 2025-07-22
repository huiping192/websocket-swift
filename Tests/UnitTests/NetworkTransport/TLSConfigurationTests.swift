import XCTest
@testable import NetworkTransport
import Network

final class TLSConfigurationTests: XCTestCase {
    
    // MARK: - 基础配置测试
    
    /// 测试默认TLS配置
    func testDefaultTLSConfiguration() {
        let config = TLSConfiguration()
        
        XCTAssertEqual(config.minimumTLSVersion, .tls12, "默认最低TLS版本应为1.2")
        XCTAssertEqual(config.maximumTLSVersion, .any, "默认最高TLS版本应为any")
        XCTAssertEqual(config.certificateVerification, .default, "默认证书验证应为default")
        XCTAssertTrue(config.verifyHostname, "默认应验证主机名")
        XCTAssertNil(config.cipherSuites, "默认加密套件应为nil")
        XCTAssertEqual(config.applicationProtocols, [], "默认应用协议应为空")
    }
    
    /// 测试自定义TLS配置
    func testCustomTLSConfiguration() {
        let config = TLSConfiguration(
            minimumTLSVersion: .tls13,
            maximumTLSVersion: .tls13,
            certificateVerification: .disabled,
            verifyHostname: false,
            cipherSuites: [0x1301], // TLS_AES_128_GCM_SHA256
            applicationProtocols: ["http/1.1", "h2"]
        )
        
        XCTAssertEqual(config.minimumTLSVersion, .tls13)
        XCTAssertEqual(config.maximumTLSVersion, .tls13)
        XCTAssertEqual(config.certificateVerification, .disabled)
        XCTAssertFalse(config.verifyHostname)
        XCTAssertEqual(config.cipherSuites, [0x1301])
        XCTAssertEqual(config.applicationProtocols, ["http/1.1", "h2"])
    }
    
    // MARK: - 预定义配置测试
    
    /// 测试安全配置
    func testSecureConfiguration() {
        let config = TLSConfiguration.secure
        
        XCTAssertEqual(config.minimumTLSVersion, .tls12)
        XCTAssertEqual(config.maximumTLSVersion, .any)
        XCTAssertEqual(config.certificateVerification, .default)
        XCTAssertTrue(config.verifyHostname)
        XCTAssertNil(config.cipherSuites)
        XCTAssertEqual(config.applicationProtocols, [])
    }
    
    /// 测试开发配置
    func testDevelopmentConfiguration() {
        let config = TLSConfiguration.development
        
        XCTAssertEqual(config.minimumTLSVersion, .tls12)
        XCTAssertEqual(config.certificateVerification, .disabled)
        XCTAssertFalse(config.verifyHostname)
    }
    
    /// 测试WebSocket配置
    func testWebSocketConfiguration() {
        let config = TLSConfiguration.webSocket
        
        XCTAssertEqual(config.minimumTLSVersion, .tls12)
        XCTAssertEqual(config.applicationProtocols, ["http/1.1"])
        XCTAssertEqual(config.certificateVerification, .default)
        XCTAssertTrue(config.verifyHostname)
    }
    
    // MARK: - 证书验证策略测试
    
    /// 测试证书验证策略相等性
    func testCertificateVerificationEquality() {
        XCTAssertEqual(TLSConfiguration.CertificateVerification.default, .default)
        XCTAssertEqual(TLSConfiguration.CertificateVerification.disabled, .disabled)
        
        XCTAssertNotEqual(TLSConfiguration.CertificateVerification.default, .disabled)
        XCTAssertNotEqual(TLSConfiguration.CertificateVerification.disabled, .default)
        
        // 测试证书固定（简化处理，认为所有固定配置相等）
        let cert1: [SecCertificate] = []
        let cert2: [SecCertificate] = []
        XCTAssertEqual(TLSConfiguration.CertificateVerification.pinned(cert1), .pinned(cert2))
    }
    
    // MARK: - TLS版本测试
    
    /// 测试TLS版本枚举
    func testTLSVersionEnum() {
        XCTAssertEqual(TLSConfiguration.TLSVersion.tls12, .tls12)
        XCTAssertEqual(TLSConfiguration.TLSVersion.tls13, .tls13)
        XCTAssertEqual(TLSConfiguration.TLSVersion.any, .any)
        
        XCTAssertNotEqual(TLSConfiguration.TLSVersion.tls12, .tls13)
        XCTAssertNotEqual(TLSConfiguration.TLSVersion.tls13, .any)
    }
    
    // MARK: - NWProtocolTLS.Options 转换测试
    
    /// 测试从TLS配置创建NW选项
    func testNWProtocolTLSOptionsCreation() {
        let config = TLSConfiguration.secure
        let options = NWProtocolTLS.Options.from(config)
        
        XCTAssertNotNil(options, "应该成功创建TLS选项")
    }
    
    /// 测试禁用证书验证的TLS选项
    func testDisabledCertificateVerificationOptions() {
        let config = TLSConfiguration.development
        let options = NWProtocolTLS.Options.from(config)
        
        XCTAssertNotNil(options, "应该成功创建开发环境TLS选项")
    }
    
    /// 测试WebSocket TLS选项
    func testWebSocketTLSOptions() {
        let config = TLSConfiguration.webSocket
        let options = NWProtocolTLS.Options.from(config)
        
        XCTAssertNotNil(options, "应该成功创建WebSocket TLS选项")
    }
    
    // MARK: - 边界条件测试
    
    /// 测试空应用协议列表
    func testEmptyApplicationProtocols() {
        let config = TLSConfiguration(applicationProtocols: [])
        
        XCTAssertEqual(config.applicationProtocols, [])
        
        let options = NWProtocolTLS.Options.from(config)
        XCTAssertNotNil(options)
    }
    
    /// 测试多个应用协议
    func testMultipleApplicationProtocols() {
        let protocols = ["http/1.1", "h2", "h3"]
        let config = TLSConfiguration(applicationProtocols: protocols)
        
        XCTAssertEqual(config.applicationProtocols, protocols)
        
        let options = NWProtocolTLS.Options.from(config)
        XCTAssertNotNil(options)
    }
    
    /// 测试自定义加密套件
    func testCustomCipherSuites() {
        let cipherSuites: [UInt16] = [0x1301, 0x1302, 0x1303] // TLS 1.3 cipher suites
        let config = TLSConfiguration(cipherSuites: cipherSuites)
        
        XCTAssertEqual(config.cipherSuites, cipherSuites)
    }
    
    /// 测试空加密套件列表
    func testEmptyCipherSuites() {
        let config = TLSConfiguration(cipherSuites: [])
        
        XCTAssertEqual(config.cipherSuites, [])
    }
    
    // MARK: - 配置组合测试
    
    /// 测试高安全性配置
    func testHighSecurityConfiguration() {
        let config = TLSConfiguration(
            minimumTLSVersion: .tls13,
            maximumTLSVersion: .tls13,
            certificateVerification: .default,
            verifyHostname: true,
            cipherSuites: [0x1301], // Only AES-128-GCM
            applicationProtocols: ["h2"]
        )
        
        XCTAssertEqual(config.minimumTLSVersion, .tls13)
        XCTAssertEqual(config.maximumTLSVersion, .tls13)
        XCTAssertEqual(config.certificateVerification, .default)
        XCTAssertTrue(config.verifyHostname)
        XCTAssertEqual(config.cipherSuites, [0x1301])
        XCTAssertEqual(config.applicationProtocols, ["h2"])
        
        let options = NWProtocolTLS.Options.from(config)
        XCTAssertNotNil(options)
    }
    
    /// 测试低安全性配置（开发环境）
    func testLowSecurityConfiguration() {
        let config = TLSConfiguration(
            minimumTLSVersion: .tls12,
            certificateVerification: .disabled,
            verifyHostname: false
        )
        
        XCTAssertEqual(config.minimumTLSVersion, .tls12)
        XCTAssertEqual(config.certificateVerification, .disabled)
        XCTAssertFalse(config.verifyHostname)
        
        let options = NWProtocolTLS.Options.from(config)
        XCTAssertNotNil(options)
    }
    
    // MARK: - 错误扩展测试
    
    /// 测试TLS握手超时错误
    func testTLSHandshakeTimeoutError() {
        let error = NetworkError.tlsHandshakeTimeout
        
        if case .tlsHandshakeFailed = error {
            // 正确的错误类型
        } else {
            XCTFail("应该是TLS握手失败错误")
        }
        
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("握手超时") ?? false)
    }
    
    /// 测试证书验证失败错误
    func testCertificateValidationFailedError() {
        let reason = "证书已过期"
        let error = NetworkError.certificateValidationFailed(reason)
        
        if case .tlsHandshakeFailed = error {
            // 正确的错误类型
        } else {
            XCTFail("应该是TLS握手失败错误")
        }
        
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains(reason) ?? false)
    }
    
    /// 测试不支持的TLS版本错误
    func testUnsupportedTLSVersionError() {
        let error = NetworkError.unsupportedTLSVersion
        
        if case .tlsHandshakeFailed = error {
            // 正确的错误类型
        } else {
            XCTFail("应该是TLS握手失败错误")
        }
        
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("TLS版本") ?? false)
    }
}