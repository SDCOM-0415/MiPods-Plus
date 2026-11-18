import XCTest
@testable import MiPodsPlusCore

final class ProtocolTests: XCTestCase {

    private func hex(_ s: String) -> [UInt8] {
        var out: [UInt8] = []; var i = s.startIndex
        while i < s.endIndex {
            let n = s.index(i, offsetBy: 2)
            out.append(UInt8(s[i..<n], radix: 16)!); i = n
        }
        return out
    }

    private func str(_ b: [UInt8]) -> String {
        b.map { String(format: "%02X", $0) }.joined()
    }

    func testEncodeMatchesHardwareCapture() {
        let message = Message(type: .phoneRequest, opcode: Opcode.getDeviceInfo.rawValue,
                              sequence: 0x00, payload: [0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(str(message.encode()), "FEDCBAC402000500FFFFFFFFEF")
    }

    func testDecodeRealDeviceInfoFrame() {
        let raw = hex("FEDCBA040200410000100076656C61206F7320656172627564730501151215120202E40503271750DB020401020500030615120208010407E4E414020D02020E03020F0103100101EF")
        var decoder = FrameDecoder()
        let messages = decoder.feed(raw)
        XCTAssertEqual(messages.count, 1)
        guard let message = messages.first else { return XCTFail("no frame decoded") }
        XCTAssertEqual(message.opcode, Opcode.getDeviceInfo.rawValue)
        XCTAssertEqual(message.type, .response)
        XCTAssertEqual(message.payload.count, 63)

        let info = DeviceInfo.parse(message.payload)
        XCTAssertEqual(info.modelName, "vela os earbuds")
        XCTAssertEqual(info.left.percent, 100)
        XCTAssertEqual(info.right.percent, 100)
        XCTAssertEqual(info.caseBattery.percent, 20)
    }

    func testDecoderHandlesSplitReads() {
        let full = hex("FEDCBA040200410000100076656C61206F7320656172627564730501151215120202E40503271750DB020401020500030615120208010407E4E414020D02020E03020F0103100101EF")
        for chunk in [1, 3, 7, 13, 29] {
            var decoder = FrameDecoder()
            var got: [Message] = []
            var index = 0
            while index < full.count {
                let end = min(index + chunk, full.count)
                got += decoder.feed(Array(full[index..<end]))
                index = end
            }
            XCTAssertEqual(got.count, 1, "chunk size \(chunk)")
            XCTAssertEqual(got.first?.payload.count, 63, "chunk size \(chunk)")
        }
    }

    func testBatteryDecoding() {
        XCTAssertNil(BatteryLevel(raw: 0xFF).percent)
        XCTAssertFalse(BatteryLevel(raw: 0xFF).isPresent)

        let full = BatteryLevel(raw: 0xE4)
        XCTAssertEqual(full.percent, 100)
        XCTAssertTrue(full.isCharging)

        let low = BatteryLevel(raw: 0x14)
        XCTAssertEqual(low.percent, 20)
        XCTAssertFalse(low.isCharging)
    }

    func testConfigRecordEncodeAndParse() {
        let eqSet = ConfigRecord.encodeSet(id: 0x0007, value: [0x0E])
        let ancSet = ConfigRecord.encodeSet(id: 0x000B, value: [0x01, 0x13])
        XCTAssertEqual(str(eqSet), "0300070E")
        XCTAssertEqual(str(ancSet), "04000B0113")

        let parsed = ConfigRecord.parse(eqSet + ancSet)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0], ConfigRecord(id: 0x0007, value: [0x0E]))
        XCTAssertEqual(parsed[1], ConfigRecord(id: 0x000B, value: [0x01, 0x13]))
    }

    func testSAFERPlusResponseVector() {
        let challenge = hex("00112233445566778899AABBCCDDEEFF")
        let resp = SAFER.response(to: challenge)
        XCTAssertNotNil(resp)
        XCTAssertEqual(resp?.count, 16)
        XCTAssertNil(SAFER.response(to: [0x00, 0x01]))
    }

    func testDiscoveredDeviceBudsDetection() {
        let buds = DiscoveredDevice(id: UUID(), name: "Xiaomi Buds 5 Pro")
        let clip = DiscoveredDevice(id: UUID(), name: "Xiaomi 耳夹式耳机")
        XCTAssertTrue(buds.isBudsSeries)
        XCTAssertFalse(clip.isBudsSeries)
    }
}
