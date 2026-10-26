import AppKit
import SwiftUI
import Combine
import ACControlCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var subscription: AnyCancellable?
    private var timer: Timer?
    private var wakeObservers: [NSObjectProtocol] = []
    private let model = AppModel(demo: CommandLine.arguments.contains("--demo"))

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let flag = CommandLine.arguments.firstIndex(of: "--render-previews"),
           CommandLine.arguments.count > flag + 1, model.demo {
            let folder = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
            Task { @MainActor in
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    guard self.model.devices.count == 3, self.model.devices.filter(\.isControllable).count == 2 else { throw ACError.invalidResponse }
                    await self.model.selectDevice("demo-office")
                    guard self.model.selectedID == "demo-office", self.model.deviceName == "Escritório" else { throw ACError.invalidResponse }
                    await self.model.selectDevice("demo-washer")
                    guard self.model.selectedID == "demo-office" else { throw ACError.invalidResponse }
                    await self.model.selectDevice("demo-ac")
                    guard self.model.selectedID == "demo-ac" else { throw ACError.invalidResponse }
                    print("Demo inventory: 3 devices, 2 ACs; screen selection and unsupported-device guard — PASS")
                    await self.model.setTemperature(25)
                    guard self.model.snapshot?.target == 25 else { throw ACError.invalidResponse }
                    await self.model.setPower(false)
                    guard self.model.snapshot?.isOn == false, self.model.snapshot?.target == 25 else { throw ACError.invalidResponse }
                    await self.model.setPower(true)
                    guard self.model.snapshot?.isOn == true, self.model.snapshot?.target == 25 else { throw ACError.invalidResponse }
                    print("Demo actions: slider target 25; power off/on preserved target — PASS")
                    await self.model.setFanSpeed("enum:HIGH")
                    guard self.model.currentFanOptionID == "enum:HIGH", self.model.snapshot?.target == 25,
                          self.model.snapshot?.isOn == true, self.model.snapshot?.jobMode == "COOL" else { throw ACError.invalidResponse }
                    try self.render(QuickControlView(model: self.model, openSettings: {}), width: 336, to: folder.appendingPathComponent("panel-fan-high.png"))
                    await self.model.setPower(false)
                    await self.model.setFanSpeed("enum:LOW")
                    guard !self.model.canSetFanSpeed, self.model.currentFanOptionID == "enum:HIGH" else { throw ACError.invalidResponse }
                    await self.model.setPower(true)
                    guard self.model.currentFanOptionID == "enum:HIGH", self.model.snapshot?.target == 25 else { throw ACError.invalidResponse }
                    await self.model.selectDevice("demo-office")
                    guard self.model.currentFanOptionID == "enum:AUTO" else { throw ACError.invalidResponse }
                    await self.model.selectDevice("demo-ac")
                    guard self.model.currentFanOptionID == "enum:HIGH" else { throw ACError.invalidResponse }
                    await self.model.setFanSpeed("enum:AUTO")
                    print("Demo fan: HIGH confirmed; temperature/mode/power preserved; off-state blocked; devices isolated — PASS")
                    for state in ["on", "off", "offline", "missing"] {
                        self.model.demoState(state)
                        if state == "offline", self.model.canSetFanSpeed { throw ACError.invalidResponse }
                        try self.render(QuickControlView(model: self.model, openSettings: {}), width: 336, to: folder.appendingPathComponent("panel-" + state + ".png"))
                        let statusImage = StatusLabelRenderer.image(for: self.model)
                        try self.render(Image(nsImage: statusImage).renderingMode(.template).foregroundStyle(.primary).padding(.horizontal, 8).frame(height: 26), width: statusImage.size.width + 16, to: folder.appendingPathComponent("bar-" + state + ".png"))
                        print("State \(state): bar=\(self.model.barTitle.isEmpty ? "ALERT_ONLY" : self.model.barTitle); controls=\(self.model.canControl)")
                    }
                    self.model.demoState("on")
                    try self.render(SettingsView(model: self.model), width: 560, to: folder.appendingPathComponent("settings.png"))
                    try self.render(AccountDevicesView(model: self.model).padding(16).frame(width: 560), width: 560, to: folder.appendingPathComponent("devices.png"))
                    await self.model.selectDevice("demo-office")
                    try self.render(QuickControlView(model: self.model, openSettings: {}), width: 336, to: folder.appendingPathComponent("panel-office.png"))
                    print("Native previews saved in \(folder.path)")
                    NSApp.terminate(nil)
                } catch {
                    FileHandle.standardError.write(Data("Preview validation failed.\n".utf8))
                    exit(1)
                }
            }
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self; button.action = #selector(togglePopover)
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.imagePosition = .imageLeading
            button.setAccessibilityLabel("AC Control")
        }
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: QuickControlView(model: model) { [weak self] in self?.showSettings() })
        subscription = model.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.updateStatusItem() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateStatusItem() }
        }
        let center = NSWorkspace.shared.notificationCenter
        wakeObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.model.suspend() }
        })
        wakeObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.model.wake() }
        })
        updateStatusItem()
        model.start()
        if CommandLine.arguments.contains("--show-panel") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                self.togglePopover()
            }
        }
        if CommandLine.arguments.contains("--show-settings") { showSettings() }
    }
    private func render<Content: View>(_ content: Content, width: CGFloat, to url: URL) throws {
        let host = NSHostingView(rootView: content.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 800)
        let size = host.fittingSize
        host.frame = NSRect(x: 0, y: 0, width: width, height: max(1, size.height))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw ACError.invalidResponse }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ACError.invalidResponse }
        try png.write(to: url)
    }
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = StatusLabelRenderer.image(for: model)
        button.title = ""
        button.toolTip = model.barHelp
        button.setAccessibilityValue(model.barHelp)
    }
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        Task { await model.refresh() }
    }
    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: controller)
            window.title = "AC Control — Configurações"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.stop(); timer?.invalidate()
        for observer in wakeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
