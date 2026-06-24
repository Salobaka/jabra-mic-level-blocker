import Cocoa
import SwiftUI

final class MenuBarManager: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let audioManager: AudioDeviceManager

    private let baseSymbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
    private var timer: Timer?

    // Lightweight breathing state. Updated at only 10 Hz.
    private var phase: Double = 0
    private let breathingPeriod: Double = 3.0

    init(audioManager: AudioDeviceManager) {
        self.audioManager = audioManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()
        setup()
        startTimer()
    }

    deinit {
        stopTimer()
    }

    private func setup() {
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        updateIcon(alpha: 0)

        let hostingView = NSHostingView(rootView: HUDView(audioManager: self.audioManager))
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 240)

        let viewController = NSViewController()
        viewController.view = hostingView

        popover.contentViewController = viewController
        popover.contentSize = NSSize(width: 280, height: 240)
        popover.behavior = .transient
        popover.delegate = self
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let normalized = (sin(phase) + 1) / 2
        let alpha = 0.25 + (normalized * 0.30)
        updateIcon(alpha: alpha)

        phase += (2 * .pi) * (0.1 / breathingPeriod)
        if phase > 2 * .pi { phase -= 2 * .pi }
    }

    private func updateIcon(alpha: Double) {
        guard let button = statusItem.button,
              let baseSymbol = baseSymbol else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(hierarchicalColor: .systemOrange))
        let colored = baseSymbol.withSymbolConfiguration(config) ?? baseSymbol

        let size = colored.size
        let result = NSImage(size: size)
        result.lockFocus()
        colored.draw(in: NSRect(origin: .zero, size: size))

        let overlay = NSImage(size: size)
        overlay.lockFocus()
        NSColor.systemOrange.withAlphaComponent(alpha).setFill()
        NSRect(origin: .zero, size: size).fill()
        overlay.unlockFocus()

        overlay.draw(in: NSRect(origin: .zero, size: size),
                     from: NSRect(origin: .zero, size: size),
                     operation: .sourceAtop,
                     fraction: 1.0)
        result.unlockFocus()

        button.image = result
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
