import Foundation
import CoreAudio
import AudioToolbox

final class AudioSensor: Sensor {
    let id = "audio"
    let isEnabled: Bool
    let pollInterval: TimeInterval

    /// Called when audio state changes (from property listeners) so SensorManager can publish immediately
    var onStateChange: (() -> Void)?

    private var listenerBlocks: [(AudioObjectID, AudioObjectPropertyAddress)] = []

    init(config: SensorConfig) {
        self.isEnabled = config.enabled
        self.pollInterval = TimeInterval(config.pollInterval)
    }

    deinit {
        removeListeners()
    }

    // MARK: - Polling

    func poll() async throws -> [String: String] {
        var results: [String: String] = [:]

        if let volume = Self.getOutputVolume() {
            results["volume"] = String(Int(volume * 100))
        }
        results["mute"] = Self.getOutputMute() ? "ON" : "OFF"

        if let outputName = Self.getDefaultDeviceName(forInput: false) {
            results["audio_output"] = outputName
        }
        if let inputName = Self.getDefaultDeviceName(forInput: true) {
            results["audio_input"] = inputName
        }

        return results
    }

    // MARK: - Discovery Configs

    func discoveryConfigs(deviceId: String, baseTopic: String, discoveryPrefix: String, deviceName: String) -> [MQTTDiscoveryConfig] {
        let device = MQTTDiscoveryConfig.deviceObject(deviceId: deviceId, deviceName: deviceName)
        let availability = "\(baseTopic)/\(deviceId)/availability"

        return [
            // Volume — number entity
            MQTTDiscoveryConfig(
                topic: "\(discoveryPrefix)/number/\(deviceId)_volume/config",
                payload: [
                    "name": "Volume",
                    "unique_id": "\(deviceId)_volume",
                    "state_topic": "\(baseTopic)/\(deviceId)/sensor/volume/state",
                    "command_topic": "\(baseTopic)/\(deviceId)/command/volume/set",
                    "min": 0,
                    "max": 100,
                    "step": 1,
                    "unit_of_measurement": "%",
                    "icon": "mdi:volume-high",
                    "availability_topic": availability,
                    "device": device,
                ]
            ),
            // Mute — switch entity
            MQTTDiscoveryConfig(
                topic: "\(discoveryPrefix)/switch/\(deviceId)_mute/config",
                payload: [
                    "name": "Mute",
                    "unique_id": "\(deviceId)_mute",
                    "state_topic": "\(baseTopic)/\(deviceId)/sensor/mute/state",
                    "command_topic": "\(baseTopic)/\(deviceId)/command/mute/set",
                    "payload_on": "ON",
                    "payload_off": "OFF",
                    "state_on": "ON",
                    "state_off": "OFF",
                    "icon": "mdi:volume-mute",
                    "availability_topic": availability,
                    "device": device,
                ]
            ),
            // Audio Output Device — sensor entity
            MQTTDiscoveryConfig(
                topic: "\(discoveryPrefix)/sensor/\(deviceId)_audio_output/config",
                payload: [
                    "name": "Audio Output Device",
                    "unique_id": "\(deviceId)_audio_output",
                    "state_topic": "\(baseTopic)/\(deviceId)/sensor/audio_output/state",
                    "icon": "mdi:speaker",
                    "availability_topic": availability,
                    "device": device,
                ]
            ),
            // Audio Input Device — sensor entity
            MQTTDiscoveryConfig(
                topic: "\(discoveryPrefix)/sensor/\(deviceId)_audio_input/config",
                payload: [
                    "name": "Audio Input Device",
                    "unique_id": "\(deviceId)_audio_input",
                    "state_topic": "\(baseTopic)/\(deviceId)/sensor/audio_input/state",
                    "icon": "mdi:microphone",
                    "availability_topic": availability,
                    "device": device,
                ]
            ),
        ]
    }

    // MARK: - Property Listeners

    func installListeners() {
        let outputDevice = Self.getDefaultOutputDevice()
        let inputDevice = Self.getDefaultInputDevice()

        // Listen for volume changes on output device
        if let device = outputDevice {
            var volumeAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            addListener(device: device, address: &volumeAddr)

            var muteAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            addListener(device: device, address: &muteAddr)
        }

        // Listen for default device changes
        var defaultOutputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        addListener(device: AudioObjectID(kAudioObjectSystemObject), address: &defaultOutputAddr)

        var defaultInputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        addListener(device: AudioObjectID(kAudioObjectSystemObject), address: &defaultInputAddr)

        if outputDevice != nil || inputDevice != nil {
            Log.info("Installed CoreAudio property listeners", category: .sensor)
        }
    }

    func removeListeners() {
        for (device, var address) in listenerBlocks {
            AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, listenerBlock)
        }
        listenerBlocks.removeAll()
    }

    private lazy var listenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.onStateChange?()
    }

    private func addListener(device: AudioObjectID, address: inout AudioObjectPropertyAddress) {
        let status = AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, listenerBlock)
        if status == noErr {
            listenerBlocks.append((device, address))
        } else {
            Log.warning("Failed to add audio listener for selector \(address.mSelector): \(status)", category: .sensor)
        }
    }

    // MARK: - CoreAudio Helpers

    static func getDefaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceId: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceId
        )
        guard status == noErr, deviceId != kAudioObjectUnknown else { return nil }
        return deviceId
    }

    static func getDefaultInputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceId: AudioObjectID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceId
        )
        guard status == noErr, deviceId != kAudioObjectUnknown else { return nil }
        return deviceId
    }

    static func getOutputVolume() -> Float32? {
        guard let device = getDefaultOutputDevice() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)

        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        guard status == noErr else { return nil }
        return max(0, min(1, volume))
    }

    static func getOutputMute() -> Bool {
        guard let device = getDefaultOutputDevice() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        guard status == noErr else { return false }
        return muted != 0
    }

    static func getDefaultDeviceName(forInput: Bool) -> String? {
        let device: AudioObjectID?
        if forInput {
            device = getDefaultInputDevice()
        } else {
            device = getDefaultOutputDevice()
        }
        guard let device = device else { return nil }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size)
        guard status == noErr else { return nil }

        var nameRef: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &nameRef)
        guard status == noErr, let cfName = nameRef?.takeRetainedValue() else { return nil }
        return cfName as String
    }

    // MARK: - CoreAudio Setters (used by AudioActions)

    static func setOutputVolume(_ volume: Float32) -> Bool {
        guard let device = getDefaultOutputDevice() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol = max(0, min(1, volume))
        let size = UInt32(MemoryLayout<Float32>.size)

        let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &vol)
        return status == noErr
    }

    static func setOutputMute(_ mute: Bool) -> Bool {
        guard let device = getDefaultOutputDevice() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = mute ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        return status == noErr
    }
}
