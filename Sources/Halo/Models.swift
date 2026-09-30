import AppKit
import Foundation

enum HaloTab: String, CaseIterable, Identifiable {
    case overview, music, timer, files, awake, power
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Home"
        case .music: return "Music"
        case .timer: return "Timer"
        case .files: return "Files"
        case .awake: return "Awake"
        case .power: return "Battery"
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .music: return "music.note"
        case .timer: return "timer"
        case .files: return "tray"
        case .awake: return "cup.and.saucer"
        case .power: return "battery.100percent"
        }
    }
}

enum MusicProvider: String, Codable, CaseIterable, Identifiable {
    case automatic, spotify, appleMusic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        }
    }
    var bundleID: String {
        self == .spotify ? "com.spotify.client" : "com.apple.Music"
    }
}

enum GlobalShortcut: String, Codable, CaseIterable, Identifiable {
    case controlOptionH, controlOptionSpace, optionShiftSpace
    var id: String { rawValue }
    var title: String {
        switch self {
        case .controlOptionH: return "Control–Option–H"
        case .controlOptionSpace: return "Control–Option–Space"
        case .optionShiftSpace: return "Option–Shift–Space"
        }
    }
    var glyphs: String {
        switch self {
        case .controlOptionH: return "⌃ ⌥ H"
        case .controlOptionSpace: return "⌃ ⌥ Space"
        case .optionShiftSpace: return "⌥ ⇧ Space"
        }
    }
}

struct Preferences: Codable, Equatable {
    var openOnHover = true
    var hoverDelay = 0.18
    var collapseDelay = 0.45
    var animationSpeed = 0.36
    var expandedWidth = 440.0
    var showCompactActivity = true
    var showInFullScreen = true
    var showOnUnnotchedDisplay = true
    var respectReduceMotion = true
    var chargingAlerts = true
    var musicEnabled = false
    var musicProvider = MusicProvider.automatic
    var timerEnabled = true
    var batteryEnabled = true
    var filesEnabled = true
    var keepAwakeEnabled = true
    var playTimerSound = true
    var timerNotifications = false
    var shortcut = GlobalShortcut.controlOptionH

    init() {}
    private enum CodingKeys: String, CodingKey {
        case openOnHover, hoverDelay, collapseDelay, animationSpeed, expandedWidth, showCompactActivity, showInFullScreen, showOnUnnotchedDisplay, respectReduceMotion, chargingAlerts, musicEnabled, musicProvider, timerEnabled, batteryEnabled, filesEnabled, keepAwakeEnabled, playTimerSound, timerNotifications, shortcut
    }
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        openOnHover = try values.decodeIfPresent(Bool.self, forKey: .openOnHover) ?? openOnHover
        hoverDelay = try values.decodeIfPresent(Double.self, forKey: .hoverDelay) ?? hoverDelay
        collapseDelay = try values.decodeIfPresent(Double.self, forKey: .collapseDelay) ?? collapseDelay
        animationSpeed = try values.decodeIfPresent(Double.self, forKey: .animationSpeed) ?? animationSpeed
        expandedWidth = try values.decodeIfPresent(Double.self, forKey: .expandedWidth) ?? expandedWidth
        showCompactActivity = try values.decodeIfPresent(Bool.self, forKey: .showCompactActivity) ?? showCompactActivity
        showInFullScreen = try values.decodeIfPresent(Bool.self, forKey: .showInFullScreen) ?? showInFullScreen
        showOnUnnotchedDisplay = try values.decodeIfPresent(Bool.self, forKey: .showOnUnnotchedDisplay) ?? showOnUnnotchedDisplay
        respectReduceMotion = try values.decodeIfPresent(Bool.self, forKey: .respectReduceMotion) ?? respectReduceMotion
        chargingAlerts = try values.decodeIfPresent(Bool.self, forKey: .chargingAlerts) ?? chargingAlerts
        musicEnabled = try values.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? musicEnabled
        musicProvider = try values.decodeIfPresent(MusicProvider.self, forKey: .musicProvider) ?? musicProvider
        timerEnabled = try values.decodeIfPresent(Bool.self, forKey: .timerEnabled) ?? timerEnabled
        batteryEnabled = try values.decodeIfPresent(Bool.self, forKey: .batteryEnabled) ?? batteryEnabled
        filesEnabled = try values.decodeIfPresent(Bool.self, forKey: .filesEnabled) ?? filesEnabled
        keepAwakeEnabled = try values.decodeIfPresent(Bool.self, forKey: .keepAwakeEnabled) ?? keepAwakeEnabled
        playTimerSound = try values.decodeIfPresent(Bool.self, forKey: .playTimerSound) ?? playTimerSound
        timerNotifications = try values.decodeIfPresent(Bool.self, forKey: .timerNotifications) ?? timerNotifications
        shortcut = try values.decodeIfPresent(GlobalShortcut.self, forKey: .shortcut) ?? shortcut
    }

    static let storageKey = "halo.preferences.v1"
    static func load(from defaults: UserDefaults = .standard) -> Preferences {
        guard let data = defaults.data(forKey: storageKey), let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return decoded
    }
    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

struct PowerSnapshot: Equatable {
    var percent = 100
    var onAC = false
    var charging = false
    var available = false
    var minutesToFull: Int?
    var status: String {
        guard available else { return "No battery" }
        if charging { return "Charging" }
        if onAC { return percent >= 99 ? "Fully charged" : "Connected to power" }
        return "On battery"
    }
    var symbol: String { onAC ? "battery.100percent.bolt" : (percent <= 20 ? "battery.25percent" : "battery.100percent") }
}

struct SystemVolumeSnapshot: Equatable {
    var outputID: UInt32 = 0
    var outputName = "Audio output"
    var volume: Double = 0
    var muted = false
    var available = false
    var error: String?
    var displayedVolume: Double { muted ? 0 : volume }
    var help: String {
        error ?? (available ? "System volume · \(outputName)" : "Use \(outputName)’s own volume controls.")
    }
}

struct MediaSnapshot: Equatable {
    var trackID = ""
    var title = "Nothing playing"
    var artist = ""
    var album = ""
    var artworkURL: URL?
    var playing = false
    var available = false
    var duration: Double = 0
    var position: Double = 0
    var provider: MusicProvider = .spotify
    var message = "Connect Spotify or Apple Music to bring your music here."
    var observedAt = Date()
    func elapsed(at date: Date = Date()) -> Double {
        min(max(0, position + (playing ? date.timeIntervalSince(observedAt) : 0)), max(0, duration))
    }
}

struct TimerSession: Codable, Equatable {
    enum Phase: String, Codable { case idle, running, paused, finished }
    var phase: Phase = .idle
    var duration: TimeInterval = 25 * 60
    var remainingWhenPaused: TimeInterval = 25 * 60
    var deadline: Date?
    var label = "Focus"

    func remaining(at now: Date = Date()) -> TimeInterval {
        switch phase {
        case .running: return max(0, deadline?.timeIntervalSince(now) ?? 0)
        case .finished: return 0
        case .paused: return remainingWhenPaused
        case .idle: return duration
        }
    }
    var active: Bool { phase == .running || phase == .paused }
    mutating func start(minutes: Int, label: String = "Focus", now: Date = Date()) {
        duration = Double(max(1, min(minutes, 180))) * 60
        remainingWhenPaused = duration
        deadline = now.addingTimeInterval(duration)
        self.label = label
        phase = .running
    }
    mutating func pause(at now: Date = Date()) {
        guard phase == .running else { return }
        remainingWhenPaused = remaining(at: now)
        deadline = nil
        phase = remainingWhenPaused > 0 ? .paused : .finished
    }
    mutating func resume(at now: Date = Date()) {
        guard phase == .paused else { return }
        deadline = now.addingTimeInterval(remainingWhenPaused)
        phase = .running
    }
    @discardableResult mutating func advance(to now: Date = Date()) -> Bool {
        guard phase == .running, remaining(at: now) <= 0 else { return false }
        phase = .finished
        deadline = nil
        return true
    }
    mutating func reset() { phase = .idle; deadline = nil; remainingWhenPaused = duration }
}

struct DisplayGeometry: Equatable {
    var screenFrame: CGRect
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool
    var centerX: CGFloat

    static func make(frame: CGRect, topInset: CGFloat, left: CGRect?, right: CGRect?) -> Self {
        if topInset > 0, let left, let right, right.minX > left.maxX {
            return Self(screenFrame: frame, notchWidth: right.minX - left.maxX, notchHeight: topInset, hasNotch: true, centerX: (left.maxX + right.minX) / 2)
        }
        return Self(screenFrame: frame, notchWidth: 156, notchHeight: 30, hasNotch: false, centerX: frame.midX)
    }
    static func read(_ screen: NSScreen) -> Self {
        make(frame: screen.frame, topInset: screen.safeAreaInsets.top, left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea)
    }
    func expandedWidth(preference: Double) -> CGFloat {
        min(max(CGFloat(preference), notchWidth + 100), screenFrame.width - 40)
    }
}

func clockString(_ seconds: TimeInterval) -> String {
    let value = max(0, Int(ceil(seconds)))
    return String(format: "%02d:%02d", value / 60, value % 60)
}
