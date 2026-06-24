import Cocoa
import SwiftUI

class MenuBarManager: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let audioManager: AudioDeviceManager

    init(audioManager: AudioDeviceManager) {
        self.audioManager = audioManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()
        setup()
    }

    private func setup() {
        statusItem.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Jabra Input")
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        let hostingView = NSHostingView(rootView: HUDView(audioManager: self.audioManager))
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 240)

        let viewController = NSViewController()
        viewController.view = hostingView

        popover.contentViewController = viewController
        popover.contentSize = NSSize(width: 280, height: 240)
        popover.behavior = .transient
        popover.delegate = self
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.close()
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func closePopover() {
        popover.close()
    }
}
