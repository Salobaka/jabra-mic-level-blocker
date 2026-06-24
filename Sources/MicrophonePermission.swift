import Foundation
import AVFoundation

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
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            completion(granted ? .authorized : .denied)
        }
    }
}
