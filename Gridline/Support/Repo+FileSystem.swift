import Foundation

extension Repo {
    /// Pengecekan filesystem murni berdasarkan path, tanpa perlu instance
    /// `Repo` (yang mengalokasikan `id` acak) — dipakai juga oleh `RepoOpener`
    /// untuk memvalidasi folder yang baru dipilih, sebelum `Repo` dibuat.
    static func isGitRepository(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git"))
    }

    /// True when the saved path still points to a directory containing Git metadata.
    var existsOnDisk: Bool {
        Self.isGitRepository(atPath: path)
    }
}
