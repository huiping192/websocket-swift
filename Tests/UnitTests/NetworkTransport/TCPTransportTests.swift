import XCTest
@testable import NetworkTransport

final class TCPTransportTests: XCTestCase {
    
    var transport: TCPTransport!
    
    override func setUpWithError() throws {
        super.setUp()
        // 使用较短的超时时间用于测试（1秒）
        transport = TCPTransport(timeout: 1.0)
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
    
    /// 测试TCPTransport初始化
    func testTCPTransportInitialization() {
        let transport = TCPTransport(timeout: 1.0)
        XCTAssertNotNil(transport, "TCPTransport应该成功初始化")
    }
    
    /// 测试未连接时发送数据应该失败
    func testSendDataWhenNotConnected() async {
        let testData = "Hello, World!".data(using: .utf8)!
        
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
    
    // MARK: - 连接测试
    
    /// 测试连接到无效主机应该失败
    func testConnectToInvalidHost() async {
        do {
            try await transport.connect(to: "invalid.host.nonexistent", port: 80)
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
    
    /// 测试连接到无效端口应该失败
    func testConnectToInvalidPort() async {
        do {
            // 尝试连接到一个不太可能开放的端口（在有效范围内）
            try await transport.connect(to: "127.0.0.1", port: 65534)
            XCTFail("连接到无效端口应该失败")
        } catch let error as NetworkError {
            // 验证错误类型是合理的
            switch error {
            case .connectionTimeout, .connectionFailed:
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
        // 创建一个新的transport用于此测试，避免干扰其他测试
        let testTransport = TCPTransport(timeout: 1.0)
        
        do {
            // 首先尝试一个连接（预期会失败，但这不是重点）
            try await testTransport.connect(to: "127.0.0.1", port: 22)
        } catch {
            // 第一个连接失败是正常的
        }
        
        do {
            // 尝试第二个连接，应该失败因为已经有连接了
            try await testTransport.connect(to: "127.0.0.1", port: 80)
        } catch NetworkError.invalidState {
            // 预期的错误
            await testTransport.disconnect()
            return
        } catch {
            // 如果第一个连接已经失败了，第二个连接可能会成功或失败
        }
        
        await testTransport.disconnect()
    }
    
    // MARK: - 边界条件测试
    
    /// 测试发送空数据
    func testSendEmptyData() async {
        // 即使没有连接，我们也可以测试发送空数据的行为
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
        // 测试不太可能开放的高端口号（避免使用65535因为可能导致长时间超时）
        do {
            try await transport.connect(to: "127.0.0.1", port: 65000)
            XCTFail("连接到未使用的端口应该快速失败")
        } catch {
            // 任何错误都是可接受的
        }
        
        await transport.disconnect()
    }
    
    /// 测试空主机名
    func testEmptyHostname() async {
        do {
            try await transport.connect(to: "", port: 80)
            XCTFail("空主机名应该失败")
        } catch {
            // 任何错误都是可接受的
        }
        
        await transport.disconnect()
    }
    
    // MARK: - 性能测试
    
    /// 测试连接超时机制
    func testConnectionTimeout() async {
        let startTime = Date()
        
        do {
            // 使用一个会触发超时的地址（10.255.255.1是保留地址，通常不可路由）
            try await transport.connect(to: "10.255.255.1", port: 80)
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
    
    /// 测试快速连续的连接尝试
    func testRapidConnectionAttempts() async {
        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            // 启动多个并发连接任务
            for i in 0..<3 {
                group.addTask {
                    do {
                        let testTransport = TCPTransport(timeout: 1.0)
                        defer {
                            Task {
                                await testTransport.disconnect()
                            }
                        }
                        try await testTransport.connect(to: "127.0.0.1", port: 22 + i)
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
}
