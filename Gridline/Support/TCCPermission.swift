//
//  TCCPermission.swift
//  Gridline
//
//  Tanpa App Sandbox (D16), aplikasi tetap bisa diblokir TCC saat mengakses
//  folder Desktop, Documents, atau Downloads jika pengguna belum memberi izin.
//  Bagian 13 apps-spec.md: tampilkan petunjuk untuk membuka
//  Pengaturan Sistem > Privasi & Keamanan.
//

import Foundation
import AppKit

enum TCCPermission {
    /// Folder yang diawasi TCC di luar sandbox: Desktop, Documents, Downloads.
    static func isProtectedByTCC(path: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let protectedFolders = ["Desktop", "Documents", "Downloads"]
        return protectedFolders.contains { folder in
            path == "\(home)/\(folder)" || path.hasPrefix("\(home)/\(folder)/")
        }
    }

    /// Percobaan baca ringan untuk mendeteksi penolakan TCC (`EPERM`) pada folder
    /// yang dipilih pengguna.
    static func canReadDirectory(path: String) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }

    @MainActor
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
