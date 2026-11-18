import SwiftUI
import MiPodsPlusCore

struct HUDView: View {

    let state: MiPodsState
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "earbuds")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(state.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(state.isConnected ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)

                    Text(state.isConnected ? L10n.statusConnected : L10n.statusDisconnected)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if state.canSwitchNoiseMode {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Text(state.noiseModeTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 4)

            BatteryTriplet(state: state, ringSize: 40, ringLineWidth: 3.5, spacing: 14)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .fixedSize()
        .scaleEffect(appeared ? 1.0 : 0.92)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [L10n.appName, state.displayName,
                     state.isConnected ? L10n.statusConnected : L10n.statusDisconnected]
        parts.append(L10n.batteryAccessibility(L10n.batteryLeft, level: state.leftLevel, charging: state.isChargingLeft))
        parts.append(L10n.batteryAccessibility(L10n.batteryRight, level: state.rightLevel, charging: state.isChargingRight))
        parts.append(L10n.batteryAccessibility(L10n.batteryCase, level: state.caseLevel, charging: state.isChargingCase))
        if state.canSwitchNoiseMode { parts.append("当前模式 \(state.noiseModeTitle)") }
        return parts.joined(separator: "，")
    }
}
