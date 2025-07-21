import XCTest
@testable import WebSocketCore
@testable import Utilities

final class FrameDecoderDebugCrash: XCTestCase {
    
    func testTwoSimpleFramesDebug() throws {
        let encoder = FrameEncoder()
        
        print("=== Creating frames ===")
        
        // 创建两个简单的帧
        let frame1 = try WebSocketFrame(fin: true, opcode: .text, masked: true, payload: Data("A".utf8), maskingKey: 0x11111111)
        let frame2 = try WebSocketFrame(fin: true, opcode: .text, masked: true, payload: Data("B".utf8), maskingKey: 0x22222222)
        
        print("Frame 1: \(frame1)")
        print("Frame 2: \(frame2)")
        
        print("=== Encoding frames ===")
        
        // 编码
        let encoded1 = try encoder.encodeFrame(frame1)
        let encoded2 = try encoder.encodeFrame(frame2)
        
        print("Encoded 1: \(encoded1.map { String(format: "%02X", $0) }.joined(separator: " "))")
        print("Encoded 2: \(encoded2.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        // 合并数据
        var combinedData = Data()
        combinedData.append(encoded1)
        combinedData.append(encoded2)
        
        print("Combined: \(combinedData.map { String(format: "%02X", $0) }.joined(separator: " "))")
        print("Combined length: \(combinedData.count)")
        
        print("=== Starting decode ===")
        
        let decoder = FrameDecoder()
        
        // 逐步解码，增加调试信息
        do {
            let decodedFrames = try decoder.decode(data: combinedData)
            print("Successfully decoded \(decodedFrames.count) frames")
            for (i, frame) in decodedFrames.enumerated() {
                print("Frame \(i): opcode=\(frame.opcode), payload=\(String(data: frame.payload, encoding: .utf8) ?? "binary")")
            }
            
            XCTAssertEqual(decodedFrames.count, 2)
            
        } catch {
            print("Decode error: \(error)")
            throw error
        }
    }
    
    // 更简单的测试：一个一个解码
    func testFrameByFrameDecode() throws {
        let encoder = FrameEncoder()
        let decoder = FrameDecoder()
        
        // 第一个帧
        let frame1 = try WebSocketFrame(fin: true, opcode: .text, masked: true, payload: Data("A".utf8), maskingKey: 0x11111111)
        let encoded1 = try encoder.encodeFrame(frame1)
        
        print("Decoding frame 1...")
        let decoded1 = try decoder.decode(data: encoded1)
        XCTAssertEqual(decoded1.count, 1)
        print("Frame 1 decoded successfully")
        
        // 第二个帧
        let frame2 = try WebSocketFrame(fin: true, opcode: .text, masked: true, payload: Data("B".utf8), maskingKey: 0x22222222)
        let encoded2 = try encoder.encodeFrame(frame2)
        
        print("Decoding frame 2...")
        let decoded2 = try decoder.decode(data: encoded2)
        XCTAssertEqual(decoded2.count, 1)
        print("Frame 2 decoded successfully")
        
        print("Sequential decode test passed!")
    }
}