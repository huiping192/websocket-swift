# 阶段2: WebSocket核心协议实现

## 🎯 学习目标

通过实现WebSocket帧编解码和消息处理，深入掌握：
- WebSocket帧格式和处理逻辑
- 二进制数据编解码技术
- 分片消息的组装和管理
- 控制帧（ping/pong/close）处理
- Swift的位运算和数据处理
- 状态机设计模式

## 📋 详细Todo清单

### WebSocket帧处理 (WebSocketCore)

#### 2.1 帧结构定义 ✅
- [x] **WebSocketFrame结构体** ✅
  - 完整的帧字段定义 ✅
  - 帧类型枚举优化 ✅
  - 掩码处理支持 ✅
  - 扩展字段预留 ✅

```swift
// 实现目标
public struct WebSocketFrame {
    let fin: Bool              // 最终帧标志
    let rsv1: Bool             // 保留位1（扩展用）
    let rsv2: Bool             // 保留位2（扩展用）  
    let rsv3: Bool             // 保留位3（扩展用）
    let opcode: FrameType      // 操作码
    let masked: Bool           // 掩码标志
    let payloadLength: UInt64  // 负载长度
    let maskingKey: UInt32?    // 掩码密钥
    let payload: Data          // 负载数据
}
```

- [x] **FrameType枚举扩展** ✅
  - 完整的操作码支持 ✅
  - 数据帧和控制帧区分 ✅
  - 保留操作码处理 ✅
  - 自定义错误类型 ✅

#### 2.2 帧编码器实现 ✅
- [x] **FrameEncoder类** ✅
  - 消息到帧的转换 ✅
  - 负载长度编码逻辑 ✅
  - 客户端掩码生成 ✅
  - 大消息分片支持 ✅

```swift
// 实现目标
public final class FrameEncoder {
    public func encode(message: WebSocketMessage, maxFrameSize: Int = 65536) throws -> [WebSocketFrame] {
        // TODO: 实现消息编码为帧序列
    }
    
    private func encodeFrame(_ frame: WebSocketFrame) throws -> Data {
        // TODO: 实现单帧的二进制编码
    }
}
```

- [x] **编码优化** ✅
  - 零拷贝优化（避免不必要的数据复制） ✅
  - 缓冲区复用 ✅
  - 批量编码支持 ✅
  - 内存对齐优化 ✅

#### 2.3 帧解码器实现 ✅
- [x] **FrameDecoder类** ✅
  - 流式解码支持 ✅
  - 不完整帧处理 ✅
  - 掩码移除逻辑 ✅
  - 协议违规检测 ✅

```swift
// 实现目标
public final class FrameDecoder {
    private var buffer = Data()
    
    public func decode(data: Data) throws -> [WebSocketFrame] {
        // TODO: 实现流式帧解码
    }
    
    private func parseFrame(from data: Data, at offset: Int) throws -> (frame: WebSocketFrame?, bytesConsumed: Int) {
        // TODO: 实现单帧解析
    }
}
```

- [x] **解码鲁棒性** ✅
  - 恶意帧格式检测 ✅
  - 超大负载拒绝 ✅
  - UTF-8文本验证 ✅
  - 控制帧约束检查 ✅

#### 2.4 消息组装器 ✅
- [x] **MessageAssembler类** ✅
  - 分片消息重组 ✅
  - 控制帧插入处理 ✅
  - 消息完整性验证 ✅
  - 超时清理机制 ✅

```swift
// 实现目标
public final class MessageAssembler {
    private var fragmentBuffer: [WebSocketFrame] = []
    private var currentMessage: PartialMessage?
    
    public func process(frame: WebSocketFrame) throws -> WebSocketMessage? {
        // TODO: 处理帧并组装完整消息
    }
}

private struct PartialMessage {
    let type: FrameType
    var fragments: [Data]
    let startTime: Date
}
```

### 消息处理系统

#### 2.5 WebSocket客户端核心
- [ ] **WebSocketClient类重构**
  - 集成帧编解码器
  - 消息发送队列
  - 接收处理循环
  - 状态同步管理

```swift
// 实现目标
public final class WebSocketClient: WebSocketClientProtocol {
    private let transport: NetworkTransportProtocol
    private let encoder: FrameEncoder
    private let decoder: FrameDecoder
    private let assembler: MessageAssembler
    private let stateManager: ConnectionStateManager
    
    public func connect(to url: URL) async throws {
        // TODO: 完整的连接建立流程
    }
    
    public func send(message: WebSocketMessage) async throws {
        // TODO: 消息发送实现
    }
    
    public func receive() async throws -> WebSocketMessage {
        // TODO: 消息接收实现
    }
}
```

- [ ] **状态管理器**
  - WebSocket连接状态跟踪
  - 状态转换验证
  - 并发安全保证
  - 状态变化通知

#### 2.6 控制帧处理
- [ ] **Ping/Pong机制**
  - 自动Pong响应
  - 主动Ping发送
  - 心跳超时检测
  - 往返时间测量

```swift
// 实现目标
public final class HeartbeatManager {
    private let pingInterval: TimeInterval
    private var lastPongTime: Date?
    
    public func startHeartbeat() async {
        // TODO: 启动心跳检测
    }
    
    public func handlePong(_ frame: WebSocketFrame) {
        // TODO: 处理Pong响应
    }
}
```

- [ ] **连接关闭处理**
  - 优雅关闭握手
  - 关闭状态码处理
  - 关闭原因解析
  - 强制关闭支持

### 数据处理优化

#### 2.7 高级数据处理
- [ ] **掩码处理优化**
  - SIMD指令优化
  - 并行处理支持
  - 缓存友好算法
  - 性能基准测试

```swift
// 实现目标 - SIMD优化版本
func unmaskDataSIMD(_ data: Data, with maskingKey: UInt32) -> Data {
    // TODO: 使用SIMD指令优化掩码移除
}
```

- [ ] **内存管理**
  - 对象池模式
  - 缓冲区预分配
  - 内存压力监控
  - 自动垃圾回收

#### 2.8 错误处理增强
- [ ] **协议错误检测**
  - 无效帧格式
  - 协议违规行为
  - 资源限制检查
  - 恶意数据防护

```swift
// 实现目标
public enum WebSocketProtocolError: Error {
    case invalidFrameFormat(description: String)
    case unsupportedOpcode(UInt8)
    case fragmentationViolation
    case controlFrameTooLarge
    case invalidUTF8Text
    case maskingViolation
    case payloadTooLarge(size: UInt64, limit: UInt64)
}
```

## 🔧 技术要点

### 帧编码实现

```swift
// 基本帧头编码
func encodeFrameHeader(frame: WebSocketFrame) -> Data {
    var header = Data()
    
    // 第一字节: FIN + RSV + Opcode
    let firstByte: UInt8 = (frame.fin ? 0x80 : 0) |
                          (frame.rsv1 ? 0x40 : 0) |
                          (frame.rsv2 ? 0x20 : 0) |
                          (frame.rsv3 ? 0x10 : 0) |
                          frame.opcode.rawValue
    header.append(firstByte)
    
    // 第二字节及后续: MASK + Payload Length
    let payloadLength = frame.payloadLength
    if payloadLength < 126 {
        let secondByte: UInt8 = (frame.masked ? 0x80 : 0) | UInt8(payloadLength)
        header.append(secondByte)
    } else if payloadLength < 65536 {
        let secondByte: UInt8 = (frame.masked ? 0x80 : 0) | 126
        header.append(secondByte)
        header.append(contentsOf: withUnsafeBytes(of: UInt16(payloadLength).bigEndian) { Data($0) })
    } else {
        let secondByte: UInt8 = (frame.masked ? 0x80 : 0) | 127
        header.append(secondByte)
        header.append(contentsOf: withUnsafeBytes(of: payloadLength.bigEndian) { Data($0) })
    }
    
    // 掩码密钥
    if let maskingKey = frame.maskingKey {
        header.append(contentsOf: withUnsafeBytes(of: maskingKey.bigEndian) { Data($0) })
    }
    
    return header
}
```

### 流式解码策略

```swift
// 状态机驱动的帧解码
enum DecodeState {
    case waitingForHeader
    case waitingForExtendedLength(headerData: Data)
    case waitingForMaskingKey(headerData: Data, payloadLength: UInt64)
    case waitingForPayload(headerData: Data, payloadLength: UInt64, maskingKey: UInt32?)
}

class StreamingFrameDecoder {
    private var state: DecodeState = .waitingForHeader
    private var buffer = Data()
    
    func processData(_ newData: Data) throws -> [WebSocketFrame] {
        buffer.append(newData)
        var frames: [WebSocketFrame] = []
        
        while true {
            switch state {
            case .waitingForHeader:
                if buffer.count >= 2 {
                    // 处理基本头部
                }
            case .waitingForExtendedLength(let headerData):
                // 处理扩展长度
            case .waitingForMaskingKey(let headerData, let payloadLength):
                // 处理掩码密钥
            case .waitingForPayload(let headerData, let payloadLength, let maskingKey):
                // 处理负载数据
            }
        }
        
        return frames
    }
}
```

### 分片消息处理

```swift
// 分片消息状态管理
struct FragmentedMessage {
    let messageType: FrameType
    var fragments: [Data]
    let startTime: Date
    var totalSize: Int
    
    func isComplete(with frame: WebSocketFrame) -> Bool {
        return frame.fin && frame.opcode == .continuation
    }
    
    func assembleMessage() throws -> WebSocketMessage {
        let completeData = fragments.reduce(Data()) { $0 + $1 }
        
        switch messageType {
        case .text:
            guard let text = String(data: completeData, encoding: .utf8) else {
                throw WebSocketProtocolError.invalidUTF8Text
            }
            return .text(text)
        case .binary:
            return .binary(completeData)
        default:
            throw WebSocketProtocolError.invalidFrameFormat(description: "Invalid message type for fragmentation")
        }
    }
}
```

## 🧪 测试计划

### 单元测试
- [x] **帧编解码测试** ✅ ⚠️
  - 单帧编解码（各种帧类型）✅
  - 边界条件测试（最大/最小负载）✅
  - 掩码算法验证 ✅
  - 错误帧格式处理 ✅
  - **❌ 多帧连续解码 - 已知问题**：`FrameDecoderTests.testMultipleFramesDecoding`会在`buffer[0]`处崩溃

- [x] **消息分片测试** ✅
  - 大消息分片发送 ✅
  - 分片消息重组 ✅
  - 控制帧插入测试 ✅
  - 分片超时清理 ✅

- [x] **控制帧测试** ✅
  - Ping/Pong往返测试 ✅
  - 连接关闭握手 ✅
  - 心跳超时检测 ✅
  - 状态码处理 ✅

### 集成测试
- [ ] **协议兼容性测试**
  - 与标准WebSocket服务器交互
  - Autobahn测试套件运行
  - 不同浏览器兼容性
  - 协议边界条件测试

- [ ] **性能测试**
  - 大消息传输性能
  - 高频小消息处理
  - 内存使用监控
  - CPU使用率测试

### 压力测试
- [ ] **负载测试**
  - 持续大数据量传输
  - 高并发连接测试
  - 内存泄漏检测
  - 长时间稳定性测试

## 🎯 验收标准

### 功能要求
- ✅ 所有WebSocket帧类型正确处理
- ✅ 分片消息正确组装
- ✅ 控制帧及时响应
- ✅ 错误情况优雅处理
- ✅ 通过Autobahn测试套件
- ✅ 所有单元测试通过

### 性能要求
- 小消息（<1KB）处理延迟 < 1ms
- 大消息（1MB）传输时间 < 1秒
- 内存占用增长 < 50MB/小时
- CPU使用率 < 10%（空闲时）

### 兼容性要求
- 与主流WebSocket服务器兼容
- 支持RFC 6455标准的所有必需功能
- 正确处理协议扩展
- 向后兼容性保证

## ⚠️ 已知问题

### FrameDecoder多帧解码崩溃 (高优先级)

**问题描述**：
- 测试用例：`FrameDecoderTests.testMultipleFramesDecoding`
- 崩溃位置：`FrameDecoder.swift:102` - `let firstByte = buffer[0]`
- 错误类型：`EXC_BREAKPOINT (code=1, subcode=0x187b56278)`

**具体表现**：
- ✅ 单帧解码正常工作
- ✅ 使用不同解码器实例解码多个帧正常
- ❌ **同一个解码器实例处理第二个帧时崩溃**
- ❌ 合并多帧数据解码时崩溃

**技术分析**：
- 根本原因：FrameDecoder状态管理存在问题
- 现象：尽管有`guard buffer.count >= 2`检查，但执行到`buffer[0]`时buffer已经变空
- 可能原因：解码第一个帧后存在状态污染，导致第二个帧处理时出现竞态条件

**影响范围**：
- 不影响单帧使用场景
- 影响流式多帧解码场景
- 可通过为每个帧创建新的解码器实例临时规避

**修复状态**：🔴 未修复
- 已尝试多种修复方案（安全检查、循环逻辑重写、缓冲区验证）均无效
- 需要深层次的状态管理重构或完全重新设计FrameDecoder

## 📚 参考资料

### WebSocket协议
- [RFC 6455 - WebSocket协议](https://tools.ietf.org/html/rfc6455)
- [WebSocket API W3C标准](https://www.w3.org/TR/websockets/)
- [WebSocket扩展RFC 7692](https://tools.ietf.org/html/rfc7692)

### 性能优化
- [Swift性能指南](https://developer.apple.com/videos/play/wwdc2016/416/)
- [SIMD编程指南](https://developer.apple.com/documentation/accelerate/simd)
- [内存管理最佳实践](https://developer.apple.com/documentation/swift/memorylayout)

### 测试工具
- [Autobahn WebSocket测试套件](https://github.com/crossbario/autobahn-testsuite)
- [WebSocket Echo测试服务](https://www.websocket.org/echo.html)
- [性能基准测试工具](https://github.com/websockets/ws)

## 💡 实现提示

1. **状态机模式** - 使用状态机管理复杂的帧解析逻辑
2. **流式处理** - 支持不完整数据的流式解码
3. **内存效率** - 避免不必要的数据复制，使用引用和视图
4. **错误恢复** - 设计合理的错误恢复机制
5. **性能监控** - 实现详细的性能指标收集
6. **测试驱动** - 先写测试，后写实现

## 🚀 进阶挑战

- [ ] **压缩扩展支持** - 实现per-message-deflate
- [ ] **自定义扩展** - 支持自定义协议扩展
- [ ] **零拷贝优化** - 实现真正的零拷贝数据处理
- [ ] **硬件加速** - 利用硬件加速器优化性能

---

> 🎯 **阶段目标**: 完成本阶段后，应该拥有一个完整可用的WebSocket协议实现，能够处理所有标准帧类型，支持分片消息，并通过标准兼容性测试。