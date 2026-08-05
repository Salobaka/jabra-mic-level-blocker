import Foundation
import CoreAudio
import CoreAudioTypes
import AudioToolbox
import Cocoa

private struct GainProperty: Equatable {
    let useVirtualMain: Bool
    let element: AudioObjectPropertyElement

    func address() -> AudioObjectPropertyAddress {
        if useVirtualMain {
            return AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: 0
            )
        }
        return AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
    }
}

// Candidate gain properties probed in priority order. VirtualMainVolume first
// because it is the OS Input Settings UI source of truth for Bluetooth devices.
private let gainPropertyCandidates: [GainProperty] = [
    GainProperty(useVirtualMain: true, element: 0),
    GainProperty(useVirtualMain: false, element: 0),
    GainProperty(useVirtualMain: false, element: 1)
]

final class AudioDeviceManager: ObservableObject {
    static let minimumGain: Float = 0.10
    static let gainTolerance: Float = 0.005

    @Published var jabraDevice: AudioDeviceID?
    @Published var jabraName: String = "Jabra Elite 85h"
    @Published var inputGain: Double = 0.5
    @Published var currentDeviceGain: Double = 0.5
    @Published var lockVolume: Bool = true
    @Published var bluetoothPermission: PermissionStatus = BluetoothPermission.shared.status
    @Published var gainIsWritable: Bool = false

    private var propertyListener: AudioObjectPropertyListenerBlock?
    private var volumeEnforcementTimer: Timer?
    private var permissionRefreshTimer: Timer?
    private var isReapplyingVolume = false
    private var lastEnforceLogTime: Date = .distantPast
    private let enforceLogThrottle: TimeInterval = 1.0

    // Confirmed-writable gain properties for the current device session.
    // Reset on device change. Populated by setInputGain via write-then-readback.
    private var writableGainProperties: [GainProperty] = []
    private var failedWriteCount: Int = 0
    private let maxFailedWrites: Int = 3

    init() {
        UserDefaults.standard.removeObject(forKey: "showDockIcon")
        refreshDevices()
        setupDeviceChangeListener()
        refreshBluetoothPermission()
        startPermissionAutoRefresh()
    }

    // MARK: - Permission

    func refreshBluetoothPermission() {
        bluetoothPermission = BluetoothPermission.shared.status
    }

    private func startPermissionAutoRefresh() {
        stopPermissionAutoRefresh()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshBluetoothPermission()
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        permissionRefreshTimer = t
    }

    private func stopPermissionAutoRefresh() {
        permissionRefreshTimer?.invalidate()
        permissionRefreshTimer = nil
    }

    func requestBluetoothAccess() {
        BluetoothPermission.shared.request { [weak self] status in
            DispatchQueue.main.async {
                self?.bluetoothPermission = status
                self?.refreshDevices()
            }
        }
    }

    func openBluetoothSettings() {
        BluetoothPermission.shared.openSettings()
    }

    func requestBluetoothAndOpenSettings() {
        requestBluetoothAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.openBluetoothSettings()
        }
    }

    func revealAppInFinder() {
        let bundleURL = Bundle.main.bundleURL
        AppLogger.shared.log("Permissions: revealing \(bundleURL.path) in Finder")
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    func resetTCCForBluetooth() {
        AppLogger.shared.log("Permissions: tccutil reset BluetoothAll jabra-mic-level-handler")
        Process.launchedProcess(launchPath: "/usr/bin/tccutil", arguments: ["reset", "BluetoothAll", "jabra-mic-level-handler"])
    }

    // MARK: - Device discovery

    func refreshDevices() {
        AppLogger.shared.log("refreshDevices called")
        let previousDevice = jabraDevice
        if let device = AudioDeviceDiscovery.findJabraDevice() {
            let deviceChanged = previousDevice != device.id
            let isFirstDiscovery = previousDevice == nil

            AppLogger.shared.log("Found Jabra device: \(device.name) (id=\(device.id), first=\(isFirstDiscovery), changed=\(deviceChanged))")

            jabraDevice = device.id
            jabraName = device.name
            gainIsWritable = deviceSupportsGain(device.id)

            // Reset per-device enforcement state for the new device session.
            writableGainProperties = []
            failedWriteCount = 0

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
        } else {
            AppLogger.shared.log("No Jabra device found")
            jabraDevice = nil
            gainIsWritable = false
            stopVolumeEnforcement()
        }
    }

    // MARK: - Gain helpers

    private func mutePropertyAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
    }

    private func deviceSupportsGain(_ device: AudioDeviceID) -> Bool {
        for candidate in gainPropertyCandidates {
            var address = candidate.address()
            if AudioObjectHasProperty(device, &address) { return true }
        }
        return false
    }

    // Read gain, preferring confirmed-writable properties (they reflect what
    // we and the OS actually set). Falls back to any existing property if no
    // write has been confirmed yet.
    func getInputGain(for device: AudioDeviceID) -> Float {
        // Prefer confirmed-writable, VirtualMainVolume first.
        for candidate in gainPropertyCandidates where writableGainProperties.contains(candidate) {
            var address = candidate.address()
            if AudioObjectHasProperty(device, &address) {
                if let value = readGain(device: device, address: address) { return value }
            }
        }
        // Fallback: any existing candidate, VirtualMainVolume first.
        for candidate in gainPropertyCandidates {
            var address = candidate.address()
            if AudioObjectHasProperty(device, &address) {
                if let value = readGain(device: device, address: address) { return value }
            }
        }
        return 0.5
    }

    private func readGain(device: AudioDeviceID, address: AudioObjectPropertyAddress) -> Float? {
        var addr = address
        var gain: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &gain)
        return status == noErr ? gain : nil
    }

    private func writeGain(device: AudioDeviceID, address: AudioObjectPropertyAddress, value: Float) -> Bool {
        var addr = address
        var v = value
        let size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectSetPropertyData(device, &addr, 0, nil, size, &v)
        return status == noErr
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

    // Write to all existing candidate properties, then verify which ones stuck.
    // Confirmed-writable properties are remembered for subsequent reads.
    func setInputGain(_ gain: Float, for device: AudioDeviceID) {
        let value = max(min(gain, 1.0), 0.0)

        // Ensure device is not muted while we are running.
        setMute(false, for: device)

        var confirmed: [GainProperty] = []

        for candidate in gainPropertyCandidates {
            var address = candidate.address()
            guard AudioObjectHasProperty(device, &address) else { continue }

            _ = writeGain(device: device, address: address, value: value)

            // Read back to confirm the write actually took effect.
            if let readback = readGain(device: device, address: address),
               abs(readback - value) <= Self.gainTolerance {
                confirmed.append(candidate)
            }
        }

        if !confirmed.isEmpty {
            writableGainProperties = confirmed
        }
    }

    func setInputGainFromUI(_ value: Double) {
        inputGain = max(value, Double(Self.minimumGain))
        // User moved the slider — re-arm enforcement in case it had backed off.
        failedWriteCount = 0
        if jabraDevice != nil && !gainIsWritable {
            gainIsWritable = deviceSupportsGain(jabraDevice!)
            if gainIsWritable { startVolumeEnforcement() }
        }
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
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.enforceVolume()
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        volumeEnforcementTimer = t
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

        guard abs(current - target) > Self.gainTolerance else {
            // In sync — reset failure counter.
            failedWriteCount = 0
            return
        }

        let now = Date()
        if now.timeIntervalSince(lastEnforceLogTime) >= enforceLogThrottle {
            AppLogger.shared.log("Enforcing gain: current=\(current), target=\(target), userTarget=\(userTarget), locked=\(lockVolume), confirmedProps=\(writableGainProperties.count)")
            lastEnforceLogTime = now
        }

        isReapplyingVolume = true
        setInputGain(target, for: device)
        isReapplyingVolume = false

        // Read back via the same (now possibly confirmed-writable) path.
        let readback = getInputGain(for: device)

        if abs(readback - target) <= Self.gainTolerance {
            failedWriteCount = 0
        } else {
            failedWriteCount += 1
            if now.timeIntervalSince(lastEnforceLogTime) >= enforceLogThrottle {
                AppLogger.shared.log("Gain write did not stick: readback=\(readback), target=\(target), failedCount=\(failedWriteCount)/\(maxFailedWrites)")
            }

            if failedWriteCount >= maxFailedWrites {
                AppLogger.shared.log("Gain write not sticking after \(maxFailedWrites) attempts — device may be hardware-controlled. Enforcement stopped.")
                DispatchQueue.main.async { [weak self] in
                    self?.gainIsWritable = false
                }
                stopVolumeEnforcement()
            }
        }
    }

    // MARK: - Device change listener

    private func setupDeviceChangeListener() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }
        self.propertyListener = listener

        var defaultInputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, nil, listener)

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, nil, listener)
    }

    deinit {
        stopVolumeEnforcement()
        stopPermissionAutoRefresh()
        if let listener = propertyListener {
            var defaultInputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, nil, listener)

            var devicesAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devicesAddress, nil, listener)
        }
    }
}
