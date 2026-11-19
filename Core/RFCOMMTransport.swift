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
    private var pendingDevice: IOBluetoothDevice?
    private var pendingChannelID: UInt8?
    private var pendingName: String = ""
    private var connectToken: Int = 0

    public private(set) var state: BLETransport.TransportState = .idle

    // MARK: - Discovery

    /// Scans paired Classic Bluetooth devices for Xiaomi `0xFD2D` RFCOMM service records.
    public func discoverPairedDevices(reachable: Set<String> = [], beaconRSSI: [String: Int] = [:]) -> [DiscoveredDevice] {
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
            let normKey = XiaomiFastPairBeacon.normalizedMACKey(addr)
            let isReachable = reachable.contains(addr) || reachable.contains(normKey) || beaconRSSI[normKey] != nil

            var record: IOBluetoothSDPServiceRecord? = device.getServiceRecord(for: uuid128)
            if record == nil, let uuid16 { record = device.getServiceRecord(for: uuid16) }

            if record == nil && isConnected && (device.services?.isEmpty ?? true) && Self.looksLikeEarbuds(name) {
                _ = device.performSDPQuery(nil)
                record = device.getServiceRecord(for: uuid128)
                if record == nil, let uuid16 { record = device.getServiceRecord(for: uuid16) }
            }

            var resolvedChannelID: UInt8?
            if let record {
                var channelID: BluetoothRFCOMMChannelID = 0
                if record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
                    resolvedChannelID = channelID
                }
            }

            // Emit if 0xFD2D SDP is known OR if this is a reachable/connected Xiaomi earbud awaiting SDP.
            guard resolvedChannelID != nil || ((isConnected || isReachable) && DiscoveredDevice.isEarbudName(name)) else {
                continue
            }

            let id = DiscoveredDevice.classicUUID(for: addr)
            let rssiVal = isConnected ? Int(device.rawRSSI()) : nil
            let classicRSSI = (rssiVal != nil && rssiVal != 127) ? rssiVal : nil
            let rssi = classicRSSI ?? beaconRSSI[normKey]

            found.append(DiscoveredDevice(
                id: id,
                name: name,
                rssi: rssi,
                isSystemConnected: isConnected,
                lastSeen: Date(),
                transportKind: .rfcomm,
                classicAddress: addr,
                rfcommChannelID: resolvedChannelID,
                isNearby: isReachable
            ))
        }

        return found.sorted { lhs, rhs in
            if lhs.isSystemConnected != rhs.isSystemConnected { return lhs.isSystemConnected }
            return lhs.name < rhs.name
        }
    }

    /// Paired but not currently connected devices that may be Xiaomi earbuds (SDP record known, or earbud-like name).
    /// These are probed for reachability so "paired but not auto-connected" earbuds can still trigger the discovery card.
    public func pairedProbeCandidates() -> [String] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        let uuid16 = IOBluetoothSDPUUID(uuid16: 0xFD2D)
        return paired.compactMap { device in
            guard let addr = device.addressString, !addr.isEmpty, !device.isConnected() else { return nil }
            let hasRecord = uuid16.map { device.getServiceRecord(for: $0) != nil } ?? false
            return (hasRecord || Self.looksLikeEarbuds(device.name ?? "")) ? addr : nil
        }
    }

    private static func looksLikeEarbuds(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("buds") || lower.contains("redmi") || lower.contains("xiaomi") || lower.contains("耳机")
    }

    // MARK: - Connection & I/O

    public func connect(address: String, channelID: UInt8?, deviceID: UUID, name: String) {
        DispatchQueue.main.async {
            self.disconnectOnMain()

            guard let device = IOBluetoothDevice(addressString: address) else {
                self.onEvent?(.log("RFCOMM 找不到经典蓝牙设备 \(address)"))
                self.setState(.disconnected("未找到经典蓝牙设备"))
                return
            }

            self.connectToken += 1
            let token = self.connectToken
            self.activeDeviceID = deviceID
            self.pendingDevice = device
            self.pendingChannelID = channelID
            self.pendingName = name
            self.decoder = FrameDecoder()
            self.sequence = 0
            self.setState(.connecting)
            self.onEvent?(.activeDeviceChanged(deviceID, name))
            self.onEvent?(.name(name))

            if device.isConnected() {
                self.proceedAfterBasebandConnect(device: device, deviceID: deviceID, channelID: channelID, name: name, token: token)
                return
            }

            self.onEvent?(.log("正在建立经典蓝牙连接（\(name)）…"))
            let rc = device.openConnection(self, withPageTimeout: 8000, authenticationRequired: true)
            if rc != kIOReturnSuccess {
                self.onEvent?(.log("经典蓝牙连接发起失败（code=\(rc)）"))
                self.setState(.disconnected("经典蓝牙连接失败"))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                guard let self, self.connectToken == token, !self.isOpen, self.channel == nil else { return }
                self.onEvent?(.log("经典蓝牙连接超时，请确认耳机已开机且未处于休眠"))
                self.setState(.disconnected("连接超时"))
            }
        }
    }

    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        let token = connectToken
        guard let device, pendingDevice === device, let deviceID = activeDeviceID, channel == nil, !isOpen else { return }
        if status != kIOReturnSuccess {
            onEvent?(.log("经典蓝牙连接失败（code=\(status)）"))
            setState(.disconnected("经典蓝牙连接失败"))
            return
        }
        proceedAfterBasebandConnect(device: device, deviceID: deviceID, channelID: pendingChannelID, name: pendingName, token: token)
    }

    private func proceedAfterBasebandConnect(device: IOBluetoothDevice, deviceID: UUID, channelID: UInt8?, name: String, token: Int) {
        guard connectToken == token, activeDeviceID == deviceID, channel == nil else { return }
        if let channelID {
            openChannel(on: device, channelID: channelID, name: name, token: token)
            return
        }
        let uuid128 = Self.fd2dBytes.withUnsafeBytes { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
        let uuid16 = IOBluetoothSDPUUID(uuid16: 0xFD2D)
        if let rec = device.getServiceRecord(for: uuid128) ?? uuid16.flatMap({ device.getServiceRecord(for: $0) }) {
            var ch: BluetoothRFCOMMChannelID = 0
            if rec.getRFCOMMChannelID(&ch) == kIOReturnSuccess {
                openChannel(on: device, channelID: ch, name: name, token: token)
                return
            }
        }
        onEvent?(.log("正在查询 0xFD2D 服务通道（\(name)）…"))
        let rc = device.performSDPQuery(self)
        if rc != kIOReturnSuccess {
            onEvent?(.log("SDP 查询失败（code=\(rc)）"))
            setState(.disconnected("未找到 0xFD2D 通道"))
        }
    }

    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        let token = connectToken
        guard let device, pendingDevice === device, activeDeviceID != nil, channel == nil else { return }
        let uuid128 = Self.fd2dBytes.withUnsafeBytes { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
        let uuid16 = IOBluetoothSDPUUID(uuid16: 0xFD2D)
        let rec = device.getServiceRecord(for: uuid128) ?? uuid16.flatMap { device.getServiceRecord(for: $0) }
        var ch: BluetoothRFCOMMChannelID = 0
        if let rec, rec.getRFCOMMChannelID(&ch) == kIOReturnSuccess {
            openChannel(on: device, channelID: ch, name: pendingName, token: token)
        } else {
            onEvent?(.log("未查到 0xFD2D RFCOMM 通道（status=\(status)）"))
            setState(.disconnected("未找到 0xFD2D 通道"))
        }
    }

    private func openChannel(on device: IOBluetoothDevice, channelID: UInt8, name: String, token: Int) {
        guard connectToken == token, channel == nil else { return }
        self.onEvent?(.log("正在打开经典蓝牙 RFCOMM 通道 \(channelID)（\(name)）"))
        var newChannel: IOBluetoothRFCOMMChannel?
        let rc = device.openRFCOMMChannelAsync(&newChannel, withChannelID: channelID, delegate: self)
        if rc != kIOReturnSuccess {
            self.onEvent?(.log("打开 RFCOMM 通道失败（code=\(rc)）"))
            self.setState(.disconnected("RFCOMM 连接失败"))
            return
        }
        self.channel = newChannel
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self, self.connectToken == token, !self.isOpen else { return }
            self.onEvent?(.log("RFCOMM 通道 \(channelID) 打开超时（可能耳机未在系统蓝牙完成连接或正在被手机占用）"))
            self.disconnectOnMain()
            self.setState(.disconnected("RFCOMM 连接超时"))
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
        self.pendingDevice = nil
        self.pendingChannelID = nil
        self.connectToken += 1
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
