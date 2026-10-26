import Foundation

enum DiffVisibilityPolicy {
    static let recentChangeWindow: TimeInterval = 10 * 60
    static let largeFileByteLimit: Int64 = 1_000_000
    static let largeChangeLineLimit = 2_000

    static func isRecent(_ entry: DiffFileEntry, now: Date = .now) -> Bool {
        guard let modificationDate = entry.modificationDate else { return false }
        return modificationDate >= now.addingTimeInterval(-recentChangeWindow)
    }

    static func isLarge(_ entry: DiffFileEntry) -> Bool {
        if let fileSizeBytes = entry.fileSizeBytes, fileSizeBytes >= largeFileByteLimit {
            return true
        }
        let changedLines = (entry.additions ?? 0) + (entry.deletions ?? 0)
        return changedLines >= largeChangeLineLimit
    }
}
