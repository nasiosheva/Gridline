//
//  GitService.swift
//  Gridline
//
//  Pemanggilan Git lewat `Process`. Pemeriksaan status tetap memakai
//  `--no-optional-locks` agar tidak mengambil lock index (D8); perubahan Git
//  hanya dilakukan lewat aksi pull eksplisit yang meminta konfirmasi.
//

import Foundation

struct RepoHeaderStatus: Equatable {
    var branch: String?
    var upstream: String?
    var ahead: Int = 0
    var behind: Int = 0
    var changedFileCount: Int = 0
    var isDetached: Bool = false
}

enum GitService {
    /// Mengambil ringkasan header dari keluaran status porcelain yang juga
    /// dipakai panel diff, agar repo hanya dipindai sekali saat pane dibuka.
    static func headerStatus(from records: [Substring]) -> RepoHeaderStatus {
        var status = RepoHeaderStatus()

        var index = 0
        while index < records.count {
            let line = records[index]
            index += 1
            if line.hasPrefix("# branch.head ") {
                let name = line.dropFirst("# branch.head ".count)
                if name == "(detached)" {
                    status.isDetached = true
                } else {
                    status.branch = String(name)
                }
            } else if line.hasPrefix("# branch.upstream ") {
                status.upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                // Format: "# branch.ab +<ahead> -<behind>"
                let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                for part in parts {
                    if part.hasPrefix("+"), let value = Int(part.dropFirst()) {
                        status.ahead = value
                    } else if part.hasPrefix("-"), let value = Int(part.dropFirst()) {
                        status.behind = value
                    }
                }
            } else if !line.hasPrefix("#") {
                status.changedFileCount += 1
                if line.hasPrefix("2 "), index < records.count {
                    index += 1 // Original path of a rename/copy is a separate -z field.
                }
            }
        }
        return status
    }
}
