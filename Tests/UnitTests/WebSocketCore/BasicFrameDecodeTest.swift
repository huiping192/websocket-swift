import XCTest
@testable import WebSocketCore
@testable import Utilities

final class BasicFrameDecodeTest: XCTestCase {
    
    func testSingleMaskedFrameDecode() throws {
        let decoder = FrameDecoder()
        let encoder = FrameEncoder()
        
        // 最简单的masked帧
        let frame = try WebSocketFrame(
            fin: true,
            opcode: .text,
            masked: true,
            payload: Data("Hi".utf8),
            maskingKey: 0x12345678
        )
        
        print("Original frame: \(frame)")
        
        let encoded = try encoder.encodeFrame(frame)
        print("Encoded: \(encoded.map { String(format: "%02X", $0) }.joined(separator: " "))")
        
        let decoded = try decoder.decode(data: encoded)
        print("Decoded \(decoded.count) frames")
        
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].payload, Data("Hi".utf8))
    }
    
    func testTwoSeparateDecodes() throws {
        // 两个独立的解码操作
        do {
            let decoder1 = FrameDecoder()
            let encoder1 = FrameEncoder()
            
            let frame1 = try WebSocketFrame(fin: true, opcode: .text, masked: true, payload: Data("A".utf8), maskingKey: 0x11111111)
            let encoded1 = try encoder1.encodeFrame(frame1)
            let decoded1 = try decoder1.decode(data: encoded1)
            
            XCTAssertEqual(decoded1.count, 1)
            print("First decode successful")
        }
        
        do {
            let decoder2 = FrameDecoder()
            let encoder2 = FrameEncoder()
            
            let frame2 = try WebSocketFrame(fin: true, opcode: .text, masked: true, payload: Data("B".utf8), maskingKey: 0x22222222)
            let encoded2 = try encoder2.encodeFrame(frame2)
            let decoded2 = try decoder2.decode(data: encoded2)
            
            XCTAssertEqual(decoded2.count, 1)
            print("Second decode successful")
        }
        
        print("Both separate decodes successful")
    }
}