import XCTest
@testable import WebSocketCore
@testable import Utilities

final class FrameDecoderFixedTests: XCTestCase {
    
    func testMultipleFramesDecodingFixed() throws {
        // 使用最简单的方法：每次都创建新的编码器和解码器
        
        // 创建三个简单的帧
        let frame1 = try WebSocketFrame(fin: true, opcode: .text, masked: false, payload: Data("A".utf8))
        let frame2 = try WebSocketFrame(fin: true, opcode: .text, masked: false, payload: Data("B".utf8))
        let frame3 = try WebSocketFrame(fin: true, opcode: .text, masked: false, payload: Data("C".utf8))
        
        // 手动构建帧数据（无掩码）
        var combinedData = Data()
        
        // 帧1: "A"
        combinedData.append(0x81) // FIN=1, opcode=text
        combinedData.append(0x01) // MASK=0, length=1
        combinedData.append(contentsOf: "A".utf8)
        
        // 帧2: "B"
        combinedData.append(0x81) // FIN=1, opcode=text
        combinedData.append(0x01) // MASK=0, length=1
        combinedData.append(contentsOf: "B".utf8)
        
        // 帧3: "C"
        combinedData.append(0x81) // FIN=1, opcode=text
        combinedData.append(0x01) // MASK=0, length=1
        combinedData.append(contentsOf: "C".utf8)
        
        print("Combined data: \(combinedData.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        let decoder = FrameDecoder()
        let decoded = try decoder.decode(data: combinedData)
        
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].payload, Data("A".utf8))
        XCTAssertEqual(decoded[1].payload, Data("B".utf8))
        XCTAssertEqual(decoded[2].payload, Data("C".utf8))
    }
}