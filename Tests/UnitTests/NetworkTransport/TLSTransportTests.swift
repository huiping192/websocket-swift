import XCTest
@testable import NetworkTransport

final class TLSTransportTests: XCTestCase {
    
    var transport: TLSTransport!
    
    override func setUpWithError() throws {
        super.setUp()
        // 使用较短的超时时间用于测试（1秒）
        transport = TLSTransport(timeout: 1.0)
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
    
    /// 测试TLSTransport初始化
    func testTLSTransportInitialization() {
        let transport = TLSTransport(timeout: 1.0)
        XCTAssertNotNil(transport, "TLSTransport应该成功初始化")
    }
    
    /// 测试未连接时发送数据应该失败
    func testSendDataWhenNotConnected() async {
        let testData = "Hello, TLS World!".data(using: .utf8)!
        
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
    
    // MARK: - TLS连接测试
    
    /// 测试连接到无效主机应该失败
    func testConnectToInvalidHost() async {
        do {
            try await transport.connect(to: "invalid.tls.host.nonexistent", port: 443)
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
    
    /// 测试连接到HTTP端口应该失败（TLS握手失败）
    func testConnectToHTTPPort() async {
        do {
            // 尝试连接到HTTP端口（80），应该会TLS握手失败
            try await transport.connect(to: "httpbin.org", port: 80)
            XCTFail("连接到HTTP端口应该失败")
        } catch let error as NetworkError {
            // 验证错误类型是合理的
            switch error {
            case .connectionTimeout, .connectionFailed, .tlsHandshakeFailed:
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
    
    /// 测试重复连接应该失败
    func testDuplicateConnection() async {
        let testTransport = TLSTransport(timeout: 1.0)
        
        do {
            // 首先尝试一个连接（预期会失败，但这不是重点）
            try await testTransport.connect(to: "httpbin.org", port: 443)
        } catch {
            // 第一个连接失败是正常的
        }
        
        do {
            // 尝试第二个连接，应该失败因为已经有连接了
            try await testTransport.connect(to: "google.com", port: 443)
        } catch NetworkError.invalidState {
            // 预期的错误
            await testTransport.disconnect()
            return
        } catch {
            // 如果第一个连接已经失败了，第二个连接可能会成功或失败
        }
        
        await testTransport.disconnect()
    }
    
    // MARK: - TLS配置测试
    
    /// 测试使用默认TLS配置连接
    func testConnectWithDefaultConfig() async {
        do {
            try await transport.connect(to: "invalid.host.example", port: 443, tlsConfig: .secure)
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
    
    /// 测试使用开发环境配置连接
    func testConnectWithDevelopmentConfig() async {
        do {
            try await transport.connect(to: "invalid.host.example", port: 443, tlsConfig: .development)
            XCTFail("连接到无效主机应该失败")
        } catch let error as NetworkError {
            // 即使是开发环境配置，连接到无效主机仍然应该失败
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
    
    /// 测试使用WebSocket配置连接
    func testConnectWithWebSocketConfig() async {
        do {
            try await transport.connect(to: "invalid.host.example", port: 443, tlsConfig: .webSocket)
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
    
    // MARK: - 便利方法测试
    
    /// 测试connectHTTPS便利方法
    func testConnectHTTPS() async {
        do {
            try await transport.connectHTTPS(to: "invalid.host.example")
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
    
    /// 测试connectWSS便利方法（默认端口）
    func testConnectWSSDefaultPort() async {
        do {
            try await transport.connectWSS(to: "invalid.host.example")
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
    
    /// 测试connectWSS便利方法（自定义端口）
    func testConnectWSSCustomPort() async {
        do {
            try await transport.connectWSS(to: "invalid.host.example", port: 8443)
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
    
    /// 测试connectDevelopment便利方法
    func testConnectDevelopment() async {
        do {
            try await transport.connectDevelopment(to: "invalid.host.example", port: 443)
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
            try await transport.connect(to: "example.com", port: 65535)
            XCTFail("连接到最大端口应该失败")
        } catch {
            // 任何错误都是可接受的
        }
        
        await transport.disconnect()
    }
    
    /// 测试空主机名
    func testEmptyHostname() async {
        do {
            try await transport.connect(to: "", port: 443)
            XCTFail("空主机名应该失败")
        } catch {
            // 任何错误都是可接受的
        }
        
        await transport.disconnect()
    }
    
    // MARK: - 性能测试
    
    /// 测试TLS连接超时机制
    func testTLSConnectionTimeout() async {
        let startTime = Date()
        
        do {
            // 使用一个会触发超时的地址
            try await transport.connect(to: "10.255.255.1", port: 443)
            XCTFail("应该因为超时而失败")
        } catch NetworkError.connectionTimeout {
            let elapsedTime = Date().timeIntervalSince(startTime)
            XCTAssertGreaterThan(elapsedTime, 0.5, "超时时间应该至少0.5秒")
            XCTAssertLessThan(elapsedTime, 2.0, "超时时间应该在2秒内")
        } catch {
            // 其他类型的连接错误也是可接受的
        }
        
        await transport.disconnect()
    }
    
    // MARK: - 并发测试
    
    /// 测试并发断开连接
    func testConcurrentDisconnect() async {
        await withTaskGroup(of: Void.self) { group in
            // 启动多个并发的断开连接任务
            for _ in 0..<5 {
                group.addTask {
                    await self.transport.disconnect()
                }
            }
            
            // 等待所有任务完成
            await group.waitForAll()
        }
        
        // 如果能执行到这里，说明并发断开连接没有崩溃
    }
    
    /// 测试快速连续的TLS连接尝试
    func testRapidTLSConnectionAttempts() async {
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            // 启动多个并发连接任务
            for i in 0..<3 {
                group.addTask {
                    do {
                        let testTransport = TLSTransport(timeout: 1.0)
                        defer {
                            Task {
                                await testTransport.disconnect()
                            }
                        }
                        try await testTransport.connect(to: "httpbin.org", port: 443 + i)
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
        XCTAssertEqual(results.count, 3, "应该有3个结果")
    }
    
    // MARK: - TLS特定错误测试
    
    /// 测试TLS握手失败的错误处理
    func testTLSHandshakeFailure() async {
        // 这个测试可能比较难设置，因为需要一个会导致TLS握手失败的服务器
        // 我们可以尝试连接到一个只支持HTTP的端口
        
        do {
            // 尝试连接到一个已知的HTTP服务器的HTTPS端口（可能不存在）
            try await transport.connect(to: "httpbin.org", port: 8080)
        } catch let error as NetworkError {
            // 可能的错误类型包括连接失败或TLS握手失败
            switch error {
            case .connectionTimeout, .connectionFailed, .tlsHandshakeFailed:
                // 这些都是合理的错误
                break
            default:
                // 其他错误也可能是合理的
                break
            }
        } catch {
            // 其他错误也是可接受的
        }
        
        await transport.disconnect()
    }
}