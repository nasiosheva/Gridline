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
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval

    init(path: String, debounceInterval: TimeInterval = 0.4, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.debounceInterval = debounceInterval
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
        let flags = UInt32(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)

        guard let streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, clientCallBackInfo, _, _, _, _) in
                guard let info = clientCallBackInfo else { return }
                let watcher = Unmanaged<RepoFileWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.scheduleDebouncedCallback()
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            debounceInterval,
            flags
        ) else { return }

        stream = streamRef
        FSEventStreamSetDispatchQueue(streamRef, DispatchQueue.main)
        FSEventStreamStart(streamRef)
    }

    private func scheduleDebouncedCallback() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        debounceWorkItem?.cancel()
    }
}
