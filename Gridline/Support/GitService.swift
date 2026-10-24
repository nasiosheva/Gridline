//
//  GitService.swift
//  Gridline
//
//  Pemanggilan Git lewat `Process`, selalu `--no-optional-locks` agar tidak
//  mengambil lock index yang bisa bentrok dengan commit dari agen atau
//  perintah lain yang berjalan bersamaan (D8). Baca saja, tidak pernah
//  menulis ke `.git`.
//

import Foundation

struct RepoHeaderStatus: Equatable {
    var branch: String?
    var ahead: Int = 0
    var behind: Int = 0
    var changedFileCount: Int = 0
    var isDetached: Bool = false
}

enum GitService {
    /// Mengambil ringkasan header dari keluaran status porcelain yang juga
    /// dipakai panel diff, agar repo hanya dipindai sekali saat pane dibuka.
    static func headerStatus(from output: String) -> RepoHeaderStatus {
        var status = RepoHeaderStatus()

        let lines = output.split(separator: "\n")
        for line in lines {
            if line.hasPrefix("# branch.head ") {
                let name = line.dropFirst("# branch.head ".count)
                if name == "(detached)" {
                    status.isDetached = true
                } else {
                    status.branch = String(name)
                }
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
            }
        }
        return status
    }
}
