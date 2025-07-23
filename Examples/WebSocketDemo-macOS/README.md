# WebSocket SwiftUI Demo

这是一个功能完整的 macOS WebSocket 调试工具，使用 SwiftUI 构建。

## 功能特性

- 🔗 **连接管理**：支持 ws/wss 协议，可配置子协议和连接超时
- 💬 **消息交互**：实时收发文本和二进制消息
- 📊 **状态监控**：详细的连接状态和日志记录
- 🎨 **现代界面**：使用 SwiftUI 构建的直观用户界面

## 如何运行

### 方法 1：使用快捷脚本
```bash
./run-demo.sh
```

### 方法 2：手动构建和运行
```bash
# 构建
swift build --target WebSocketDemo

# 运行
swift run WebSocketDemo
```

## 界面说明

### 左侧面板 - 连接设置
- **WebSocket URL**：输入要连接的 WebSocket 服务器地址
- **子协议**：可选，多个协议用逗号分隔
- **连接超时**：设置连接超时时间（5-60秒）
- **自动重连**：启用后会在断线时自动重连

### 左下面板 - 系统日志
- 显示详细的连接状态和操作日志
- 支持不同级别的日志（DEBUG, INFO, WARN, ERROR）
- 统计信息显示消息收发数量

### 右侧面板 - 消息交互
- **消息列表**：显示所有收发的消息，支持文本和二进制数据
- **输入框**：支持多行输入，按 Enter 发送消息
- **自动滚动**：可切换是否自动滚动到最新消息

## 测试服务器

推荐使用以下公共 WebSocket 测试服务器：
- `wss://echo.websocket.org` - Echo 服务器，会回显发送的消息
- `wss://ws-feed.exchange.coinbase.com` - Coinbase 加密货币数据流
- `wss://stream.binance.com:9443/ws/btcusdt@ticker` - Binance 行情数据

## 系统要求

- **macOS**: 13.0+ (Ventura)
- **Swift**: 5.9+
- **Xcode**: 15.0+ (如果需要 IDE 支持)

## 项目结构

```
WebSocketDemo-macOS/
├── WebSocketDemoApp.swift         # SwiftUI App 入口
├── ContentView.swift              # 主界面
├── Models/
│   └── AppModels.swift            # 数据模型
├── ViewModels/
│   └── WebSocketViewModel.swift   # 业务逻辑
├── Views/
│   ├── ConnectionPanel.swift      # 连接配置面板
│   ├── MessagePanel.swift         # 消息交互面板
│   └── StatusPanel.swift          # 状态显示面板
└── README.md                      # 本文档
```