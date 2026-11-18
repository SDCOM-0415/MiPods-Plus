import AppKit
import SwiftUI
import Combine
import MiPodsPlusCore

@main
struct MiPodsPlusApp {

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate
        objc_setAssociatedObject(app, "MiPodsPlusAppDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private let controller = MiPodsController()
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var hud: HUDController?
    private var touchBar: TouchBarController?
    private var cancellables = Set<AnyCancellable>()
    private var wasConnected = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        let hud = HUDController(controller: controller)
        self.hud = hud

        let touchBar = TouchBarController(controller: controller)
        self.touchBar = touchBar

        controller.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.updateStatusItemTitle(state)

                if state.isConnected && !self.wasConnected {
                    self.hud?.show()
                }
                self.wasConnected = state.isConnected
                self.hud?.updateIfVisible()
            }
            .store(in: &cancellables)

        controller.start()

        if ProcessInfo.processInfo.environment["MIPODS_DEMO"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.openPanel()
                self?.hud?.showForced()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.controller.state.isConnected else { return }
            self.hud?.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hud?.hide()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: L10n.appName)
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.action = #selector(togglePanel)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateStatusItemTitle(controller.state)
    }

    private func updateStatusItemTitle(_ state: MiPodsState) {
        guard let button = statusItem?.button else { return }

        if state.isConnected {
            button.title = " " + state.compactBatteryText
            button.image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: L10n.appName)
            if let lowest = state.lowestBattery, lowest <= 20, !state.isAnyCharging {
                button.contentTintColor = .systemRed
            } else {
                button.contentTintColor = nil
            }
        } else {
            button.title = ""
            button.contentTintColor = nil
            button.image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: L10n.statusDisconnected)
        }
        button.image?.isTemplate = true
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let view = PanelView(
            controller: controller,
            onShowHUD: { [weak self] in self?.hud?.showForced() },
            onOpenSoundSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize
        hosting.layoutSubtreeIfNeeded()
        panel.setContentSize(hosting.fittingSize)
        panel.contentView = hosting
        panel.layoutIfNeeded()

        positionPanelBelowStatusItem(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        touchBar?.attach(to: hosting)
    }

    private func closePanel() {
        touchBar?.detach()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = true
        panel.delegate = self
        return panel
    }

    private func positionPanelBelowStatusItem(_ panel: NSPanel) {
        let size = panel.frame.size
        guard let screen = NSScreen.main ?? statusItem?.button?.window?.screen else { return }
        let visible = screen.visibleFrame

        var centerX: CGFloat
        if let button = statusItem?.button, let window = button.window {
            let rectInWindow = button.convert(button.bounds, to: nil)
            let rectInScreen = window.convertToScreen(rectInWindow)
            if rectInScreen.width > 0 {
                centerX = rectInScreen.midX
            } else if window.frame.width > 0 {
                centerX = window.frame.midX
            } else {
                centerX = NSEvent.mouseLocation.x
            }
        } else {
            centerX = NSEvent.mouseLocation.x
        }

        var x = centerX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let menuBarHeight = screen.frame.maxY - visible.maxY
        let y = screen.frame.maxY - menuBarHeight - size.height - 6
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }
}
