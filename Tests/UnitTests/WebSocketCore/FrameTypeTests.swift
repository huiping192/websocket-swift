import XCTest
@testable import WebSocketCore

final class FrameTypeTests: XCTestCase {
    
    // MARK: - 基本初始化测试
    
    func testFrameTypeInitialization() {
        XCTAssertEqual(FrameType.continuation.rawValue, 0x0)
        XCTAssertEqual(FrameType.text.rawValue, 0x1)
        XCTAssertEqual(FrameType.binary.rawValue, 0x2)
        XCTAssertEqual(FrameType.close.rawValue, 0x8)
        XCTAssertEqual(FrameType.ping.rawValue, 0x9)
        XCTAssertEqual(FrameType.pong.rawValue, 0xA)
    }
    
    func testFrameTypeFromRawValue() {
        XCTAssertEqual(FrameType(rawValue: 0x0), .continuation)
        XCTAssertEqual(FrameType(rawValue: 0x1), .text)
        XCTAssertEqual(FrameType(rawValue: 0x2), .binary)
        XCTAssertEqual(FrameType(rawValue: 0x8), .close)
        XCTAssertEqual(FrameType(rawValue: 0x9), .ping)
        XCTAssertEqual(FrameType(rawValue: 0xA), .pong)
    }
    
    func testReservedFrameTypes() {
        XCTAssertEqual(FrameType(rawValue: 0x3), .reserved3)
        XCTAssertEqual(FrameType(rawValue: 0x4), .reserved4)
        XCTAssertEqual(FrameType(rawValue: 0x5), .reserved5)
        XCTAssertEqual(FrameType(rawValue: 0x6), .reserved6)
        XCTAssertEqual(FrameType(rawValue: 0x7), .reserved7)
        XCTAssertEqual(FrameType(rawValue: 0xB), .reservedB)
        XCTAssertEqual(FrameType(rawValue: 0xC), .reservedC)
        XCTAssertEqual(FrameType(rawValue: 0xD), .reservedD)
        XCTAssertEqual(FrameType(rawValue: 0xE), .reservedE)
        XCTAssertEqual(FrameType(rawValue: 0xF), .reservedF)
    }
    
    func testInvalidFrameType() {
        // 无效的操作码应该返回nil
        XCTAssertNil(FrameType(rawValue: 0x10))
        XCTAssertNil(FrameType(rawValue: 0xFF))
    }
    
    // MARK: - 帧类型分类测试
    
    func testDataFrameClassification() {
        XCTAssertTrue(FrameType.continuation.isDataFrame)
        XCTAssertTrue(FrameType.text.isDataFrame)
        XCTAssertTrue(FrameType.binary.isDataFrame)
        
        XCTAssertFalse(FrameType.continuation.isControlFrame)
        XCTAssertFalse(FrameType.text.isControlFrame)
        XCTAssertFalse(FrameType.binary.isControlFrame)
    }
    
    func testControlFrameClassification() {
        XCTAssertTrue(FrameType.close.isControlFrame)
        XCTAssertTrue(FrameType.ping.isControlFrame)
        XCTAssertTrue(FrameType.pong.isControlFrame)
        
        XCTAssertFalse(FrameType.close.isDataFrame)
        XCTAssertFalse(FrameType.ping.isDataFrame)
        XCTAssertFalse(FrameType.pong.isDataFrame)
    }
    
    func testReservedFrameClassification() {
        // 保留的数据帧操作码
        XCTAssertTrue(FrameType.reserved3.isReserved)
        XCTAssertTrue(FrameType.reserved4.isReserved)
        XCTAssertTrue(FrameType.reserved5.isReserved)
        XCTAssertTrue(FrameType.reserved6.isReserved)
        XCTAssertTrue(FrameType.reserved7.isReserved)
        
        // 保留的控制帧操作码
        XCTAssertTrue(FrameType.reservedB.isReserved)
        XCTAssertTrue(FrameType.reservedC.isReserved)
        XCTAssertTrue(FrameType.reservedD.isReserved)
        XCTAssertTrue(FrameType.reservedE.isReserved)
        XCTAssertTrue(FrameType.reservedF.isReserved)
        
        // 标准操作码不应该是保留的
        XCTAssertFalse(FrameType.text.isReserved)
        XCTAssertFalse(FrameType.binary.isReserved)
        XCTAssertFalse(FrameType.close.isReserved)
        XCTAssertFalse(FrameType.ping.isReserved)
        XCTAssertFalse(FrameType.pong.isReserved)
    }
    
    func testReservedDataFrames() {
        // 保留的数据帧操作码应该是数据帧
        XCTAssertTrue(FrameType.reserved3.isDataFrame)
        XCTAssertTrue(FrameType.reserved4.isDataFrame)
        XCTAssertTrue(FrameType.reserved5.isDataFrame)
        XCTAssertTrue(FrameType.reserved6.isDataFrame)
        XCTAssertTrue(FrameType.reserved7.isDataFrame)
        
        XCTAssertFalse(FrameType.reserved3.isControlFrame)
        XCTAssertFalse(FrameType.reserved4.isControlFrame)
        XCTAssertFalse(FrameType.reserved5.isControlFrame)
        XCTAssertFalse(FrameType.reserved6.isControlFrame)
        XCTAssertFalse(FrameType.reserved7.isControlFrame)
    }
    
    func testReservedControlFrames() {
        // 保留的控制帧操作码应该是控制帧
        XCTAssertTrue(FrameType.reservedB.isControlFrame)
        XCTAssertTrue(FrameType.reservedC.isControlFrame)
        XCTAssertTrue(FrameType.reservedD.isControlFrame)
        XCTAssertTrue(FrameType.reservedE.isControlFrame)
        XCTAssertTrue(FrameType.reservedF.isControlFrame)
        
        XCTAssertFalse(FrameType.reservedB.isDataFrame)
        XCTAssertFalse(FrameType.reservedC.isDataFrame)
        XCTAssertFalse(FrameType.reservedD.isDataFrame)
        XCTAssertFalse(FrameType.reservedE.isDataFrame)
        XCTAssertFalse(FrameType.reservedF.isDataFrame)
    }
}