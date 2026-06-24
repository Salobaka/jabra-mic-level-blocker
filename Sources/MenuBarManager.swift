import Cocoa
import SwiftUI
import Combine

final class MenuBarManager: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let audioManager: AudioDeviceManager

    private let baseSymbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
    private let lockSymbol = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
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
        observeLockState()
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

    private func observeLockState() {
        audioManager.$lockVolume
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.renderCurrentFrame()
            }
            .store(in: &cancellables)
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
        phase += (2 * .pi) * (0.1 / breathingPeriod)
        if phase > 2 * .pi { phase -= 2 * .pi }
        renderCurrentFrame()
    }

    private func renderCurrentFrame() {
        let normalized = (sin(phase) + 1) / 2
        let alpha = 0.25 + (normalized * 0.30)
        updateIcon(alpha: alpha)
    }

    private func updateIcon(alpha: Double) {
        guard let button = statusItem.button,
              let baseSymbol = baseSymbol else { return }

        let isLocked = audioManager.lockVolume
        let symbolColor: NSColor = isLocked ? .white : .systemOrange
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(hierarchicalColor: symbolColor))
        let colored = baseSymbol.withSymbolConfiguration(config) ?? baseSymbol

        let size = colored.size
        let result = NSImage(size: size)
        result.lockFocus()

        // Soft orange breathing background.
        NSColor.systemOrange.withAlphaComponent(alpha).setFill()
        NSRect(origin: .zero, size: size).fill()

        // Draw mic icon using source-atop so it tints over the orange background.
        colored.draw(in: NSRect(origin: .zero, size: size),
                     from: NSRect(origin: .zero, size: size),
                     operation: .sourceAtop,
                     fraction: 1.0)

        // High-contrast lock badge when lock is enabled.
        if isLocked, let lockSymbol = lockSymbol {
            let badgeSize = NSSize(width: size.width * 0.55, height: size.height * 0.55)
            let badgeOrigin = NSPoint(x: size.width - badgeSize.width + 2, y: -2)
            let badgeRect = NSRect(origin: badgeOrigin, size: badgeSize)

            let badgeConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
                .applying(.init(hierarchicalColor: .systemOrange))
            let coloredLock = lockSymbol.withSymbolConfiguration(badgeConfig) ?? lockSymbol

            // Small dark backing circle for contrast.
            let backing = NSBezierPath(ovalIn: badgeRect.insetBy(dx: -1, dy: -1))
            NSColor.black.withAlphaComponent(0.7).setFill()
            backing.fill()

            coloredLock.draw(in: badgeRect,
                             from: NSRect(origin: .zero, size: coloredLock.size),
                             operation: .sourceAtop,
                             fraction: 1.0)
        }

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

    private var cancellables = Set<AnyCancellable>()
}
