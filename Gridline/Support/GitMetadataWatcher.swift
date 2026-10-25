//
//  GitMetadataWatcher.swift
//  Gridline
//
//  Memeriksa perubahan HEAD, index, dan ref selama pane terlihat.
//

import Darwin
import Foundation

final class GitMetadataWatcher {
    private static let checkInterval: TimeInterval = 1
    private struct FileStamp: Equatable {
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init?(at url: URL) {
            var info = stat()
            guard lstat(url.path, &info) == 0 else { return nil }
            inode = UInt64(info.st_ino)
            size = info.st_size
            modifiedSeconds = info.st_mtimespec.tv_sec
            modifiedNanoseconds = info.st_mtimespec.tv_nsec
            changedSeconds = info.st_ctimespec.tv_sec
            changedNanoseconds = info.st_ctimespec.tv_nsec
        }
    }

    private struct Snapshot: Equatable {
        let head: Data?
        let index: FileStamp?
        let currentRef: Data?
        let comparisonRefs: [Data?]
        let packedRefs: FileStamp?
    }

    private let gitDirectory: URL
    private let commonDirectory: URL
    private let watchedBranches: () -> [String]
    private let onChange: () -> Void
    private var lastSnapshot: Snapshot
    private var timer: DispatchSourceTimer?

    init?(repoPath: String, watchedBranches: @escaping () -> [String], onChange: @escaping () -> Void) {
        guard let gitDirectory = Self.gitDirectory(for: repoPath) else { return nil }
        let commonDirectory = Self.commonDirectory(for: gitDirectory)
        guard FileManager.default.fileExists(atPath: gitDirectory.appendingPathComponent("HEAD").path) else { return nil }

        self.gitDirectory = gitDirectory
        self.commonDirectory = commonDirectory
        self.watchedBranches = watchedBranches
        self.onChange = onChange
        self.lastSnapshot = Self.snapshot(gitDirectory: gitDirectory, commonDirectory: commonDirectory, watchedBranches: watchedBranches())

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.checkInterval, repeating: Self.checkInterval)
        timer.setEventHandler { [weak self] in
            self?.checkForChange()
        }
        self.timer = timer
        timer.resume()
    }

    deinit {
        timer?.cancel()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func checkForChange() {
        let snapshot = Self.snapshot(gitDirectory: gitDirectory, commonDirectory: commonDirectory, watchedBranches: watchedBranches())
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        onChange()
    }

    private static func snapshot(gitDirectory: URL, commonDirectory: URL, watchedBranches: [String]) -> Snapshot {
        let head = try? Data(contentsOf: gitDirectory.appendingPathComponent("HEAD"))
        let refName = head.flatMap { String(data: $0, encoding: .utf8) }
            .flatMap { $0.hasPrefix("ref: refs/") ? String($0.dropFirst("ref: ".count)).trimmingCharacters(in: .whitespacesAndNewlines) : nil }
        let currentRef = refName.flatMap { try? Data(contentsOf: commonDirectory.appendingPathComponent($0)) }
        let comparisonRefs = watchedBranches.map {
            try? Data(contentsOf: commonDirectory.appendingPathComponent("refs/heads/\($0)"))
        }
        return Snapshot(
            head: head,
            index: FileStamp(at: gitDirectory.appendingPathComponent("index")),
            currentRef: currentRef,
            comparisonRefs: comparisonRefs,
            packedRefs: FileStamp(at: commonDirectory.appendingPathComponent("packed-refs"))
        )
    }

    private static func commonDirectory(for gitDirectory: URL) -> URL {
        let commonDirURL = gitDirectory.appendingPathComponent("commondir")
        guard let value = try? String(contentsOf: commonDirURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return gitDirectory }
        return URL(fileURLWithPath: value, relativeTo: gitDirectory).standardizedFileURL
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
