//
//  DiffModels.swift
//  Gridline
//
//  Model untuk panel diff (bagian 6 apps-spec.md): daftar file berubah
//  (staged/unstaged/untracked) dan isi diff per file sebagai kumpulan hunk.
//

import Foundation

enum DiffChangeGroup: String, CaseIterable, Identifiable, Sendable {
    case staged
    case unstaged
    case untracked
    /// Hanya terisi saat pengguna menyalakan "Show Ignored Files" — defaultnya
    /// tidak diambil sama sekali (lihat `GitDiffService.statusSnapshot`).
    case ignored

    var id: String { rawValue }
}

enum DiffFileStatus: Equatable, Sendable {
    case added
    case deleted
    case modified
    case renamed(from: String)
    case copied(from: String)
    case untracked
    case unmerged
    case typeChanged
    case ignored

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
        case .ignored: return "I"
        }
    }
}

struct DiffFileEntry: Identifiable, Equatable, Sendable {
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

struct DiffLine: Identifiable, Sendable {
    enum Kind: Sendable {
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

struct DiffHunk: Identifiable, Sendable {
    let id = UUID()
    let header: String
    let lines: [DiffLine]
}

struct FileDiff: Sendable {
    let entry: DiffFileEntry
    let hunks: [DiffHunk]
    let isBinary: Bool
    /// Output `git diff` mentah, dipakai tombol "Salin diff" (bagian 17a
    /// apps-spec.md) supaya hasil salin identik dengan yang Git tampilkan,
    /// bukan rekonstruksi dari `hunks`.
    let rawText: String
}
