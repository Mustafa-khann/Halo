import AppKit
import CoreAudio

@MainActor final class SystemVolumeService {
    private let receive: (SystemVolumeSnapshot) -> Void
    private var started = false
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var volumeAddresses: [AudioObjectPropertyAddress] = []
    private var muteAddresses: [AudioObjectPropertyAddress] = []
    private var listenedAddresses: [AudioObjectPropertyAddress] = []
    private var channelRatios: [Float32] = []
    private var snapshot = SystemVolumeSnapshot()
    private var defaultAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private lazy var defaultListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        Task { @MainActor in if self?.started == true { self?.connect() } }
    }
    private lazy var volumeListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        Task { @MainActor in if self?.started == true { self?.refresh() } }
    }

    init(receive: @escaping (SystemVolumeSnapshot) -> Void) { self.receive = receive }

    func start() {
        guard !started else { return }
        started = true
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, .main, defaultListener)
        connect()
    }
    func stop() {
        guard started else { return }
        started = false
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, .main, defaultListener)
        disconnect()
    }
    private func defaultDevice() -> AudioObjectID {
        var output = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, &size, &output)
        return output
    }
    private func address(_ selector: AudioObjectPropertySelector, channel: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput, mElement: channel)
    }
    private func exists(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(device, &address)
    }
    private func writable(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }
    private func controls(_ selector: AudioObjectPropertySelector, channels: [UInt32]) -> [AudioObjectPropertyAddress] {
        let main = address(selector)
        if exists(main) { return [main] }
        return channels.map { address(selector, channel: $0) }.filter(exists)
    }
    private func connect() {
        disconnect()
        device = defaultDevice()
        guard device != kAudioObjectUnknown else { receive(SystemVolumeSnapshot()); return }

        var stereo = [UInt32](repeating: 0, count: 2)
        var size = UInt32(MemoryLayout<UInt32>.size * stereo.count)
        var preferred = address(kAudioDevicePropertyPreferredChannelsForStereo)
        let status = stereo.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(device, &preferred, 0, nil, &size, $0.baseAddress!)
        }
        let channels = status == noErr ? Array(Set(stereo.filter { $0 > 0 })).sorted() : [1, 2]
        volumeAddresses = controls(kAudioDevicePropertyVolumeScalar, channels: channels)
        muteAddresses = controls(kAudioDevicePropertyMute, channels: channels)
        channelRatios = Array(repeating: 1, count: volumeAddresses.count)

        var name: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let nameStatus = AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name)
        let outputName = nameStatus == noErr ? (name?.takeRetainedValue() as String? ?? "Audio output") : "Audio output"
        snapshot = SystemVolumeSnapshot(outputID: device, outputName: outputName)

        for var property in volumeAddresses + muteAddresses {
            if AudioObjectAddPropertyListenerBlock(device, &property, .main, volumeListener) == noErr {
                listenedAddresses.append(property)
            }
        }
        refresh()
    }
    private func disconnect() {
        for var property in listenedAddresses {
            AudioObjectRemovePropertyListenerBlock(device, &property, .main, volumeListener)
        }
        listenedAddresses.removeAll()
        volumeAddresses.removeAll()
        muteAddresses.removeAll()
        channelRatios.removeAll()
        device = AudioObjectID(kAudioObjectUnknown)
    }
    private func volumeValues() -> [Float32] {
        volumeAddresses.compactMap { property in
            var property = property
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr, value.isFinite else { return nil }
            return min(max(0, value), 1)
        }
    }
    private func refresh(error: String? = nil) {
        let values = volumeValues()
        let maximum = values.max() ?? 0
        if maximum > 0, values.count == volumeAddresses.count {
            channelRatios = values.map { $0 / maximum }
        }
        let muted = muteAddresses.compactMap { property -> Bool? in
            var property = property
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr else { return nil }
            return value != 0
        }
        snapshot.volume = Double(maximum) * 100
        snapshot.muted = !muted.isEmpty && muted.allSatisfy { $0 }
        snapshot.available = !volumeAddresses.isEmpty && values.count == volumeAddresses.count && volumeAddresses.allSatisfy(writable)
        snapshot.error = error
        receive(snapshot)
    }
    func setVolume(_ percent: Double) {
        guard started, percent.isFinite else { return }
        if device != defaultDevice() { connect() }
        guard snapshot.available else { return }
        let scalar = Float32(min(max(0, percent), 100) / 100)
        var succeeded = true
        for (index, var property) in volumeAddresses.enumerated() {
            // Preserve the user's left/right balance on devices with channel controls.
            var value = scalar * channelRatios[index]
            let status = AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
            succeeded = succeeded && status == noErr
        }
        if scalar > 0, snapshot.muted {
            for var property in muteAddresses where writable(property) {
                var unmuted: UInt32 = 0
                let status = AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &unmuted)
                succeeded = succeeded && status == noErr
            }
        }
        refresh(error: succeeded ? nil : "Couldn’t change system volume. Try again.")
    }
}
