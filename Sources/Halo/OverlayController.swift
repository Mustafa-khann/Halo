import AppKit
import Carbon
import SwiftUI

final class HaloPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class ShortcutController {
    private var handler: EventHandlerRef?
    private var toggleReference: EventHotKeyRef?
    private var escapeReference: EventHotKeyRef?
    private var registeredShortcut: GlobalShortcut?
    private var available = false
    var onToggle: (() -> Void)?
    var onEscape: (() -> Void)?

    func start() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr else { return result }
            let controller = Unmanaged<ShortcutController>.fromOpaque(context).takeUnretainedValue()
            let id = identifier.id
            Task { @MainActor in id == 1 ? controller.onToggle?() : controller.onEscape?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func configure(_ shortcut: GlobalShortcut) -> Bool {
        if registeredShortcut == shortcut { return available }
        if let toggleReference { UnregisterEventHotKey(toggleReference) }
        toggleReference = nil
        let key = shortcut == .controlOptionH ? UInt32(kVK_ANSI_H) : UInt32(kVK_Space)
        let modifiers = shortcut == .optionShiftSpace ? UInt32(optionKey | shiftKey) : UInt32(controlKey | optionKey)
        available = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x49534C44, id: 1), GetApplicationEventTarget(), 0, &toggleReference) == noErr
        registeredShortcut = shortcut
        return available
    }
    func captureEscape(_ capture: Bool) {
        if capture, escapeReference == nil {
            RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: 0x49534C44, id: 2), GetApplicationEventTarget(), 0, &escapeReference)
        } else if !capture, let reference = escapeReference {
            UnregisterEventHotKey(reference)
            escapeReference = nil
        }
    }
    func stop() {
        captureEscape(false)
        if let toggleReference { UnregisterEventHotKey(toggleReference) }
        if let handler { RemoveEventHandler(handler) }
        handler = nil; toggleReference = nil
    }
}

@MainActor final class OverlayController {
    let model: AppModel
    private var panel: HaloPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var hoverWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var pointerInside = false
    private var trackingPointer = false
    private var fileDragMonitor: Timer?
    private var dragPasteboardBaseline = NSPasteboard(name: .drag).changeCount
    private let shortcuts = ShortcutController()

    init(model: AppModel) { self.model = model }
    func start() {
        shortcuts.onToggle = { [weak self] in self?.model.overlayEnabled = true; self?.model.toggle(); self?.refreshVisibility() }
        shortcuts.onEscape = { [weak self] in self?.model.close() }
        shortcuts.start()
        model.shortcutAvailable = shortcuts.configure(model.preferences.shortcut)
        model.onExpansionChanged = { [weak self] in
            guard let self else { return }
            self.shortcuts.captureEscape(self.model.expanded)
            self.updateMouseRouting()
        }
        model.onPreferencesChanged = { [weak self] in
            guard let self else { return }
            self.model.shortcutAvailable = self.shortcuts.configure(self.model.preferences.shortcut)
            self.position()
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.position() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.keepAwake.stop(); self?.model.close(); self?.panel?.orderOut(nil) }
        })
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.model.tick(); self?.position() }
            })
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .leftMouseUp]
        // AppKit delivers both monitor handlers on the main thread. Handle them
        // immediately so the pointer cannot move before hit testing the event.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.handleMouse(event) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleMouse(event)
            return event
        }
        position()
    }
    func stop() {
        hoverWork?.cancel(); closeWork?.cancel()
        fileDragMonitor?.invalidate()
        fileDragMonitor = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        shortcuts.stop()
        panel?.close()
    }
    func refreshVisibility() {
        guard model.overlayEnabled && (model.geometry.hasNotch || model.preferences.showOnUnnotchedDisplay) else {
            panel?.orderOut(nil); model.close(); return
        }
        panel?.orderFrontRegardless()
    }
    private func position() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        model.geometry = .read(screen)
        let width = max(model.geometry.expandedWidth(preference: model.preferences.expandedWidth), model.geometry.notchWidth + 96) + 48
        let height = model.geometry.notchHeight + 300
        let top = screen.frame.maxY - (model.geometry.hasNotch ? 0 : 6)
        let frame = NSRect(x: model.geometry.centerX - width / 2, y: top - height, width: width, height: height)
        if panel == nil {
            let created = HaloPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            created.backgroundColor = .clear
            created.title = "Halo Island"
            created.isOpaque = false
            created.hasShadow = false
            created.hidesOnDeactivate = false
            created.isFloatingPanel = true
            created.isReleasedWhenClosed = false
            created.animationBehavior = .none
            created.level = .statusBar
            created.acceptsMouseMovedEvents = true
            created.ignoresMouseEvents = true
            created.contentView = NSHostingView(rootView: HaloView(model: model))
            panel = created
        }
        panel?.collectionBehavior = model.preferences.showInFullScreen ? [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle] : [.canJoinAllSpaces, .fullScreenNone, .stationary, .ignoresCycle]
        panel?.setFrame(frame, display: true)
        refreshVisibility()
        updateMouseRouting()
    }
    private var haloRect: NSRect {
        let top = model.geometry.screenFrame.maxY - (model.geometry.hasNotch ? 0 : 6)
        return NSRect(x: model.geometry.centerX - model.currentWidth / 2, y: top - model.currentHeight, width: model.currentWidth, height: model.currentHeight)
    }
    private func containsPointer(at point: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard model.overlayEnabled else { return false }
        let rect = haloRect
        guard rect.contains(point) else { return false }
        let inset: CGFloat = model.expanded ? 12 : 5
        if point.y < rect.maxY - inset && (point.x < rect.minX + inset || point.x > rect.maxX - inset) { return false }
        let radius: CGFloat = model.expanded ? 28 : 12
        if point.y < rect.minY + radius {
            let left = CGPoint(x: rect.minX + inset + radius, y: rect.minY + radius)
            let right = CGPoint(x: rect.maxX - inset - radius, y: rect.minY + radius)
            if point.x < left.x { return hypot(point.x - left.x, point.y - left.y) <= radius }
            if point.x > right.x { return hypot(point.x - right.x, point.y - right.y) <= radius }
        }
        return true
    }
    private func updateMouseRouting() { panel?.ignoresMouseEvents = !trackingPointer && !containsPointer() }
    private func monitorFileDrag() {
        guard fileDragMonitor == nil, model.preferences.filesEnabled else { return }
        // A drag session can stop delivering ordinary mouse events. Only while
        // a drag is held, track its pointer so the notch remains a drop target.
        fileDragMonitor = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.trackFileDrag() }
        }
        if let fileDragMonitor { RunLoop.main.add(fileDragMonitor, forMode: .common) }
    }
    private func trackFileDrag() {
        if NSEvent.pressedMouseButtons & 1 == 0 || !model.overlayEnabled || !model.preferences.filesEnabled {
            fileDragMonitor?.invalidate(); fileDragMonitor = nil
            updateMouseRouting()
            return
        }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragPasteboardBaseline,
              pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
        let point = NSEvent.mouseLocation
        if haloRect.insetBy(dx: -20, dy: -12).contains(point) {
            hoverWork?.cancel(); closeWork?.cancel(); closeWork = nil
            if !model.expanded || model.selectedTab != .files { model.open(tab: .files) }
            panel?.ignoresMouseEvents = false
            pointerInside = true
        } else if model.expanded && !model.pinned && !model.fileShelf.draggingOver && !model.interactionInProgress && closeWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.closeWork = nil
                if !self.containsPointer() && !self.model.pinned && !self.model.fileShelf.draggingOver && !self.model.interactionInProgress { self.model.close() }
            }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + model.preferences.collapseDelay, execute: work)
        }
    }
    private func handleMouse(_ event: NSEvent) {
        // Local events carry the actual window position, including during native
        // slider tracking. The global cursor can lag behind the delivered event.
        let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        let inside = containsPointer(at: point)
        let type = event.type
        if type == .leftMouseDown { dragPasteboardBaseline = NSPasteboard(name: .drag).changeCount }
        if type == .leftMouseDragged && !trackingPointer { monitorFileDrag() }
        if type == .leftMouseDragged, trackingPointer { return }
        if type == .leftMouseDragged, inside, model.preferences.filesEnabled,
           NSPasteboard(name: .drag).canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            hoverWork?.cancel(); closeWork?.cancel(); closeWork = nil
            if !model.expanded || model.selectedTab != .files { model.open(tab: .files) }
            pointerInside = true
            updateMouseRouting()
            return
        }
        if type == .leftMouseUp { trackingPointer = false }
        panel?.ignoresMouseEvents = !trackingPointer && !inside
        if type == .leftMouseDown || type == .rightMouseDown {
            hoverWork?.cancel(); closeWork?.cancel(); closeWork = nil
            trackingPointer = type == .leftMouseDown && inside
            if !inside && model.expanded && !model.interactionInProgress { model.close() }
            else if inside && !model.expanded { model.open(pin: true) }
            return
        }
        if inside {
            closeWork?.cancel()
            closeWork = nil
            if !pointerInside && !model.expanded && model.preferences.openOnHover {
                hoverWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.containsPointer(), self.model.overlayEnabled, !self.model.expanded else { return }
                    self.model.open()
                }
                hoverWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + model.preferences.hoverDelay, execute: work)
            }
        } else {
            hoverWork?.cancel()
            if pointerInside && model.expanded && !model.pinned && !model.interactionInProgress && !model.fileShelf.draggingOver {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, !self.containsPointer(), !self.model.pinned, !self.model.interactionInProgress, !self.model.fileShelf.draggingOver else { return }
                    self.closeWork = nil
                    self.model.close()
                }
                closeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + model.preferences.collapseDelay, execute: work)
            }
        }
        pointerInside = inside
    }
}
