#!/bin/bash

# WebSocket Demo SwiftUI App 启动脚本

echo "🚀 构建 WebSocket SwiftUI Demo 应用..."
swift build --target WebSocketDemo

if [ $? -eq 0 ]; then
    echo "✅ 构建成功！"
    echo "🖥️  启动应用程序..."
    swift run WebSocketDemo
else
    echo "❌ 构建失败！"
    exit 1
fi