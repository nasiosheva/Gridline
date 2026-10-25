//
//  GitProcess.swift
//  Gridline
//
//  Helper umum untuk memanggil `git` lewat `Process`. Semua pemanggilan Git
//  di aplikasi melewati sini. Status dan diff bersifat baca saja serta memakai
//  `--no-optional-locks`; `GitWorktreeService` menjalankan `worktree add` hanya
//  setelah pengguna memilih branch untuk pane baru.
//

import Foundation

enum GitProcess {
    struct Output {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    static func run(_ arguments: [String], at path: String) async -> Output {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git", "-C", path] + arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdoutBuffer = PipeOutputBuffer()
            let stderrBuffer = PipeOutputBuffer()
            let readers = DispatchGroup()
            readers.enter()
            readers.enter()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                readers.notify(queue: .global(qos: .utility)) {
                    continuation.resume(returning: Output(
                        exitCode: proc.terminationStatus,
                        stdout: stdoutBuffer.string,
                        stderr: stderrBuffer.string
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                try? stdoutPipe.fileHandleForWriting.close()
                try? stderrPipe.fileHandleForWriting.close()
                try? stdoutPipe.fileHandleForReading.close()
                try? stderrPipe.fileHandleForReading.close()
                readers.leave()
                readers.leave()
                continuation.resume(returning: Output(exitCode: -1, stdout: "", stderr: error.localizedDescription))
                return
            }

            // Close the parent's write handles. The child owns its duplicated
            // handles; closing these lets each reader observe EOF on exit.
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            read(stdoutPipe.fileHandleForReading, into: stdoutBuffer, readers: readers)
            read(stderrPipe.fileHandleForReading, into: stderrBuffer, readers: readers)
        }
    }

    private static func read(_ handle: FileHandle, into buffer: PipeOutputBuffer, readers: DispatchGroup) {
        handle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                readers.leave()
                return
            }
            buffer.append(data)
        }
    }

    static func version() async -> String {
        let output = await run(["--version"], at: NSHomeDirectory())
        guard output.exitCode == 0 else { return String(localized: L10n.Repository.gitUnavailable) }
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isGitAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/git")
    }
}

nonisolated private final class PipeOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ value: Data) {
        lock.lock()
        data.append(value)
        lock.unlock()
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
