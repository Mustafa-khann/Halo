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
}
