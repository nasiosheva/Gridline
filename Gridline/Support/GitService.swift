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
    /// Status ringkas untuk header pane: branch aktif, ahead/behind terhadap
    /// upstream, dan jumlah file berubah (staged + unstaged + untracked).
    static func headerStatus(at path: String) async -> RepoHeaderStatus {
        var status = RepoHeaderStatus()

        let output = await GitProcess.run(["--no-optional-locks", "status", "--porcelain=v2", "--branch"], at: path)
        if output.exitCode == 0 {
            let lines = output.stdout.split(separator: "\n")
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
        } else {
            DiagnosticLog.shared.record(.gitStatusFailed(output.exitCode))
        }

        return status
    }
}
