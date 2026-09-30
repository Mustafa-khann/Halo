import AppKit
import SwiftUI
import UserNotifications

@main enum HaloApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSToolbarDelegate, UNUserNotificationCenterDelegate {
    private let model = AppModel()
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var pauseItem: NSMenuItem!
    private var timerItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.halo.mac").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }
        model.showSettings = { [weak self] in self?.openSettings() }
        overlay = OverlayController(model: model)
        overlay.start()
        model.start()
        createApplicationMenu()
        createMenu()
        UNUserNotificationCenter.current().delegate = self
        if !UserDefaults.standard.bool(forKey: "halo.launched") || CommandLine.arguments.contains("--show-settings") {
            UserDefaults.standard.set(true, forKey: "halo.launched")
            openSettings()
        }
        if CommandLine.arguments.contains("--preview") { model.open(pin: true) }
    }
    func applicationWillTerminate(_ notification: Notification) { overlay?.stop(); model.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }

    private func createApplicationMenu() {
        let bar = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Halo")
        for (title, action, key) in [("About Halo", #selector(aboutHalo), ""), ("Settings…", #selector(openSettings), ",")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            applicationMenu.addItem(item)
        }
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(NSMenuItem(title: "Hide Halo", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        applicationMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Halo", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu
        bar.addItem(applicationItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key))
        }
        editItem.submenu = edit; bar.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowItem.submenu = windowMenu; bar.addItem(windowItem)
        NSApp.mainMenu = bar
        NSApp.windowsMenu = windowMenu
    }

    private func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Halo")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "Halo · A little more Mac."
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Halo", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        let show = NSMenuItem(title: "Show Halo", action: #selector(showHalo), keyEquivalent: "")
        menu.addItem(show)
        timerItem = NSMenuItem(title: "Start a 25-minute focus timer", action: #selector(startFocusTimer), keyEquivalent: "")
        menu.addItem(timerItem)
        menu.addItem(.separator())
        pauseItem = NSMenuItem(title: "Hide Halo", action: #selector(toggleVisibility), keyEquivalent: "")
        menu.addItem(pauseItem)
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About Halo", action: #selector(aboutHalo), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Halo", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }
    func menuWillOpen(_ menu: NSMenu) {
        pauseItem.title = model.overlayEnabled ? "Hide Halo" : "Resume Halo"
        timerItem.isEnabled = model.preferences.timerEnabled && !model.timer.active
    }
    @objc private func showHalo() { model.overlayEnabled = true; overlay.refreshVisibility(); model.open(pin: true) }
    @objc private func startFocusTimer() { if !model.timer.active { model.startTimer(minutes: 25) }; model.overlayEnabled = true; overlay.refreshVisibility(); model.open(pin: true, tab: .timer) }
    @objc private func toggleVisibility() { model.overlayEnabled.toggle(); model.close(); overlay.refreshVisibility() }
    @objc private func aboutHalo() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Halo", .credits: NSAttributedString(string: "A little more Mac.\nMedia, battery, and focus at your fingertips.")])
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc func openSettings() {
        model.close()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Halo"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 740, height: 550)
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            let toolbar = NSToolbar(identifier: "halo.settings.toolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            if !window.setFrameUsingName("halo.settings") { window.center() }
            window.setFrameAutosaveName("halo.settings")
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .init("halo.preview")] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .init("halo.preview")] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier.rawValue == "halo.preview" else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Show Halo"
        item.toolTip = "Show Halo"
        item.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Show Halo")
        item.target = self
        item.action = #selector(showHalo)
        return item
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in model.open(pin: true, tab: .timer) }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
}
