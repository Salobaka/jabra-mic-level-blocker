import Cocoa
import SwiftUI
import Combine

final class MenuBarManager: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let audioManager: AudioDeviceManager

    private let baseSymbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
    private let lockSymbol = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)

    // Cached, symbol-configured images — built once, reused every frame.
    private lazy var unlockedMic: NSImage? = baseSymbol?.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(hierarchicalColor: .black))
    )
    private lazy var lockedMic: NSImage? = baseSymbol?.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(hierarchicalColor: .white))
    )
    private lazy var lockedBadge: NSImage? = lockSymbol?.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            .applying(.init(hierarchicalColor: .systemOrange))
    )

    private var timer: Timer?

    // Animation state. 5 Hz is imperceptible for a 3 s breathing period.
    private var phase: Double = 0
    private let breathingPeriod: Double = 3.0
    private let tickInterval: TimeInterval = 0.2

    init(audioManager: AudioDeviceManager) {
        self.audioManager = audioManager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()
        setup()
        observeLockState()
        renderCurrentFrame()
        if audioManager.lockVolume {
            startTimer()
        }
    }

    deinit {
        stopTimer()
    }

    private func setup() {
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        let hostingView = NSHostingView(rootView: HUDView(audioManager: self.audioManager, onClose: { [weak self] in
            self?.closePopover()
        }))
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
            .sink { [weak self] locked in
                guard let self = self else { return }
                self.renderCurrentFrame()
                if locked {
                    self.startTimer()
                } else {
                    self.stopTimer()
                }
            }
            .store(in: &cancellables)
    }

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = tickInterval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        phase += (2 * .pi) * (tickInterval / breathingPeriod)
        if phase > 2 * .pi { phase -= 2 * .pi }
        renderCurrentFrame()
    }

    private func renderCurrentFrame() {
        let normalized = (sin(phase) + 1) / 2
        let alpha = 0.25 + (normalized * 0.30)
        updateIcon(alpha: alpha)
    }

    private func updateIcon(alpha: Double) {
        guard let button = statusItem.button else { return }

        let isLocked = audioManager.lockVolume
        let symbol = isLocked ? lockedMic : unlockedMic
        guard let colored = symbol else { return }

        let size = colored.size
        let result = NSImage(size: size)
        result.lockFocus()

        if isLocked {
            NSColor.systemOrange.withAlphaComponent(alpha).setFill()
        } else {
            NSColor.white.setFill()
        }
        NSRect(origin: .zero, size: size).fill()

        colored.draw(in: NSRect(origin: .zero, size: size),
                     from: NSRect(origin: .zero, size: size),
                     operation: .sourceAtop,
                     fraction: 1.0)

        if isLocked, let coloredLock = lockedBadge {
            let badgeSize = NSSize(width: size.width * 0.55, height: size.height * 0.55)
            let badgeOrigin = NSPoint(x: size.width - badgeSize.width + 2, y: -2)
            let badgeRect = NSRect(origin: badgeOrigin, size: badgeSize)

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