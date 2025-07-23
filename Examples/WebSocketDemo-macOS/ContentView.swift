import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WebSocketViewModel()
    
    var body: some View {
        HSplitView {
            // 左侧面板：连接配置和状态
            VStack(spacing: 0) {
                ConnectionPanel(viewModel: viewModel)
                Divider()
                StatusPanel(viewModel: viewModel)
            }
            .frame(minWidth: 300, maxWidth: 400)
            
            // 右侧面板：消息交互
            MessagePanel(viewModel: viewModel)
                .frame(minWidth: 400)
        }
        .frame(minWidth: 800, minHeight: 600)
        .navigationTitle("WebSocket 调试工具")
    }
}

#Preview {
    ContentView()
}