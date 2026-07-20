import SwiftUI
import AppKit

struct HUDView: View {
    @StateObject var audioManager: AudioDeviceManager
    @StateObject var daisyController: DaisyMuteController
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(audioManager.jabraDevice == nil ? "Jabra not found" : audioManager.jabraName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button(action: onClose, label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                })
                .buttonStyle(.plain)
            }

            PermissionsSection(audioManager: audioManager, daisyController: daisyController)

            if audioManager.microphonePermission == .granted && audioManager.jabraDevice != nil {
                Toggle("Show mic level", isOn: Binding(
                    get: { audioManager.isRunning },
                    set: { newValue in
                        if newValue {
                            audioManager.startMetering()
                        } else {
                            audioManager.stopMetering()
                        }
                    }
                ))
                .font(.system(size: 12))

                Toggle("Lock input level", isOn: Binding(
                    get: { audioManager.lockVolume },
                    set: { audioManager.setLockVolume($0) }
                ))
                .font(.system(size: 12))

                LevelBar(level: audioManager.level)
                    .frame(height: 14)

                HStack(spacing: 6) {
                    Image(systemName: "microphone")
                        .font(.caption)
                    Slider(value: Binding(
                        get: { audioManager.inputGain },
                        set: { audioManager.setInputGainFromUI($0) }
                    ), in: 0.1...1, step: 0.01)
                    .onChange(of: audioManager.inputGain) { _, newValue in
                        if newValue < 0.1 {
                            audioManager.setInputGainFromUI(0.1)
                        }
                    }
                    Image(systemName: "microphone.fill")
                        .font(.caption)
                }

                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Minimum 10% enforced")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !audioManager.gainIsWritable {
                    Text("This device does not expose a software gain control.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                DisconnectButton(audioManager: audioManager)
            } else {
                VStack(spacing: 6) {
                    Text("Connect Jabra Elite 85h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ConnectButton(audioManager: audioManager)
                }
            }

            if daisyController.isDaisyPaired {
                Divider()
                DaisySection(controller: daisyController)
            }
        }
        .padding()
        .frame(width: 280)
    }
}

struct ConnectButton: View {
    @StateObject var audioManager: AudioDeviceManager
    @State private var lastResult: String?

    var body: some View {
        VStack(spacing: 4) {
            Button {
                let result = BluetoothController.connectJabra()
                lastResult = result
                if result == nil {
                    audioManager.refreshDevices()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.horizontal")
                    Text("Connect Jabra Elite 85h")
                }
                .font(.system(size: 12))
            }
            .controlSize(.small)
            .disabled(BluetoothController.isJabraConnected)

            if let lastResult = lastResult {
                Text(lastResult)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct DisconnectButton: View {
    @StateObject var audioManager: AudioDeviceManager
    @State private var lastResult: String?

    var body: some View {
        VStack(spacing: 4) {
            Button {
                let result = BluetoothController.disconnectJabra()
                lastResult = result
                if result == nil {
                    audioManager.refreshDevices()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.horizontal.fill")
                    Text("Disconnect Jabra Elite 85h")
                }
                .font(.system(size: 12))
            }
            .controlSize(.small)
            .disabled(!BluetoothController.isJabraConnected)

            if let lastResult = lastResult {
                Text(lastResult)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.25))
                RoundedRectangle(cornerRadius: 4)
                    .fill(barColor)
                    .frame(width: geo.size.width * CGFloat(level))
            }
        }
    }

    private var barColor: Color {
        if level < 0.6 { return .green }
        if level < 0.85 { return .yellow }
        return .red
    }
}

struct DaisySection: View {
    @ObservedObject var controller: DaisyMuteController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: controller.isDaisyConnected ? "headphones" : "headphones.circle")
                    .foregroundStyle(controller.isDaisyConnected ? .green : .secondary)
                Text(controller.isDaisyConnected ? "\(controller.daisyName) connected" : "\(controller.daisyName) not connected")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }

            HStack {
                Image(systemName: controller.isMuted ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(controller.isMuted ? .red : .green)
                Text(controller.isMuted ? "Muted" : "Unmuted")
                    .font(.system(size: 12))
                Spacer()
            }

            Button {
                controller.toggleMute()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: controller.isMuted ? "mic" : "mic.slash")
                    Text(controller.isMuted ? "Unmute" : "Mute")
                }
                .font(.system(size: 12))
            }
            .controlSize(.small)
            .disabled(!controller.isDaisyConnected)
        }
    }
}

struct PermissionsSection: View {
    @ObservedObject var audioManager: AudioDeviceManager
    @ObservedObject var daisyController: DaisyMuteController

    private var allGranted: Bool {
        audioManager.microphonePermission == .granted &&
        audioManager.bluetoothPermission == .granted &&
        daisyController.inputMonitoringStatus == .granted
    }

    var body: some View {
        if allGranted {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Permissions OK")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Permissions")
                    .font(.system(size: 12, weight: .semibold))

                PermissionRow(
                    icon: "mic.fill",
                    name: "Microphone",
                    status: audioManager.microphonePermission,
                    actionTitle: "Grant",
                    action: { audioManager.requestMicrophoneAccess() }
                )

                PermissionRow(
                    icon: "antenna.radiowaves.left.and.right",
                    name: "Bluetooth",
                    status: audioManager.bluetoothPermission,
                    actionTitle: "Grant",
                    action: { audioManager.requestBluetoothAccess() }
                )

                PermissionRow(
                    icon: "dot.radiowaves.left.and.right",
                    name: "Input Monitoring",
                    status: daisyController.inputMonitoringStatus,
                    actionTitle: "Open Settings",
                    action: { daisyController.openInputMonitoringSettings() }
                )
            }
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let name: String
    let status: PermissionStatus
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 16)
                .foregroundStyle(.secondary)

            Text(name)
                .font(.system(size: 12))

            Spacer()

            statusBadge

            if status != .granted {
                Button(actionTitle, action: action)
                    .font(.caption2)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 12))
        case .denied:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 12))
        case .notDetermined:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.yellow)
                .font(.system(size: 12))
        }
    }
}
