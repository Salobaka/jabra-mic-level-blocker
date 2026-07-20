import Foundation
import Cocoa
import CoreAudio
import IOBluetooth
import ApplicationServices

private let kCGEventTypeSystemDefinedValue: CGEventType = CGEventType(rawValue: 14)!
private let kCGEventTapLocationHIDValue: CGEventTapLocation = CGEventTapLocation(rawValue: 0)!

private func daisyMediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard type == kCGEventTypeSystemDefinedValue else {
        return Unmanaged.passUnretained(event)
    }

    guard let nsEvent = NSEvent(cgEvent: event) else {
        AppLogger.shared.log("Daisy: could not decode system media event")
        return Unmanaged.passUnretained(event)
    }

    let keyCode = (nsEvent.data1 & 0xFFFF0000) >> 16
    let keyFlags = nsEvent.data1 & 0xFFFF
    let keyState = (keyFlags & 0xFF00) >> 8
    let isDown = keyState == 0x0A

    guard keyCode == NX_KEYTYPE_PLAY else {
        return Unmanaged.passUnretained(event)
    }

    AppLogger.shared.log("Daisy: received Play/Pause media event state=\(keyState) data1=\(nsEvent.data1)")

    guard isDown else { return nil }

    guard let refcon = refcon else {
        return Unmanaged.passUnretained(event)
    }

    let controller = Unmanaged<DaisyMuteController>.fromOpaque(refcon).takeUnretainedValue()
    guard controller.isDaisyConnected else {
        return Unmanaged.passUnretained(event)
    }

    DispatchQueue.main.async {
        controller.toggleMute()
    }
    return nil
}

final class DaisyMuteController: ObservableObject {
    @Published var isDaisyConnected: Bool = false
    @Published var isDaisyPaired: Bool = false
    @Published var isMuted: Bool = false
    @Published var daisyName: String = "Daisy One"
    @Published var isTapActive: Bool = false

    private var propertyListener: AudioObjectPropertyListenerBlock?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapHealthTimer: Timer?
    private var feedbackSound: NSSound?

    private var tapCreationAttempts: Int = 0
    private let maxTapCreationAttempts: Int = 3

    init() {}

    func startMonitoring() {
        tapCreationAttempts = 0
        setupCGEventTap()
        startTapHealthCheck()
        refreshDaisyState()
        setupDeviceChangeListener()
    }

    deinit {
        stopTapHealthCheck()
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    // MARK: - Daisy detection

    private static func pairedDaisyDevices() -> [IOBluetoothDevice] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }
        return devices.filter { device in
            guard let name = device.name?.lowercased() else { return false }
            return name.contains("daisy")
        }
    }

    func refreshDaisyState() {
        let daisyDevices = Self.pairedDaisyDevices()
        let connected = daisyDevices.first(where: { $0.isConnected() })

        DispatchQueue.main.async { [weak self] in
            self?.isDaisyPaired = !daisyDevices.isEmpty
            if let connected = connected {
                self?.isDaisyConnected = true
                self?.daisyName = connected.name ?? "Daisy One"
            } else {
                self?.isDaisyConnected = false
                if let first = daisyDevices.first {
                    self?.daisyName = first.name ?? "Daisy One"
                }
            }
        }
    }

    private func setupDeviceChangeListener() {
        guard propertyListener == nil else { return }

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshDaisyState()
            }
        }
        self.propertyListener = listener

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, nil, listener)
    }

    // MARK: - Media key tap

    private func setupCGEventTap() {
        guard eventTap == nil else { return }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: kCGEventTapLocationHIDValue,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << kCGEventTypeSystemDefinedValue.rawValue),
            callback: daisyMediaKeyTapCallback,
            userInfo: selfPointer
        ) else {
            AppLogger.shared.log("Daisy: CGEventTap creation failed - Input Monitoring permission may be required")
            DispatchQueue.main.async { [weak self] in
                self?.isTapActive = false
            }
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        DispatchQueue.main.async { [weak self] in
            self?.isTapActive = true
        }
        AppLogger.shared.log("Daisy: CGEventTap installed")
    }

    private func startTapHealthCheck() {
        stopTapHealthCheck()
        tapHealthTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkTapHealth()
        }
    }

    private func stopTapHealthCheck() {
        tapHealthTimer?.invalidate()
        tapHealthTimer = nil
    }

    private func checkTapHealth() {
        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                AppLogger.shared.log("Daisy: CGEventTap re-enabled")
            }
            DispatchQueue.main.async { [weak self] in
                self?.isTapActive = CGEvent.tapIsEnabled(tap: tap)
            }
        } else if tapCreationAttempts < maxTapCreationAttempts {
            tapCreationAttempts += 1
            setupCGEventTap()
            DispatchQueue.main.async { [weak self] in
                self?.isTapActive = self?.eventTap != nil
            }
        } else {
            stopTapHealthCheck()
            DispatchQueue.main.async { [weak self] in
                self?.isTapActive = false
            }
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Mute control

    func toggleMute() {
        guard let defaultDevice = currentDefaultInputDevice() else {
            AppLogger.shared.log("Daisy mute: no default input device")
            return
        }

        let currentMute = getMute(for: defaultDevice)
        let newMute = !currentMute
        setMute(newMute, for: defaultDevice)

        DispatchQueue.main.async { [weak self] in
            self?.isMuted = newMute
        }

        AppLogger.shared.log("Daisy mute toggled: \(newMute ? "muted" : "unmuted")")
        playTone(muted: newMute)
    }

    func setMuted(_ muted: Bool) {
        guard let defaultDevice = currentDefaultInputDevice() else {
            AppLogger.shared.log("Daisy mute: no default input device")
            return
        }

        let currentMute = getMute(for: defaultDevice)
        guard currentMute != muted else {
            DispatchQueue.main.async { [weak self] in
                self?.isMuted = muted
            }
            return
        }

        setMute(muted, for: defaultDevice)
        DispatchQueue.main.async { [weak self] in
            self?.isMuted = muted
        }

        AppLogger.shared.log("Daisy mute set: \(muted ? "muted" : "unmuted")")
        playTone(muted: muted)
    }

    private func currentDefaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private func getMute(for device: AudioDeviceID) -> Bool {
        for element in [AudioObjectPropertyElement(0), AudioObjectPropertyElement(1)] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            if AudioObjectHasProperty(device, &address) {
                var muted: UInt32 = 0
                var size = UInt32(MemoryLayout<UInt32>.size)
                let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
                if status == noErr {
                    return muted != 0
                }
            }
        }
        return false
    }

    private func setMute(_ muted: Bool, for device: AudioDeviceID) {
        var mutedValue: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)

        for element in [AudioObjectPropertyElement(0), AudioObjectPropertyElement(1)] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: element
            )
            if AudioObjectHasProperty(device, &address) {
                AudioObjectSetPropertyData(device, &address, 0, nil, size, &mutedValue)
            }
        }
    }

    // MARK: - Feedback sound

    private func playTone(muted: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.feedbackSound?.stop()

            let name = NSSound.Name(muted ? "Basso" : "Pop")
            guard let sound = NSSound(named: name) else {
                AppLogger.shared.log("Daisy: feedback sound \(name) unavailable")
                NSSound.beep()
                return
            }

            sound.volume = 0.65
            self.feedbackSound = sound
            if !sound.play() {
                AppLogger.shared.log("Daisy: feedback sound failed to play")
                NSSound.beep()
            }
        }
    }
}
