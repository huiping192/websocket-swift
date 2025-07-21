import XCTest
@testable import WebSocketCore
@testable import Utilities

final class SameDecoderTest: XCTestCase {
    
    func testSameDecoderTwoFrames() throws {
        let decoder = FrameDecoder()
        let encoder = FrameEncoder()
        
        // 第一个帧
        print("=== Decoding first frame ===")
        let frame1 = try WebSocketFrame(fin: true, opcode: .text, masked: true, payload: Data("A".utf8), maskingKey: 0x11111111)
        let encoded1 = try encoder.encodeFrame(frame1)
        
        print("Frame 1 encoded: \(encoded1.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        let decoded1 = try decoder.decode(data: encoded1)
        print("Frame 1 decoded successfully: \(decoded1.count) frames")
        XCTAssertEqual(decoded1.count, 1)
        
        // 第二个帧 - 这里应该会崩溃
        print("=== Decoding second frame ===")
        let frame2 = try WebSocketFrame(fin: true, opcode: .text, masked: true, payload: Data("B".utf8), maskingKey: 0x22222222)
        let encoded2 = try encoder.encodeFrame(frame2)
        
        print("Frame 2 encoded: \(encoded2.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        // 这里应该崩溃
        let decoded2 = try decoder.decode(data: encoded2)
        print("Frame 2 decoded successfully: \(decoded2.count) frames")
        XCTAssertEqual(decoded2.count, 1)
        
        print("Both frames decoded successfully with same decoder!")
    }
    
    func testSameDecoderAfterReset() throws {
        let decoder = FrameDecoder()
        let encoder = FrameEncoder()
        
        // 第一个帧
        let frame1 = try WebSocketFrame(fin: true, opcode: .text, masked: true, payload: Data("A".utf8), maskingKey: 0x11111111)
        let encoded1 = try encoder.encodeFrame(frame1)
        let decoded1 = try decoder.decode(data: encoded1)
        XCTAssertEqual(decoded1.count, 1)
        
        // 重置解码器
        decoder.reset()
        
        // 第二个帧
        let frame2 = try WebSocketFrame(fin: true, opcode: .text, masked: true, payload: Data("B".utf8), maskingKey: 0x22222222)
        let encoded2 = try encoder.encodeFrame(frame2)
        let decoded2 = try decoder.decode(data: encoded2)
        XCTAssertEqual(decoded2.count, 1)
        
        print("Reset decoder test successful!")
    }
}