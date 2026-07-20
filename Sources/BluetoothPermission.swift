import Foundation
import CoreBluetooth

final class BluetoothPermission: NSObject {
    static let shared = BluetoothPermission()

    var status: PermissionStatus {
        switch CBManager.authorization {
        case .allowedAlways:
            return .granted
        case .denied:
            return .denied
        case .restricted:
            return .denied
        default:
            return .notDetermined
        }
    }

    private var centralManager: CBCentralManager?
    private var completion: ((PermissionStatus) -> Void)?

    private override init() {
        super.init()
    }

    func request(completion: @escaping (PermissionStatus) -> Void) {
        let current = status
        guard current == .notDetermined else {
            completion(current)
            return
        }
        self.completion = completion
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
    }
}

extension BluetoothPermission: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let resolved = status
        let c = completion
        completion = nil
        centralManager = nil
        DispatchQueue.main.async {
            c?(resolved)
        }
    }
}