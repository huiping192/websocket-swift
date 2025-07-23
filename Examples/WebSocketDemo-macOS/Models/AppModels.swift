import Foundation

// MARK: - 连接状态
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed(Error)
    
    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected),
             (.reconnecting, .reconnecting):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
    
    var displayText: String {
        switch self {
        case .disconnected:
            return "未连接"
        case .connecting:
            return "连接中..."
        case .connected:
            return "已连接"
        case .reconnecting:
            return "重连中..."
        case .failed:
            return "连接失败"
        }
    }
    
    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

// MARK: - 聊天消息模型
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let type: MessageType
    let timestamp: Date
    let direction: MessageDirection
    
    enum MessageType {
        case text
        case binary
        case control
    }
    
    enum MessageDirection {
        case sent
        case received
    }
    
    var displayTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
}

// MARK: - 日志条目
struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let level: LogLevel
    let timestamp: Date
    
    enum LogLevel {
        case debug
        case info
        case warning
        case error
        
        var displayName: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .warning: return "WARN"
            case .error: return "ERROR"
            }
        }
    }
    
    var displayTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
}

// MARK: - 连接配置
struct ConnectionConfig {
    var url: String = "wss://echo.websocket.org"
    var protocols: [String] = []
    var autoReconnect: Bool = false
    var connectTimeout: TimeInterval = 10.0
    
    var isValidURL: Bool {
        guard let url = URL(string: url) else { return false }
        return url.scheme == "ws" || url.scheme == "wss"
    }
}