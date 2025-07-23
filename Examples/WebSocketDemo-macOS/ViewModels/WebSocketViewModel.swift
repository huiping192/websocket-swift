import Foundation
import SwiftUI
import WebSocketCore
import NetworkTransport
import HTTPUpgrade
import Utilities

@MainActor
class WebSocketViewModel: ObservableObject {
    
    // MARK: - Published 属性
    @Published var connectionState: ConnectionState = .disconnected
    @Published var messages: [ChatMessage] = []
    @Published var logs: [LogEntry] = []
    @Published var config: ConnectionConfig = ConnectionConfig()
    @Published var newMessageText: String = ""
    @Published var isAutoScrollEnabled: Bool = true
    
    // MARK: - 私有属性
    private var webSocketClient: WebSocketClient?
    private var connectionTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    
    // MARK: - 连接管理
    
    func connect() {
        guard connectionState != .connecting && connectionState != .connected else {
            addLog("已在连接状态，无需重复连接", level: .warning)
            return
        }
        
        guard config.isValidURL, let url = URL(string: config.url) else {
            addLog("无效的 WebSocket URL: \(config.url)", level: .error)
            connectionState = .failed(WebSocketError.invalidURL)
            return
        }
        
        addLog("开始连接到: \(config.url)", level: .info)
        connectionState = .connecting
        
        // 创建 WebSocket 客户端配置
        let clientConfig = WebSocketClient.Configuration(
            connectTimeout: config.connectTimeout,
            maxFrameSize: 1024 * 1024, // 1MB
            maxMessageSize: 10 * 1024 * 1024, // 10MB
            fragmentTimeout: 30.0,
            subprotocols: config.protocols
        )
        
        // 创建客户端实例
        webSocketClient = WebSocketClient(configuration: clientConfig)
        
        // 开始连接任务
        connectionTask = Task {
            do {
                try await webSocketClient?.connect(to: url)
                await MainActor.run {
                    self.connectionState = .connected
                    self.addLog("WebSocket 连接成功", level: .info)
                }
                
                // 开始接收消息
                await startReceiving()
                
            } catch {
                await MainActor.run {
                    self.connectionState = .failed(error)
                    self.addLog("连接失败: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }
    
    func disconnect() {
        addLog("断开连接", level: .info)
        
        // 取消任务
        connectionTask?.cancel()
        receiveTask?.cancel()
        
        // 关闭连接
        Task {
            try? await webSocketClient?.close()
            await MainActor.run {
                self.connectionState = .disconnected
                self.webSocketClient = nil
                self.addLog("连接已断开", level: .info)
            }
        }
    }
    
    // MARK: - 消息处理
    
    func sendMessage() {
        guard !newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        guard connectionState.isConnected, let client = webSocketClient else {
            addLog("未连接到 WebSocket 服务器", level: .warning)
            return
        }
        
        let messageText = newMessageText.trimmingCharacters(in: .whitespacesAndNewlines)
        newMessageText = ""
        
        // 添加发送的消息到列表
        let sentMessage = ChatMessage(
            content: messageText,
            type: .text,
            timestamp: Date(),
            direction: .sent
        )
        messages.append(sentMessage)
        addLog("发送消息: \(messageText)", level: .info)
        
        // 发送消息
        Task {
            do {
                let message = WebSocketMessage.text(messageText)
                try await client.send(message: message)
                await MainActor.run {
                    self.addLog("消息发送成功", level: .debug)
                }
            } catch {
                await MainActor.run {
                    self.addLog("消息发送失败: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }
    
    // MARK: - 私有方法
    
    private func startReceiving() async {
        receiveTask = Task {
            while !Task.isCancelled && connectionState.isConnected {
                do {
                    guard let client = webSocketClient else { break }
                    let message = try await client.receive()
                    
                    await MainActor.run {
                        self.handleReceivedMessage(message)
                    }
                } catch {
                    // 检查是否是因为连接关闭导致的错误
                    if connectionState.isConnected {
                        await MainActor.run {
                            self.addLog("接收消息错误: \(error.localizedDescription)", level: .error)
                        }
                    }
                    break
                }
            }
        }
    }
    
    private func handleReceivedMessage(_ message: WebSocketMessage) {
        switch message {
        case .text(let text):
            let chatMessage = ChatMessage(
                content: text,
                type: .text,
                timestamp: Date(),
                direction: .received
            )
            messages.append(chatMessage)
            addLog("收到文本消息: \(text)", level: .info)
            
        case .binary(let data):
            let hexString = data.map { String(format: "%02x", $0) }.joined()
            let chatMessage = ChatMessage(
                content: "二进制数据 (\(data.count) 字节): \(hexString)",
                type: .binary,
                timestamp: Date(),
                direction: .received
            )
            messages.append(chatMessage)
            addLog("收到二进制消息: \(data.count) 字节", level: .info)
            
        case .ping(let data):
            addLog("收到 Ping: \(data?.count ?? 0) 字节", level: .debug)
            
        case .pong(let data):
            addLog("收到 Pong: \(data?.count ?? 0) 字节", level: .debug)
        }
    }
    
    private func addLog(_ message: String, level: LogEntry.LogLevel) {
        let logEntry = LogEntry(
            message: message,
            level: level,
            timestamp: Date()
        )
        logs.append(logEntry)
        
        // 限制日志数量
        if logs.count > 1000 {
            logs.removeFirst(logs.count - 1000)
        }
    }
    
    // MARK: - 清理方法
    
    func clearMessages() {
        messages.removeAll()
        addLog("消息列表已清空", level: .info)
    }
    
    func clearLogs() {
        logs.removeAll()
        addLog("日志已清空", level: .info)
    }
    
    deinit {
        connectionTask?.cancel()
        receiveTask?.cancel()
    }
}

// MARK: - 错误类型
enum WebSocketError: LocalizedError {
    case invalidURL
    case connectionFailed
    case messageSendFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 WebSocket URL"
        case .connectionFailed:
            return "WebSocket 连接失败"
        case .messageSendFailed:
            return "消息发送失败"
        }
    }
}