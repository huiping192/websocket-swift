import SwiftUI

struct MessagePanel: View {
    @ObservedObject var viewModel: WebSocketViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "message")
                    .foregroundColor(.blue)
                Text("消息交互")
                    .font(.headline)
                
                Spacer()
                
                // 清空消息按钮
                Button(action: viewModel.clearMessages) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("清空消息")
                .disabled(viewModel.messages.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if viewModel.messages.isEmpty {
                            // 空状态
                            VStack(spacing: 12) {
                                Image(systemName: "message.badge")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text("还没有消息")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("连接到 WebSocket 服务器后，消息将在此显示")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        } else {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if viewModel.isAutoScrollEnabled, let lastMessage = viewModel.messages.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // 消息输入区域
            VStack(spacing: 12) {
                // 自动滚动开关
                HStack {
                    Toggle("自动滚动到底部", isOn: $viewModel.isAutoScrollEnabled)
                        .font(.caption)
                    Spacer()
                }
                
                // 输入框和发送按钮
                HStack(alignment: .bottom) {
                    TextField("输入消息...", text: $viewModel.newMessageText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...5)
                        .onSubmit {
                            if !viewModel.newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                viewModel.sendMessage()
                            }
                        }
                    
                    Button(action: viewModel.sendMessage) {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.connectionState.isConnected || 
                             viewModel.newMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }
}

// MARK: - 消息气泡视图
struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.direction == .sent {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.direction == .sent ? .trailing : .leading, spacing: 4) {
                // 消息内容
                HStack(alignment: .top, spacing: 8) {
                    if message.direction == .received {
                        messageTypeIcon
                    }
                    
                    Text(message.content)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(message.direction == .sent ? 
                                      Color.accentColor : Color(NSColor.controlBackgroundColor))
                        )
                        .foregroundColor(message.direction == .sent ? .white : .primary)
                    
                    if message.direction == .sent {
                        messageTypeIcon
                    }
                }
                
                // 时间戳
                Text(message.displayTime)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if message.direction == .received {
                Spacer(minLength: 60)
            }
        }
    }
    
    @ViewBuilder
    private var messageTypeIcon: some View {
        Group {
            switch message.type {
            case .text:
                Image(systemName: "text.bubble")
                    .foregroundColor(.blue)
            case .binary:
                Image(systemName: "doc.binary")
                    .foregroundColor(.orange)
            case .control:
                Image(systemName: "gear")
                    .foregroundColor(.gray)
            }
        }
        .font(.caption)
    }
}

#Preview {
    MessagePanel(viewModel: {
        let vm = WebSocketViewModel()
        vm.messages = [
            ChatMessage(content: "Hello, WebSocket!", type: .text, timestamp: Date(), direction: .sent),
            ChatMessage(content: "Hello back!", type: .text, timestamp: Date(), direction: .received),
            ChatMessage(content: "二进制数据 (4 字节): deadbeef", type: .binary, timestamp: Date(), direction: .received)
        ]
        return vm
    }())
    .frame(width: 500, height: 600)
}