import AppKit
import SwiftUI
import MiPodsPlusCore

@MainActor
final class HUDController {

    private weak var controller: MiPodsController?
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var lastShown = Date.distantPast

    private let debounceInterval: TimeInterval = 20
    private let autoDismissDelay: TimeInterval = 4.0
    private let topInset: CGFloat = 24

    init(controller: MiPodsController) {
        self.controller = controller
    }

    func show() { show(force: false) }
    func showForced() { show(force: true) }

    private func show(force: Bool) {
        if !force {
            guard Date().timeIntervalSince(lastShown) > debounceInterval else { return }
        }
        lastShown = Date()

        guard let controller else { return }
        dismissTask?.cancel()

        let panel = panel ?? makePanel()
        self.panel = panel

        let hosting = NSHostingView(rootView: HUDView(state: controller.state))
        hosting.frame.size = hosting.fittingSize
        hosting.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.fittingSize)
        panel.contentView = hosting

        positionTopCenter(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(self!.autoDismissDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hide(animated: true)
        }
    }

    func hide(animated: Bool = false) {
        dismissTask?.cancel()
        dismissTask = nil
        guard let panel else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        } else {
            panel.alphaValue = 0
            panel.orderOut(nil)
        }
    }

    func updateIfVisible() {
        guard let panel, panel.isVisible, let controller else { return }
        let hosting = NSHostingView(rootView: HUDView(state: controller.state))
        hosting.frame.size = hosting.fittingSize
        hosting.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.fittingSize)
        panel.contentView = hosting
        positionTopCenter(panel)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        return panel
    }

    private func positionTopCenter(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }

        let area = screen.visibleFrame
        let size = panel.frame.size
        let x = area.midX - size.width / 2
        let y = area.maxY - size.height - topInset
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }
}
