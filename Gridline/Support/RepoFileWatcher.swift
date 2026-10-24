//
//  RepoFileWatcher.swift
//  Gridline
//
//  Memantau perubahan file di folder repo lewat FSEvents, dengan pembaruan
//  digabung (debounce) agar `git status`/`git diff` tidak dipanggil berulang
//  kali saat banyak file berubah sekaligus (bagian 6 & 15 apps-spec.md).
//

import CoreServices
import Foundation

final class RepoFileWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: () -> Void
    private let latency: TimeInterval

    init(path: String, latency: TimeInterval = 0.4, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.latency = latency
        start(path: path)
    }

    deinit {
        stop()
    }

    private func start(path: String) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let pathsToWatch = [path] as CFArray
        let flags = UInt32(kFSEventStreamCreateFlagWatchRoot)

        guard let streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, clientCallBackInfo, _, _, _, _) in
                guard let info = clientCallBackInfo else { return }
                let watcher = Unmanaged<RepoFileWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.onChange()
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }

        let gitMetadataPath = (path as NSString).appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: gitMetadataPath, isDirectory: &isDirectory), isDirectory.boolValue {
            _ = FSEventStreamSetExclusionPaths(streamRef, [gitMetadataPath] as CFArray)
        }

        stream = streamRef
        FSEventStreamSetDispatchQueue(streamRef, DispatchQueue.main)
        FSEventStreamStart(streamRef)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
