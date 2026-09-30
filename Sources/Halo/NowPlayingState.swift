import Foundation
import CoreFoundation

/// MediaRemote sends full records on item changes and small diffs between them.
struct NowPlayingState {
    private var values: [String: Any] = [:]
    private var artworkString: String?
    private var artwork: Data?

    mutating func consume(_ data: Data, at now: Date = Date()) throws -> MediaSnapshot {
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["type"] as? String == "data", let diff = event["diff"] as? Bool,
              let payload = event["payload"] as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if !diff { values.removeAll() }
        for (key, value) in payload {
            if value is NSNull { values.removeValue(forKey: key) }
            else { values[key] = value }
        }
        return snapshot(at: now)
    }

    static func decodeRecord(_ data: Data, at now: Date = Date()) throws -> MediaSnapshot {
        let object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        guard object is NSNull || object is [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        var state = NowPlayingState()
        state.values = object as? [String: Any] ?? [:]
        return state.snapshot(at: now)
    }

    private mutating func snapshot(at now: Date) -> MediaSnapshot {
        var result = MediaSnapshot()
        guard let pid = number("processIdentifier"), pid > 0, pid <= Double(Int32.max),
              let playing = values["playing"] as? Bool else {
            artworkString = nil; artwork = nil
            return result
        }
        result.available = true
        result.message = ""
        result.processID = Int32(pid)
        result.sourceBundleID = string("parentApplicationBundleIdentifier") ?? string("bundleIdentifier") ?? ""
        result.title = string("title") ?? "Now Playing"
        result.artist = string("artist") ?? ""
        result.album = string("album") ?? ""
        // A source without an item identifier still has a stable identity for seeking.
        result.trackID = [String(result.processID), result.sourceBundleID,
                          identifier("contentItemIdentifier"), identifier("uniqueIdentifier"),
                          result.title, result.artist, result.album].joined(separator: "\u{1F}")
        result.playing = playing
        result.duration = max(0, (number("durationMicros") ?? 0) / 1_000_000)
        result.position = max(0, (number("elapsedTimeMicros") ?? 0) / 1_000_000)
        result.playbackRate = max(0, min(16, number("playbackRate") ?? 1))
        if let timestamp = number("timestampEpochMicros") {
            result.observedAt = Date(timeIntervalSince1970: timestamp / 1_000_000)
        } else { result.observedAt = now }
        result.position = result.elapsed(at: now)
        result.observedAt = now
        let podcast = (string("mediaType") ?? "").localizedCaseInsensitiveContains("podcast")
        result.skipBackward = values["supportsRewind15Seconds"] as? Bool ?? podcast
        result.skipForward = values["supportsFastForward15Seconds"] as? Bool ?? podcast
        result.prohibitsSkip = values["prohibitsSkip"] as? Bool ?? false
        let encoded = string("artworkData")
        if encoded != artworkString {
            artworkString = encoded
            artwork = encoded.flatMap { $0.utf8.count <= 8_000_000 ? Data(base64Encoded: $0) : nil }
        }
        result.artworkData = artwork
        return result
    }

    private func string(_ key: String) -> String? {
        guard let value = values[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
    private func number(_ key: String) -> Double? {
        guard let value = values[key] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    private func identifier(_ key: String) -> String {
        string(key) ?? (values[key] as? NSNumber)?.stringValue ?? ""
    }
}

struct NowPlayingLineBuffer {
    static let maximumLineBytes = 12_000_000
    private var pending = Data()
    mutating func append(_ chunk: Data) throws -> [Data] {
        pending.append(chunk)
        var lines: [Data] = []
        while let newline = pending.firstIndex(of: 10) {
            guard newline - pending.startIndex <= Self.maximumLineBytes else { throw CocoaError(.fileReadTooLarge) }
            let line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            if !line.isEmpty { lines.append(line) }
        }
        guard pending.count <= Self.maximumLineBytes else { throw CocoaError(.fileReadTooLarge) }
        return lines
    }
}
