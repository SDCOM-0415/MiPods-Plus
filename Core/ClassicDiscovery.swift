import Foundation
import IOBluetooth

/// Classic Bluetooth inquiry for earbuds in pairing mode (not yet paired with this Mac),
/// plus reachability probing for paired-but-disconnected earbuds and pairing support.
/// Inquiry and remoteNameRequest are strictly serialized so they never collide on the HCI controller.
/// All calls must happen on the main thread.
final class ClassicDiscovery: NSObject, IOBluetoothDeviceInquiryDelegate, IOBluetoothDevicePairDelegate {
    var onDevices: (([DiscoveredDevice]) -> Void)?
    var onPaired: ((String, Bool) -> Void)?
    /// Provides paired-but-unconnected candidate addresses to probe for reachability.
    var probeProvider: (() -> [String])?
    var onReachable: ((Set<String>) -> Void)?
    var onLog: ((String) -> Void)?
    var verboseLogging = false

    private var inquiry: IOBluetoothDeviceInquiry?
    private var pair: IOBluetoothDevicePair?
    private var running = false
    private var inquiryActive = false
    private var restartWorkItem: DispatchWorkItem?

    private var reachable: Set<String> = []
    private var probeQueue: [String] = []
    private var probing: String?
    private var probeToken = 0
    private var found: [String: DiscoveredDevice] = [:]

    func start() {
        guard !running else { return }
        running = true
        runInquiry()
    }

    /// Immediately starts a fresh inquiry round (used by manual rescan).
    func restart() {
        restartWorkItem?.cancel()
        restartWorkItem = nil
        running = true
        if inquiryActive || probing != nil {
            return
        }
        runInquiry()
    }

    func stop() {
        running = false
        restartWorkItem?.cancel()
        restartWorkItem = nil
        inquiry?.stop()
        inquiry = nil
        inquiryActive = false
        probing = nil
        probeQueue.removeAll()
        probeToken += 1
    }

    // MARK: - Classic Inquiry

    private func runInquiry() {
        guard running, !inquiryActive, pair == nil else { return }
        restartWorkItem?.cancel()
        restartWorkItem = nil

        let inq = IOBluetoothDeviceInquiry(delegate: self)
        inq?.inquiryLength = 6
        inq?.updateNewDeviceNames = true
        inquiry = inq
        let status = inq?.start() ?? kIOReturnError
        if status == kIOReturnSuccess {
            inquiryActive = true
            if verboseLogging { onLog?("[经典] 开始 Inquiry 扫描 (6s)…") }
        } else {
            onLog?("[经典] Inquiry 启动失败 (code=\(status))")
            startProbeRound()
        }
    }

    private func scheduleNextRound() {
        guard running else { return }
        restartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.runInquiry()
        }
        restartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: item)
    }

    private func consider(_ device: IOBluetoothDevice) {
        guard let addr = device.addressString, !addr.isEmpty else { return }
        let name = device.name ?? ""
        let paired = device.isPaired()

        if verboseLogging {
            onLog?("[经典] 发现设备: \(name.isEmpty ? "(无名)" : name) [\(addr)] paired=\(paired) rssi=\(device.rawRSSI())")
        }

        if paired {
            if DiscoveredDevice.isEarbudName(name), reachable.insert(addr).inserted {
                onReachable?(reachable)
            }
            return
        }

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

    // MARK: - IOBluetoothDeviceInquiryDelegate

    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        if let device { consider(device) }
    }

    func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        if let device { consider(device) }
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        inquiryActive = false
        let current = (sender.foundDevices() as? [IOBluetoothDevice]) ?? []
        for device in current {
            consider(device)
        }
        if verboseLogging || error != kIOReturnSuccess {
            onLog?("[经典] Inquiry 完成: count=\(current.count) error=\(error) aborted=\(aborted)")
        }
        let addrs = Set(current.compactMap { $0.addressString })
        found = found.filter { addrs.contains($0.key) }
        onDevices?(Array(found.values))

        // Run paired reachability probes only after inquiry completes to avoid HCI contention.
        startProbeRound()
    }

    // MARK: - Reachability Probe of Paired Devices

    private func startProbeRound() {
        guard running, !inquiryActive, probing == nil, pair == nil else {
            scheduleNextRound()
            return
        }
        probeQueue = probeProvider?() ?? []
        let valid = Set(probeQueue)
        if !reachable.isSubset(of: valid) {
            reachable = reachable.intersection(valid)
            onReachable?(reachable)
        }
        if probeQueue.isEmpty {
            scheduleNextRound()
        } else {
            probeNext()
        }
    }

    private func probeNext() {
        guard running, !inquiryActive, !probeQueue.isEmpty else {
            probing = nil
            scheduleNextRound()
            return
        }
        let addr = probeQueue.removeFirst()
        guard let device = IOBluetoothDevice(addressString: addr) else {
            probeNext()
            return
        }
        probing = addr
        probeToken += 1
        let token = probeToken
        let rc = device.remoteNameRequest(self)
        if rc != kIOReturnSuccess {
            finishProbe(addr, ok: false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.probing == addr, self.probeToken == token else { return }
            self.finishProbe(addr, ok: false)
        }
    }

    @objc func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard let addr = device?.addressString, addr == probing else { return }
        finishProbe(addr, ok: status == kIOReturnSuccess)
    }

    private func finishProbe(_ addr: String, ok: Bool) {
        probing = nil
        let changed = ok ? reachable.insert(addr).inserted : (reachable.remove(addr) != nil)
        if changed { onReachable?(reachable) }
        probeNext()
    }

    // MARK: - Pairing

    func pair(address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else {
            onLog?("无法创建蓝牙设备 \(address)")
            return
        }
        restartWorkItem?.cancel()
        restartWorkItem = nil
        inquiry?.stop()
        inquiryActive = false
        probing = nil
        probeQueue.removeAll()
        probeToken += 1

        let p = IOBluetoothDevicePair(device: device)
        p?.delegate = self
        pair = p
        let status = p?.start() ?? kIOReturnError
        if status != kIOReturnSuccess {
            onLog?("配对启动失败 (\(status))")
            pair = nil
            onPaired?(address, false)
            scheduleNextRound()
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
        scheduleNextRound()
    }
}
