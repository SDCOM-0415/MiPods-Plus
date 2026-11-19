import SwiftUI
import MiPodsPlusCore

/// AirPods-style proximity discovery & battery card popup.
struct ProximityPopupView: View {

    @ObservedObject var controller: MiPodsController
    let candidateDevice: DiscoveredDevice?
    let onConnect: (DiscoveredDevice?) -> Void
    let onOpenMainPanel: () -> Void
    let onClose: () -> Void

    @State private var appeared = false
    @State private var pulse = false
    @State private var isConnecting = false

    private var state: MiPodsState { controller.state }

    private var titleText: String {
        if state.isConnected {
            return state.displayName
        }
        if let name = candidateDevice?.name, !name.isEmpty {
            return name
        }
        return state.displayName
    }

    private var subtitleText: String {
        if state.isConnected {
            if state.canSwitchNoiseMode {
                return "已连接 · \(state.noiseModeTitle)"
            }
            return "已连接到此 Mac"
        }
        if isConnecting || state.statusDetail.contains("连接中") {
            return "正在连接耳机…"
        }
        if state.statusDetail.contains("失败") || state.statusDetail.contains("超时") || state.statusDetail.contains("未找到") {
            return "\(state.statusDetail)（请确认已在系统蓝牙连接音频）"
        }
        if let dev = candidateDevice {
            var parts = [dev.needsPairing ? "配对模式耳机" : "附近发现耳机"]
            parts.append(dev.transportKind.rawValue)
            if let rssi = dev.rssi {
                parts.append("\(rssi) dBm")
            }
            return parts.joined(separator: " · ")
        }
        return "附近发现小米/Redmi 耳机"
    }

    var body: some View {
        VStack(spacing: 14) {
            // Top bar with status badge & close button
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(state.isConnected ? Color.green : Color.accentColor)
                        .frame(width: 7, height: 7)
                    Text(state.isConnected ? "已连接" : "附近发现")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                )

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("关闭弹窗")
            }

            // Animated Earbuds Hero Graphic (AirPods card style)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.accentColor.opacity(pulse ? 0.24 : 0.10),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 64
                        )
                    )
                    .frame(width: 118, height: 118)
                    .scaleEffect(pulse ? 1.07 : 0.94)

                Circle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 86, height: 86)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                    )

                Image(systemName: CompatSymbols.earbudsCase)
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(.primary)
                    .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
                    .rotation3DEffect(
                        .degrees(pulse ? 7 : -7),
                        axis: (x: 0, y: 1, z: 0)
                    )
            }
            .padding(.top, -4)

            // Title & Subtitle
            VStack(spacing: 4) {
                Text(titleText)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Battery Section or Proximity Prompt
            if state.isConnected {
                BatteryTriplet(state: state, ringSize: 58, ringLineWidth: 5, spacing: 18)
                    .padding(.vertical, 2)

                if state.canSwitchNoiseMode {
                    noiseQuickRow
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Text(candidateDevice?.needsPairing == true
                         ? "检测到配对模式耳机，点击将配对并连接"
                         : candidateDevice?.isSystemConnected == true
                         ? "耳机已与系统蓝牙配对，可立即接管控制"
                         : "检测到耳机开盖/靠近广播，点击即可连接")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            // Action button (AirPods bottom pill button)
            actionButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(width: 300)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
        .scaleEffect(appeared ? 1.0 : 0.90)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChangeCompat(of: state.isConnected) { connected in
            if connected {
                isConnecting = false
            }
        }
        .onChangeCompat(of: state.statusDetail) { detail in
            if detail.contains("失败") || detail.contains("超时") || detail.contains("未找到") {
                isConnecting = false
            }
        }
    }

    @ViewBuilder
    private var noiseQuickRow: some View {
        HStack(spacing: 6) {
            ForEach(state.availableNoiseModes, id: \.self) { mode in
                let active = state.noiseMode == mode
                Button {
                    controller.setNoiseMode(mode)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 10, weight: .semibold))
                        Text(mode.localizedTitle)
                            .font(.system(size: 10.5, weight: active ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(active ? Color.accentColor : Color.primary.opacity(0.06))
                    )
                    .foregroundStyle(active ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if state.isConnected {
            HStack(spacing: 8) {
                Button {
                    onOpenMainPanel()
                } label: {
                    Text("更多音频设置")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    onClose()
                } label: {
                    Text("完成")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
            }
        } else {
            Button {
                isConnecting = true
                onConnect(candidateDevice)
            } label: {
                HStack(spacing: 6) {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.system(size: 13))
                    }
                    Text(isConnecting ? "正在连接…" : (candidateDevice?.needsPairing == true ? "配对并连接" : "通过此 Mac 连接"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor)
                )
            }
            .buttonStyle(.plain)
            .disabled(isConnecting)

            if state.statusDetail.contains("失败") || state.statusDetail.contains("超时") || state.statusDetail.contains("未找到") {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("打开系统蓝牙设置")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
