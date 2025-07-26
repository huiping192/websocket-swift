import SwiftUI

struct ConnectionPanel: View {
    @ObservedObject var viewModel: WebSocketViewModel
    @State private var protocolText: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.blue)
                Text("连接设置")
                    .font(.headline)
                Spacer()
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)
            
            VStack(alignment: .leading, spacing: 8) {
                // WebSocket URL 输入
                VStack(alignment: .leading, spacing: 4) {
                    Text("WebSocket URL:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("wss://echo.websocket.org", text: $viewModel.config.url)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.connectionState == .connecting || viewModel.connectionState.isConnected)
                }
                
                // 子协议配置
                VStack(alignment: .leading, spacing: 4) {
                    Text("子协议 (可选，逗号分隔):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("chat, superchat", text: $protocolText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.connectionState == .connecting || viewModel.connectionState.isConnected)
                        .onChange(of: protocolText) { newValue in
                            viewModel.config.protocols = newValue
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                        }
                }
                
                // 连接超时配置
                VStack(alignment: .leading, spacing: 4) {
                    Text("连接超时 (秒):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Slider(value: $viewModel.config.connectTimeout, in: 5...60, step: 5) {
                            Text("超时")
                        }
                        .disabled(viewModel.connectionState == .connecting || viewModel.connectionState.isConnected)
                        
                        Text("\(Int(viewModel.config.connectTimeout))s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 30)
                    }
                }
                
                // 自动重连选项
                HStack {
                    Toggle("自动重连", isOn: $viewModel.config.autoReconnect)
                        .disabled(viewModel.connectionState == .connecting || viewModel.connectionState.isConnected)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            
            Divider()
                .padding(.horizontal, 16)
            
            // 连接状态和按钮
            VStack(spacing: 8) {
                HStack {
                    connectionStatusIndicator
                    Text(viewModel.connectionState.displayText)
                        .font(.subheadline)
                        .foregroundColor(connectionStatusColor)
                    Spacer()
                }
                
                // 连接/断开按钮
                HStack {
                    if viewModel.connectionState.isConnected {
                        Button(action: viewModel.disconnect) {
                            HStack {
                                Image(systemName: "stop.fill")
                                Text("断开连接")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    } else {
                        Button(action: viewModel.connect) {
                            HStack {
                                if viewModel.connectionState == .connecting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "play.fill")
                                }
                                Text(viewModel.connectionState == .connecting ? "连接中..." : "连接")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(!viewModel.config.isValidURL || viewModel.connectionState == .connecting)
                    }
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            
            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - 辅助视图
    
    @ViewBuilder
    private var connectionStatusIndicator: some View {
        Circle()
            .fill(connectionStatusColor)
            .frame(width: 8, height: 8)
    }
    
    private var connectionStatusColor: Color {
        switch viewModel.connectionState {
        case .disconnected:
            return .gray
        case .connecting, .reconnecting:
            return .orange
        case .connected:
            return .green
        case .disconnecting:
            return .yellow
        case .failed:
            return .red
        }
    }
}

#Preview {
    ConnectionPanel(viewModel: WebSocketViewModel())
        .frame(width: 300, height: 400)
}