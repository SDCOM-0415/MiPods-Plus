import Foundation
import IOBluetooth

/// Classic Bluetooth inquiry for earbuds in pairing mode (not yet paired with this Mac),
/// plus pairing support. All calls must happen on the main thread.
final class ClassicDiscovery: NSObject, IOBluetoothDeviceInquiryDelegate, IOBluetoothDevicePairDelegate {
    var onDevices: (([DiscoveredDevice]) -> Void)?
    var onPaired: ((String, Bool) -> Void)?
    var onLog: ((String) -> Void)?

    private var inquiry: IOBluetoothDeviceInquiry?
    private var pair: IOBluetoothDevicePair?
    private var running = false
    private var found: [String: DiscoveredDevice] = [:]

    func start() {
        guard !running else { return }
        running = true
        runInquiry()
    }

    func stop() {
        running = false
        inquiry?.stop()
        inquiry = nil
    }

    private func runInquiry() {
        guard running else { return }
        let inq = IOBluetoothDeviceInquiry(delegate: self)
        inq?.inquiryLength = 8
        inq?.updateNewDeviceNames = true
        inquiry = inq
        let status = inq?.start() ?? kIOReturnError
        if status != kIOReturnSuccess {
            onLog?("经典蓝牙查询启动失败 (\(status))")
            scheduleRestart()
        }
    }

    private func scheduleRestart() {
        guard running else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.runInquiry()
        }
    }

    private func consider(_ device: IOBluetoothDevice) {
        guard !device.isPaired(), let addr = device.addressString else { return }
        let name = device.name ?? ""
        guard DiscoveredDevice.isEarbudName(name) else { return }
        let raw = Int(device.rawRSSI())
        let rssi: Int? = (raw == 127 || raw == 0) ? nil : raw
        found[addr] = DiscoveredDevice(
            id: DiscoveredDevice.classicUUID(for: addr),
            name: name,
            rssi: rssi,
            transportKind: .rfcomm,
            classicAddress: addr,
            needsPairing: true
        )
        onDevices?(Array(found.values))
    }

    // MARK: IOBluetoothDeviceInquiryDelegate

    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        if let device { consider(device) }
    }

    func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        if let device { consider(device) }
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        // Drop devices not seen again (they left pairing mode / went away) after each round.
        let current = (sender.foundDevices() as? [IOBluetoothDevice]) ?? []
        let addrs = Set(current.compactMap { $0.addressString })
        found = found.filter { addrs.contains($0.key) }
        onDevices?(Array(found.values))
        scheduleRestart()
    }

    // MARK: Pairing

    func pair(address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else {
            onLog?("无法创建蓝牙设备 \(address)")
            return
        }
        inquiry?.stop()
        let p = IOBluetoothDevicePair(device: device)
        p?.delegate = self
        pair = p
        let status = p?.start() ?? kIOReturnError
        if status != kIOReturnSuccess {
            onLog?("配对启动失败 (\(status))")
            pair = nil
            onPaired?(address, false)
        }
    }

    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        let addr = (sender as? IOBluetoothDevicePair)?.device()?.addressString ?? ""
        let ok = error == kIOReturnSuccess
        if ok { (sender as? IOBluetoothDevicePair)?.device()?.openConnection() }
        onLog?(ok ? "配对成功 \(addr)" : "配对失败 (\(error))")
        pair = nil
        if ok { found[addr] = nil; onDevices?(Array(found.values)) }
        onPaired?(addr, ok)
    }
}
