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
    private var proximityPopup: ProximityPopupController?
    private var touchBar: TouchBarController?
    private var cancellables = Set<AnyCancellable>()
    private var wasConnected = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        let hud = HUDController(controller: controller)
        self.hud = hud

        let proximityPopup = ProximityPopupController(controller: controller)
        proximityPopup.onOpenMainPanel = { [weak self] in
            self?.openPanel()
        }
        self.proximityPopup = proximityPopup

        let touchBar = TouchBarController(controller: controller)
        self.touchBar = touchBar

        controller.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.updateStatusItemTitle(state)

                if state.isConnected && !self.wasConnected {
                    self.hud?.show()
                    self.proximityPopup?.handleConnectedTransition()
                }
                self.wasConnected = state.isConnected
                self.hud?.updateIfVisible()
                self.proximityPopup?.updateIfVisible()
            }
            .store(in: &cancellables)

        controller.$discoveredDevices
            .receive(on: RunLoop.main)
            .sink { [weak self] devices in
                self?.proximityPopup?.handleDiscoveredDevices(devices)
            }
            .store(in: &cancellables)

        controller.start()

        if ProcessInfo.processInfo.environment["MIPODS_DEMO"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.openPanel()
                self?.hud?.showForced()
                self?.proximityPopup?.showForced()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.controller.state.isConnected else { return }
            self.hud?.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hud?.hide()
        proximityPopup?.hide(animated: false)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: L10n.appName)
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.action = #selector(handleStatusClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        updateStatusItemTitle(controller.state)
    }

    private func updateStatusItemTitle(_ state: MiPodsState) {
        guard let button = statusItem?.button else { return }

        if state.isConnected {
            button.title = " " + state.compactBatteryText
            let symbol = state.canSwitchNoiseMode && state.noiseMode != .off ? state.noiseMode.symbolName : "earbuds"
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: L10n.appName)
            button.toolTip = "\(state.displayName) · \(state.noiseModeTitle) (\(state.compactBatteryText))"
            if let lowest = state.lowestBattery, lowest <= 20, !state.isAnyCharging {
                button.contentTintColor = .systemRed
            } else {
                button.contentTintColor = nil
            }
        } else {
            button.title = ""
            button.contentTintColor = nil
            button.toolTip = "\(L10n.appName) · \(state.statusDetail)"
            button.image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: L10n.statusDisconnected)
        }
        button.image?.isTemplate = true
    }

    @objc private func handleStatusClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            closePanel()
            showQuickMenu()
            return
        }
        togglePanel()
    }

    private func showQuickMenu() {
        let menu = NSMenu()
        let state = controller.state

        let titleItem = NSMenuItem(title: "\(state.displayName) · \(state.isConnected ? state.compactBatteryText : L10n.statusDisconnected)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        if state.isConnected && state.canSwitchNoiseMode {
            for mode in state.availableNoiseModes {
                let item = NSMenuItem(title: mode.localizedTitle, action: #selector(selectQuickNoiseMode(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = mode
                item.state = state.noiseMode == mode ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        if state.isConnected && state.capabilities.contains(.hasAdaptiveANC) {
            let item = NSMenuItem(title: "自适应降噪", action: #selector(toggleQuickAdaptiveANC), keyEquivalent: "")
            item.target = self
            item.state = state.adaptiveANC ? .on : .off
            menu.addItem(item)
        }

        if state.isConnected && state.capabilities.contains(.hasLowLatency) {
            let item = NSMenuItem(title: "低延迟游戏模式", action: #selector(toggleQuickLowLatency), keyEquivalent: "")
            item.target = self
            item.state = state.lowLatency ? .on : .off
            menu.addItem(item)
        }

        if state.isConnected && state.capabilities.contains(.hasDualDevice) {
            let item = NSMenuItem(title: "双设备连接", action: #selector(toggleQuickDualDevice), keyEquivalent: "")
            item.target = self
            item.state = state.dualDevice ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let cardItem = NSMenuItem(title: "弹出耳机发现卡片", action: #selector(triggerShowDiscoveryCard), keyEquivalent: "d")
        cardItem.target = self
        menu.addItem(cardItem)

        let autoCardItem = NSMenuItem(title: "自动弹出附近发现弹窗", action: #selector(toggleAutoProximityPopup), keyEquivalent: "")
        autoCardItem.target = self
        autoCardItem.state = (proximityPopup?.isAutoPopupEnabled ?? true) ? .on : .off
        menu.addItem(autoCardItem)

        let captureItem = NSMenuItem(title: "抓取 BLE 广播（诊断）", action: #selector(toggleCaptureAdvertisements), keyEquivalent: "")
        captureItem.target = self
        captureItem.state = controller.captureAdvertisements ? .on : .off
        menu.addItem(captureItem)

        let rescanItem = NSMenuItem(title: L10n.actionRescan, action: #selector(triggerQuickRescan), keyEquivalent: "r")
        rescanItem.target = self
        menu.addItem(rescanItem)

        let quitItem = NSMenuItem(title: L10n.actionQuit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func selectQuickNoiseMode(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? NoiseMode {
            controller.setNoiseMode(mode)
        }
    }

    @objc private func toggleQuickAdaptiveANC() {
        controller.setAdaptiveANC(!controller.state.adaptiveANC)
    }

    @objc private func toggleQuickLowLatency() {
        controller.setLowLatency(!controller.state.lowLatency)
    }

    @objc private func toggleQuickDualDevice() {
        controller.setDualDevice(!controller.state.dualDevice)
    }

    @objc private func triggerShowDiscoveryCard() {
        proximityPopup?.showForced()
    }

    @objc private func toggleAutoProximityPopup() {
        guard let proximityPopup else { return }
        proximityPopup.isAutoPopupEnabled.toggle()
    }

    @objc private func toggleCaptureAdvertisements() {
        controller.captureAdvertisements.toggle()
    }

    @objc private func triggerQuickRescan() {
        controller.rescanDevices()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
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
            onShowDiscoveryCard: { [weak self] in
                self?.closePanel()
                self?.proximityPopup?.showForced()
            },
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
