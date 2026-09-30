import AppKit
import IOKit.ps

@MainActor final class PowerService {
    private let receive: (PowerSnapshot) -> Void
    private var source: CFRunLoopSource?
    init(receive: @escaping (PowerSnapshot) -> Void) { self.receive = receive }
    func start() {
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<PowerService>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in service.refresh() }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    }
    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
    }
    private func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            receive(PowerSnapshot()); return
        }
        for item in sources {
            guard let dictionary = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  dictionary[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = dictionary[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = dictionary[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let time = dictionary[kIOPSTimeToFullChargeKey] as? Int
            receive(PowerSnapshot(
                percent: min(100, max(0, Int((Double(capacity) / Double(maximum) * 100).rounded()))),
                onAC: dictionary[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                charging: dictionary[kIOPSIsChargingKey] as? Bool ?? false,
                available: true,
                minutesToFull: time.flatMap { $0 > 0 ? $0 : nil }
            ))
            return
        }
        receive(PowerSnapshot())
    }
}

@MainActor final class MediaService {
    enum Command: String { case playpause = "playpause", next = "next track", previous = "previous track" }
    private enum RequestKind { case transport, seek }
    private struct Request {
        var kind: RequestKind
        var provider: MusicProvider
        var body: String
    }
    private let receive: (MediaSnapshot) -> Void
    private let controlError: (String?) -> Void
    private let queue = DispatchQueue(label: "app.halo.media", qos: .utility)
    private var enabled = false
    private var provider = MusicProvider.automatic
    private var lastProvider = MusicProvider.spotify
    private var poller: Timer?
    private var observers: [NSObjectProtocol] = []
    private var busy = false
    private var generation = 0
    private var pendingRequests: [Request] = []

    init(receive: @escaping (MediaSnapshot) -> Void, controlError: @escaping (String?) -> Void) {
        self.receive = receive
        self.controlError = controlError
        for (name, source) in [("com.spotify.client.PlaybackStateChanged", MusicProvider.spotify), ("com.apple.Music.playerInfo", .appleMusic)] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.lastProvider = source; self?.refresh() }
            })
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }
    func configure(enabled: Bool, provider: MusicProvider) {
        self.enabled = enabled
        self.provider = provider
        generation += 1
        pendingRequests.removeAll()
        controlError(nil)
        poller?.invalidate()
        poller = nil
        if enabled { refresh() } else { receive(MediaSnapshot()) }
    }
    func stop() { enabled = false; generation += 1; pendingRequests.removeAll(); poller?.invalidate(); poller = nil }
    private func runningProvider() -> MusicProvider? {
        let running = Set(NSWorkspace.shared.runningApplications.map(\.bundleIdentifier).compactMap { $0 })
        if provider != .automatic { return running.contains(provider.bundleID) ? provider : nil }
        for candidate in [lastProvider, lastProvider == .spotify ? .appleMusic : .spotify] {
            if running.contains(candidate.bundleID) { return candidate }
        }
        return nil
    }
    func refresh() {
        guard enabled, !busy else { return }
        guard let current = runningProvider() else {
            var empty = MediaSnapshot()
            empty.message = "Open Spotify or Apple Music, then play something you love."
            receive(empty)
            poller?.invalidate(); poller = nil
            return
        }
        busy = true
        let revision = generation
        queue.async { [weak self] in
            let result = Self.read(current)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if self.enabled, self.generation == revision, self.pendingRequests.isEmpty {
                    self.publish(result)
                }
                self.runNextRequest()
                if self.enabled, self.generation != revision { self.refresh() }
            }
        }
    }
    func command(_ command: Command) {
        guard enabled, let current = runningProvider() else { return }
        enqueue(Request(kind: .transport, provider: current, body: command.rawValue))
    }
    func seek(to seconds: Double, in snapshot: MediaSnapshot) {
        guard snapshot.available, snapshot.duration > 0, seconds.isFinite, !snapshot.trackID.isEmpty else { return }
        let position = min(max(0, seconds), snapshot.duration)
        let idProperty = snapshot.provider == .spotify ? "id" : "persistent ID"
        let body = """
        if \(idProperty) of current track is not \(Self.quoted(snapshot.trackID)) then return false
        set player position to \(position)
        return true
        """
        enqueue(Request(kind: .seek, provider: snapshot.provider, body: body))
    }
    private func enqueue(_ request: Request) {
        guard enabled else { return }
        controlError(nil)
        // Keep the most recent slider value while an Apple Event is in flight.
        if request.kind != .transport {
            pendingRequests.removeAll { $0.kind == request.kind && $0.provider == request.provider }
        }
        pendingRequests.append(request)
        runNextRequest()
    }
    private func runNextRequest() {
        guard enabled, !busy, !pendingRequests.isEmpty else { return }
        let request = pendingRequests.removeFirst()
        guard NSRunningApplication.runningApplications(withBundleIdentifier: request.provider.bundleID).contains(where: { !$0.isTerminated }) else {
            pendingRequests.removeAll()
            refresh()
            return
        }
        busy = true
        let revision = generation
        queue.async { [weak self] in
            let (response, error) = Self.execute("tell application id \"\(request.provider.bundleID)\"\n\(request.body)\nend tell")
            let snapshot = Self.read(request.provider)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if self.enabled, self.generation == revision, self.pendingRequests.isEmpty {
                    if let error {
                        self.controlError((error[NSAppleScript.errorNumber] as? Int) == -1743 ? "Automation access is needed." : "Couldn’t update your player. Try again.")
                    } else if request.kind == .seek, response?.booleanValue == false {
                        self.controlError("The track changed. Try seeking again.")
                    }
                    self.publish(snapshot)
                }
                self.runNextRequest()
                if self.enabled, self.generation != revision { self.refresh() }
            }
        }
    }
    private func publish(_ snapshot: MediaSnapshot) {
        receive(snapshot)
        if poller == nil && snapshot.message != "Automation access is needed." {
            poller = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
    }
    nonisolated private static func quoted(_ string: String) -> String {
        "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    func openPlayer() {
        let selected = provider == .automatic ? lastProvider : provider
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: selected.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
    nonisolated private static func execute(_ body: String) -> (NSAppleEventDescriptor?, NSDictionary?) {
        let source = "with timeout of 4 seconds\n\(body)\nend timeout"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return (result, error)
    }
    nonisolated private static func read(_ provider: MusicProvider) -> MediaSnapshot {
        let artwork = provider == .spotify ? "artwork url of current track" : "\"\""
        let idProperty = provider == .spotify ? "id" : "persistent ID"
        let body = """
        tell application id "\(provider.bundleID)"
            if player state is stopped then return {"", "", "", false, 0, 0, "", ""}
            return {name of current track, artist of current track, album of current track, player state is playing, duration of current track, player position, \(artwork), \(idProperty) of current track}
        end tell
        """
        let (result, error) = execute(body)
        var snapshot = MediaSnapshot()
        snapshot.provider = provider
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int
            snapshot.message = number == -1743 ? "Automation access is needed." : "Your player isn’t ready. Start a track and try again."
            return snapshot
        }
        guard let result, result.numberOfItems >= 8, let title = result.atIndex(1)?.stringValue, !title.isEmpty else {
            snapshot.message = "Your next track will appear here."
            return snapshot
        }
        snapshot.title = title
        snapshot.artist = result.atIndex(2)?.stringValue ?? ""
        snapshot.album = result.atIndex(3)?.stringValue ?? ""
        snapshot.playing = result.atIndex(4)?.booleanValue ?? false
        let duration = result.atIndex(5)?.doubleValue ?? 0
        snapshot.duration = provider == .spotify ? duration / 1000 : duration
        snapshot.position = result.atIndex(6)?.doubleValue ?? 0
        snapshot.trackID = result.atIndex(8)?.stringValue ?? ""
        if let artwork = result.atIndex(7)?.stringValue, let url = URL(string: artwork), url.scheme == "https" { snapshot.artworkURL = url }
        snapshot.available = true
        snapshot.message = ""
        snapshot.observedAt = Date()
        return snapshot
    }
}
