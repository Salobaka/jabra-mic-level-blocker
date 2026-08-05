import Foundation

final class AppLogger {
    static let shared = AppLogger()

    private static let iso8601 = ISO8601DateFormatter()

    private let queue = DispatchQueue(label: "com.jabrainputtracker.logger", qos: .utility)
    private let logFile: URL
    private let rotatedFile: URL
    private let maxLogBytes: Int64 = 1_048_576

    private var currentSize: Int64 = 0

    init() {
        let folder = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("JabraInputTracker", isDirectory: true)
        if let folder = folder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            logFile = folder.appendingPathComponent("app.log")
            rotatedFile = folder.appendingPathComponent("app.log.1")
        } else {
            logFile = URL(fileURLWithPath: "/tmp/jabra_input_tracker.log")
            rotatedFile = URL(fileURLWithPath: "/tmp/jabra_input_tracker.log.1")
        }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
           let size = attrs[.size] as? Int64 {
            currentSize = size
        }
    }

    func log(_ message: String, level: String = "INFO", synchronous: Bool = false) {
        let timestamp = Self.iso8601.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"
        let write = { [weak self] in
            guard let self = self else { return }
            if let data = line.data(using: .utf8) {
                let byteCount = Int64(data.count)
                self.rotateIfNeeded(adding: byteCount)

                if FileManager.default.fileExists(atPath: self.logFile.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFile) {
                        _ = handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: self.logFile)
                }
                self.currentSize += byteCount
            }
        }
        if synchronous {
            queue.sync(execute: write)
        } else {
            queue.async(execute: write)
        }
    }

    private func rotateIfNeeded(adding bytes: Int64) {
        let projected = currentSize + bytes
        guard projected >= maxLogBytes else { return }

        try? FileManager.default.removeItem(at: rotatedFile)
        try? FileManager.default.moveItem(at: logFile, to: rotatedFile)
        currentSize = 0
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