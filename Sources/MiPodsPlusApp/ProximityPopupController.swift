import AppKit
import SwiftUI
import MiPodsPlusCore

/// Floating AirPods-style proximity discovery & connection card controller.
///
/// Automatically pops up when:
/// - Nearby Xiaomi / Redmi earbuds are newly discovered via BLE broadcast (`RSSI >= -75 dBm`) or paired RFCOMM while disconnected.
/// - Earbuds connect (when proximity popup mode is enabled).
/// - The user clicks "弹出发现卡片" in the menu or panel.
@MainActor
final class ProximityPopupController {

    private weak var controller: MiPodsController?
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var currentCandidate: DiscoveredDevice?
    private var lastAutoPopupByDevice: [UUID: Date] = [:]

    private static let autoPopupEnabledKey = "mipods.plus.proximityAutoPopup"
    private let cooldownPerDevice: TimeInterval = 45
    private let connectedAutoDismissDelay: TimeInterval = 5.5
    private let discoveredAutoDismissDelay: TimeInterval = 10.0

    var onOpenMainPanel: (() -> Void)?

    var isAutoPopupEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.autoPopupEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.autoPopupEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.autoPopupEnabledKey)
        }
    }

    init(controller: MiPodsController) {
        self.controller = controller
    }

    /// Evaluates newly discovered devices and pops up the discovery card when a nearby earbud appears while disconnected.
    func handleDiscoveredDevices(_ devices: [DiscoveredDevice]) {
        guard isAutoPopupEnabled, let controller, !controller.state.isConnected else { return }

        // Pick a strong-signal nearby earbud (or a system-connected one not yet attached).
        let candidate = devices.first { dev in
            if dev.isSystemConnected { return true }
            if let rssi = dev.rssi, rssi >= -75 { return true }
            return false
        }
        guard let candidate else { return }

        let now = Date()
        if let last = lastAutoPopupByDevice[candidate.id],
           now.timeIntervalSince(last) < cooldownPerDevice {
            return
        }
        lastAutoPopupByDevice[candidate.id] = now
        show(device: candidate, autoDismissAfter: discoveredAutoDismissDelay)
    }

    /// Shows the AirPods-style card on connection.
    func showConnectedCard() {
        guard isAutoPopupEnabled else { return }
        show(device: currentCandidate, autoDismissAfter: connectedAutoDismissDelay)
    }

    /// Explicitly opens the card (from menu or panel button).
    func showForced() {
        let candidate = controller?.discoveredDevices.first(where: { $0.id == controller?.activeDeviceID })
            ?? controller?.discoveredDevices.first
        show(device: candidate, autoDismissAfter: discoveredAutoDismissDelay)
    }

    func updateIfVisible() {
        guard let panel, panel.isVisible else { return }
        refreshContent(on: panel)
    }

    private func show(device: DiscoveredDevice?, autoDismissAfter delay: TimeInterval) {
        guard controller != nil else { return }
        currentCandidate = device
        dismissTask?.cancel()

        let panel = self.panel ?? makePanel()
        self.panel = panel

        refreshContent(on: panel)
        positionTopRight(panel)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.24
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }

        scheduleAutoDismiss(after: delay)
    }

    func hide(animated: Bool = true) {
        dismissTask?.cancel()
        dismissTask = nil
        guard let panel, panel.isVisible else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.20
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        } else {
            panel.alphaValue = 0
            panel.orderOut(nil)
        }
    }

    private func scheduleAutoDismiss(after delay: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide(animated: true)
        }
    }

    private func refreshContent(on panel: NSPanel) {
        guard let controller else { return }
        let rootView = ProximityPopupView(
            controller: controller,
            candidateDevice: currentCandidate,
            onConnect: { [weak self, weak controller] target in
                guard let self, let controller else { return }
                // Extend auto-dismiss while connecting so user sees battery rings once connected.
                self.scheduleAutoDismiss(after: 12.0)
                if let target {
                    controller.selectDevice(target.id)
                } else {
                    controller.rescanDevices()
                }
            },
            onOpenMainPanel: { [weak self] in
                self?.hide(animated: false)
                self?.onOpenMainPanel?()
            },
            onClose: { [weak self] in
                self?.hide(animated: true)
            }
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame.size = hosting.fittingSize
        hosting.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.fittingSize)
        panel.contentView = hosting
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 340),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        return panel
    }

    private func positionTopRight(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }

        let area = screen.visibleFrame
        let size = panel.frame.size
        let x = area.maxX - size.width - 20
        let y = area.maxY - size.height - 18
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }
}
