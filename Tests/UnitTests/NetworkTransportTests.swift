import XCTest
@testable import NetworkTransport

/// 网络传输基础测试
final class NetworkTransportTests: XCTestCase {
    
    /// 测试连接状态枚举的相等性
    func testConnectionStateEquality() {
        XCTAssertEqual(ConnectionState.disconnected, ConnectionState.disconnected)
        XCTAssertEqual(ConnectionState.connecting, ConnectionState.connecting)
        XCTAssertEqual(ConnectionState.connected, ConnectionState.connected)
        
        let error1 = NetworkError.connectionTimeout
        let error2 = NetworkError.hostUnreachable
        XCTAssertEqual(ConnectionState.failed(error1), ConnectionState.failed(error2))
        
        XCTAssertNotEqual(ConnectionState.disconnected, ConnectionState.connecting)
        XCTAssertNotEqual(ConnectionState.connecting, ConnectionState.connected)
    }
    
    /// 测试网络错误的本地化描述
    func testNetworkErrorDescriptions() {
        let errors: [NetworkError] = [
            .connectionTimeout,
            .hostUnreachable,
            .connectionFailed(NSError(domain: "test", code: 1)),
            .connectionReset,
            .notConnected,
            .invalidState("test state")
        ]
        
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "错误描述不应该为空: \(error)")
            // 恢复建议可能为空，所以不强制要求
        }
    }
    
    /// 测试TCPTransport基本功能
    func testTCPTransportBasics() async {
        let transport = TCPTransport()
        
        // 测试未连接时的操作应该失败
        do {
            let testData = "test".data(using: .utf8)!
            try await transport.send(data: testData)
            XCTFail("应该抛出错误")
        } catch NetworkError.notConnected {
            // 预期的错误
        } catch {
            XCTFail("意外的错误: \(error)")
        }
        
        do {
            _ = try await transport.receive()
            XCTFail("应该抛出错误")
        } catch NetworkError.notConnected {
            // 预期的错误
        } catch {
            XCTFail("意外的错误: \(error)")
        }
        
        // 断开连接应该总是成功
        await transport.disconnect()
    }
    
    /// 测试连接到无效主机
    func testConnectToInvalidHost() async {
        let transport = TCPTransport()
        
        do {
            try await transport.connect(to: "invalid.host.example", port: 80, useTLS: false)
            XCTFail("应该抛出错误")
        } catch let error as NetworkError {
            // 验证错误类型合理
            switch error {
            case .connectionTimeout, .connectionFailed, .hostUnreachable:
                // 这些都是合理的错误类型
                break
            default:
                XCTFail("意外的错误类型: \(error)")
            }
        } catch {
            XCTFail("意外的错误: \(error)")
        }
        
        await transport.disconnect()
    }
    
    /// 测试TLS配置
    func testTLSConfiguration() {
        let secureConfig = TLSConfiguration.secure
        let devConfig = TLSConfiguration.development
        let wsConfig = TLSConfiguration.webSocket
        
        XCTAssertEqual(secureConfig.minimumTLSVersion, .tls12)
        XCTAssertEqual(devConfig.certificateVerification, .disabled)
        XCTAssertEqual(wsConfig.applicationProtocols, ["http/1.1"])
    }
    
    /// 测试TLS连接方法
    func testTLSConnectionMethods() async {
        let transport = TCPTransport()
        
        // 测试无效主机的TLS连接
        do {
            try await transport.connectSecure(to: "invalid.host.example", port: 443)
            XCTFail("应该抛出错误")
        } catch let error as NetworkError {
            // 验证错误类型合理
            switch error {
            case .connectionTimeout, .connectionFailed, .hostUnreachable:
                // 这些都是合理的错误类型
                break
            default:
                XCTFail("意外的错误类型: \(error)")
            }
        } catch {
            XCTFail("意外的错误: \(error)")
        }
        
        await transport.disconnect()
    }
}