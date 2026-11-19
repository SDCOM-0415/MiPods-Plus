import SwiftUI
import MiPodsPlusCore

struct BatteryRing: View {

    enum Role {
        case left, right, case_

        var label: String {
            switch self {
            case .left: return L10n.batteryLeft
            case .right: return L10n.batteryRight
            case .case_: return L10n.batteryCase
            }
        }

        var tint: Color {
            switch self {
            case .left: return Color(red: 0.24, green: 0.52, blue: 0.98)
            case .right: return Color(red: 0.16, green: 0.72, blue: 0.88)
            case .case_: return Color(red: 0.96, green: 0.62, blue: 0.16)
            }
        }
    }

    let role: Role
    let level: Int?
    let isCharging: Bool

    var size: CGFloat = 44
    var lineWidth: CGFloat = 4
    var showsLabel: Bool = true

    private var fraction: Double {
        guard let level else { return 0 }
        return min(max(Double(level) / 100.0, 0), 1)
    }

    private var isLow: Bool {
        guard let level else { return false }
        return level <= 20
    }

    private var ringColor: Color {
        if isLow && !isCharging { return .red }
        return role.tint
    }

    private var levelText: String {
        guard let level else { return L10n.unknown }
        return "\(level)%"
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.16), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.35), value: fraction)

                VStack(spacing: 1) {
                    Text(levelText)
                        .font(.system(size: size * 0.28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(level == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))

                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: size * 0.16, weight: .bold))
                            .foregroundStyle(.green)
                    }
                }
            }
            .frame(width: size, height: size)

            if showsLabel {
                Text(role.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.batteryAccessibility(role.label, level: level, charging: isCharging))
    }
}

struct BatteryTriplet: View {
    let state: MiPodsState
    var ringSize: CGFloat = 44
    var ringLineWidth: CGFloat = 4
    var spacing: CGFloat = 18

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            BatteryRing(role: .left,
                        level: state.leftLevel,
                        isCharging: state.isChargingLeft,
                        size: ringSize,
                        lineWidth: ringLineWidth)
            BatteryRing(role: .right,
                        level: state.rightLevel,
                        isCharging: state.isChargingRight,
                        size: ringSize,
                        lineWidth: ringLineWidth)
            BatteryRing(role: .case_,
                        level: state.caseLevel,
                        isCharging: state.isChargingCase,
                        size: ringSize,
                        lineWidth: ringLineWidth)
        }
    }
}
