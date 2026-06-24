import Foundation
import CoreAudio
import AVFoundation
import CoreAudioTypes
import AudioToolbox

final class AudioDeviceManager: ObservableObject {
    static let minimumGain: Float = 0.10
    static let gainTolerance: Float = 0.005

    @Published var jabraDevice: AudioDeviceID?
    @Published var jabraName: String = "Jabra Elite 85h"
    @Published var inputGain: Double = 0.5
    @Published var isRunning: Bool = false
    @Published var level: Float = 0.0
    @Published var lockVolume: Bool = true
    @Published var authorizationStatus: MicrophoneAuthorization = MicrophonePermission.shared.status
    @Published var gainIsWritable: Bool = false

    private var levelMeter: LevelMeter?
    private var previousDefaultInput: AudioDeviceID?
    private var propertyListener: AudioObjectPropertyListenerBlock?
    private var volumeEnforcementTimer: Timer?
    private var isReapplyingVolume = false
    private let queue = DispatchQueue(label: "com.jabrainputtracker.audio", qos: .userInitiated)

    init() {
        refreshDevices()
        setupDeviceChangeListener()
    }

    // MARK: - Permission

    func requestMicrophoneAccess() {
        MicrophonePermission.shared.request { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
                if status == .authorized {
                    self?.refreshDevices()
                }
            }
        }
    }

    // MARK: - Device discovery

    func refreshDevices() {
        let previousDevice = jabraDevice
        if let device = findJabraDevice() {
            let wasRunning = isRunning
            let deviceChanged = previousDevice != device.id
            jabraDevice = device.id
            jabraName = device.name
            inputGain = Double(getInputGain(for: device.id))
            gainIsWritable = deviceSupportsGain(device.id)
            updateVolumeEnforcement()
            if wasRunning && deviceChanged {
                startMetering()
            }
        } else {
            jabraDevice = nil
            gainIsWritable = false
            if isRunning {
                stopMetering()
            }
            stopVolumeEnforcement()
        }
    }

    private func findJabraDevice() -> (id: AudioDeviceID, name: String)? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size)
        guard status == noErr else { return nil }

        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &size, &deviceIDs)
        guard status == noErr else { return nil }

        // Prefer exact "85h" match, fallback to any Jabra Elite.
        var fallback: (id: AudioDeviceID, name: String)?
        for id in deviceIDs {
            guard let name = getDeviceName(id: id) else { continue }
            guard getInputChannels(id: id) > 0 else { continue }
            guard isBluetoothDevice(id: id) else { continue }
            let lower = name.lowercased()
            guard lower.contains("jabra") else { continue }
            if lower.contains("85h") {
                return (id, name)
            }
            if lower.contains("elite") && fallback == nil {
                fallback = (id, name)
            }
        }
        return fallback
    }

    private func isBluetoothDevice(id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(id, &address) else { return false }
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transportType)
        guard status == noErr else { return false }
        return transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    private func getDeviceName(id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &cfName) { namePtr in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, namePtr)
        }
        guard status == noErr, let name = cfName else { return nil }
        return name as String
    }

    private func getInputChannels(id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size)
        guard status == noErr else { return 0 }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferList.deallocate() }
        status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, bufferList)
        guard status == noErr else { return 0 }

        var channels = 0
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        for buffer in buffers {
            channels += Int(buffer.mNumberChannels)
        }
        return channels
    }

    // MARK: - Gain helpers

    private func volumePropertyAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
    }

    private func virtualMainVolumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: 0
        )
    }

    private func mutePropertyAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
    }

    private func deviceSupportsGain(_ device: AudioDeviceID) -> Bool {
        for element in [AudioObjectPropertyElement(0), AudioObjectPropertyElement(1)] {
            var address = volumePropertyAddress(element: element)
            if AudioObjectHasProperty(device, &address) { return true }
        }
        var address = virtualMainVolumeAddress()
        if AudioObjectHasProperty(device, &address) { return true }
        return false
    }

    func getInputGain(for device: AudioDeviceID) -> Float {
        for element in [AudioObjectPropertyElement(0), AudioObjectPropertyElement(1)] {
            var address = volumePropertyAddress(element: element)
            if AudioObjectHasProperty(device, &address) {
                var gain: Float = 0
                var size = UInt32(MemoryLayout<Float>.size)
                let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &gain)
                if status == noErr { return gain }
            }
        }

        var address = virtualMainVolumeAddress()
        if AudioObjectHasProperty(device, &address) {
            var gain: Float = 0
            var size = UInt32(MemoryLayout<Float>.size)
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &gain)
            if status == noErr { return gain }
        }
        return 0.5
    }

    private func setMute(_ muted: Bool, for device: AudioDeviceID) {
        var mutedValue: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)

        for element in [AudioObjectPropertyElement(0), AudioObjectPropertyElement(1)] {
            var address = mutePropertyAddress(element: element)
            if AudioObjectHasProperty(device, &address) {
                AudioObjectSetPropertyData(device, &address, 0, nil, size, &mutedValue)
            }
        }
    }

    func setInputGain(_ gain: Float, for device: AudioDeviceID) {
        var value = max(min(gain, 1.0), 0.0)
        let size = UInt32(MemoryLayout<Float>.size)

        // Ensure device is not muted while we are running.
        setMute(false, for: device)

        for element in [AudioObjectPropertyElement(0), AudioObjectPropertyElement(1)] {
            var address = volumePropertyAddress(element: element)
            if AudioObjectHasProperty(device, &address) {
                AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
            }
        }

        var address = virtualMainVolumeAddress()
        if AudioObjectHasProperty(device, &address) {
            AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        }
    }

    func setInputGainFromUI(_ value: Double) {
        inputGain = value
        if let device = jabraDevice {
            setInputGain(Float(value), for: device)
        }
    }

    func setLockVolume(_ value: Bool) {
        lockVolume = value
        updateVolumeEnforcement()
    }

    // MARK: - Volume enforcement

    private func updateVolumeEnforcement() {
        if jabraDevice != nil {
            startVolumeEnforcement()
        } else {
            stopVolumeEnforcement()
        }
    }

    private func startVolumeEnforcement() {
        stopVolumeEnforcement()
        volumeEnforcementTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.enforceVolume()
        }
    }

    private func stopVolumeEnforcement() {
        volumeEnforcementTimer?.invalidate()
        volumeEnforcementTimer = nil
    }

    private func enforceVolume() {
        guard let device = jabraDevice, !isReapplyingVolume else { return }

        let current = getInputGain(for: device)
        let userTarget = Float(inputGain)

        // Always enforce absolute minimum so we are never fully muted.
        let desiredTarget = max(userTarget, Self.minimumGain)

        // If locked, keep the user-selected level; otherwise still enforce minimum.
        let target: Float = lockVolume ? desiredTarget : max(current, Self.minimumGain)

        guard abs(current - target) > Self.gainTolerance else { return }

        isReapplyingVolume = true
        setInputGain(target, for: device)
        DispatchQueue.main.async { [weak self] in
            self?.inputGain = Double(self?.getInputGain(for: device) ?? target)
        }
        isReapplyingVolume = false
    }

    // MARK: - Default device switching

    func startMetering() {
        guard authorizationStatus == .authorized else {
            requestMicrophoneAccess()
            return
        }
        guard let device = jabraDevice else { return }

        stopMetering()
        previousDefaultInput = getDefaultInputDevice()
        setDefaultInputDevice(device)

        // Give CoreAudio a moment to propagate the default-input change before
        // AVAudioEngine initializes its input node. This avoids the engine
        // caching the previous default format.
        queue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self, self.jabraDevice == device else { return }

            let meter = LevelMeter()
            meter.levelUpdate = { [weak self] level in
                DispatchQueue.main.async {
                    self?.level = level
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.levelMeter = meter
                self?.isRunning = true
            }
            meter.start()
        }
    }

    func stopMetering() {
        levelMeter?.stop()
        levelMeter = nil
        isRunning = false
        level = 0
        if let previous = previousDefaultInput {
            setDefaultInputDevice(previous)
            previousDefaultInput = nil
        }
    }

    private func setupDeviceChangeListener() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }
        self.propertyListener = listener

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, listener)

        address.mSelector = kAudioHardwarePropertyDevices
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, listener)
    }

    private func getDefaultInputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func setDefaultInputDevice(_ deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = deviceID
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device)
    }

    deinit {
        stopMetering()
    }
}
