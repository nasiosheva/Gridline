//
//  DiffModels.swift
//  Gridline
//
//  Model untuk panel diff (bagian 6 apps-spec.md): daftar file berubah
//  (staged/unstaged/untracked) dan isi diff per file sebagai kumpulan hunk.
//

import Foundation

enum DiffChangeGroup: String, CaseIterable, Identifiable {
    case staged
    case unstaged
    case untracked

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .staged: return L10n.Diff.staged
        case .unstaged: return L10n.Diff.unstaged
        case .untracked: return L10n.Diff.untracked
        }
    }
}

enum DiffFileStatus: Equatable {
    case added
    case deleted
    case modified
    case renamed(from: String)
    case copied(from: String)
    case untracked
    case unmerged
    case typeChanged

    var letter: String {
        switch self {
        case .added: return "A"
        case .deleted: return "D"
        case .modified: return "M"
        case .renamed: return "R"
        case .copied: return "C"
        case .untracked: return "U"
        case .unmerged: return "!"
        case .typeChanged: return "T"
        }
    }
}

struct DiffFileEntry: Identifiable, Equatable {
    var id: String { "\(group.rawValue):\(path)" }
    let path: String
    let group: DiffChangeGroup
    let status: DiffFileStatus
    var additions: Int?
    var deletions: Int?
    var fileSizeBytes: Int64? = nil
    var modificationDate: Date? = nil

    var displayName: String {
        (path as NSString).lastPathComponent
    }
}

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

struct DiffLine: Identifiable {
    enum Kind {
        case context
        case addition
        case deletion
    }

    let id = UUID()
    let kind: Kind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String
}

struct DiffHunk: Identifiable {
    let id = UUID()
    let header: String
    let lines: [DiffLine]
}

struct FileDiff {
    let entry: DiffFileEntry
    let hunks: [DiffHunk]
    let isBinary: Bool
    /// Output `git diff` mentah, dipakai tombol "Salin diff" (bagian 17a
    /// apps-spec.md) supaya hasil salin identik dengan yang Git tampilkan,
    /// bukan rekonstruksi dari `hunks`.
    let rawText: String
}
