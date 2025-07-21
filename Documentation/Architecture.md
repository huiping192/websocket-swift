# 系统架构设计

## 🏗️ 总体架构

SwiftWebSocketLearning采用**分层模块化架构**，每个模块职责单一，接口清晰，便于学习和扩展。

### 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                     应用层 (Application)                      │
├─────────────────────────────────────────────────────────────┤
│                   WebSocketDemo示例应用                       │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                  WebSocket核心层                             │
├─────────────────────────────────────────────────────────────┤
│  WebSocketCore - 协议核心实现                                │
│  ├── WebSocketClient - 客户端主接口                          │
│  ├── FrameCodec - 帧编解码器                                 │
│  ├── MessageHandler - 消息处理器                             │
│  └── StateManager - 状态管理器                               │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                  协议处理层                                   │  
├─────────────────────────────────────────────────────────────┤
│  HTTPUpgrade - HTTP升级握手                                  │
│  ├── HandshakeManager - 握手管理器                           │
│  ├── RequestBuilder - 请求构建器                             │
│  └── ResponseParser - 响应解析器                             │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                  网络传输层                                   │
├─────────────────────────────────────────────────────────────┤
│  NetworkTransport - 网络传输                                 │
│  ├── TCPTransport - TCP连接管理                              │
│  ├── TLSTransport - TLS安全传输                              │
│  └── ConnectionManager - 连接生命周期管理                     │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                   工具支持层                                  │
├─────────────────────────────────────────────────────────────┤
│  Utilities - 工具类库                                        │
│  ├── DataExtensions - 数据扩展                               │
│  ├── CryptoUtilities - 加密工具                              │
│  └── LoggingUtilities - 日志工具                             │
└─────────────────────────────────────────────────────────────┘
```

## 📦 模块详细设计

### 1. WebSocketCore 模块

**职责**: WebSocket协议的核心实现，负责帧处理、消息管理和状态控制。

#### 核心组件

```swift
// 主要接口
public protocol WebSocketClientProtocol {
    func connect(to url: URL) async throws
    func send(message: WebSocketMessage) async throws  
    func receive() async throws -> WebSocketMessage
    func close() async throws
}

// 状态管理
public enum WebSocketState {
    case connecting    // 连接中
    case open         // 已开启
    case closing      // 关闭中  
    case closed       // 已关闭
}

// 消息类型
public enum WebSocketMessage {
    case text(String)     // 文本消息
    case binary(Data)     // 二进制消息
    case ping(Data?)      // Ping帧
    case pong(Data?)      // Pong帧
}
```

#### 关键类设计

```swift
// WebSocket客户端实现
public final class WebSocketClient: WebSocketClientProtocol {
    private let transport: NetworkTransportProtocol
    private let upgradeManager: HandshakeManagerProtocol  
    private let frameCodec: FrameCodecProtocol
    private let stateManager: StateManagerProtocol
    
    // 异步连接实现
    public func connect(to url: URL) async throws {
        // 1. 建立TCP连接
        // 2. 执行HTTP升级握手
        // 3. 切换到WebSocket模式
    }
}

// 帧编解码器
public protocol FrameCodecProtocol {
    func encode(message: WebSocketMessage) throws -> Data
    func decode(data: Data) throws -> [WebSocketFrame]
}

// WebSocket帧结构
public struct WebSocketFrame {
    let fin: Bool              // 是否为最后一帧
    let opcode: FrameType      // 操作码
    let masked: Bool           // 是否使用掩码
    let payloadLength: UInt64  // 负载长度
    let maskingKey: UInt32?    // 掩码密钥
    let payload: Data          // 负载数据
}
```

### 2. HTTPUpgrade 模块  

**职责**: 实现WebSocket握手协议，处理HTTP升级请求和响应。

#### 核心组件

```swift
// 握手管理协议
public protocol HandshakeManagerProtocol {
    func performHandshake(
        url: URL, 
        transport: NetworkTransportProtocol
    ) async throws -> HandshakeResult
}

// 握手结果
public struct HandshakeResult {
    let success: Bool
    let selectedProtocol: String?
    let extensions: [String]
    let error: Error?
}

// 请求构建器
public struct RequestBuilder {
    public func buildUpgradeRequest(
        for url: URL,
        protocols: [String] = [],
        extensions: [String] = []
    ) -> UpgradeRequest
}

// 响应解析器  
public struct ResponseParser {
    public func parseUpgradeResponse(
        _ data: Data
    ) throws -> UpgradeResponse
}
```

#### 握手流程设计

```
客户端                                  服务器
  │                                      │
  │──── HTTP Upgrade Request ────────────▶│
  │     GET /path HTTP/1.1               │
  │     Host: example.com                │
  │     Upgrade: websocket               │  
  │     Connection: Upgrade              │
  │     Sec-WebSocket-Key: [key]         │
  │     Sec-WebSocket-Version: 13        │
  │                                      │
  │◀──── HTTP Upgrade Response ──────────│
  │     HTTP/1.1 101 Switching Protocols │
  │     Upgrade: websocket               │
  │     Connection: Upgrade              │
  │     Sec-WebSocket-Accept: [accept]   │
  │                                      │
  │═══════ WebSocket Connection ═════════│
```

### 3. NetworkTransport 模块

**职责**: 提供底层网络传输能力，支持TCP和TLS连接。

#### 核心组件

```swift
// 网络传输协议
public protocol NetworkTransportProtocol {
    func connect(to host: String, port: Int, useTLS: Bool) async throws
    func send(data: Data) async throws
    func receive(maxLength: Int) async throws -> Data
    func disconnect() async
}

// TCP传输实现
public final class TCPTransport: NetworkTransportProtocol {
    private var connection: NWConnection?
    
    public func connect(to host: String, port: Int, useTLS: Bool) async throws {
        // 使用Network.framework建立连接
    }
}

// 连接管理器
public final class ConnectionManager {
    private let transport: NetworkTransportProtocol
    private let reconnectStrategy: ReconnectStrategy
    
    public func maintainConnection() async {
        // 连接保活和重连逻辑
    }
}
```

#### 连接状态管理

```swift
public enum ConnectionState {
    case disconnected           // 未连接
    case connecting            // 连接中
    case connected             // 已连接
    case reconnecting          // 重连中
    case failed(Error)         // 连接失败
}

// 连接事件
public enum ConnectionEvent {
    case connected
    case disconnected(Error?)
    case dataReceived(Data)
    case error(Error)
}
```

### 4. Utilities 模块

**职责**: 提供通用工具函数和扩展，支持其他模块的功能实现。

#### 核心组件

```swift
// 数据处理扩展
public extension Data {
    var hexString: String { /* 十六进制字符串 */ }
    func masked(with key: UInt32) -> Data { /* WebSocket掩码处理 */ }
}

// 加密工具
public struct CryptoUtilities {
    public static func generateWebSocketKey() -> String
    public static func computeWebSocketAccept(key: String) -> String
    public static func generateMaskingKey() -> UInt32
}

// 字符串工具
public extension String {
    var utf8ByteCount: Int { self.utf8.count }
    func base64Encoded() -> String
}
```

## 🔄 数据流设计

### 发送消息流程

```
应用层调用
    │
    ▼
WebSocketClient.send()
    │
    ▼  
FrameCodec.encode()     ← 消息编码为WebSocket帧
    │
    ▼
NetworkTransport.send() ← 通过网络传输发送
    │
    ▼
TCP/TLS Socket         ← 底层网络发送
```

### 接收消息流程

```
TCP/TLS Socket         ← 底层网络接收
    │
    ▼
NetworkTransport.receive() ← 网络传输层接收数据
    │
    ▼
FrameCodec.decode()    ← 解码WebSocket帧
    │
    ▼
MessageHandler.process() ← 处理业务消息
    │  
    ▼
应用层回调/返回值       ← 传递给应用层
```

## 🧵 并发设计

### Actor模型应用

```swift
// 连接状态管理Actor
public actor ConnectionStateActor {
    private var currentState: ConnectionState = .disconnected
    
    public func updateState(_ newState: ConnectionState) {
        currentState = newState
    }
    
    public func getCurrentState() -> ConnectionState {
        return currentState
    }
}

// 消息队列Actor
public actor MessageQueueActor {
    private var pendingMessages: [WebSocketMessage] = []
    
    public func enqueue(_ message: WebSocketMessage) {
        pendingMessages.append(message)
    }
    
    public func dequeue() -> WebSocketMessage? {
        return pendingMessages.isEmpty ? nil : pendingMessages.removeFirst()
    }
}
```

### 异步流处理

```swift
// 消息接收流
public func messageStream() -> AsyncThrowingStream<WebSocketMessage, Error> {
    AsyncThrowingStream { continuation in
        Task {
            while !isClosed {
                do {
                    let message = try await receive()
                    continuation.yield(message)
                } catch {
                    continuation.finish(throwing: error)
                    break
                }
            }
            continuation.finish()
        }
    }
}

// 使用示例
for try await message in webSocket.messageStream() {
    switch message {
    case .text(let text):
        print("收到文本: \\(text)")
    case .binary(let data):
        print("收到二进制数据: \\(data.count) bytes")
    }
}
```

## 🛡️ 错误处理设计

### 错误类型层次

```swift
// 基础WebSocket错误
public enum WebSocketError: Error {
    case connectionFailed(underlying: Error)
    case handshakeFailed(reason: String)
    case protocolError(description: String)
    case invalidFrame(reason: String)
    case connectionClosed(code: UInt16, reason: String)
}

// 网络传输错误
public enum NetworkError: Error {
    case connectionTimeout
    case hostUnreachable
    case tlsError(underlying: Error)
    case dataCorrupted
}

// 协议错误
public enum ProtocolError: Error {
    case invalidHTTPResponse
    case unsupportedVersion
    case serverRejection(statusCode: Int)
    case missingRequiredHeader(String)
}
```

### 错误恢复策略

```swift
// 重连策略
public protocol ReconnectStrategy {
    func shouldReconnect(after error: Error, attemptCount: Int) -> Bool
    func delayBeforeReconnect(attemptCount: Int) -> TimeInterval
}

// 指数退避重连
public struct ExponentialBackoffStrategy: ReconnectStrategy {
    public func shouldReconnect(after error: Error, attemptCount: Int) -> Bool {
        return attemptCount < maxAttempts && isRecoverableError(error)
    }
    
    public func delayBeforeReconnect(attemptCount: Int) -> TimeInterval {
        return min(baseDelay * pow(2.0, Double(attemptCount)), maxDelay)
    }
}
```

## 📊 性能考虑

### 内存管理

- **零拷贝优化**: 尽可能避免不必要的数据复制
- **缓冲区复用**: 重用网络缓冲区减少内存分配
- **懒加载**: 按需初始化大型对象

### 并发优化

- **Actor隔离**: 使用Actor确保状态安全访问
- **异步流**: 利用AsyncStream处理持续数据流
- **并发控制**: 合理控制并发连接数量

### 网络优化

- **批量发送**: 合并小消息减少系统调用
- **压缩支持**: 可选的消息压缩扩展
- **心跳优化**: 智能心跳间隔调整

## 🧪 测试架构

### 测试层次

1. **单元测试**: 各模块独立功能测试
2. **集成测试**: 模块间协作测试  
3. **端到端测试**: 完整连接流程测试
4. **性能测试**: 吞吐量和延迟基准测试

### 模拟和依赖注入

```swift
// 可测试的设计
public protocol NetworkTransportProtocol {
    // 网络接口定义
}

// 模拟实现用于测试
public class MockNetworkTransport: NetworkTransportProtocol {
    var receivedData: [Data] = []
    var responseData: [Data] = []
    
    public func send(data: Data) async throws {
        receivedData.append(data)
    }
    
    public func receive(maxLength: Int) async throws -> Data {
        return responseData.removeFirst()
    }
}
```

---

这个架构设计为WebSocket学习提供了清晰的技术蓝图，既保证了代码的可维护性，又便于逐步学习和实现各个模块的功能。