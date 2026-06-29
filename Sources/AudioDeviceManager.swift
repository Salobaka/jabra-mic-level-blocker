import Foundation
import CoreAudio
import AVFoundation
import CoreAudioTypes
import AudioToolbox
import Cocoa

final class AudioDeviceManager: ObservableObject {
    static let minimumGain: Float = 0.10
    static let gainTolerance: Float = 0.005

    @Published var jabraDevice: AudioDeviceID?
    @Published var jabraName: String = "Jabra Elite 85h"
    @Published var inputGain: Double = 0.5
    @Published var currentDeviceGain: Double = 0.5
    @Published var isRunning: Bool = false
    @Published var level: Float = 0.0
    @Published var lockVolume: Bool = true
    @Published var showDockIcon: Bool = true {
        didSet {
            applyDockIconPolicy()
            UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
        }
    }
    @Published var authorizationStatus: MicrophoneAuthorization = MicrophonePermission.shared.status
    @Published var gainIsWritable: Bool = false

    private var levelMeter: LevelMeter?
    private var previousDefaultInput: AudioDeviceID?
    private var propertyListener: AudioObjectPropertyListenerBlock?
    private var volumeEnforcementTimer: Timer?
    private var isReapplyingVolume = false
    private let queue = DispatchQueue(label: "com.jabrainputtracker.audio", qos: .userInitiated)

    init() {
        showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
        refreshDevices()
        setupDeviceChangeListener()
        applyDockIconPolicy()
    }

    private func applyDockIconPolicy() {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        NSApplication.shared.setActivationPolicy(policy)
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
        AppLogger.shared.log("refreshDevices called")
        let previousDevice = jabraDevice
        if let device = AudioDeviceDiscovery.findJabraDevice() {
            let wasRunning = isRunning
            let deviceChanged = previousDevice != device.id
            let isFirstDiscovery = previousDevice == nil

            AppLogger.shared.log("Found Jabra device: \(device.name) (id=\(device.id), first=\(isFirstDiscovery), changed=\(deviceChanged))")

            jabraDevice = device.id
            jabraName = device.name
            gainIsWritable = deviceSupportsGain(device.id)

            // On first discovery, seed the user target from the device's current gain.
            // After that, preserve the user's target; do not let other apps corrupt it.
            let deviceGain = Double(getInputGain(for: device.id))
            currentDeviceGain = deviceGain
            if isFirstDiscovery {
                inputGain = max(deviceGain, Double(Self.minimumGain))
            }

            updateVolumeEnforcement()

            // Re-apply the target immediately whenever a device appears or reappears.
            applyTargetGain()

            if wasRunning && deviceChanged {
                AppLogger.shared.log("Device changed while running, restarting metering")
                startMetering()
            }
        } else {
            AppLogger.shared.log("No Jabra device found")
            jabraDevice = nil
            gainIsWritable = false
            if isRunning {
                stopMetering()
            }
            stopVolumeEnforcement()
        }
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
        inputGain = max(value, Double(Self.minimumGain))
        applyTargetGain()
    }

    private func applyTargetGain() {
        guard let device = jabraDevice else { return }
        let target = Float(inputGain)
        setInputGain(target, for: device)
        // Reflect what the device actually reports without changing the user target.
        currentDeviceGain = Double(getInputGain(for: device))
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

        // Update the displayed current gain without corrupting the user target.
        DispatchQueue.main.async { [weak self] in
            self?.currentDeviceGain = Double(current)
        }

        guard abs(current - target) > Self.gainTolerance else { return }

        AppLogger.shared.log("Enforcing gain: current=\(current), target=\(target), userTarget=\(userTarget), locked=\(lockVolume)")

        isReapplyingVolume = true
        setInputGain(target, for: device)
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
        applyTargetGain()

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
