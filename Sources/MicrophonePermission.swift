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
        guard current == .notDetermined else {
            completion(current)
            return
        }

        let wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                if wasAccessory {
                    NSApp.setActivationPolicy(.accessory)
                }
                completion(granted ? .authorized : .denied)
            }
        }
    }
}
