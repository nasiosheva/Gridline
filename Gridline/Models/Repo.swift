//
//  Repo.swift
//  Gridline
//
//  Model repo: identitas dan path. Lihat bagian "Model data" di apps-spec.md —
//  sesi terminal TIDAK disimpan di sini sebagai value, melainkan akan dikelola
//  oleh RepoSession (class, identity-based) agar tidak ikut hilang saat repo
//  ditutup dari pane (D6).
//

import Foundation

struct Repo: Identifiable, Codable, Hashable {
    let id: UUID
    var path: String

    init(id: UUID = UUID(), path: String) {
        self.id = id
        self.path = path
    }

    var url: URL {
        URL(fileURLWithPath: path)
    }

    var name: String {
        url.lastPathComponent
    }

    /// Repo dianggap valid jika foldernya ada dan punya `.git` (folder biasa atau file,
    /// seperti pada worktree) di dalamnya.
    var existsOnDisk: Bool {
        var isDirectory: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return fm.fileExists(atPath: url.appendingPathComponent(".git").path)
    }
}
