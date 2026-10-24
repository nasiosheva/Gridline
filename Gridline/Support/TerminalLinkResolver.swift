//
//  TerminalLinkResolver.swift
//  Gridline
//
//  Parsing & resolusi path yang terdeteksi lewat regex implicit-link bawaan
//  SwiftTerm (gaya Ghostty) saat Cmd+klik di terminal (apps-spec.md bagian 9).
//

import Foundation

enum TerminalLinkTarget: Equatable {
    case file(path: String, line: Int?, isOutsideRepo: Bool)
    case ambiguous(candidates: [String], line: Int?)
    case notFound(text: String)
}

struct TerminalLinkResolver {

    /// Memisahkan sufiks `:baris` atau `:baris:kolom` dari teks link mentah.
    /// SwiftTerm sudah membuang tanda kutip/kurung pembungkus lewat regexnya
    /// sendiri, jadi `raw` di sini sudah berupa teks path bersih.
    static func parse(_ raw: String) -> (pathText: String, line: Int?) {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return (raw, nil) }

        if parts.count >= 3,
           let line = Int(parts[parts.count - 2]),
           Int(parts[parts.count - 1]) != nil {
            let pathText = parts[0..<(parts.count - 2)].joined(separator: ":")
            return (pathText, line)
        }
        if let line = Int(parts[parts.count - 1]) {
            let pathText = parts[0..<(parts.count - 1)].joined(separator: ":")
            return (pathText, line)
        }
        return (raw, nil)
    }

    private static func resolvedCandidate(pathText: String, cwd: String) -> String {
        if pathText.hasPrefix("/") {
            return (pathText as NSString).standardizingPath
        }
        return ((cwd as NSString).appendingPathComponent(pathText) as NSString).standardizingPath
    }

    /// Resolusi penuh dengan akses disk (cek keberadaan file + pencarian nama
    /// file ambigu di repo). Melakukan I/O — panggil dari luar main thread.
    static func resolve(raw: String, cwd: String, repoPath: String) -> TerminalLinkTarget {
        let (pathText, line) = parse(raw)
        let candidate = resolvedCandidate(pathText: pathText, cwd: cwd)
        let standardizedRepoPath = (repoPath as NSString).standardizingPath

        if FileManager.default.fileExists(atPath: candidate) {
            let isOutside = candidate != standardizedRepoPath && !candidate.hasPrefix(standardizedRepoPath + "/")
            return .file(path: candidate, line: line, isOutsideRepo: isOutside)
        }

        // Nama file polos (tanpa "/") yang tidak ditemukan langsung di cwd:
        // cari di seluruh repo. cwd saat ini masih fallback ke folder repo
        // (pelacakan cwd asli lewat shell integration ada di langkah 8).
        guard !pathText.contains("/") else {
            return .notFound(text: raw)
        }
        let matches = findFiles(named: pathText, in: standardizedRepoPath)
        switch matches.count {
        case 0:
            return .notFound(text: raw)
        case 1:
            return .file(path: matches[0], line: line, isOutsideRepo: false)
        default:
            return .ambiguous(candidates: matches, line: line)
        }
    }

    private static func findFiles(named basename: String, in repoPath: String, limit: Int = 25) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: repoPath),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [String] = []
        for entry in enumerator {
            guard let url = entry as? URL else { continue }
            if url.lastPathComponent == basename {
                results.append(url.path)
                if results.count >= limit { break }
            }
        }
        return results
    }
}
