import Foundation
import AVFoundation
import Cocoa

enum MicrophoneAuthorization: Equatable {
    case notDetermined
    case denied
    case authorized
}

final class MicrophonePermission {
    static let shared = MicrophonePermission()

    var status: MicrophoneAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    func request(completion: @escaping (MicrophoneAuthorization) -> Void) {
        let current = status
        AppLogger.shared.log("Mic: requestAccess called, current status=\(current)")
        guard current == .notDetermined else {
            AppLogger.shared.log("Mic: skipping request, status already \(current)")
            completion(current)
            return
        }

        let wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory {
            AppLogger.shared.log("Mic: flipping to .regular for TCC modal")
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }

        let startTime = Date()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            let elapsed = Date().timeIntervalSince(startTime)
            DispatchQueue.main.async {
                if wasAccessory {
                    NSApp.setActivationPolicy(.accessory)
                }
                AppLogger.shared.log("Mic: requestAccess returned granted=\(granted) in \(String(format: "%.0f", elapsed * 1000))ms")
                if !granted && elapsed < 0.5 {
                    AppLogger.shared.log("Mic: TCC refused without modal. Provenance blocks on Sequoia 15.7. Add manually: System Settings → Privacy & Security → Microphone → +")
                }
                completion(granted ? .authorized : .denied)
            }
        }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
