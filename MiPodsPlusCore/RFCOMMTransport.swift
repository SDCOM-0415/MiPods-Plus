import Foundation
import IOBluetooth

/// Classic Bluetooth RFCOMM transport for Xiaomi / Redmi earbuds exposing SDP service `0xFD2D`
/// (e.g. Redmi Buds 6 青春版 / Redmi Buds 6 Lite, Redmi Buds 5 Pro, etc.).
///
/// Uses the exact same `FE DC BA ... EF` frame protocol and SAFER+ handshake as BLE `AF00`.
public final class RFCOMMTransport: NSObject, IOBluetoothRFCOMMChannelDelegate {

    public var onEvent: ((BLETransport.Event) -> Void)?

    private static let fd2dBytes: [UInt8] = [
        0x00, 0x00, 0xFD, 0x2D,
        0x00, 0x00, 0x10, 0x00,
        0x80, 0x00, 0x00, 0x80,
        0x5F, 0x9B, 0x34, 0xFB
    ]

    private var channel: IOBluetoothRFCOMMChannel?
    private var activeDeviceID: UUID?
    private var decoder = FrameDecoder()
    private var sequence: UInt8 = 0
    private var isOpen = false

    public private(set) var state: BLETransport.TransportState = .idle

    // MARK: - Discovery

    /// Scans paired Classic Bluetooth devices for Xiaomi `0xFD2D` RFCOMM service records.
    public func discoverPairedDevices() -> [DiscoveredDevice] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        let uuid128 = Self.fd2dBytes.withUnsafeBytes { ptr in
            IOBluetoothSDPUUID(bytes: ptr.baseAddress, length: 16)
        }
        let uuid16 = IOBluetoothSDPUUID(uuid16: 0xFD2D)

        var found: [DiscoveredDevice] = []
        for device in paired {
            guard let addr = device.addressString, !addr.isEmpty else { continue }
            let name = (device.name?.isEmpty == false ? device.name! : addr)
            let isConnected = device.isConnected()

            var record: IOBluetoothSDPServiceRecord? = device.getServiceRecord(for: uuid128)
            if record == nil, let uuid16 { record = device.getServiceRecord(for: uuid16) }

            // If SDP cache is empty on a currently connected Xiaomi/Redmi/Buds headset, query it once.
            if record == nil && isConnected && (device.services?.isEmpty ?? true) && Self.looksLikeEarbuds(name) {
                _ = device.performSDPQuery(nil)
                record = device.getServiceRecord(for: uuid128)
                if record == nil, let uuid16 { record = device.getServiceRecord(for: uuid16) }
            }

            guard let record else { continue }

            var channelID: BluetoothRFCOMMChannelID = 0
            guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else { continue }

            let id = DiscoveredDevice.classicUUID(for: addr)
            let rssiVal = isConnected ? Int(device.rawRSSI()) : nil
            let rssi = (rssiVal != nil && rssiVal != 127) ? rssiVal : nil

            found.append(DiscoveredDevice(
                id: id,
                name: name,
                rssi: rssi,
                isSystemConnected: isConnected,
                lastSeen: Date(),
                transportKind: .rfcomm,
                classicAddress: addr,
                rfcommChannelID: channelID
            ))
        }

        return found.sorted { lhs, rhs in
            if lhs.isSystemConnected != rhs.isSystemConnected { return lhs.isSystemConnected }
            return lhs.name < rhs.name
        }
    }

    private static func looksLikeEarbuds(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("buds") || lower.contains("redmi") || lower.contains("xiaomi") || lower.contains("耳机")
    }

    // MARK: - Connection & I/O

    public func connect(address: String, channelID: UInt8, deviceID: UUID, name: String) {
        DispatchQueue.main.async {
            self.disconnectOnMain()

            guard let device = IOBluetoothDevice(addressString: address) else {
                self.onEvent?(.log("RFCOMM 找不到经典蓝牙设备 \(address)"))
                self.setState(.disconnected("未找到经典蓝牙设备"))
                return
            }

            self.activeDeviceID = deviceID
            self.decoder = FrameDecoder()
            self.sequence = 0
            self.setState(.connecting)
            self.onEvent?(.activeDeviceChanged(deviceID, name))
            self.onEvent?(.name(name))
            self.onEvent?(.log("正在打开经典蓝牙 RFCOMM 通道 \(channelID)（\(name)）"))

            var newChannel: IOBluetoothRFCOMMChannel?
            let rc = device.openRFCOMMChannelAsync(&newChannel, withChannelID: channelID, delegate: self)
            if rc != kIOReturnSuccess {
                self.onEvent?(.log("打开 RFCOMM 通道失败（code=\(rc)）"))
                self.setState(.disconnected("RFCOMM 连接失败"))
                return
            }
            self.channel = newChannel
        }
    }

    public func disconnect() {
        DispatchQueue.main.async {
            self.disconnectOnMain()
        }
    }

    private func disconnectOnMain() {
        if let ch = self.channel {
            ch.setDelegate(nil)
            ch.close()
        }
        self.channel = nil
        self.isOpen = false
        self.activeDeviceID = nil
        self.setState(.idle)
    }

    public func send(_ opcode: Opcode, payload: [UInt8]) {
        DispatchQueue.main.async {
            let frame = Message(type: .phoneRequest, opcode: opcode.rawValue,
                                sequence: self.sequence, payload: payload).encode()
            self.sequence &+= 1
            self.write(frame)
        }
    }

    public func reply(_ opcode: UInt8, sequence seq: UInt8, payload: [UInt8] = []) {
        DispatchQueue.main.async {
            let frame = Message(type: .response, opcode: opcode, sequence: seq, payload: payload).encode()
            self.write(frame)
        }
    }

    public func resetSequence() {
        DispatchQueue.main.async { self.sequence = 0 }
    }

    private func setState(_ newState: BLETransport.TransportState) {
        guard state != newState else { return }
        state = newState
        onEvent?(.stateChanged(newState))
    }

    private func write(_ frame: [UInt8]) {
        guard let ch = channel, isOpen else {
            onEvent?(.log("RFCOMM 写入被丢弃：通道未就绪"))
            return
        }
        var mutable = frame
        let length = UInt16(mutable.count)
        let rc = mutable.withUnsafeMutableBytes { ptr in
            ch.writeSync(ptr.baseAddress, length: length)
        }
        if rc != kIOReturnSuccess {
            onEvent?(.log("RFCOMM 写入失败（code=\(rc)）"))
        } else {
            onEvent?(.log("TX(RFCOMM) \(frame.hexString)"))
        }
    }

    // MARK: - IOBluetoothRFCOMMChannelDelegate

    public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        guard error == kIOReturnSuccess else {
            onEvent?(.log("RFCOMM 通道打开失败（status=\(error)）"))
            channel = nil
            isOpen = false
            setState(.disconnected("RFCOMM 打开失败"))
            return
        }
        channel = rfcommChannel
        isOpen = true
        let chID = rfcommChannel?.getID() ?? 0
        setState(.connected)
        onEvent?(.ready(write: "RFCOMM:\(chID)", notify: "RFCOMM:\(chID)"))
    }

    public func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                                  data dataPointer: UnsafeMutableRawPointer!,
                                  length dataLength: Int) {
        guard let dataPointer, dataLength > 0 else { return }
        let bytes = [UInt8](UnsafeBufferPointer(
            start: dataPointer.assumingMemoryBound(to: UInt8.self),
            count: dataLength
        ))
        for message in decoder.feed(bytes) {
            onEvent?(.message(message))
        }
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        channel = nil
        isOpen = false
        setState(.disconnected("RFCOMM 通道已断开"))
    }
}
