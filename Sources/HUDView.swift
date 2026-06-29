import SwiftUI
import AppKit

struct HUDView: View {
    @StateObject var audioManager: AudioDeviceManager

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(audioManager.jabraDevice == nil ? "Jabra not found" : audioManager.jabraName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button(action: { NSApp.terminate(nil) }, label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                })
                .buttonStyle(.plain)
            }

            if audioManager.authorizationStatus != .authorized {
                VStack(spacing: 6) {
                    Text("Microphone access required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Grant Permission") {
                        audioManager.requestMicrophoneAccess()
                    }
                    .controlSize(.small)
                }
            } else if audioManager.jabraDevice != nil {
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

                Toggle("Show Dock icon (restart required)", isOn: Binding(
                    get: { audioManager.showDockIcon },
                    set: { audioManager.showDockIcon = $0 }
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
            } else {
                Text("Connect Jabra Elite 85h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 280)
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
