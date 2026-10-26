import Foundation

/// Memasangkan baris hapus dan tambah yang berdekatan dalam satu hunk supaya
/// bisa ditampilkan berdampingan (mode split) atau dibandingkan kata per kata
/// (word-level highlight, lihat `WordDiffPolicy`). Baris konteks dipasangkan
/// dengan dirinya sendiri; baris tambah/hapus murni tanpa pasangan mendapat
/// `nil` di sisi lainnya.
enum DiffLinePairingPolicy {
    static func pairs(in lines: [DiffLine]) -> [(DiffLine?, DiffLine?)] {
        var rows: [(DiffLine?, DiffLine?)] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            switch line.kind {
            case .context:
                rows.append((line, line))
                index += 1
            case .deletion:
                var deletions: [DiffLine] = []
                while index < lines.count, lines[index].kind == .deletion {
                    deletions.append(lines[index])
                    index += 1
                }
                var additions: [DiffLine] = []
                while index < lines.count, lines[index].kind == .addition {
                    additions.append(lines[index])
                    index += 1
                }
                let maxCount = max(deletions.count, additions.count)
                for i in 0..<maxCount {
                    rows.append((i < deletions.count ? deletions[i] : nil, i < additions.count ? additions[i] : nil))
                }
            case .addition:
                rows.append((nil, line))
                index += 1
            }
        }
        return rows
    }
}
