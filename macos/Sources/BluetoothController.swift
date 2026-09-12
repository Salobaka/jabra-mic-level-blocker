import Foundation
import IOBluetooth

final class BluetoothController {
    static func findJabraDevice() -> IOBluetoothDevice? {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return nil
        }
        return devices.first { device in
            guard let name = device.name?.lowercased() else { return false }
            return name.contains("jabra") && (name.contains("85h") || name.contains("elite"))
        }
    }

    static var isJabraConnected: Bool {
        findJabraDevice()?.isConnected() ?? false
    }

    @discardableResult
    static func connectJabra() -> String? {
        guard let device = findJabraDevice() else {
            return "No paired Jabra Elite 85h found."
        }

        guard !device.isConnected() else {
            return "\(device.name ?? "Jabra") is already connected."
        }

        let result = device.openConnection()
        if result == kIOReturnSuccess {
            AppLogger.shared.log("Connected Bluetooth device: \(device.name ?? "Jabra") (\(device.addressString ?? "unknown"))")
            return nil
        } else {
            return "Failed to connect \(device.name ?? "Jabra") (error \(result))."
        }
    }

    @discardableResult
    static func disconnectJabra() -> String? {
        guard let device = findJabraDevice() else {
            return "No paired Jabra Elite 85h found."
        }

        guard device.isConnected() else {
            return "\(device.name ?? "Jabra") is already disconnected."
        }

        let result = device.closeConnection()
        if result == kIOReturnSuccess {
            AppLogger.shared.log("Disconnected Bluetooth device: \(device.name ?? "Jabra") (\(device.addressString ?? "unknown"))")
            return nil
        } else {
            return "Failed to disconnect \(device.name ?? "Jabra") (error \(result))."
        }
    }
}
