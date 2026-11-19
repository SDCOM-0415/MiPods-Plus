import Foundation
import Combine
import ServiceManagement

/// Snapshot of the active device state rendered by the HUD, Panel, and Touch Bar.
public struct MiPodsState: Sendable, Equatable {
    public var isConnected = false
    public var isAuthenticated = false
    public var isAuthenticating = false

    public var deviceName = ""
    public var modelName = ""

    public var leftBattery: Int?
    public var rightBattery: Int?
    public var caseBattery: Int?

    public var isLeftCharging = false
    public var isRightCharging = false
    public var isCaseCharging = false

    public var noiseMode: NoiseMode = .off
    public var ancLevel: Int = 19
    public var transparencyLevel: TransparencyLevel = .standard
    public var adaptiveANC = false
    public var personalANC = false

    public var eqPreset: EQPreset = .default
    public var customEQBands: [EQBand] = EQBand.defaultBands
    public var spatialBits: UInt8 = 0
    public var spatialScene: SpatialScene = .off
    public var wearDetect = false
    public var hotword = false
    public var autoAnswer = false
    public var dualDevice = false
    public var lowLatency = false
    public var adaptiveSense = false
    public var adaptiveVolume = false
    public var freeTalk: FreeTalkDuration = .off

    /// Gesture map: GestureType -> (left, right)
    public var gestures: [GestureType: (left: GestureAction, right: GestureAction)] = [:]
    public var configs: [UInt16: [UInt8]] = [:]

    public var capabilities: Capabilities = []
    public var canRecordLocally: Bool?
    public var wearingFlags: UInt8?

    public var firmware: String = ""
    public var lastUpdate: Date?
    public var statusDetail = "未连接"
    public var log: [String] = []

    public init() {}

    public static func == (lhs: MiPodsState, rhs: MiPodsState) -> Bool {
        lhs.isConnected == rhs.isConnected &&
        lhs.isAuthenticated == rhs.isAuthenticated &&
        lhs.isAuthenticating == rhs.isAuthenticating &&
        lhs.deviceName == rhs.deviceName &&
        lhs.modelName == rhs.modelName &&
        lhs.leftBattery == rhs.leftBattery &&
        lhs.rightBattery == rhs.rightBattery &&
        lhs.caseBattery == rhs.caseBattery &&
        lhs.isLeftCharging == rhs.isLeftCharging &&
        lhs.isRightCharging == rhs.isRightCharging &&
        lhs.isCaseCharging == rhs.isCaseCharging &&
        lhs.noiseMode == rhs.noiseMode &&
        lhs.ancLevel == rhs.ancLevel &&
        lhs.transparencyLevel == rhs.transparencyLevel &&
        lhs.adaptiveANC == rhs.adaptiveANC &&
        lhs.personalANC == rhs.personalANC &&
        lhs.eqPreset == rhs.eqPreset &&
        lhs.customEQBands == rhs.customEQBands &&
        lhs.spatialBits == rhs.spatialBits &&
        lhs.spatialScene == rhs.spatialScene &&
        lhs.wearDetect == rhs.wearDetect &&
        lhs.hotword == rhs.hotword &&
        lhs.autoAnswer == rhs.autoAnswer &&
        lhs.dualDevice == rhs.dualDevice &&
        lhs.lowLatency == rhs.lowLatency &&
        lhs.adaptiveSense == rhs.adaptiveSense &&
        lhs.adaptiveVolume == rhs.adaptiveVolume &&
        lhs.freeTalk == rhs.freeTalk &&
        lhs.configs == rhs.configs &&
        lhs.capabilities == rhs.capabilities &&
        lhs.canRecordLocally == rhs.canRecordLocally &&
        lhs.wearingFlags == rhs.wearingFlags &&
        lhs.firmware == rhs.firmware &&
        lhs.lastUpdate == rhs.lastUpdate &&
        lhs.statusDetail == rhs.statusDetail
    }
}

/// Hybrid multi-device controller:
/// 1. Discovers all nearby & system-connected Xiaomi / Redmi / Buds devices.
/// 2. Always reads battery & basic info first (`0x02` / `0x09`, unauthenticated) so
///    open-ear / restricted models (e.g. M2529E1) never go silent.
/// 3. Automatically runs SAFER+ handshake (`0x50` / `0x51`) for Buds-series models or
///    previously authenticated devices, and lets users trigger it on demand for others.
@MainActor
public final class MiPodsController: ObservableObject {

    @Published public var state = MiPodsState()
    @Published public var discoveredDevices: [DiscoveredDevice] = []
    @Published public var activeDeviceID: UUID?
    @Published public var launchAtLogin: Bool = {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }()

    public var supportsLaunchAtLogin: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    private let bleTransport = BLETransport()
    private let rfcommTransport = RFCOMMTransport()
    private var activeTransportKind: TransportKind = .ble
    private var bleDevices: [DiscoveredDevice] = []
    private var rfcommDevices: [DiscoveredDevice] = []
    private var inquiryDevices: [DiscoveredDevice] = []
    private let classicDiscovery = ClassicDiscovery()
    private var reachableAddresses: Set<String> = []
    private var connectTimeoutTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var pendingCommandAfterAuth: (() -> Void)?

    private static let preferredDeviceKey = "mipods.plus.preferredDeviceID"
    private static let authedDevicesKey = "mipods.plus.authedDeviceIDs"
    private static let statusConfigIDs: [UInt16] = [
        0x02, 0x03, 0x04, 0x07, 0x0A, 0x0B, 0x0C, 0x0D, 0x1E, 0x25, 0x29, 0x2F, 0x36, 0x37, 0x3A, 0x3B, 0x48
    ]

    public static let pollInterval: TimeInterval = 30

    public init() {
        if let saved = UserDefaults.standard.string(forKey: Self.preferredDeviceKey),
           let uuid = UUID(uuidString: saved) {
            bleTransport.preferredDeviceID = uuid
            activeDeviceID = uuid
        }
        bleTransport.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in self?.handle(event, from: .ble) }
        }
        rfcommTransport.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in self?.handle(event, from: .rfcomm) }
        }
        classicDiscovery.onLog = { [weak self] line in
            Task { @MainActor [weak self] in self?.append(line) }
        }
        classicDiscovery.onDevices = { [weak self] devices in
            Task { @MainActor [weak self] in
                self?.inquiryDevices = devices
                self?.mergeDiscoveredDevices()
            }
        }
        let transport = rfcommTransport
        classicDiscovery.probeProvider = { transport.pairedProbeCandidates() }
        classicDiscovery.onReachable = { [weak self] addrs in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reachableAddresses = addrs
                self.refreshRFCOMMDevices(autoConnect: false)
            }
        }
        classicDiscovery.onPaired = { [weak self] _, ok in
            Task { @MainActor [weak self] in
                guard let self, ok else { return }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                self.refreshRFCOMMDevices(autoConnect: true)
            }
        }
    }

    // MARK: - Lifecycle & Multi-Device

    public func start() {
        append("开始多设备扫描（经典蓝牙 RFCOMM 0xFD2D + BLE 0xAF00）")
        refreshRFCOMMDevices(autoConnect: true)
        classicDiscovery.start()
        bleTransport.allowAutoConnect = !state.isConnected && activeTransportKind != .rfcomm
        bleTransport.start()
        scheduleConnectFallback()
    }

    public func stop() {
        pollTask?.cancel()
        connectTimeoutTask?.cancel()
        bleTransport.stop()
        classicDiscovery.stop()
        rfcommTransport.disconnect()
    }

    public func rescanDevices() {
        append("重新扫描附近小米耳机（经典蓝牙 + BLE）")
        refreshRFCOMMDevices(autoConnect: !state.isConnected)
        classicDiscovery.start()
        bleTransport.allowAutoConnect = !state.isConnected
        bleTransport.rescan()
        scheduleConnectFallback()
    }

    private func refreshRFCOMMDevices(autoConnect: Bool) {
        let found = rfcommTransport.discoverPairedDevices(reachable: reachableAddresses)
        rfcommDevices = found
        mergeDiscoveredDevices()

        guard autoConnect, !state.isConnected else { return }
        let connected = found.filter { $0.isSystemConnected }
        let preferred = connected.first(where: { $0.id == activeDeviceID }) ?? connected.first
        if let target = preferred, let addr = target.classicAddress, let ch = target.rfcommChannelID {
            activeTransportKind = .rfcomm
            bleTransport.allowAutoConnect = false
            append("发现已连接的经典蓝牙耳机 \(target.name)（RFCOMM 通道 \(ch)），直接连接")
            rfcommTransport.connect(address: addr, channelID: ch, deviceID: target.id, name: target.name)
        }
    }

    private func mergeDiscoveredDevices() {
        var combined: [DiscoveredDevice] = []
        var seen = Set<UUID>()
        let pairedIDs = Set(rfcommDevices.map(\.id))
        let pending = inquiryDevices.filter { !pairedIDs.contains($0.id) }
        for dev in rfcommDevices + pending + bleDevices {
            if seen.insert(dev.id).inserted {
                combined.append(dev)
            }
        }
        discoveredDevices = combined.sorted { lhs, rhs in
            if lhs.id == activeDeviceID { return true }
            if rhs.id == activeDeviceID { return false }
            if lhs.isSystemConnected != rhs.isSystemConnected { return lhs.isSystemConnected }
            return (lhs.rssi ?? -127) > (rhs.rssi ?? -127)
        }
    }

    public func selectDevice(_ id: UUID) {
        guard id != activeDeviceID || !state.isConnected else { return }
        UserDefaults.standard.set(id.uuidString, forKey: Self.preferredDeviceKey)
        activeDeviceID = id
        state = MiPodsState()

        guard let dev = discoveredDevices.first(where: { $0.id == id }) else {
            bleTransport.connect(deviceID: id)
            return
        }

        state.deviceName = dev.name
        append("切换设备 → \(dev.name)（\(dev.transportKind.rawValue)）")

        if dev.needsPairing, let addr = dev.classicAddress {
            append("正在配对 \(dev.name)…")
            bleTransport.allowAutoConnect = false
            classicDiscovery.pair(address: addr)
            return
        }

        if dev.transportKind == .rfcomm, let addr = dev.classicAddress, let ch = dev.rfcommChannelID {
            bleTransport.allowAutoConnect = false
            bleTransport.stop()
            activeTransportKind = .rfcomm
            rfcommTransport.connect(address: addr, channelID: ch, deviceID: dev.id, name: dev.name)
        } else {
            rfcommTransport.disconnect()
            activeTransportKind = .ble
            bleTransport.allowAutoConnect = true
            bleTransport.preferredDeviceID = id
            bleTransport.connect(deviceID: id)
            scheduleConnectFallback()
        }
    }

    public func refresh() {
        guard state.isConnected else {
            append("未连接，重新扫描")
            rescanDevices()
            return
        }
        sendFrame(.getDeviceInfo, payload: [0xFF, 0xFF, 0xFF, 0xFF])
        sendFrame(.getRunInfo, payload: [0xFF, 0xFF, 0xFF, 0xFF])
        if state.isAuthenticated {
            requestExtendedConfigs()
        }
    }

    public func setLaunchAtLogin(_ on: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                append("开机自启设置失败：\(error.localizedDescription)")
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            append("开机自启需要 macOS 13 及以上系统")
            launchAtLogin = false
        }
    }

    private func sendFrame(_ opcode: Opcode, payload: [UInt8]) {
        switch activeTransportKind {
        case .ble:
            bleTransport.send(opcode, payload: payload)
        case .rfcomm:
            rfcommTransport.send(opcode, payload: payload)
        }
    }

    private func replyFrame(_ opcode: UInt8, sequence: UInt8, payload: [UInt8] = []) {
        switch activeTransportKind {
        case .ble:
            bleTransport.reply(opcode, sequence: sequence, payload: payload)
        case .rfcomm:
            rfcommTransport.reply(opcode, sequence: sequence, payload: payload)
        }
    }

    // MARK: - Hybrid Authentication

    public func requestAuthentication() {
        guard state.isConnected, !state.isAuthenticated, !state.isAuthenticating else { return }
        state.isAuthenticating = true
        let challenge = SAFER.randomChallenge()
        append("发起 SAFER+ 认证以解锁高级控制")
        sendFrame(.authChallenge, payload: [0x01] + challenge)
    }

    private func shouldAutoAuthenticate() -> Bool {
        if state.deviceName.localizedCaseInsensitiveContains("buds")
            || state.modelName.localizedCaseInsensitiveContains("buds") {
            return true
        }
        if let id = activeDeviceID {
            let saved = UserDefaults.standard.stringArray(forKey: Self.authedDevicesKey) ?? []
            return saved.contains(id.uuidString)
        }
        return false
    }

    private func markCurrentDeviceAuthenticated() {
        guard let id = activeDeviceID else { return }
        var saved = Set(UserDefaults.standard.stringArray(forKey: Self.authedDevicesKey) ?? [])
        saved.insert(id.uuidString)
        UserDefaults.standard.set(Array(saved), forKey: Self.authedDevicesKey)
    }

    // MARK: - Controls

    public func setNoiseMode(_ mode: NoiseMode) {
        state.noiseMode = mode
        performAuthenticatedWrite { [weak self] in
            self?.append("切换模式 → \(mode.displayTitle)")
            self?.sendFrame(.setANC, payload: [0x02, 0x04, mode.rawByte])
        }
    }

    public func setANCLevel(_ level: Int) {
        let clamped = max(0, min(19, level))
        state.ancLevel = clamped
        state.adaptiveANC = false
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x25, [0x00])
            self?.sendSetConfig(0x0B, [0x01, UInt8(clamped)])
        }
    }

    public func setAdaptiveANC(_ on: Bool) {
        state.adaptiveANC = on
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x25, [on ? 0x01 : 0x00])
        }
    }

    public func setTransparencyLevel(_ level: TransparencyLevel) {
        state.transparencyLevel = level
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x0B, [0x02, level.rawValue])
        }
    }

    public func setEQ(_ preset: EQPreset) {
        state.eqPreset = preset
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x07, [preset.rawValue])
        }
    }

    public func setSpatialAudio(enabled: Bool, headTracking: Bool? = nil) {
        var bits = state.spatialBits
        bits = enabled ? (bits | 0x01) : (bits & ~0x01)
        if let headTracking {
            bits = headTracking ? (bits | 0x02) : (bits & ~0x02)
        }
        state.spatialBits = bits
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x1D, [bits])
        }
    }

    public func setSpatialScene(_ scene: SpatialScene) {
        state.spatialScene = scene
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x36, scene == .off ? [0x00] : [0x01, scene.rawValue])
        }
    }

    public func setWearDetect(_ on: Bool) {
        state.wearDetect = on
        performAuthenticatedWrite { [weak self] in
            self?.sendFrame(.setANC, payload: [0x02, 0x06, on ? 0x00 : 0x01])
        }
    }

    public func setHotword(_ on: Bool) {
        state.hotword = on
        performAuthenticatedWrite { [weak self] in
            self?.sendFrame(.setANC, payload: [0x02, 0x02, on ? 0x01 : 0x00])
        }
    }

    public func setAutoAnswer(_ on: Bool) {
        state.autoAnswer = on
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x03, [on ? 0x01 : 0x00])
        }
    }

    public func setDualDevice(_ on: Bool) {
        state.dualDevice = on
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x04, [on ? 0x01 : 0x00])
        }
    }

    public func setAdaptiveSense(_ on: Bool) {
        state.adaptiveSense = on
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x29, [on ? 0x01 : 0x00])
        }
    }

    public func setAdaptiveVolume(_ on: Bool) {
        state.adaptiveVolume = on
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x48, [on ? 0x01 : 0x00])
        }
    }

    public func setFreeTalk(_ duration: FreeTalkDuration) {
        state.freeTalk = duration
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x0D, duration == .off ? [0x00, 0x00] : [0x01, duration.rawValue])
        }
    }

    public func setGesture(_ type: GestureType, action: GestureAction) {
        state.gestures[type] = (action, action)
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x02, [type.rawValue, action.rawValue, action.rawValue])
        }
    }

    public func setLowLatency(_ on: Bool) {
        state.lowLatency = on
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x2F, [on ? 0x01 : 0x00])
        }
    }

    public func previewCustomEQ(_ bands: [EQBand]) {
        state.customEQBands = bands
        state.eqPreset = .custom
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x37, CustomEQCodec.encodePreview(bands))
        }
    }

    public func saveCustomEQ(_ bands: [EQBand]) {
        state.customEQBands = bands
        state.eqPreset = .custom
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x37, CustomEQCodec.encodeSave(bands))
        }
    }

    public func resetCustomEQ() {
        state.customEQBands = EQBand.defaultBands
        performAuthenticatedWrite { [weak self] in
            self?.sendSetConfig(0x37, CustomEQCodec.resetPayload)
        }
    }

    public func findEarbuds(_ on: Bool, target: FindTarget = .both) {
        performAuthenticatedWrite { [weak self] in
            self?.append(on ? "触发查找耳机响铃（\(target.displayTitle)）" : "停止查找耳机响铃")
            self?.sendSetConfig(0x09, [on ? 0x01 : 0x00, target.rawValue])
        }
    }

    private func performAuthenticatedWrite(_ action: @escaping () -> Void) {
        guard state.isConnected else {
            append("未连接，无法下发控制命令")
            return
        }
        if state.isAuthenticated {
            action()
            schedulePostWriteRefresh()
        } else {
            pendingCommandAfterAuth = { [weak self] in
                action()
                self?.schedulePostWriteRefresh()
            }
            requestAuthentication()
        }
    }

    private func sendSetConfig(_ id: UInt16, _ value: [UInt8]) {
        sendFrame(.setConfig, payload: ConfigRecord.encodeSet(id: id, value: value))
    }

    private func requestExtendedConfigs() {
        sendFrame(.getConfig, payload: ConfigRecord.encodeGet(ids: Self.statusConfigIDs))
    }

    private func schedulePostWriteRefresh() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            self?.refresh()
        }
    }

    // MARK: - Event Handling

    private func handle(_ event: BLETransport.Event, from kind: TransportKind) {
        switch event {
        case .devicesUpdated(let devices):
            if kind == .ble {
                bleDevices = devices
                mergeDiscoveredDevices()
            }

        case .stateChanged(let newState):
            switch newState {
            case .connected:
                if kind != activeTransportKind {
                    if state.isConnected { return }
                    activeTransportKind = kind
                }
                if kind == .rfcomm {
                    bleTransport.allowAutoConnect = false
                }
                state.isConnected = true
                state.statusDetail = kind == .rfcomm ? "RFCOMM 已连接" : "BLE 已连接"
                connectTimeoutTask?.cancel()
                beginSession()
            case .connecting:
                guard kind == activeTransportKind || !state.isConnected else { return }
                state.statusDetail = kind == .rfcomm ? "RFCOMM 连接中…" : "连接中…"
            case .scanning:
                guard !state.isConnected else { return }
                state.statusDetail = "正在搜索小米耳机…"
            case .disconnected(let reason):
                guard kind == activeTransportKind else { return }
                state.isConnected = false
                state.isAuthenticated = false
                state.isAuthenticating = false
                state.statusDetail = reason ?? "未连接"
                pollTask?.cancel()
                if kind == .rfcomm {
                    bleTransport.allowAutoConnect = true
                    refreshRFCOMMDevices(autoConnect: false)
                }
            case .idle:
                guard kind == activeTransportKind else { return }
                state.isConnected = false
                state.isAuthenticated = false
                state.isAuthenticating = false
                state.statusDetail = "未连接"
                pollTask?.cancel()
            }

        case .activeDeviceChanged(let id, let name):
            guard kind == activeTransportKind || !state.isConnected else { return }
            activeDeviceID = id
            if let name, !name.isEmpty { state.deviceName = name }
            mergeDiscoveredDevices()

        case .ready(let write, let notify):
            guard kind == activeTransportKind else { return }
            append(kind == .rfcomm
                   ? "RFCOMM 通道就绪（\(write) / \(notify)）"
                   : "GATT 就绪（写 \(write) / 收 \(notify)）")

        case .name(let name):
            guard kind == activeTransportKind else { return }
            state.deviceName = name

        case .gattBattery(let bytes):
            guard kind == activeTransportKind else { return }
            append("GATT 电量 \(bytes.hexString)")

        case .message(let message):
            guard kind == activeTransportKind else { return }
            handle(message)

        case .log(let line):
            append(line)
        }
    }

    private func beginSession() {
        pollTask?.cancel()
        // Always fetch battery & basic info first (safe for all models).
        sendFrame(.getDeviceInfo, payload: [0xFF, 0xFF, 0xFF, 0xFF])
        sendFrame(.getRunInfo, payload: [0xFF, 0xFF, 0xFF, 0xFF])
        startPolling()

        if shouldAutoAuthenticate() {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, self.state.isConnected, !self.state.isAuthenticated else { return }
                self.requestAuthentication()
            }
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
                guard let self, self.state.isConnected else { return }
                self.sendFrame(.getDeviceInfo, payload: [0xFF, 0xFF, 0xFF, 0xFF])
            }
        }
    }

    private func scheduleConnectFallback() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !self.state.isConnected else { return }
            self.append("未建立连接，重新检索经典蓝牙 RFCOMM 与系统已连 BLE 外设")
            self.refreshRFCOMMDevices(autoConnect: true)
            if !self.state.isConnected && self.activeTransportKind != .rfcomm {
                self.bleTransport.connectKnownPeripheral()
            }
        }
    }

    // MARK: - Protocol Dispatch

    private func handle(_ message: Message) {
        append("RX 0x\(String(format: "%02X", message.opcode)) · \(message.payload.count)B")

        switch message.opcode {
        case Opcode.authChallenge.rawValue:
            if message.type == .response {
                sendFrame(.authConfirm, payload: [0x01, 0x00])
            } else if message.payload.count >= 17,
                      let answer = SAFER.response(to: Array(message.payload[1..<17])) {
                replyFrame(Opcode.authChallenge.rawValue, sequence: message.sequence, payload: [0x01] + answer)
            }

        case Opcode.authConfirm.rawValue:
            if message.type.isRequest {
                replyFrame(Opcode.authConfirm.rawValue, sequence: message.sequence, payload: [0x01])
            }
            state.isAuthenticating = false
            if !state.isAuthenticated {
                state.isAuthenticated = true
                markCurrentDeviceAuthenticated()
                append("SAFER+ 认证完成，高阶控制已解锁")
                requestExtendedConfigs()
                if let pending = pendingCommandAfterAuth {
                    pendingCommandAfterAuth = nil
                    pending()
                }
            }

        case Opcode.getDeviceInfo.rawValue:
            apply(DeviceInfo.parse(message.payload))

        case Opcode.getRunInfo.rawValue:
            let info = RunInfo.parse(message.payload)
            if let mode = info.noiseMode { state.noiseMode = mode }
            if let hw = info.hotwordEnabled { state.hotword = hw }
            if let autoPlay = info.autoPlayEnabled { state.wearDetect = autoPlay }
            state.lastUpdate = Date()
            refreshCapabilities()

        case Opcode.reportStatus.rawValue:
            apply(StatusUpdate.parse(message.payload))
            if message.type.isRequest {
                replyFrame(message.opcode, sequence: message.sequence)
            }

        case Opcode.getConfig.rawValue:
            apply(ConfigRecord.parse(message.payload))

        case Opcode.notifyConfig.rawValue:
            apply(ConfigRecord.parse(message.payload))
            if message.type.isRequest {
                replyFrame(message.opcode, sequence: message.sequence)
            }

        case Opcode.setANC.rawValue, Opcode.setConfig.rawValue:
            append("命令已确认")

        default:
            if message.type.isRequest {
                replyFrame(message.opcode, sequence: message.sequence)
            }
        }
    }

    private func apply(_ info: DeviceInfo) {
        if let model = info.modelName, !model.isEmpty { state.modelName = model }
        if let firmware = info.firmware { state.firmware = firmware }
        state.leftBattery = info.left.percent
        state.rightBattery = info.right.percent
        state.caseBattery = info.caseBattery.percent
        state.isLeftCharging = info.left.isCharging
        state.isRightCharging = info.right.isCharging
        state.isCaseCharging = info.caseBattery.isCharging
        state.lastUpdate = Date()
        refreshCapabilities()
        append("电量 左\(info.left.displayPercent) 右\(info.right.displayPercent) 盒\(info.caseBattery.displayPercent)")
    }

    private func apply(_ updates: [StatusUpdate]) {
        for update in updates {
            switch update {
            case .battery(let left, let right, let caseBattery):
                state.leftBattery = left.percent
                state.rightBattery = right.percent
                state.caseBattery = caseBattery.percent
                state.isLeftCharging = left.isCharging
                state.isRightCharging = right.isCharging
                state.isCaseCharging = caseBattery.isCharging
                state.lastUpdate = Date()
            case .noiseMode(let mode):
                state.noiseMode = mode
            case .localRecording(let allowed):
                state.canRecordLocally = allowed
                state.capabilities.insert(.hasRecording)
            case .unknown:
                break
            }
        }
        refreshCapabilities()
    }

    private func apply(_ records: [ConfigRecord]) {
        for rec in records {
            state.configs[rec.id] = rec.value
            switch rec.id {
            case 0x02:
                var i = 0
                while i + 2 < rec.value.count {
                    if let gType = GestureType(rawValue: rec.value[i]),
                       let leftAct = GestureAction(rawValue: rec.value[i + 1]),
                       let rightAct = GestureAction(rawValue: rec.value[i + 2]) {
                        state.gestures[gType] = (leftAct, rightAct)
                    }
                    i += 3
                }
            case 0x03:
                state.autoAnswer = rec.value.first == 1
            case 0x04:
                state.dualDevice = rec.value.first == 1
            case 0x07:
                if let b = rec.value.first, let eq = EQPreset(rawValue: b) { state.eqPreset = eq }
            case 0x0B:
                if let modeByte = rec.value.first, let mode = NoiseMode(rawByte: modeByte) {
                    state.noiseMode = mode
                    if mode == .anc, rec.value.count >= 2 {
                        state.ancLevel = Int(rec.value[1])
                    } else if mode == .transparency, rec.value.count >= 2,
                              let t = TransparencyLevel(rawValue: rec.value[1]) {
                        state.transparencyLevel = t
                    }
                }
            case 0x0C:
                if let flags = rec.value.first {
                    state.wearingFlags = flags
                    state.canRecordLocally = (flags & 0x03) == 0x03
                    state.capabilities.insert(.hasRecording)
                }
            case 0x0D:
                if rec.value.count >= 2, rec.value[0] == 1,
                   let dur = FreeTalkDuration(rawValue: rec.value[1]) {
                    state.freeTalk = dur
                } else {
                    state.freeTalk = .off
                }
            case 0x1E:
                if let bits = rec.value.first { state.spatialBits = bits }
            case 0x25:
                state.adaptiveANC = rec.value.first == 1
            case 0x29:
                state.adaptiveSense = rec.value.first == 1
            case 0x2F:
                state.lowLatency = rec.value.first == 1
            case 0x36:
                if rec.value.first == 1, rec.value.count >= 2,
                   let sc = SpatialScene(rawValue: rec.value[1]) {
                    state.spatialScene = sc
                } else {
                    state.spatialScene = .off
                }
            case 0x37:
                if let bands = CustomEQCodec.parse(rec.value) {
                    state.customEQBands = bands
                }
            case 0x3B:
                state.personalANC = rec.value.first == 1
            case 0x48:
                state.adaptiveVolume = rec.value.first == 1
            default:
                break
            }
        }
        state.lastUpdate = Date()
        refreshCapabilities()
    }

    private func refreshCapabilities() {
        var caps: Capabilities = [.hasWearingDetection]

        if state.noiseMode != .off || state.configs[0x0B] != nil {
            caps.insert(.hasANC)
            caps.insert(.hasTransparency)
        }
        if state.configs[0x0B] != nil {
            caps.insert(.hasANCLevel)
            caps.insert(.hasTransparencyLevel)
        }
        if state.configs[0x25] != nil { caps.insert(.hasAdaptiveANC) }
        if state.configs[0x3B] != nil { caps.insert(.hasPersonalANC) }
        if state.configs[0x07] != nil { caps.insert(.hasEqualizer) }
        if state.configs[0x37] != nil { caps.insert(.hasCustomEQ) }
        if state.configs[0x1E] != nil { caps.insert(.hasSpatialAudio) }
        if state.configs[0x36] != nil { caps.insert(.hasSceneMode) }
        if state.configs[0x02] != nil { caps.insert(.hasGesture) }
        if state.configs[0x03] != nil { caps.insert(.hasAutoAnswer) }
        if state.configs[0x04] != nil { caps.insert(.hasDualDevice) }
        if state.configs[0x0D] != nil { caps.insert(.hasFreeTalk) }
        if state.configs[0x29] != nil { caps.insert(.hasAdaptiveSense) }
        if state.configs[0x2F] != nil { caps.insert(.hasLowLatency) }
        if state.configs[0x48] != nil { caps.insert(.hasAdaptiveVolume) }
        if state.isAuthenticated {
            caps.insert(.hasFindMyEarbuds)
            caps.insert(.hasHotword)
        }
        if state.canRecordLocally != nil || state.wearingFlags != nil {
            caps.insert(.hasRecording)
        }

        state.capabilities = caps
    }

    private func append(_ line: String) {
        let stamp = Self.timeFormatter.string(from: Date())
        state.log.append("[\(stamp)] \(line)")
        if state.log.count > 300 {
            state.log.removeFirst(state.log.count - 300)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
