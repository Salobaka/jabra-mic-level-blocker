import Cocoa
import SwiftUI

class FloatingPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?

    func show(rootView: some View) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 200, y: 200, width: 280, height: 240),
                styleMask: [.nonactivatingPanel, .hudWindow, .utilityWindow, .titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.title = "Jabra Input"
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.titlebarAppearsTransparent = true
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: rootView)
            self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }
}
