import SwiftUI
import MiPodsPlusCore

struct PanelView: View {

    @ObservedObject var controller: MiPodsController
    var onShowHUD: () -> Void
    var onOpenSoundSettings: () -> Void

    @State private var showDevices = false
    @State private var showAudioSection = false
    @State private var showSmartSection = false
    @State private var showGesturesSection = false
    @State private var isFindingEarbuds = false

    private var state: MiPodsState { controller.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 16)

            if showDevices {
                deviceSwitcherSection
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
            }

            Divider().padding(.horizontal, 18).padding(.top, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    BatteryTriplet(state: state, ringSize: 68, ringLineWidth: 6, spacing: 20)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                        .padding(.bottom, 4)

                    if state.isConnected && !state.isAuthenticated {
                        authUnlockBanner
                    }

                    noiseModeSection

                    if hasAudioControls {
                        audioSection
                    }

                    if hasSmartControls {
                        smartSection
                    }

                    if state.capabilities.contains(.hasGesture) && !state.gestures.isEmpty {
                        gestureSection
                    }

                    if state.capabilities.contains(.hasRecording) {
                        recordingSection
                    }

                    infoSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: 460)

            Divider().padding(.horizontal, 18)

            footer
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .frame(width: 340)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header & Multi-Device Switcher

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "earbuds")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(state.isConnected ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(state.statusDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !state.firmware.isEmpty {
                        Text("·").font(.system(size: 11)).foregroundStyle(.tertiary)
                        Text("v\(state.firmware)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showDevices.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right.circle")
                        .font(.system(size: 12))
                    Text("\(max(controller.discoveredDevices.count, 1))")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.primary.opacity(showDevices ? 0.12 : 0.06))
                )
            }
            .buttonStyle(.plain)
            .help("切换或重新扫描小米耳机")
        }
    }

    private var deviceSwitcherSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("已发现设备")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    controller.rescanDevices()
                } label: {
                    Label(L10n.actionRescan, systemImage: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
            }

            if controller.discoveredDevices.isEmpty {
                Text("暂未发现小米/Redmi 耳机，请确认蓝牙已开启")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(controller.discoveredDevices) { device in
                    let isSelected = device.id == controller.activeDeviceID
                    Button {
                        controller.selectDevice(device.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "earbuds")
                                .font(.system(size: 12))
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                            Text(device.name)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                .lineLimit(1)

                            Spacer()

                            if device.isSystemConnected {
                                Text("系统已连")
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.green.opacity(0.15)))
                                    .foregroundStyle(.green)
                            } else if let rssi = device.rssi {
                                Text("\(rssi) dBm")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(isSelected ? 0.08 : 0.03))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Hybrid Auth Banner

    private var authUnlockBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.open")
                .font(.system(size: 12))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.isAuthenticating ? "正在进行 SAFER+ 认证…" : "已获取基础电量")
                    .font(.system(size: 11, weight: .medium))
                Text("点击解锁降噪深度、音效与手势等高级控制")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(state.isAuthenticating ? "认证中" : "解锁") {
                controller.requestAuthentication()
            }
            .disabled(state.isAuthenticating)
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        )
    }

    // MARK: - Noise Control

    @ViewBuilder
    private var noiseModeSection: some View {
        let modes = state.availableNoiseModes

        if modes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.noModeSupport)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(L10n.noModeSupportDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.modeTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Picker("", selection: Binding(
                    get: { state.noiseMode },
                    set: { controller.setNoiseMode($0) }
                )) {
                    ForEach(modes, id: \.self) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if state.noiseMode == .anc && state.capabilities.contains(.hasANCLevel) {
                    VStack(spacing: 4) {
                        HStack {
                            Text("降噪深度")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(state.ancLevel)")
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(state.ancLevel) },
                                set: { controller.setANCLevel(Int($0.rounded())) }
                            ),
                            in: 0...19,
                            step: 1
                        )
                        .controlSize(.small)
                    }
                    .padding(.top, 2)
                }

                if state.noiseMode == .anc && state.capabilities.contains(.hasAdaptiveANC) {
                    Toggle("自适应降噪", isOn: Binding(
                        get: { state.adaptiveANC },
                        set: { controller.setAdaptiveANC($0) }
                    ))
                    .font(.system(size: 11))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                if state.noiseMode == .transparency && state.capabilities.contains(.hasTransparencyLevel) {
                    Picker("通透模式", selection: Binding(
                        get: { state.transparencyLevel },
                        set: { controller.setTransparencyLevel($0) }
                    )) {
                        ForEach(TransparencyLevel.allCases, id: \.self) { lv in
                            Text(lv.displayTitle).tag(lv)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Audio & Spatial

    private var hasAudioControls: Bool {
        state.capabilities.contains(.hasEqualizer)
            || state.capabilities.contains(.hasSpatialAudio)
            || state.capabilities.contains(.hasSceneMode)
    }

    private var audioSection: some View {
        DisclosureGroup(isExpanded: $showAudioSection) {
            VStack(alignment: .leading, spacing: 8) {
                if state.capabilities.contains(.hasEqualizer) {
                    HStack {
                        Text("音效 EQ")
                            .font(.system(size: 11))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { state.eqPreset },
                            set: { controller.setEQ($0) }
                        )) {
                            ForEach(EQPreset.allCases, id: \.self) { preset in
                                Text(preset.displayTitle).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }

                if state.capabilities.contains(.hasSpatialAudio) {
                    Toggle("空间音频", isOn: Binding(
                        get: { (state.spatialBits & 0x01) != 0 },
                        set: { controller.setSpatialAudio(enabled: $0) }
                    ))
                    .font(.system(size: 11))
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    if (state.spatialBits & 0x01) != 0 {
                        Toggle("头部追踪", isOn: Binding(
                            get: { (state.spatialBits & 0x02) != 0 },
                            set: { controller.setSpatialAudio(enabled: true, headTracking: $0) }
                        ))
                        .font(.system(size: 11))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }
                }

                if state.capabilities.contains(.hasSceneMode) {
                    HStack {
                        Text("场景渲染")
                            .font(.system(size: 11))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { state.spatialScene },
                            set: { controller.setSpatialScene($0) }
                        )) {
                            ForEach(SpatialScene.allCases, id: \.self) { sc in
                                Text(sc.displayTitle).tag(sc)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("音效与空间音频")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Smart Features

    private var hasSmartControls: Bool {
        state.capabilities.contains(.hasDualDevice)
            || state.capabilities.contains(.hasAutoAnswer)
            || state.capabilities.contains(.hasHotword)
            || state.capabilities.contains(.hasFreeTalk)
            || state.capabilities.contains(.hasAdaptiveSense)
            || state.capabilities.contains(.hasAdaptiveVolume)
            || state.capabilities.contains(.hasFindMyEarbuds)
    }

    private var smartSection: some View {
        DisclosureGroup(isExpanded: $showSmartSection) {
            VStack(alignment: .leading, spacing: 7) {
                if state.capabilities.contains(.hasDualDevice) {
                    Toggle("双设备连接", isOn: Binding(
                        get: { state.dualDevice },
                        set: { controller.setDualDevice($0) }
                    ))
                    .font(.system(size: 11))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                if state.capabilities.contains(.hasAutoAnswer) {
                    Toggle("自动接听来电", isOn: Binding(
                        get: { state.autoAnswer },
                        set: { controller.setAutoAnswer($0) }
                    ))
                    .font(.system(size: 11))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                if state.capabilities.contains(.hasHotword) {
                    Toggle("语音免唤醒", isOn: Binding(
                        get: { state.hotword },
                        set: { controller.setHotword($0) }
                    ))
                    .font(.system(size: 11))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                if state.capabilities.contains(.hasAdaptiveSense) {
                    Toggle("自适应听感", isOn: Binding(
                        get: { state.adaptiveSense },
                        set: { controller.setAdaptiveSense($0) }
                    ))
                    .font(.system(size: 11))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                if state.capabilities.contains(.hasAdaptiveVolume) {
                    Toggle("自适应音量", isOn: Binding(
                        get: { state.adaptiveVolume },
                        set: { controller.setAdaptiveVolume($0) }
                    ))
                    .font(.system(size: 11))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                if state.capabilities.contains(.hasFreeTalk) {
                    HStack {
                        Text("智能免摘")
                            .font(.system(size: 11))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { state.freeTalk },
                            set: { controller.setFreeTalk($0) }
                        )) {
                            ForEach(FreeTalkDuration.allCases, id: \.self) { dur in
                                Text(dur.displayTitle).tag(dur)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }

                if state.capabilities.contains(.hasFindMyEarbuds) {
                    Button {
                        isFindingEarbuds.toggle()
                        controller.findEarbuds(isFindingEarbuds)
                    } label: {
                        Label(isFindingEarbuds ? "停止查找响铃" : "查找耳机（响铃）",
                              systemImage: isFindingEarbuds ? "bell.slash.fill" : "bell.and.waves.left.and.right")
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("智能功能")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Gestures

    private var gestureSection: some View {
        DisclosureGroup(isExpanded: $showGesturesSection) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(GestureType.allCases, id: \.self) { gType in
                    if let pair = state.gestures[gType] {
                        HStack {
                            Text(gType.displayTitle)
                                .font(.system(size: 11))
                            Spacer()
                            Picker("", selection: Binding(
                                get: { pair.left },
                                set: { controller.setGesture(gType, action: $0) }
                            )) {
                                ForEach(GestureAction.allCases, id: \.self) { act in
                                    Text(act.displayTitle).tag(act)
                                }
                            }
                            .labelsHidden()
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("手势设置")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Recording (Open-ear / M2529E1)

    @ViewBuilder
    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.recordingTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                Image(systemName: recordSymbol)
                    .font(.system(size: 11))
                    .foregroundStyle(recordTint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recordStateTitle)
                        .font(.system(size: 11, weight: .medium))
                    Text(L10n.recordingLocalHint)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var recordStateTitle: String {
        guard let allowed = state.canRecordLocally else { return L10n.recordingUnknown }
        return allowed ? L10n.recordingAvailable : L10n.recordingUnavailable
    }

    private var recordSymbol: String {
        guard let allowed = state.canRecordLocally else { return "questionmark.circle" }
        return allowed ? "record.circle" : "record.circle.fill"
    }

    private var recordTint: Color {
        guard let allowed = state.canRecordLocally else { return .secondary }
        return allowed ? .red : .secondary
    }

    // MARK: - Info & Footer

    private var infoSection: some View {
        HStack(spacing: 6) {
            Text(L10n.infoUpdated)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(L10n.relativeTime(from: state.lastUpdate))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Spacer()
            if !state.modelName.isEmpty {
                Text(state.modelName)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                controller.refresh()
                onShowHUD()
            } label: {
                Label(L10n.actionRefresh, systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)

            Spacer()

            Toggle("开机自启", isOn: Binding(
                get: { controller.launchAtLogin },
                set: { controller.setLaunchAtLogin($0) }
            ))
            .font(.system(size: 11))
            .toggleStyle(.checkbox)
            .controlSize(.small)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text(L10n.actionQuit)
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
