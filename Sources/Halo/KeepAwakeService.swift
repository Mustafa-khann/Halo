import AppKit
import Combine
import IOKit.pwr_mgt

enum AwakeDuration: Int, CaseIterable, Identifiable {
    case fifteen = 15, thirty = 30, hour = 60, twoHours = 120, untilStopped = 0
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .fifteen: return "15 min"
        case .thirty: return "30 min"
        case .hour: return "1 hour"
        case .twoHours: return "2 hours"
        case .untilStopped: return "Until stopped"
        }
    }
    var seconds: TimeInterval? { self == .untilStopped ? nil : Double(rawValue * 60) }
}

struct AwakeSession: Equatable {
    var active = false
    var deadline: Date?
    var keepDisplayAwake = true
    func remaining(at date: Date) -> TimeInterval? { deadline.map { max(0, $0.timeIntervalSince(date)) } }
    func expired(at date: Date) -> Bool { active && deadline.map { $0 <= date } == true }
}

@MainActor final class KeepAwakeService: ObservableObject {
    @Published private(set) var session = AwakeSession()
    @Published private(set) var now = Date()
    @Published private(set) var error: String?
    private var assertions: [IOPMAssertionID] = []
    private var ticker: Timer?

    func start(duration: AwakeDuration, keepDisplayAwake: Bool) {
        stop()
        error = nil
        let started = Date()
        let types = [kIOPMAssertionTypePreventUserIdleSystemSleep] + (keepDisplayAwake ? [kIOPMAssertionTypePreventUserIdleDisplaySleep] : [])
        for type in types {
            var properties: [String: Any] = [
                kIOPMAssertionTypeKey: type,
                kIOPMAssertionNameKey: "Halo Keep awake",
                kIOPMAssertionLevelKey: kIOPMAssertionLevelOn
            ]
            if let seconds = duration.seconds {
                // The OS timeout also ends the assertion if Halo's run loop stalls.
                properties[kIOPMAssertionTimeoutKey] = seconds
                properties[kIOPMAssertionTimeoutActionKey] = kIOPMAssertionTimeoutActionRelease
            }
            var assertion = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &assertion)
            guard result == kIOReturnSuccess else {
                stop()
                error = "Your Mac could not start Keep awake. Try again."
                return
            }
            assertions.append(assertion)
        }
        session = AwakeSession(active: true, deadline: duration.seconds.map { started.addingTimeInterval($0) }, keepDisplayAwake: keepDisplayAwake)
        now = started
        if session.deadline != nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            if let ticker { RunLoop.main.add(ticker, forMode: .common) }
        }
    }
    func tick(at date: Date = Date()) {
        now = date
        if session.expired(at: date) { stop() }
    }
    func stop() {
        ticker?.invalidate(); ticker = nil
        for assertion in assertions { IOPMAssertionRelease(assertion) }
        assertions.removeAll()
        session = AwakeSession()
    }
}
