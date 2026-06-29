import Foundation

final class AppLogger {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "com.jabrainputtracker.logger", qos: .utility)
    private let logFile: URL

    init() {
        let folder = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("JabraInputTracker", isDirectory: true)
        if let folder = folder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            logFile = folder.appendingPathComponent("app.log")
        } else {
            logFile = URL(fileURLWithPath: "/tmp/jabra_input_tracker.log")
        }
    }

    func log(_ message: String, level: String = "INFO", synchronous: Bool = false) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"
        let write = { [weak self] in
            guard let self = self else { return }
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFile.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFile) {
                        _ = handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: self.logFile)
                }
            }
        }
        if synchronous {
            queue.sync(execute: write)
        } else {
            queue.async(execute: write)
        }
    }

    func crash(_ message: String) {
        log(message, level: "CRASH")
    }

    var logPath: String {
        logFile.path
    }
}

func installCrashHandler() {
    NSSetUncaughtExceptionHandler { exception in
                AppLogger.shared.crash(
                    "Uncaught exception: \(exception.name.rawValue) - \(exception.reason ?? "unknown")\n" +
                    exception.callStackSymbols.joined(separator: "\n")
                )
        // Give logger time to flush.
        Thread.sleep(forTimeInterval: 0.5)
    }
}
