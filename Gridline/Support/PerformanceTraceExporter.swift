import Foundation

#if DEBUG
/// Dev-only bridge so a PERF-02 measurement script can pull `PerformanceTrace`
/// snapshots out of a real running Gridline process without any shipped UI.
/// Writing any content to the watched "command" file triggers a dump; writing
/// "reset" also clears the collector afterwards. Inert unless both
/// `PerformanceTrace.shared.isEnabled` and `GRIDLINE_PERF_TRACE_DIR` are set.
enum PerformanceTraceExporter {
    private static var source: DispatchSourceFileSystemObject?
    private static var sequence = 0

    static func startIfNeeded() {
        guard PerformanceTrace.shared.isEnabled,
              let dirPath = ProcessInfo.processInfo.environment["GRIDLINE_PERF_TRACE_DIR"] else { return }
        let dirURL = URL(fileURLWithPath: dirPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let commandURL = dirURL.appendingPathComponent("command")
        if !FileManager.default.fileExists(atPath: commandURL.path) {
            FileManager.default.createFile(atPath: commandURL.path, contents: nil)
        }
        let fd = open(commandURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let fileSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend], queue: .main)
        fileSource.setEventHandler {
            handleCommand(dirURL: dirURL, commandURL: commandURL)
        }
        fileSource.setCancelHandler { close(fd) }
        fileSource.resume()
        source = fileSource
    }

    private static func handleCommand(dirURL: URL, commandURL: URL) {
        guard let raw = try? String(contentsOf: commandURL, encoding: .utf8) else { return }
        let command = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        sequence += 1
        let snapshot = PerformanceTrace.shared.snapshot()
        let outputURL = dirURL.appendingPathComponent("snapshot-\(sequence).json")
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: outputURL, options: .atomic)
        }
        if command == "reset" {
            _ = PerformanceTrace.shared.reset()
        }
        try? Data().write(to: commandURL, options: .atomic)
    }
}
#endif
