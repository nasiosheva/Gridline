//
//  GridlineTerminalView.swift
//  Gridline
//
//  Subclass SwiftTerm `LocalProcessTerminalView` hanya untuk mengarahkan
//  Cmd+klik path yang terdeteksi (regex implicit-link bawaan SwiftTerm, gaya
//  Ghostty) ke viewer file Gridline, bukan ke pembuka URL default SwiftTerm.
//
//  `requestOpenLink` adalah satu-satunya titik ekstensi `open` yang
//  dibutuhkan di sini: garis bawah saat hover+Cmd dan preview teks mentah di
//  pojok kiri bawah sudah bawaan SwiftTerm lewat `linkHighlightMode =
//  .hoverWithModifier` (default), jadi tidak perlu kode tambahan untuk itu.
//

import SwiftTerm

final class GridlineTerminalView: LocalProcessTerminalView {
    /// Dipanggil dengan teks link mentah (misalnya "src/app.ts:42") saat
    /// pengguna Cmd+klik sebuah path yang terdeteksi. Resolusi path
    /// dilakukan oleh pemanggil (`TerminalTab`), bukan di sini, supaya view
    /// ini tetap tidak tahu apa-apa soal model repo/viewer Gridline.
    var onOpenLink: ((String) -> Void)?

    override func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard !Self.isURLScheme(link) else {
            super.requestOpenLink(source: source, link: link, params: params)
            return
        }
        onOpenLink?(link)
    }

    // Daftar skema yang dikenali regex implicit-link bawaan SwiftTerm (lihat
    // `ghosttyImplicitLinkRegex` di Terminal.swift) — dibiarkan terbuka lewat
    // `openLink` default-nya alih-alih dipaksa jadi path lokal.
    private static let urlSchemePrefixes = [
        "http://", "https://", "mailto:", "ftp://", "file:", "ssh:", "git://",
        "ssh://", "tel:", "magnet:", "ipfs://", "ipns://", "gemini://", "gopher://", "news:"
    ]

    private static func isURLScheme(_ text: String) -> Bool {
        urlSchemePrefixes.contains { text.hasPrefix($0) }
    }
}
