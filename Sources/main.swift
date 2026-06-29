import Cocoa

autoreleasepool {
    installCrashHandler()
    AppLogger.shared.log("Application starting", synchronous: true)

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
