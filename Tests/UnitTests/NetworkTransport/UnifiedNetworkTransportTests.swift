import XCTest
@testable import NetworkTransport

/// UnifiedNetworkTransport测试
/// 测试统一网络传输适配器的功能
final class UnifiedNetworkTransportTests: XCTestCase {
    
    var transport: UnifiedNetworkTransport!
    
    override func setUp() {
        super.setUp()
        // 使用较短的超时时间用于测试（1秒）
        transport = UnifiedNetworkTransport(timeout: 1.0)
    }
    
    override func tearDown() {
        if let transport = transport {
            Task {
                await transport.disconnect()
            }
        }
        transport = nil
        super.tearDown()
    }
    
    // MARK: - 基础功能测试
    
    /// 测试UnifiedNetworkTransport初始化
    func testUnifiedNetworkTransportInitialization() {
        let transport = UnifiedNetworkTransport(timeout: 1.0)
        XCTAssertNotNil(transport, "UnifiedNetworkTransport应该成功初始化")
    }
    
    /// 测试协议一致性
    func testProtocolConformance() {
        XCTAssertNotNil(transport, "transport不应为nil")
        if let transport = transport {
            XCTAssertTrue(transport is NetworkTransportProtocol, "UnifiedNetworkTransport应实现NetworkTransportProtocol")
        }
    }
    
    /// 测试未连接时发送数据应该失败
    func testSendDataWhenNotConnected() async {
        let testData = "Hello, Unified World!".data(using: .utf8)!
        
        do {
            try await transport.send(data: testData)
            XCTFail("未连接时发送数据应该抛出错误")
        } catch NetworkError.notConnected {
            // 预期的错误
        } catch {
            XCTFail("意外的错误类型: \(error)")
        }
    }
    
    /// 测试未连接时接收数据应该失败
    func testReceiveDataWhenNotConnected() async {
        do {
            _ = try await transport.receive()
            XCTFail("未连接时接收数据应该抛出错误")
        } catch NetworkError.notConnected {
            // 预期的错误
        } catch {
            XCTFail("意外的错误类型: \(error)")
        }
    }
    
    /// 测试断开连接操作总是成功
    func testDisconnectAlwaysSucceeds() async {
        // 即使未连接，断开操作也应该成功
        await transport.disconnect()
        // 如果能执行到这里就说明没有抛出异常
    }
    
    // MARK: - TCP连接测试
    
    /// 测试TCP连接模式
    func testTCPConnectionMode() async {
        do {
            try await transport.connect(to: "invalid.tcp.host.example", port: 80, useTLS: false)
            XCTFail("连接到无效主机应该失败")
        } catch let error as NetworkError {
            // 验证错误类型是合理的
            switch error {
            case .connectionTimeout, .connectionFailed, .hostUnreachable:
                // 这些都是预期的错误类型
                break
            default:
                XCTFail("意外的错误类型: \(error)")
            }
        } catch {
            XCTFail("意外的错误: \(error)")
        }
        
        await transport.disconnect()
    }
    
    /// 测试TLS连接模式
    func testTLSConnectionMode() async {
        do {
            try await transport.connect(to: "invalid.tls.host.example", port: 443, useTLS: true, tlsConfig: .secure)
            XCTFail("连接到无效主机应该失败")
        } catch let error as NetworkError {
            // 验证错误类型是合理的
            switch error {
            case .connectionTimeout, .connectionFailed, .hostUnreachable, .tlsHandshakeFailed:
                // 这些都是预期的错误类型
                break
            default:
                XCTFail("意外的错误类型: \(error)")
            }
        } catch {
            XCTFail("意外的错误: \(error)")
        }
        
        await transport.disconnect()
    }
    
    // MARK: - TLS配置测试
    
    /// 测试使用安全TLS配置连接
    func testConnectWithSecureTLSConfig() async {
        do {
            try await transport.connect(
                to: "invalid.host.example", 
                port: 443, 
                useTLS: true, 
                tlsConfig: .secure
            )
            XCTFail("连接到无效主机应该失败")
        } catch let error as NetworkError {
            // 验证错误类型是合理的
            switch error {
            case .connectionTimeout, .connectionFailed, .hostUnreachable:
                break
            default:
                XCTFail("意外的错误类型: \(error)")
            }
        } catch {
            XCTFail("意外的错误: \(error)")
        }
        
        await transport.disconnect()
    }
    
    /// 测试使用开发环境TLS配置连接
    func testConnectWithDevelopmentTLSConfig() async {
        do {
            try await transport.connect(
                to: "invalid.host.example", 
                port: 443, 
                useTLS: true, 
                tlsConfig: .development
            )
            XCTFail("连接到无效主机应该失败")
        } catch let error as NetworkError {
            switch error {
            case .connectionTimeout, .connectionFailed, .hostUnreachable:
                break
            default:
                XCTFail("意外的错误类型: \(error)")
            }
        } catch {
            XCTFail("意外的错误: \(error)")
        }
        
        await transport.disconnect()
    }
    
    /// 测试使用WebSocket TLS配置连接
    func testConnectWithWebSocketTLSConfig() async {
        do {
            try await transport.connect(
                to: "invalid.host.example", 
                port: 443, 
                useTLS: true, 
                tlsConfig: .webSocket
            )
            XCTFail("连接到无效主机应该失败")
        } catch let error as NetworkError {
            switch error {
            case .connectionTimeout, .connectionFailed, .hostUnreachable:
                break
            default:
                XCTFail("意外的错误类型: \(error)")
            }
        } catch {
            XCTFail("意外的错误: \(error)")
        }
        
        await transport.disconnect()
    }
    
    // MARK: - 连接切换测试
    
    /// 测试从TCP切换到TLS连接
    func testSwitchFromTCPToTLS() async {
        // 首先尝试TCP连接
        do {
            try await transport.connect(to: "invalid.host1.example", port: 80, useTLS: false)
        } catch {
            // 连接失败是预期的
        }
        
        // 然后尝试TLS连接（应该清理之前的连接）
        do {
            try await transport.connect(to: "invalid.host2.example", port: 443, useTLS: true)
        } catch {
            // 连接失败是预期的
        }
        
        await transport.disconnect()
    }
    
    /// 测试从TLS切换到TCP连接
    func testSwitchFromTLSToTCP() async {
        // 首先尝试TLS连接
        do {
            try await transport.connect(to: "invalid.host1.example", port: 443, useTLS: true)
        } catch {
            // 连接失败是预期的
        }
        
        // 然后尝试TCP连接（应该清理之前的连接）
        do {
            try await transport.connect(to: "invalid.host2.example", port: 80, useTLS: false)
        } catch {
            // 连接失败是预期的
        }
        
        await transport.disconnect()
    }
    
    // MARK: - 边界条件测试
    
    /// 测试发送空数据
    func testSendEmptyData() async {
        let emptyData = Data()
        
        do {
            try await transport.send(data: emptyData)
            XCTFail("未连接时发送数据应该失败")
        } catch NetworkError.notConnected {
            // 预期的错误
        } catch {
            XCTFail("意外的错误: \(error)")
        }
    }
    
    /// 测试连接参数验证
    func testConnectionParameterValidation() async {
        // 测试端口号边界值
        do {
            try await transport.connect(to: "example.com", port: 65535, useTLS: false)
            XCTFail("连接到边界端口应该失败")
        } catch {
            // 任何错误都是可接受的
        }
        
        await transport.disconnect()
    }
    
    /// 测试空主机名
    func testEmptyHostname() async {
        do {
            try await transport.connect(to: "", port: 80, useTLS: false)
            XCTFail("空主机名应该失败")
        } catch {
            // 任何错误都是可接受的
        }
        
        await transport.disconnect()
    }
    
    // MARK: - 并发测试
    
    /// 测试并发断开连接
    func testConcurrentDisconnect() async {
        await withTaskGroup(of: Void.self) { group in
            // 启动多个并发的断开连接任务
            for _ in 0..<3 {
                group.addTask {
                    await self.transport.disconnect()
                }
            }
            
            // 等待所有任务完成
            await group.waitForAll()
        }
        
        // 如果能执行到这里，说明并发断开连接没有崩溃
    }
    
    /// 测试快速连续的连接尝试
    func testRapidConnectionAttempts() async {
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            // 启动多个并发连接任务
            for i in 0..<2 {
                group.addTask {
                    do {
                        let testTransport = UnifiedNetworkTransport(timeout: 1.0)
                        defer {
                            Task {
                                await testTransport.disconnect()
                            }
                        }
                        
                        let useTLS = i % 2 == 0
                        let port = useTLS ? 443 : 80
                        try await testTransport.connect(
                            to: "invalid.host\(i).example", 
                            port: port, 
                            useTLS: useTLS
                        )
                        return true
                    } catch {
                        return false
                    }
                }
            }
            
            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        
        // 我们期望大部分连接都会失败，但不应该崩溃
        XCTAssertEqual(results.count, 2, "应该有2个结果")
    }
}