import Cocoa

autoreleasepool {
    installCrashHandler()
    AppLogger.shared.log("Application starting", synchronous: true)

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
