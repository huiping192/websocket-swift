import SwiftUI

struct StatusPanel: View {
    @ObservedObject var viewModel: WebSocketViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .foregroundColor(.blue)
                Text("系统日志")
                    .font(.headline)
                
                Spacer()
                
                // 清空日志按钮
                Button(action: viewModel.clearLogs) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("清空日志")
                .disabled(viewModel.logs.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 日志列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if viewModel.logs.isEmpty {
                            // 空状态
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 32))
                                    .foregroundColor(.secondary)
                                Text("暂无日志")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        } else {
                            ForEach(viewModel.logs) { log in
                                LogEntryView(log: log)
                                    .id(log.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.logs.count) { _ in
                    if let lastLog = viewModel.logs.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // 统计信息
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("统计信息")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                
                HStack {
                    statisticItem(title: "消息数", value: "\(viewModel.messages.count)", color: .blue)
                    Spacer()
                    statisticItem(title: "日志数", value: "\(viewModel.logs.count)", color: .green)
                    Spacer()
                    statisticItem(title: "发送", 
                                value: "\(viewModel.messages.filter { $0.direction == .sent }.count)", 
                                color: .orange)
                    Spacer()
                    statisticItem(title: "接收", 
                                value: "\(viewModel.messages.filter { $0.direction == .received }.count)", 
                                color: .purple)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }
    
    @ViewBuilder
    private func statisticItem(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 日志条目视图
struct LogEntryView: View {
    let log: LogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 日志级别指示器
            Circle()
                .fill(levelColor)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(log.level.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(levelColor)
                    
                    Spacer()
                    
                    Text(log.displayTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Text(log.message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.3))
        )
    }
    
    private var levelColor: Color {
        switch log.level {
        case .debug:
            return .gray
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

#Preview {
    StatusPanel(viewModel: {
        let vm = WebSocketViewModel()
        vm.logs = [
            LogEntry(message: "应用启动", level: .info, timestamp: Date()),
            LogEntry(message: "开始连接到 wss://echo.websocket.org", level: .info, timestamp: Date()),
            LogEntry(message: "WebSocket 连接成功", level: .info, timestamp: Date()),
            LogEntry(message: "发送消息: Hello World", level: .debug, timestamp: Date()),
            LogEntry(message: "收到消息: Hello World", level: .info, timestamp: Date())
        ]
        return vm
    }())
    .frame(width: 300, height: 400)
}