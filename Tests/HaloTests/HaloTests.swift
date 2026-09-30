import AppKit
import Testing
@testable import Halo

struct HaloTests {
    @Test func addingPreferencesPreservesExistingChoices() throws {
        let data = Data("{\"openOnHover\":false,\"expandedWidth\":500}".utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(!preferences.openOnHover)
        #expect(preferences.expandedWidth == 500)
        #expect(preferences.shortcut == .controlOptionH)
        #expect(!preferences.musicEnabled)
        #expect(preferences.filesEnabled)
        #expect(preferences.keepAwakeEnabled)
    }
    @Test func timerUsesDeadlineAcrossSleep() {
        let start = Date(timeIntervalSince1970: 1000)
        var session = TimerSession()
        session.start(minutes: 25, now: start)
        #expect(session.remaining(at: start.addingTimeInterval(120)) == 1380)
        let completed = session.advance(to: start.addingTimeInterval(1600))
        #expect(completed)
        #expect(session.phase == .finished)
        let repeated = session.advance(to: start.addingTimeInterval(1800))
        #expect(!repeated)
    }
    @Test func pauseDoesNotCountTimeSpentPaused() {
        let start = Date(timeIntervalSince1970: 1000)
        var session = TimerSession()
        session.start(minutes: 5, now: start)
        session.pause(at: start.addingTimeInterval(60))
        #expect(session.remaining(at: start.addingTimeInterval(600)) == 240)
        session.resume(at: start.addingTimeInterval(600))
        #expect(session.remaining(at: start.addingTimeInterval(660)) == 180)
    }
    @Test func runningTimerSurvivesSerialization() throws {
        var session = TimerSession()
        let start = Date(timeIntervalSince1970: 2000)
        session.start(minutes: 15, now: start)
        let restored = try JSONDecoder().decode(TimerSession.self, from: JSONEncoder().encode(session))
        #expect(restored.remaining(at: start.addingTimeInterval(400)) == 500)
    }
    @Test func geometryUsesScreenCoordinatesNotMainDisplayOrigin() {
        let frame = CGRect(x: -1728, y: 120, width: 1728, height: 1117)
        let left = CGRect(x: -1728, y: 1205, width: 771.5, height: 32)
        let right = CGRect(x: -771.5, y: 1205, width: 771.5, height: 32)
        let geometry = DisplayGeometry.make(frame: frame, topInset: 32, left: left, right: right)
        #expect(geometry.notchWidth == 185)
        #expect(geometry.centerX == -864)
        #expect(geometry.notchHeight == 32)
        #expect(geometry.hasNotch)
    }
    @Test func unnotchedDisplayUsesFloatingFallback() {
        let geometry = DisplayGeometry.make(frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080), topInset: 0, left: nil, right: nil)
        #expect(!geometry.hasNotch)
        #expect(geometry.centerX == 2880)
        #expect(geometry.expandedWidth(preference: 440) == 440)
    }
    @Test func mediaPositionIsBoundedAndPausedPositionDoesNotAdvance() {
        let start = Date(timeIntervalSince1970: 1000)
        var media = MediaSnapshot()
        media.position = 50; media.duration = 100; media.observedAt = start
        #expect(media.elapsed(at: start.addingTimeInterval(10)) == 50)
        media.playing = true
        #expect(media.elapsed(at: start.addingTimeInterval(10)) == 60)
        #expect(media.elapsed(at: start.addingTimeInterval(100)) == 100)
    }
    @Test func preferencesPersistWithoutEnablingPermissionsByDefault() {
        let suite = "app.halo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!Preferences.load(from: defaults).musicEnabled)
        var preferences = Preferences()
        preferences.expandedWidth = 500
        preferences.openOnHover = false
        preferences.save(to: defaults)
        #expect(Preferences.load(from: defaults) == preferences)
    }
    @Test func shelfDeduplicatesNormalizedPathsAndRejectsWebURLs() {
        var shelf = FileShelfState()
        let file = URL(fileURLWithPath: "/tmp/halo-fixtures/report.pdf")
        let sameFile = URL(fileURLWithPath: "/tmp/halo-fixtures/subfolder/../report.pdf")
        #expect(shelf.add([file, sameFile, URL(string: "https://example.com/report.pdf")!]) == 1)
        #expect(shelf.files.count == 1)
        #expect(shelf.files.first?.url == file.resolvingSymlinksInPath())
    }
    @Test func fullShelfKeepsExistingFilesAndDoesNotEvictThem() {
        var shelf = FileShelfState()
        let urls = (0..<25).map { URL(fileURLWithPath: "/tmp/halo-file-\($0)") }
        #expect(shelf.add(urls) == FileShelfState.capacity)
        #expect(shelf.files.map(\.url) == Array(urls.prefix(FileShelfState.capacity)).map { $0.resolvingSymlinksInPath() })
    }
    @MainActor @Test func removingShelfReferencePreservesOriginalAndSavedState() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("halo-shelf-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("keep-me.txt")
        try Data("Original stays intact".utf8).write(to: original)
        let suite = "app.halo.shelf.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let shelf = FileShelfService(defaults: defaults)
        #expect(shelf.add([original]) == 1)
        let restored = FileShelfService(defaults: defaults)
        #expect(restored.state.files.first?.url == original.resolvingSymlinksInPath())
        shelf.clear()
        #expect(FileShelfService(defaults: defaults).state.files.isEmpty)
        #expect(try Data(contentsOf: original) == Data("Original stays intact".utf8))
    }
    @Test func awakeDeadlineExpiresAcrossSleepAndIndefiniteSessionsHaveNoDeadline() {
        let start = Date(timeIntervalSince1970: 1000)
        let timed = AwakeSession(active: true, deadline: start.addingTimeInterval(900))
        #expect(timed.remaining(at: start.addingTimeInterval(300)) == 600)
        #expect(!timed.expired(at: start.addingTimeInterval(899)))
        #expect(timed.expired(at: start.addingTimeInterval(900)))
        #expect(timed.remaining(at: start.addingTimeInterval(1200)) == 0)
        let indefinite = AwakeSession(active: true)
        #expect(indefinite.remaining(at: start) == nil)
        #expect(!indefinite.expired(at: start.addingTimeInterval(100_000)))
        #expect(AwakeDuration.untilStopped.seconds == nil)
    }
    @MainActor @Test func finderStyleDropLoadsFileURLsAndLeavesTheOriginalInPlace() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("halo-drop-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("drop-me.txt")
        try Data("Drag and drop fixture".utf8).write(to: original)
        let suite = "app.halo.drop.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let shelf = FileShelfService(defaults: defaults)
        let provider = NSItemProvider(object: original as NSURL)
        #expect(shelf.acceptDrop([provider]))
        for _ in 0..<200 where shelf.loading { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!shelf.loading)
        #expect(shelf.state.files.count == 1)
        #expect(shelf.state.files.first?.url == original.standardizedFileURL.resolvingSymlinksInPath())
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(shelf.add([original]) == 0)
    }
    private func event(_ payload: [String: Any], diff: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": "data", "diff": diff, "payload": payload])
    }
    @Test func systemMediaReadsPodcastsAndPlaybackSpeed() throws {
        var state = NowPlayingState()
        let now = Date(timeIntervalSince1970: 1000)
        let media = try state.consume(event([
            "processIdentifier": 123, "bundleIdentifier": "com.apple.podcasts", "playing": true,
            "title": "An episode", "artist": "A show", "mediaType": "MRMediaRemoteMediaTypePodcast",
            "durationMicros": 600_000_000, "elapsedTimeMicros": 20_000_000,
            "timestampEpochMicros": 990_000_000, "playbackRate": 1.5
        ]), at: now)
        #expect(media.provider == .automatic)
        #expect(media.sourceBundleID == "com.apple.podcasts")
        #expect(media.position == 35)
        #expect(media.elapsed(at: now.addingTimeInterval(10)) == 50)
        #expect(media.skipBackward && media.skipForward)
        #expect(media.canSeek)
    }
    @Test func systemDiffsKeepArtworkAndNullRemovesIt() throws {
        var state = NowPlayingState()
        let image = Data([1, 2, 3])
        _ = try state.consume(event(["processIdentifier": 123, "playing": false, "title": "First", "artworkData": image.base64EncodedString()]))
        let paused = try state.consume(event(["elapsedTimeMicros": 40_000_000], diff: true))
        #expect(paused.artworkData == image)
        #expect(paused.position == 40)
        let removed = try state.consume(event(["artworkData": NSNull()], diff: true))
        #expect(removed.artworkData == nil)
    }
    @Test func changingSystemPlayerClearsOldMetadata() throws {
        var state = NowPlayingState()
        let previous = try state.consume(event(["processIdentifier": 123, "playing": false, "title": "Episode", "artist": "A show", "artworkData": "AQID"]))
        let next = try state.consume(event(["processIdentifier": 456, "playing": true, "title": "A video", "bundleIdentifier": "com.apple.Safari"]))
        #expect(next.sourceBundleID == "com.apple.Safari")
        #expect(next.artist.isEmpty && next.artworkData == nil)
        #expect(next.trackID != previous.trackID)
        let empty = try state.consume(event([:]))
        #expect(!empty.available && empty.artworkData == nil)
    }
    @Test func untaggedAndLiveMediaRemainControllableWithoutSeeking() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let data = try JSONSerialization.data(withJSONObject: ["processIdentifier": 456, "playing": true, "elapsedTimeMicros": 20_000_000])
        let live = try NowPlayingState.decodeRecord(data, at: now)
        #expect(live.available && live.title == "Now Playing")
        #expect(!live.canSeek)
        #expect(live.elapsed(at: now.addingTimeInterval(5)) == 25)
        #expect(!(try NowPlayingState.decodeRecord(Data("null".utf8))).available)
    }
    @Test func malformedSystemRecordsAreRejectedOrSafe() throws {
        var state = NowPlayingState()
        #expect(throws: (any Error).self) { try state.consume(Data("{\"payload\":123}".utf8)) }
        let invalidPID = try state.consume(event(["processIdentifier": true, "playing": true]))
        #expect(!invalidPID.available)
        let badTimes = try state.consume(event(["processIdentifier": 123, "playing": false, "durationMicros": "broken", "elapsedTimeMicros": -10, "artworkData": "invalid!"]))
        #expect(badTimes.available && !badTimes.canSeek)
        #expect(badTimes.position == 0 && badTimes.artworkData == nil)
    }
    @Test func systemStreamHandlesPartialAndMultipleLines() throws {
        var buffer = NowPlayingLineBuffer()
        let first = try event(["processIdentifier": 123, "playing": false])
        let second = try event([:], diff: false)
        #expect(try buffer.append(first.prefix(10)).isEmpty)
        var tail = Data(first.dropFirst(10)); tail.append(10); tail.append(second); tail.append(10)
        #expect(try buffer.append(tail) == [first, second])
        #expect(throws: (any Error).self) { try buffer.append(Data(repeating: 65, count: NowPlayingLineBuffer.maximumLineBytes + 1)) }
    }
    @Test func existingAutomaticPreferenceUsesSystemNowPlaying() throws {
        let prefs = try JSONDecoder().decode(Preferences.self, from: Data("{\"musicEnabled\":true,\"musicProvider\":\"automatic\"}".utf8))
        #expect(prefs.musicEnabled && prefs.musicProvider == .automatic)
        #expect(prefs.musicProvider.title == "System Now Playing")
    }

}
