import Foundation
import CoreBluetooth
import Cocoa

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
    private var wasAccessory: Bool = false

    private override init() {
        super.init()
    }

    func request(completion: @escaping (PermissionStatus) -> Void) {
        let current = status
        AppLogger.shared.log("Bluetooth: request called, current status=\(current)")
        guard current == .notDetermined else {
            AppLogger.shared.log("Bluetooth: skipping request, status already \(current)")
            completion(current)
            return
        }
        self.wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory {
            AppLogger.shared.log("Bluetooth: flipping to .regular for TCC modal")
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        self.completion = completion
        AppLogger.shared.log("Bluetooth: creating CBCentralManager to trigger prompt")
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
    }
}

extension BluetoothPermission: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let resolved = status
        AppLogger.shared.log("Bluetooth: centralManagerDidUpdateState, resolved status=\(resolved)")
        let c = completion
        completion = nil
        centralManager = nil
        DispatchQueue.main.async { [weak self] in
            if self?.wasAccessory == true {
                NSApp.setActivationPolicy(.accessory)
            }
            c?(resolved)
        }
    }
}