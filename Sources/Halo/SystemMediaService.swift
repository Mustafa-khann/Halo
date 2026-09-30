import AppKit

/// Owns every helper process in one configuration, including short-lived commands.
private final class MediaProcessSession: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var processes: [Process] = []
    func launch(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        try process.run()
        processes.append(process)
    }
    func forget(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        processes.removeAll { $0 === process }
    }
    func cancel() {
        lock.lock(); cancelled = true
        let children = processes; processes.removeAll(); lock.unlock()
        children.forEach(Self.terminate)
    }
    static func terminate(_ child: Process) {
        guard child.isRunning else { return }
        child.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }
}

@MainActor final class SystemMediaService {
    private let receive: (MediaSnapshot) -> Void
    private let controlError: (String?) -> Void
    private let queue = DispatchQueue(label: "app.halo.now-playing", qos: .utility)
    private var session: MediaProcessSession?
    private var stream: Process?
    private var revision = 0
    private var failures = 0
    private var latest = MediaSnapshot()
    private var pending: [(arguments: [String], expected: MediaSnapshot, seek: Bool)] = []
    private var commanding = false
    private var receivedData = false

    init(receive: @escaping (MediaSnapshot) -> Void, controlError: @escaping (String?) -> Void) {
        self.receive = receive; self.controlError = controlError
    }
    func start() {
        stop()
        failures = 0
        session = MediaProcessSession()
        launchStream()
    }
    func stop() {
        revision += 1
        (stream?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        session?.cancel(); session = nil; stream = nil
        pending.removeAll(); commanding = false
        latest = MediaSnapshot()
    }
    func refresh() { start() }
    func command(_ command: MediaService.Command) {
        guard latest.available else { return }
        let id: Int
        switch command {
        case .playpause: id = 2
        case .previous:
            guard !latest.prohibitsSkip || latest.skipBackward else { return }
            id = latest.skipBackward ? 12 : 5
        case .next:
            guard !latest.prohibitsSkip || latest.skipForward else { return }
            id = latest.skipForward ? 13 : 4
        }
        enqueue(["send", String(id)], expected: latest, seek: false)
    }
    func seek(to seconds: Double, in snapshot: MediaSnapshot) {
        guard snapshot.canSeek, seconds.isFinite, snapshot.provider == .automatic else { return }
        let position = min(max(0, seconds), snapshot.duration)
        guard position < Double(Int64.max) / 1_000_000 else { return }
        enqueue(["seek", String(Int64(position * 1_000_000))], expected: snapshot, seek: true)
    }
    func openPlayer() {
        guard !latest.sourceBundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: latest.sourceBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
    private func enqueue(_ arguments: [String], expected: MediaSnapshot, seek: Bool) {
        guard session != nil else { return }
        controlError(nil)
        if seek { pending.removeAll { $0.seek } }
        pending.append((arguments, expected, seek))
        runNext()
    }
    private func runNext() {
        guard let session, !commanding, !pending.isEmpty else { return }
        let request = pending.removeFirst()
        commanding = true
        let generation = revision
        queue.async { [weak self] in
            var message: String?
            do {
                // A queued slider gesture must never seek a newly selected episode or video.
                let data = try Self.run(["get", "--micros", "--no-artwork", "--allow-missing-title"], session: session)
                let current = try NowPlayingState.decodeRecord(data)
                guard current.available, current.trackID == request.expected.trackID else { throw PlaybackChanged() }
                _ = try Self.run(request.arguments, session: session)
            } catch is PlaybackChanged { message = "Playback changed. Try again." }
            catch { message = "This player couldn’t complete the request. Try again." }
            DispatchQueue.main.async {
                guard let self, self.revision == generation, self.session != nil else { return }
                self.commanding = false
                self.controlError(message)
                self.runNext()
            }
        }
    }
    private struct PlaybackChanged: Error {}
    private func launchStream() {
        guard let session else { return }
        let generation = revision
        receivedData = false
        do {
            let process = try Self.process(["stream", "--micros", "--allow-missing-title", "--debounce=80"])
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            // This state is touched only on the serial reader queue.
            var buffer = NowPlayingLineBuffer()
            var state = NowPlayingState()
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                if chunk.isEmpty { handle.readabilityHandler = nil; return }
                self?.queue.async { [weak self] in
                    do {
                        for line in try buffer.append(chunk) {
                            let snapshot = try state.consume(line)
                            DispatchQueue.main.async {
                                guard let self, self.revision == generation, self.stream === process else { return }
                                self.receivedData = true
                                self.publish(snapshot)
                            }
                        }
                    } catch { MediaProcessSession.terminate(process) }
                }
            }
            process.terminationHandler = { [weak self] terminated in
                pipe.fileHandleForReading.readabilityHandler = nil
                session.forget(terminated)
                terminated.terminationHandler = nil
                DispatchQueue.main.async {
                    guard let self, self.revision == generation, self.stream === terminated else { return }
                    self.stream = nil
                    self.failures += 1
                    self.unavailable()
                    if self.failures <= 3 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(self.failures * 2)) { [weak self] in
                            guard let self, self.revision == generation, self.session != nil else { return }
                            self.launchStream()
                        }
                    }
                }
            }
            try session.launch(process)
            stream = process
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, self.revision == generation, self.stream === process, !self.receivedData, process.isRunning else { return }
                MediaProcessSession.terminate(process)
            }
        } catch { unavailable() }
    }
    private func unavailable() {
        var snapshot = MediaSnapshot()
        snapshot.message = "Now Playing is unavailable. Try Refresh, or choose a player in Settings → Activities."
        publish(snapshot)
    }
    private func publish(_ value: MediaSnapshot) {
        var snapshot = value
        if snapshot.available {
            let app = !snapshot.sourceBundleID.isEmpty
                ? NSRunningApplication.runningApplications(withBundleIdentifier: snapshot.sourceBundleID).first
                : NSRunningApplication(processIdentifier: snapshot.processID)
            snapshot.sourceName = app?.localizedName ?? "Now Playing"
            if snapshot.sourceBundleID.isEmpty { snapshot.sourceBundleID = app?.bundleIdentifier ?? "" }
        }
        latest = snapshot
        receive(snapshot)
    }
    nonisolated private static func process(_ arguments: [String]) throws -> Process {
        guard let resources = Bundle.main.resourceURL, let frameworks = Bundle.main.privateFrameworksURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        let script = resources.appendingPathComponent("MediaRemote/mediaremote-adapter.pl")
        let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: script.path), FileManager.default.fileExists(atPath: framework.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, framework.path] + arguments
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["HALO_MEDIA_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        process.environment = environment
        return process
    }
    nonisolated private static func run(_ arguments: [String], session: MediaProcessSession) throws -> Data {
        let child = try process(arguments)
        let pipe = Pipe()
        child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice
        try session.launch(child)
        defer { session.forget(child) }
        let timeout = DispatchWorkItem {
            MediaProcessSession.terminate(child)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        child.waitUntilExit()
        timeout.cancel()
        guard child.terminationStatus == 0, data.count < 1_000_000 else { throw CocoaError(.fileReadUnknown) }
        return data
    }
}
