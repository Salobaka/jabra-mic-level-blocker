import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let audioManager = AudioDeviceManager()
    let floatingPanel = FloatingPanelController()
    var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        menuBarManager = MenuBarManager(audioManager: audioManager)
        showHUD()
        observeReactivation()
    }

    private func observeReactivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.audioManager.refreshBluetoothPermission()
        }
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Show HUD", action: #selector(showHUD), keyEquivalent: "")
        appMenu.addItem(withTitle: "Hide HUD", action: #selector(hideHUD), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Jabra Input Tracker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc func showHUD() {
        floatingPanel.show(rootView: HUDView(audioManager: self.audioManager, onClose: { [weak self] in
            self?.hideHUD()
        }))
    }

    @objc func hideHUD() {
        floatingPanel.hide()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}