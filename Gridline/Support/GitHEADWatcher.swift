//
//  GitHEADWatcher.swift
//  Gridline
//
//  Mendeteksi perpindahan branch tanpa memantau seluruh isi `.git`.
//

import Darwin
import Foundation

final class GitHEADWatcher {
    private let headURL: URL
    private let onChange: () -> Void
    private var lastHeadContents: Data
    private var source: DispatchSourceFileSystemObject?

    init?(repoPath: String, onChange: @escaping () -> Void) {
        guard let gitDirectory = Self.gitDirectory(for: repoPath) else { return nil }
        let headURL = gitDirectory.appendingPathComponent("HEAD")
        guard let headContents = try? Data(contentsOf: headURL) else { return nil }
        let descriptor = open(gitDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        self.headURL = headURL
        self.onChange = onChange
        self.lastHeadContents = headContents

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.checkForChange()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        source.resume()
    }

    deinit {
        stop()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func checkForChange() {
        guard let contents = try? Data(contentsOf: headURL), contents != lastHeadContents else { return }
        lastHeadContents = contents
        onChange()
    }

    private static func gitDirectory(for repoPath: String) -> URL? {
        let repoURL = URL(fileURLWithPath: repoPath, isDirectory: true)
        let dotGitURL = repoURL.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGitURL.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue { return dotGitURL.standardizedFileURL }

        guard let contents = try? String(contentsOf: dotGitURL, encoding: .utf8),
              let firstLine = contents.split(whereSeparator: \.isNewline).first else { return nil }
        let prefix = "gitdir: "
        guard firstLine.hasPrefix(prefix) else { return nil }
        let path = String(firstLine.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, relativeTo: repoURL).standardizedFileURL
    }
}
