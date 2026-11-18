import AppKit
import SwiftUI
import MiPodsPlusCore

@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {

    private weak var controller: MiPodsController?
    private var touchBar: NSTouchBar?
    private weak var hostView: NSView?

    init(controller: MiPodsController) {
        self.controller = controller
        super.init()
    }

    func attach(to view: NSView) {
        hostView = view
        let bar = touchBar ?? makeTouchBar()
        touchBar = bar
        view.touchBar = bar
    }

    func detach() {
        hostView?.touchBar = nil
        hostView = nil
    }

    private func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [
            .batteryLeft,
            .batteryRight,
            .batteryCase,
            .flexibleSpace,
            .modeButtons,
        ]
        return bar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .batteryLeft:
            return batteryItem(identifier, label: L10n.batteryLeft, level: controller?.state.leftLevel,
                               charging: controller?.state.isChargingLeft ?? false)
        case .batteryRight:
            return batteryItem(identifier, label: L10n.batteryRight, level: controller?.state.rightLevel,
                               charging: controller?.state.isChargingRight ?? false)
        case .batteryCase:
            return batteryItem(identifier, label: L10n.batteryCase, level: controller?.state.caseLevel,
                               charging: controller?.state.isChargingCase ?? false)
        case .modeButtons:
            return modeItem(identifier)
        default:
            return nil
        }
    }

    private func batteryItem(_ identifier: NSTouchBarItem.Identifier,
                             label: String,
                             level: Int?,
                             charging: Bool) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let text = level.map { "\(label) \($0)%" } ?? "\(label) \(L10n.unknown)"
        let symbol = charging ? "bolt.fill" : "earbuds"
        item.view = NSHostingView(rootView: TouchBarBatteryLabel(
            label: label, level: level, charging: charging, symbol: symbol, fallbackText: text
        ))
        return item
    }

    private func modeItem(_ identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)

        guard let controller, controller.state.canSwitchNoiseMode else {
            item.view = NSHostingView(rootView: TouchBarUnsupportedLabel(text: L10n.noModeSupport))
            return item
        }

        let modes = controller.state.availableNoiseModes
        let current = controller.state.noiseMode

        item.view = NSHostingView(rootView: HStack(spacing: 8) {
            ForEach(modes, id: \.self) { mode in
                Button(action: {
                    controller.setNoiseMode(mode)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: mode.symbolName)
                            .font(.system(size: 13, weight: .medium))
                        Text(mode.localizedTitle)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(mode == current ? 0.28 : 0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6))
        return item
    }
}

private struct TouchBarBatteryLabel: View {
    let label: String
    let level: Int?
    let charging: Bool
    let symbol: String
    let fallbackText: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(charging ? Color.green : Color.white.opacity(0.85))

            if let level {
                Text("\(level)%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(level <= 20 ? Color.red : Color.white)
            } else {
                Text(L10n.unknown)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 8)
        .accessibilityLabel(fallbackText)
    }
}

private struct TouchBarUnsupportedLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(.horizontal, 8)
    }
}

extension NSTouchBarItem.Identifier {
    static let batteryLeft  = NSTouchBarItem.Identifier("com.mipods.plus.touchbar.battery.left")
    static let batteryRight = NSTouchBarItem.Identifier("com.mipods.plus.touchbar.battery.right")
    static let batteryCase  = NSTouchBarItem.Identifier("com.mipods.plus.touchbar.battery.case")
    static let modeButtons  = NSTouchBarItem.Identifier("com.mipods.plus.touchbar.mode")
}
