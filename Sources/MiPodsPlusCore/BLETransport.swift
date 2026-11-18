import Foundation
import CoreBluetooth

/// Multi-device BLE GATT transport for Xiaomi / Redmi earbuds.
///
/// Combines:
/// - `buds-ctl` fast path: `retrieveConnectedPeripherals(withServices: [AF00])`
/// - `MiPods` unfiltered scan + `0x038F` company ID / name matching + role-based characteristic discovery
/// - Multi-device tracking & switching (`discoveredDevices`, `connect(deviceID:)`, `rescan()`)
public final class BLETransport: NSObject {
    public enum Event: Sendable {
        case stateChanged(TransportState)
        case devicesUpdated([DiscoveredDevice])
        case activeDeviceChanged(UUID?, String?)
        case ready(write: String, notify: String)
        case name(String)
        case message(Message)
        case gattBattery([UInt8])
        case log(String)
    }

    public enum TransportState: Sendable, Equatable {
        case idle
        case scanning
        case connecting
        case connected
        case disconnected(String?)
    }

    public static let xiaomiCompanyID: UInt16 = 0x038F
    public static let serviceAF00 = CBUUID(string: "AF00")

    public var onEvent: ((Event) -> Void)?

    /// Optional preferred device UUID (persisted by controller for auto-reconnect).
    public var preferredDeviceID: UUID?

    private let queue = DispatchQueue(label: "com.mipods.plus.ble", qos: .utility)
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var decoder = FrameDecoder()
    private var sequence: UInt8 = 0
    private var isReady = false
    private var wantsScan = false

    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var devicesByID: [UUID: DiscoveredDevice] = [:]

    public private(set) var state: TransportState = .idle

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    // MARK: - Public API

    public func start() {
        queue.async {
            self.wantsScan = true
            self.scanAndAttachIfPossible(autoConnect: true)
        }
    }

    public func rescan() {
        queue.async {
            self.wantsScan = true
            self.central.stopScan()
            self.devicesByID = self.devicesByID.filter { $0.key == self.peripheral?.identifier }
            self.emitDevices()
            self.scanAndAttachIfPossible(autoConnect: self.peripheral == nil)
        }
    }

    public func connect(deviceID: UUID) {
        queue.async {
            self.preferredDeviceID = deviceID
            guard self.central.state == .poweredOn else { return }
            guard let target = self.peripheralsByID[deviceID] else {
                self.onEvent?(.log("未找到目标外设 \(deviceID.uuidString)"))
                return
            }
            if let current = self.peripheral, current.identifier != deviceID {
                self.central.cancelPeripheralConnection(current)
                self.resetChannelState()
            }
            self.attach(target)
        }
    }

    public func stop() {
        queue.async {
            self.wantsScan = false
            self.central.stopScan()
            if let peripheral = self.peripheral {
                self.central.cancelPeripheralConnection(peripheral)
            }
            self.resetChannelState()
            self.setState(.idle)
        }
    }

    public func send(_ opcode: Opcode, payload: [UInt8]) {
        queue.async {
            let frame = Message(type: .phoneRequest, opcode: opcode.rawValue,
                                sequence: self.sequence, payload: payload).encode()
            self.sequence &+= 1
            self.write(frame)
        }
    }

    public func reply(_ opcode: UInt8, sequence seq: UInt8, payload: [UInt8] = []) {
        queue.async {
            let frame = Message(type: .response, opcode: opcode, sequence: seq, payload: payload).encode()
            self.write(frame)
        }
    }

    public func resetSequence() {
        queue.async { self.sequence = 0 }
    }

    public func connectKnownPeripheral() {
        queue.async {
            guard self.central.state == .poweredOn, self.peripheral == nil else { return }
            self.refreshSystemConnectedPeripherals()
            let candidates = self.central.retrieveConnectedPeripherals(withServices: [Self.serviceAF00])
            guard let candidate = self.pickPreferred(from: candidates) else { return }
            self.onEvent?(.log("使用系统已连接外设重连：\(candidate.name ?? candidate.identifier.uuidString)"))
            self.attach(candidate)
        }
    }

    // MARK: - Internals

    private func resetChannelState() {
        peripheral = nil
        writeChar = nil
        notifyChar = nil
        isReady = false
    }

    private func setState(_ newState: TransportState) {
        guard state != newState else { return }
        state = newState
        onEvent?(.stateChanged(newState))
    }

    private func scanAndAttachIfPossible(autoConnect: Bool) {
        guard wantsScan, central.state == .poweredOn else { return }

        refreshSystemConnectedPeripherals()

        if autoConnect, peripheral == nil {
            let connected = central.retrieveConnectedPeripherals(withServices: [Self.serviceAF00])
            if let preferred = pickPreferred(from: connected) {
                onEvent?(.log("复用系统已连接耳机：\(preferred.name ?? "小米耳机")"))
                attach(preferred)
            }
        }

        // Keep scanning unfiltered so all nearby Xiaomi/Redmi/Buds devices appear in the switcher.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        if peripheral == nil && state != .connected && state != .connecting {
            setState(.scanning)
        }
    }

    private func refreshSystemConnectedPeripherals() {
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.serviceAF00])
        for p in connected {
            peripheralsByID[p.identifier] = p
            let name = (p.name?.isEmpty == false) ? p.name! : (devicesByID[p.identifier]?.name ?? "已连接小米耳机")
            var item = devicesByID[p.identifier] ?? DiscoveredDevice(id: p.identifier, name: name)
            item.name = name
            item.isSystemConnected = true
            item.lastSeen = Date()
            devicesByID[p.identifier] = item
        }
        if !connected.isEmpty {
            emitDevices()
        }
    }

    private func pickPreferred(from list: [CBPeripheral]) -> CBPeripheral? {
        guard !list.isEmpty else { return nil }
        if let preferredDeviceID, let match = list.first(where: { $0.identifier == preferredDeviceID }) {
            return match
        }
        return list.first(where: { isXiaomiName($0.name) }) ?? list.first
    }

    private func isXiaomiName(_ name: String?) -> Bool {
        guard let name else { return false }
        return name.localizedCaseInsensitiveContains("xiaomi")
            || name.localizedCaseInsensitiveContains("redmi")
            || name.localizedCaseInsensitiveContains("buds")
    }

    private func attach(_ target: CBPeripheral) {
        peripheral = target
        target.delegate = self
        setState(.connecting)
        onEvent?(.activeDeviceChanged(target.identifier, target.name))
        if let name = target.name, !name.isEmpty {
            onEvent?(.name(name))
        }
        central.connect(target, options: nil)
    }

    private func emitDevices() {
        let sorted = devicesByID.values.sorted { lhs, rhs in
            if lhs.id == peripheral?.identifier { return true }
            if rhs.id == peripheral?.identifier { return false }
            if lhs.isSystemConnected != rhs.isSystemConnected { return lhs.isSystemConnected }
            return (lhs.rssi ?? -127) > (rhs.rssi ?? -127)
        }
        onEvent?(.devicesUpdated(sorted))
    }

    private func write(_ frame: [UInt8]) {
        guard let peripheral, let writeChar else {
            onEvent?(.log("写入被丢弃：通道未就绪"))
            return
        }
        let type: CBCharacteristicWriteType =
            writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(Data(frame), for: writeChar, type: type)
        onEvent?(.log("TX \(frame.hexString)"))
    }
}

// MARK: - CBCentralManagerDelegate

extension BLETransport: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            scanAndAttachIfPossible(autoConnect: true)
        case .unauthorized:
            setState(.disconnected("蓝牙权限被拒绝"))
        case .poweredOff:
            setState(.disconnected("蓝牙已关闭"))
        case .unsupported:
            setState(.disconnected("此设备不支持蓝牙低功耗"))
        default:
            setState(.disconnected(nil))
        }
    }

    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any],
                               rssi RSSI: NSNumber) {
        let mfrData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        var isXiaomi = false
        if let mfrData, mfrData.count >= 2 {
            let company = UInt16(mfrData[0]) | (UInt16(mfrData[1]) << 8)
            isXiaomi = company == Self.xiaomiCompanyID
        }
        let adName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = (adName?.isEmpty == false ? adName : peripheral.name) ?? "小米设备"
        if !isXiaomi && (isXiaomiName(adName) || isXiaomiName(peripheral.name)) {
            isXiaomi = true
        }
        guard isXiaomi else { return }

        peripheralsByID[peripheral.identifier] = peripheral
        var item = devicesByID[peripheral.identifier] ?? DiscoveredDevice(id: peripheral.identifier, name: name)
        item.name = name
        item.rssi = RSSI.intValue
        item.lastSeen = Date()
        item.mfrHex = mfrData?.hexString
        devicesByID[peripheral.identifier] = item
        emitDevices()

        guard self.peripheral == nil else { return }
        if let preferredDeviceID, preferredDeviceID != peripheral.identifier {
            return
        }

        onEvent?(.log("发现 \(name)，正在连接"))
        attach(peripheral)
    }

    public func centralManager(_ central: CBCentralManager,
                               didConnect peripheral: CBPeripheral) {
        decoder = FrameDecoder()
        sequence = 0
        peripheral.discoverServices([Self.serviceAF00,
                                     CBUUID(string: "180F"),
                                     CBUUID(string: "180A")])
    }

    public func centralManager(_ central: CBCentralManager,
                               didFailToConnect peripheral: CBPeripheral, error: Error?) {
        resetChannelState()
        setState(.disconnected(error?.localizedDescription ?? "连接失败"))
        scanAndAttachIfPossible(autoConnect: false)
    }

    public func centralManager(_ central: CBCentralManager,
                               didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        resetChannelState()
        setState(.disconnected(error?.localizedDescription))
        scanAndAttachIfPossible(autoConnect: false)
    }
}

// MARK: - CBPeripheralDelegate

extension BLETransport: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services, !services.isEmpty else {
            onEvent?(.log("未发现服务：\(error?.localizedDescription ?? "空")"))
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        let isAudioControl = service.uuid == Self.serviceAF00
        for characteristic in service.characteristics ?? [] {
            let props = characteristic.properties
            if isAudioControl {
                if props.contains(.write) || props.contains(.writeWithoutResponse) {
                    if writeChar == nil { writeChar = characteristic }
                    if props.contains(.notify) || props.contains(.indicate) {
                        notifyChar = characteristic
                        peripheral.setNotifyValue(true, for: characteristic)
                    }
                } else if props.contains(.notify) || props.contains(.indicate) {
                    if notifyChar == nil {
                        notifyChar = characteristic
                        peripheral.setNotifyValue(true, for: characteristic)
                    }
                }
            }
            if characteristic.uuid == CBUUID(string: "2A19") {
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }

        if writeChar != nil, notifyChar != nil, !isReady {
            isReady = true
            setState(.connected)
            onEvent?(.ready(write: writeChar?.uuid.uuidString ?? "?",
                            notify: notifyChar?.uuid.uuidString ?? "?"))
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)

        if characteristic.uuid == CBUUID(string: "2A19") {
            onEvent?(.gattBattery(bytes))
            return
        }
        for message in decoder.feed(bytes) {
            onEvent?(.message(message))
        }
    }
}

// MARK: - Helpers

extension Array where Element == UInt8 {
    public var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}

extension Data {
    public var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}
