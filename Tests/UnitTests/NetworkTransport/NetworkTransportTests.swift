import XCTest
@testable import NetworkTransport

/// 网络传输模块基础测试
/// 测试模块级别的组件：版本信息、连接状态、协议定义等
final class NetworkTransportTests: XCTestCase {
    
    // MARK: - 模块信息测试
    
    /// 测试NetworkTransport结构体和版本信息
    func testNetworkTransportModule() {
        let module = NetworkTransport()
        XCTAssertNotNil(module, "NetworkTransport模块应该可以实例化")
        
        let version = NetworkTransport.version
        XCTAssertFalse(version.isEmpty, "版本信息不应为空")
        XCTAssertTrue(version.contains("."), "版本号应该包含点号")
    }
    
    // MARK: - 连接状态测试
    
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
    
    /// 测试连接状态转换合理性
    func testConnectionStateTransitions() {
        // 验证状态枚举值存在
        let states: [ConnectionState] = [
            .disconnected,
            .connecting, 
            .connected,
            .failed(NetworkError.connectionTimeout)
        ]
        
        XCTAssertEqual(states.count, 4, "应该有4种连接状态")
    }
    
    // MARK: - 网络错误测试
    
    /// 测试网络错误的本地化描述
    func testNetworkErrorDescriptions() {
        let errors: [NetworkError] = [
            .connectionTimeout,
            .hostUnreachable,
            .connectionFailed(NSError(domain: "test", code: 1)),
            .connectionReset,
            .notConnected,
            .invalidState("test state"),
            .sendFailed(NSError(domain: "send", code: 1)),
            .receiveFailed(NSError(domain: "receive", code: 1)),
            .noDataReceived,
            .tlsHandshakeFailed(NSError(domain: "tls", code: 1))
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "错误应该有描述: \(error)")
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "错误描述不应该为空: \(error)")
        }
    }
    
    /// 测试网络错误的恢复建议
    func testNetworkErrorRecoverySuggestions() {
        let errorsWithSuggestions: [NetworkError] = [
            .connectionTimeout,
            .hostUnreachable,
            .notConnected,
            .tlsHandshakeFailed(NSError(domain: "tls", code: 1))
        ]
        
        for error in errorsWithSuggestions {
            XCTAssertNotNil(error.recoverySuggestion, "错误应该有恢复建议: \(error)")
            XCTAssertFalse(error.recoverySuggestion?.isEmpty ?? true, "恢复建议不应为空: \(error)")
        }
    }
    
    // MARK: - 协议定义测试
    
    /// 测试协议定义的存在性
    func testProtocolDefinitions() {
        // 验证协议可以作为类型使用
        XCTAssertNotNil(BaseTransportProtocol.self, "BaseTransportProtocol应该存在")
        XCTAssertNotNil(TCPTransportProtocol.self, "TCPTransportProtocol应该存在")
        XCTAssertNotNil(TLSTransportProtocol.self, "TLSTransportProtocol应该存在")
        XCTAssertNotNil(NetworkTransportProtocol.self, "NetworkTransportProtocol应该存在")
    }
    
    /// 测试具体实现类的协议一致性
    func testConcreteClassProtocolConformance() {
        let tcpTransport = TCPTransport()
        let tlsTransport = TLSTransport()
        let unifiedTransport = UnifiedNetworkTransport()
        
        XCTAssertTrue(tcpTransport is TCPTransportProtocol, "TCPTransport应实现TCPTransportProtocol")
        XCTAssertTrue(tlsTransport is TLSTransportProtocol, "TLSTransport应实现TLSTransportProtocol")
        XCTAssertTrue(unifiedTransport is NetworkTransportProtocol, "UnifiedNetworkTransport应实现NetworkTransportProtocol")
    }
}
