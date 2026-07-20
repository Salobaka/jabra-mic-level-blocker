import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    let audioManager = AudioDeviceManager()
    let daisyController = DaisyMuteController()
    let floatingPanel = FloatingPanelController()
    var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        daisyController.startMonitoring()
        menuBarManager = MenuBarManager(audioManager: audioManager, daisyController: daisyController)
        showHUD()
        audioManager.requestMicrophoneAccess()
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
        floatingPanel.show(rootView: HUDView(audioManager: self.audioManager, daisyController: self.daisyController, onClose: { [weak self] in
            self?.hideHUD()
        }))
    }

    @objc func hideHUD() {
        floatingPanel.hide()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioManager.stopMetering()
    }
}
