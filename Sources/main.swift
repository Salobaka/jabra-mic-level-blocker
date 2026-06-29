import Cocoa

autoreleasepool {
    installCrashHandler()
    AppLogger.shared.log("Application starting")

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
