import AppKit
import Combine
import UserNotifications

@MainActor final class AppModel: ObservableObject {
    @Published var preferences = Preferences.load() {
        didSet {
            preferences.save()
            if preferences.musicEnabled != oldValue.musicEnabled || preferences.musicProvider != oldValue.musicProvider {
                mediaService.configure(enabled: preferences.musicEnabled, provider: preferences.musicProvider)
            }
            onPreferencesChanged?()
        }
    }
    @Published var power = PowerSnapshot()
    @Published var media = MediaSnapshot()
    @Published var systemVolume = SystemVolumeSnapshot()
    @Published var mediaControlError: String?
    @Published var timer: TimerSession
    @Published var now = Date()
    @Published var expanded = false
    @Published var pinned = false
    @Published var selectedTab: HaloTab = .overview
    @Published var geometry = DisplayGeometry.make(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), topInset: 0, left: nil, right: nil)
    @Published var chargingToast = false
    @Published var overlayEnabled = true
    @Published var shortcutAvailable = true
    var onPreferencesChanged: (() -> Void)?
    var onExpansionChanged: (() -> Void)?
    var showSettings: (() -> Void)?
    var powerService: PowerService!
    var mediaService: MediaService!
    var volumeService: SystemVolumeService!
    private var ticker: Timer?
    private var toastTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: "halo.timer.v1"), let saved = try? JSONDecoder().decode(TimerSession.self, from: data) {
            var restored = saved
            // A timer that expired while the app was closed must not alert on every launch.
            if restored.advance() { restored.reset() }
            timer = restored
        } else { timer = TimerSession() }
        powerService = PowerService { [weak self] snapshot in self?.updatePower(snapshot) }
        mediaService = MediaService(receive: { [weak self] snapshot in self?.media = snapshot },
                                    controlError: { [weak self] error in self?.mediaControlError = error })
        volumeService = SystemVolumeService { [weak self] snapshot in self?.systemVolume = snapshot }

    }

    func start() {
        powerService.start()
        volumeService.start()
        mediaService.configure(enabled: preferences.musicEnabled, provider: preferences.musicProvider)
        updateTicker()
    }
    func stop() {
        ticker?.invalidate()
        powerService.stop()
        volumeService.stop()
        mediaService.stop()
        persistTimer()
    }

    var tabs: [HaloTab] {
        [.overview] + (preferences.musicEnabled ? [.music] : []) + (preferences.timerEnabled || timer.active || timer.phase == .finished ? [.timer] : []) + (preferences.batteryEnabled ? [.power] : [])
    }
    var compactActivity: Bool {
        preferences.showCompactActivity && (chargingToast || timer.active || timer.phase == .finished || (preferences.musicEnabled && media.playing))
    }
    var currentWidth: CGFloat {
        if expanded { return geometry.expandedWidth(preference: preferences.expandedWidth) }
        return geometry.notchWidth + (compactActivity ? 96 : (geometry.hasNotch ? 6 : 0))
    }
    var currentHeight: CGFloat { expanded ? geometry.notchHeight + 250 : geometry.notchHeight + (geometry.hasNotch ? 2 : 0) }
    var reduceMotion: Bool { preferences.respectReduceMotion && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func open(pin: Bool = false, tab: HaloTab? = nil) {
        if let tab { selectedTab = tab }
        expanded = true
        pinned = pin
        onExpansionChanged?()
    }
    func close() { expanded = false; pinned = false; onExpansionChanged?() }
    func toggle() { expanded ? close() : open(pin: true) }
    func pin() { pinned.toggle(); onExpansionChanged?() }

    func startTimer(minutes: Int, label: String = "Focus") {
        timer.start(minutes: minutes, label: label)
        now = Date()
        persistTimer()
        updateTicker()
    }
    func pauseTimer() { timer.pause(); persistTimer(); updateTicker() }
    func resumeTimer() { timer.resume(); persistTimer(); updateTicker() }
    func resetTimer() { timer.reset(); persistTimer(); updateTicker() }

    private func updateTicker() {
        ticker?.invalidate()
        ticker = nil
        if timer.phase == .running {
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            if let ticker { RunLoop.main.add(ticker, forMode: .common) }
        }
    }
    func tick(at date: Date = Date()) {
        now = date
        if timer.advance(to: date) {
            persistTimer()
            updateTicker()
            open(pin: true, tab: .timer)
            if preferences.playTimerSound { NSSound(named: "Glass")?.play() }
            if preferences.timerNotifications {
                let content = UNMutableNotificationContent()
                content.title = "Time’s up"
                content.body = "Your \(timer.label.lowercased()) timer is complete."
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "halo.timer", content: content, trigger: nil))
            }
        }
    }
    private func persistTimer() {
        if let data = try? JSONEncoder().encode(timer) { UserDefaults.standard.set(data, forKey: "halo.timer.v1") }
    }
    private func updatePower(_ snapshot: PowerSnapshot) {
        let changed = power.available && snapshot.onAC != power.onAC
        power = snapshot
        if changed && preferences.chargingAlerts {
            chargingToast = true
            toastTask?.cancel()
            toastTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.chargingToast = false
            }
        }
    }
    func requestTimerNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] allowed, _ in
            Task { @MainActor in self?.preferences.timerNotifications = allowed }
        }
    }
}
