import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+).
/// Default: ON — the app registers itself as a login item on first launch.
/// Opting out via the HUD checkbox is persisted in UserDefaults.
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()

    private static let defaultsKey = "launchAtLogin"

    @Published private(set) var enabled: Bool

    /// SMAppService requires macOS 13; gain control still works on macOS 12.
    var isSupported: Bool {
        if #available(macOS 13, *) { return true }
        return false
    }

    private init() {
        if let stored = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool {
            enabled = stored
        } else {
            enabled = true
        }
        apply()
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: Self.defaultsKey)
        apply()
    }

    private func apply() {
        guard #available(macOS 13, *) else {
            AppLogger.shared.log("LoginItem: requires macOS 13, skipping")
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                // Throws if not registered — harmless, logged below.
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppLogger.shared.log("LoginItem: apply(enabled=\(enabled)) failed: \(error.localizedDescription)")
        }
        let status = SMAppService.mainApp.status
        AppLogger.shared.log("LoginItem: enabled=\(enabled), status=\(status.rawValue)")
        if status == .requiresApproval {
            AppLogger.shared.log("LoginItem: needs approval — System Settings → General → Login Items")
        }
    }
}
