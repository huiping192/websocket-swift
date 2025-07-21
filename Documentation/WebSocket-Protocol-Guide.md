# WebSocket协议深度解析

## 📖 RFC 6455 WebSocket协议学习指南

WebSocket是一种在单个TCP连接上进行全双工通信的协议。本指南深入解析RFC 6455标准，为实现WebSocket库提供理论基础。

## 🔄 WebSocket连接建立流程

### 1. HTTP升级握手

WebSocket连接通过HTTP升级请求建立，这是一个标准的HTTP请求-响应流程。

#### 客户端握手请求

```http
GET /chat HTTP/1.1
Host: server.example.com
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
Origin: http://example.com
Sec-WebSocket-Protocol: chat, superchat
Sec-WebSocket-Version: 13
```

**关键字段解析：**

| 字段 | 必需 | 说明 |
|------|------|------|
| `Upgrade: websocket` | ✅ | 请求协议升级到WebSocket |
| `Connection: Upgrade` | ✅ | 表示连接需要升级 |
| `Sec-WebSocket-Key` | ✅ | 16字节随机值的Base64编码 |
| `Sec-WebSocket-Version` | ✅ | WebSocket版本，当前为13 |
| `Sec-WebSocket-Protocol` | ❌ | 可选的子协议列表 |
| `Origin` | ❌ | 浏览器环境下的源站标识 |

#### 服务器握手响应

```http
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
Sec-WebSocket-Protocol: chat
```

**关键字段解析：**

| 字段 | 必需 | 说明 |
|------|------|------|
| `HTTP/1.1 101` | ✅ | 状态码101表示协议切换 |
| `Upgrade: websocket` | ✅ | 确认升级到WebSocket |
| `Connection: Upgrade` | ✅ | 确认连接升级 |
| `Sec-WebSocket-Accept` | ✅ | 基于客户端Key计算的接受值 |
| `Sec-WebSocket-Protocol` | ❌ | 选定的子协议 |

### 2. Sec-WebSocket-Accept计算

这是WebSocket握手的核心安全机制：

```
Sec-WebSocket-Accept = base64(sha1(Sec-WebSocket-Key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
```

**实现步骤：**
1. 将客户端的`Sec-WebSocket-Key`与魔术字符串拼接
2. 对拼接结果进行SHA-1哈希运算  
3. 将哈希结果进行Base64编码

**Swift实现示例：**
```swift
import Foundation
import CryptoKit

func computeWebSocketAccept(key: String) -> String {
    let magicString = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    let combined = key + magicString
    let data = Data(combined.utf8)
    let hash = Insecure.SHA1.hash(data: data)
    return Data(hash).base64EncodedString()
}
```

## 📦 WebSocket帧格式

握手完成后，所有数据都通过WebSocket帧传输。理解帧格式是实现协议的关键。

### 帧结构图

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-------+-+-------------+-------------------------------+
|F|R|R|R| opcode|M| Payload len |    Extended payload length    |
|I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
|N|V|V|V|       |S|             |   (if payload len==126/127)   |
| |1|2|3|       |K|             |                               |
+-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
|     Extended payload length continued, if payload len == 127  |
+ - - - - - - - - - - - - - - - +-------------------------------+
|                               |Masking-key, if MASK set to 1  |
+-------------------------------+-------------------------------+
| Masking-key (continued)       |          Payload Data         |
+-------------------------------- - - - - - - - - - - - - - - - +
:                     Payload Data continued ...                :
+ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
|                     Payload Data continued ...                |
+---------------------------------------------------------------+
```

### 字段详解

#### 1. FIN位 (1位)
- `1`: 这是消息的最后一个分片
- `0`: 还有后续分片

#### 2. RSV1-3 (3位)  
- 保留位，必须为0
- 可用于扩展协议

#### 3. Opcode (4位)
操作码定义帧类型：

| Opcode | 类型 | 说明 |
|--------|------|------|
| `0x0` | 继续帧 | 分片消息的后续帧 |
| `0x1` | 文本帧 | UTF-8文本数据 |
| `0x2` | 二进制帧 | 任意二进制数据 |
| `0x3-0x7` | 保留 | 数据帧的保留操作码 |
| `0x8` | 关闭帧 | 连接关闭 |
| `0x9` | Ping帧 | 心跳检测 |
| `0xA` | Pong帧 | 心跳响应 |
| `0xB-0xF` | 保留 | 控制帧的保留操作码 |

#### 4. MASK位 (1位)
- 客户端发送的帧**必须**设置为1（掩码）
- 服务器发送的帧**必须**设置为0（无掩码）

#### 5. Payload Length (7位 + 扩展)
负载长度编码：

| 值 | 编码方式 |
|-------|----------|
| `0-125` | 直接使用7位值 |
| `126` | 后续16位为实际长度 |
| `127` | 后续64位为实际长度 |

#### 6. Masking Key (32位)
- 仅当MASK=1时存在
- 用于对负载数据进行掩码处理

#### 7. Payload Data
实际的负载数据，可能经过掩码处理。

### 掩码算法

客户端必须对发送的数据进行掩码处理：

```
masked_data[i] = original_data[i] XOR masking_key[i % 4]
```

**Swift实现：**
```swift
func maskData(_ data: Data, with maskingKey: UInt32) -> Data {
    let keyBytes = withUnsafeBytes(of: maskingKey.bigEndian) { Data($0) }
    return Data(data.enumerated().map { index, byte in
        return byte ^ keyBytes[index % 4]
    })
}
```

## 🔄 消息分片处理

WebSocket支持将大消息分成多个帧传输。

### 分片规则

1. **首帧**: `FIN=0`, `opcode=0x1或0x2`
2. **中间帧**: `FIN=0`, `opcode=0x0` 
3. **尾帧**: `FIN=1`, `opcode=0x0`

### 分片示例

发送一个大的文本消息"Hello WebSocket World"：

```
帧1: FIN=0, opcode=0x1, payload="Hello "
帧2: FIN=0, opcode=0x0, payload="WebSocket "  
帧3: FIN=1, opcode=0x0, payload="World"
```

### 实现注意事项

- 控制帧（ping/pong/close）不能分片
- 控制帧可以插入分片消息中间
- 必须按顺序组装分片

## 🛡️ 连接关闭

### 关闭握手

WebSocket连接关闭是双向的：

1. 一方发送Close帧
2. 另一方响应Close帧  
3. 关闭底层TCP连接

### Close帧格式

```
+--------+--------+
| Status |        |
| Code   | Reason |
| (16)   | (UTF8) |
+--------+--------+
```

### 标准状态码

| 状态码 | 说明 |
|--------|------|
| `1000` | 正常关闭 |
| `1001` | 端点离开 |
| `1002` | 协议错误 |
| `1003` | 不支持的数据类型 |
| `1007` | 数据不一致 |
| `1008` | 策略违反 |
| `1009` | 消息过大 |
| `1011` | 服务器错误 |

## 💓 心跳机制

### Ping/Pong帧

- **Ping帧**: `opcode=0x9`，可携带应用数据
- **Pong帧**: `opcode=0xA`，必须回显Ping帧的数据

### 心跳实现策略

```swift
// 发送心跳
func sendPing() async throws {
    let pingFrame = WebSocketFrame(
        fin: true,
        opcode: .ping,
        masked: true,
        payload: Data("ping".utf8)
    )
    try await send(frame: pingFrame)
}

// 处理心跳响应
func handlePong(_ frame: WebSocketFrame) {
    let responseTime = Date().timeIntervalSince(pingTime)
    print("Pong received in \\(responseTime)ms")
}
```

## 🔒 安全考虑

### 1. 掩码的重要性
- 防止代理服务器的缓存污染攻击
- 客户端必须使用随机掩码密钥
- 服务器必须验证掩码位正确设置

### 2. Origin验证
```swift
func validateOrigin(_ origin: String) -> Bool {
    let allowedOrigins = ["https://example.com", "https://app.example.com"]
    return allowedOrigins.contains(origin)
}
```

### 3. 数据验证
- UTF-8文本帧必须是有效的UTF-8
- 控制帧负载不能超过125字节
- 保留位必须为0

## 📊 性能优化要点

### 1. 帧大小选择
- 小帧：低延迟，高开销
- 大帧：高吞吐，高内存占用
- 推荐：1-16KB的帧大小

### 2. 缓冲区管理
```swift
class FrameBuffer {
    private var buffer = Data()
    private let maxSize = 64 * 1024 // 64KB
    
    func append(_ data: Data) throws {
        guard buffer.count + data.count <= maxSize else {
            throw WebSocketError.bufferOverflow
        }
        buffer.append(data)
    }
}
```

### 3. 压缩扩展
- Per-message-deflate扩展
- 减少带宽使用
- 增加CPU开销

## 🧪 协议测试要点

### 握手测试
- [ ] 正确的Sec-WebSocket-Accept计算
- [ ] 不支持的版本处理
- [ ] 缺失必需头部的处理

### 帧处理测试  
- [ ] 各种帧类型的编解码
- [ ] 分片消息的正确组装
- [ ] 掩码的正确应用和移除

### 错误处理测试
- [ ] 无效帧格式的处理
- [ ] 协议违反的检测
- [ ] 连接异常中断的处理

### 性能测试
- [ ] 大消息传输性能
- [ ] 高频小消息处理
- [ ] 内存使用监控

## 📚 扩展学习

### RFC文档
- [RFC 6455 - WebSocket协议](https://tools.ietf.org/html/rfc6455)
- [RFC 7692 - Per-Message Deflate压缩](https://tools.ietf.org/html/rfc7692)

### 安全标准
- [RFC 6455 Section 10 - 安全考虑](https://tools.ietf.org/html/rfc6455#section-10)

### 测试套件  
- [Autobahn WebSocket测试套件](https://github.com/crossbario/autobahn-testsuite)

---

> 💡 **学习建议**: 建议先实现基础的帧编解码，再逐步添加分片、心跳、关闭等功能。每个功能都要有对应的测试用例来验证正确性。