//
//  GitProcess.swift
//  Gridline
//
//  Helper umum untuk memanggil `git` lewat `Process`. Semua pemanggilan Git
//  di aplikasi (status, diff) melewati sini agar konsisten: baca saja, dan
//  untuk perintah yang memantau working tree selalu lewat `GitService`/
//  `GitDiffService` yang menambahkan `--no-optional-locks` (D8).
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
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { proc in
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: Output(
                    exitCode: proc.terminationStatus,
                    stdout: String(data: outData, encoding: .utf8) ?? "",
                    stderr: String(data: errData, encoding: .utf8) ?? ""
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: Output(exitCode: -1, stdout: "", stderr: error.localizedDescription))
            }
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
