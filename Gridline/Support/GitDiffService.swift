//
//  GitDiffService.swift
//  Gridline
//
//  Mengambil dan mem-parsing data untuk panel diff: daftar file berubah dari
//  `git --no-optional-locks status --porcelain=v2`, jumlah baris dari
//  `git diff --numstat`, dan isi diff per file dari `git diff` (unified).
//  Semua baca saja, tidak pernah menulis ke `.git` (D8, bagian 6).
//

import Foundation

struct GitDiffStatusSnapshot {
    let entries: [DiffFileEntry]
    let headerStatus: RepoHeaderStatus?
}

enum GitDiffService {
    nonisolated private static let maximumConcurrentUntrackedFileReads = 4
    nonisolated private static let untrackedReadChunkSize = 64 * 1024
    nonisolated private static let binaryDetectionPrefixLength = 8_000

    static func comparisonBranches(at path: String) async -> [String] {
        let branches = await GitProcess.run(
            ["--no-optional-locks", "branch", "--format=%(refname:short)"],
            at: path
        )
        guard branches.exitCode == 0 else { return [] }
        return branches.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
            .sorted()
    }

    static func comparisonEntries(at path: String, against branch: String) async -> [DiffFileEntry] {
        await comparisonEntries(at: path, revisions: [branch], readWorkingTreeMetadata: true)
    }

    static func comparisonEntries(at path: String, from baseBranch: String, to targetBranch: String) async -> [DiffFileEntry] {
        await comparisonEntries(
            at: path,
            revisions: ["\(baseBranch)...\(targetBranch)"],
            readWorkingTreeMetadata: false
        )
    }

    private static func comparisonEntries(at path: String, revisions: [String], readWorkingTreeMetadata: Bool) async -> [DiffFileEntry] {
        async let statusOutput = GitProcess.run(
            ["--no-optional-locks", "diff", "--no-ext-diff", "--name-status", "-z"] + revisions + ["--"],
            at: path
        )
        async let countsOutput = GitProcess.run(
            ["--no-optional-locks", "diff", "--no-ext-diff", "--numstat", "-z"] + revisions + ["--"],
            at: path
        )
        let (output, countsResult) = await (statusOutput, countsOutput)
        guard output.exitCode == 0 else { return [] }
        let counts = countsResult.exitCode == 0 ? parseNumstat(countsResult.stdout) : [:]
        let fields = output.stdout.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var entries: [DiffFileEntry] = []
        var index = 0
        while index < fields.count {
            let statusToken = fields[index]
            index += 1
            guard let code = statusToken.first else { continue }
            if code == "R" || code == "C" {
                guard index + 1 < fields.count else { break }
                let oldPath = fields[index]
                let newPath = fields[index + 1]
                index += 2
                let status: DiffFileStatus = code == "R" ? .renamed(from: oldPath) : .copied(from: oldPath)
                entries.append(DiffFileEntry(path: newPath, group: .unstaged, status: status))
            } else {
                guard index < fields.count else { break }
                let filePath = fields[index]
                index += 1
                let status: DiffFileStatus
                switch code {
                case "A": status = .added
                case "D": status = .deleted
                case "T": status = .typeChanged
                default: status = .modified
                }
                entries.append(DiffFileEntry(path: filePath, group: .unstaged, status: status))
            }
        }

        for index in entries.indices {
            if let lineCounts = counts[entries[index].path] {
                entries[index].additions = lineCounts.additions
                entries[index].deletions = lineCounts.deletions
            }
            if readWorkingTreeMetadata {
                let filePath = (path as NSString).appendingPathComponent(entries[index].path)
                if let attributes = try? FileManager.default.attributesOfItem(atPath: filePath) {
                    entries[index].fileSizeBytes = (attributes[.size] as? NSNumber)?.int64Value
                    entries[index].modificationDate = attributes[.modificationDate] as? Date
                }
            }
        }
        return entries
    }

    // MARK: - Status (daftar file)

    /// Mengambil daftar file berubah, dikelompokkan staged/unstaged/untracked
    /// (dan ignored bila `includeIgnored` dinyalakan dari toggle "Show Ignored
    /// Files"), lengkap dengan jumlah baris ditambah/dihapus.
    static func statusSnapshot(at path: String, includeIgnored: Bool = false) async -> GitDiffStatusSnapshot {
        var arguments = ["--no-optional-locks", "status", "--porcelain=v2", "--branch", "-z"]
        if includeIgnored {
            // Mode "traditional" (default `--ignored`), bukan "matching": direktori yang
            // seluruhnya diabaikan (mis. node_modules/, .build/) dilaporkan sebagai satu
            // entri, bukan setiap file di dalamnya satu per satu — jauh lebih murah untuk
            // repo besar sesuai prinsip hemat resource di CLAUDE.md.
            arguments += ["--ignored"]
        }
        let statusOutput = await GitProcess.run(arguments, at: path)
        guard statusOutput.exitCode == 0 else {
            DiagnosticLog.shared.record(.gitStatusFailed(statusOutput.exitCode))
            return GitDiffStatusSnapshot(entries: [], headerStatus: nil)
        }

        let records = statusOutput.stdout.split(separator: "\0", omittingEmptySubsequences: true)
        var entries = parsePorcelainV2(records)
        let headerStatus = GitService.headerStatus(from: records)
        let untrackedFiles = entries.filter { $0.group == .untracked }.map(\.path)

        async let stagedCounts = numstat(at: path, cached: true)
        async let unstagedCounts = numstat(at: path, cached: false)
        async let untrackedCountsRequest = untrackedCounts(at: path, files: untrackedFiles)
        let (staged, unstaged, untracked) = await (stagedCounts, unstagedCounts, untrackedCountsRequest)

        for index in entries.indices {
            switch entries[index].group {
            case .staged:
                if let counts = staged[entries[index].path] {
                    entries[index].additions = counts.additions
                    entries[index].deletions = counts.deletions
                }
            case .unstaged:
                if let counts = unstaged[entries[index].path] {
                    entries[index].additions = counts.additions
                    entries[index].deletions = counts.deletions
                }
            case .untracked:
                if let counts = untracked[entries[index].path] {
                    entries[index].additions = counts.additions
                    entries[index].deletions = counts.deletions
                }
            case .ignored:
                break
            }

            let absolutePath = (path as NSString).appendingPathComponent(entries[index].path)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: absolutePath) {
                entries[index].fileSizeBytes = (attributes[.size] as? NSNumber)?.int64Value
                entries[index].modificationDate = attributes[.modificationDate] as? Date
            }
        }

        return GitDiffStatusSnapshot(entries: entries, headerStatus: headerStatus)
    }

    private static func parsePorcelainV2(_ records: [Substring]) -> [DiffFileEntry] {
        var entries: [DiffFileEntry] = []
        var index = 0
        while index < records.count {
            let record = records[index]
            index += 1
            if record.hasPrefix("1 ") {
                // 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
                let fields = record.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
                guard fields.count == 9 else { continue }
                let xy = fields[1]
                let filePath = String(fields[8])
                appendOrdinary(xy: xy, path: filePath, into: &entries)
            } else if record.hasPrefix("2 ") {
                // With -z, the original path follows as a separate NUL-terminated field.
                let fields = record.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: true)
                guard fields.count == 10 else { continue }
                guard index < records.count else { break }
                let xy = fields[1]
                let originalPath = String(records[index])
                index += 1
                appendRenameOrCopy(xy: xy, path: String(fields[9]), origPath: originalPath, into: &entries)
            } else if record.hasPrefix("u ") {
                // u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
                let fields = record.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: true)
                guard fields.count == 11 else { continue }
                let filePath = String(fields[10])
                entries.append(DiffFileEntry(path: filePath, group: .staged, status: .unmerged))
                entries.append(DiffFileEntry(path: filePath, group: .unstaged, status: .unmerged))
            } else if record.hasPrefix("? ") {
                let filePath = String(record.dropFirst(2))
                entries.append(DiffFileEntry(path: filePath, group: .untracked, status: .untracked))
            } else if record.hasPrefix("! ") {
                // Hanya muncul saat `--ignored=matching` diminta lewat toggle
                // "Show Ignored Files" (lihat `statusSnapshot(includeIgnored:)`).
                let filePath = String(record.dropFirst(2))
                entries.append(DiffFileEntry(path: filePath, group: .ignored, status: .ignored))
            }
        }

        return entries
    }

    private static func appendOrdinary(xy: Substring, path: String, into entries: inout [DiffFileEntry]) {
        guard xy.count == 2 else { return }
        let x = xy[xy.startIndex]
        let y = xy[xy.index(after: xy.startIndex)]
        if x != ".", let status = statusFromCode(x) {
            entries.append(DiffFileEntry(path: path, group: .staged, status: status))
        }
        if y != ".", let status = statusFromCode(y) {
            entries.append(DiffFileEntry(path: path, group: .unstaged, status: status))
        }
    }

    private static func appendRenameOrCopy(xy: Substring, path: String, origPath: String, into entries: inout [DiffFileEntry]) {
        guard xy.count == 2 else { return }
        let x = xy[xy.startIndex]
        let y = xy[xy.index(after: xy.startIndex)]
        let stagedStatus: DiffFileStatus = (x == "C") ? .copied(from: origPath) : .renamed(from: origPath)
        if x != "." {
            entries.append(DiffFileEntry(path: path, group: .staged, status: stagedStatus))
        }
        if y != ".", let status = statusFromCode(y) {
            entries.append(DiffFileEntry(path: path, group: .unstaged, status: status))
        }
    }

    private static func statusFromCode(_ code: Character) -> DiffFileStatus? {
        switch code {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "T": return .typeChanged
        case "U": return .unmerged
        default: return nil
        }
    }

    // MARK: - Jumlah baris (numstat)

    nonisolated private struct LineCounts: Sendable {
        let additions: Int?
        let deletions: Int?
    }

    nonisolated private static func untrackedCounts(at path: String, files: [String]) async -> [String: LineCounts] {
        guard !files.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, LineCounts?).self) { group in
            var result: [String: LineCounts] = [:]
            var nextFileIndex = 0

            for _ in 0..<min(maximumConcurrentUntrackedFileReads, files.count) {
                let file = files[nextFileIndex]
                nextFileIndex += 1
                group.addTask {
                    (file, untrackedCount(at: path, file: file))
                }
            }

            while let (file, counts) = await group.next() {
                if let counts {
                    result[file] = counts
                }
                guard nextFileIndex < files.count else { continue }
                let nextFile = files[nextFileIndex]
                nextFileIndex += 1
                group.addTask {
                    (nextFile, untrackedCount(at: path, file: nextFile))
                }
            }

            return result
        }
    }

    private static func numstat(at path: String, cached: Bool) async -> [String: LineCounts] {
        var args = ["--no-optional-locks", "diff", "--numstat", "-z"]
        if cached { args.insert("--cached", at: 2) }
        let output = await GitProcess.run(args, at: path)
        guard output.exitCode == 0 else { return [:] }
        return parseNumstat(output.stdout)
    }

    private static func parseNumstat(_ output: String) -> [String: LineCounts] {
        var result: [String: LineCounts] = [:]
        let records = output.split(separator: "\0", omittingEmptySubsequences: false)
        var index = 0
        while index < records.count {
            let record = records[index]
            index += 1
            let fields = record.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            let added = Int(fields[0])
            let deleted = Int(fields[1])
            let filePath: String
            if fields[2].isEmpty {
                // Rename/copy: counts<TAB><NUL>oldPath<NUL>newPath<NUL>.
                guard index + 1 < records.count else { break }
                filePath = String(records[index + 1])
                index += 2
            } else {
                filePath = String(fields[2])
            }
            result[filePath] = LineCounts(additions: added, deletions: deleted)
        }
        return result
    }

    nonisolated private static func untrackedCount(at path: String, file: String) -> LineCounts? {
        let fileURL = URL(fileURLWithPath: (path as NSString).appendingPathComponent(file))
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileType = attributes[.type] as? FileAttributeType else { return nil }

        if fileType == .typeSymbolicLink {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: fileURL.path) else { return nil }
            let bytes = Array(destination.utf8)
            var lineCount = 0
            for byte in bytes where byte == 0x0A {
                lineCount += 1
            }
            if !bytes.isEmpty, bytes.last != 0x0A {
                lineCount += 1
            }
            return LineCounts(additions: lineCount, deletions: 0)
        }

        guard fileType == .typeRegular else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        var lineCount = 0
        var inspectedPrefixLength = 0
        var lastByte: UInt8?

        do {
            while let chunk = try handle.read(upToCount: untrackedReadChunkSize), !chunk.isEmpty {
                for byte in chunk {
                    if inspectedPrefixLength < binaryDetectionPrefixLength {
                        if byte == 0 {
                            return LineCounts(additions: nil, deletions: nil)
                        }
                        inspectedPrefixLength += 1
                    }
                    if byte == 0x0A {
                        lineCount += 1
                    }
                }
                lastByte = chunk.last
            }
        } catch {
            return nil
        }

        if let lastByte, lastByte != 0x0A {
            lineCount += 1
        }
        return LineCounts(additions: lineCount, deletions: 0)
    }

    // MARK: - Isi diff per file

    static func fileDiff(at repoPath: String, for entry: DiffFileEntry) async -> FileDiff {
        // Direktori yang seluruhnya diabaikan dilaporkan git sebagai satu entri
        // dengan "/" di akhir (mode "traditional", lihat `statusSnapshot`) —
        // `git diff --no-index` tidak bisa membandingkan direktori, jadi tidak
        // perlu memanggil proses Git sama sekali untuk kasus ini.
        if entry.status == .ignored, entry.path.hasSuffix("/") {
            return FileDiff(entry: entry, hunks: [], isBinary: false, rawText: "")
        }

        let output: GitProcess.Output
        switch entry.group {
        case .staged:
            output = await GitProcess.run(["--no-optional-locks", "diff", "--cached", "--", entry.path], at: repoPath)
        case .unstaged:
            output = await GitProcess.run(["--no-optional-locks", "diff", "--", entry.path], at: repoPath)
        case .untracked, .ignored:
            output = await GitProcess.run(["--no-optional-locks", "diff", "--no-index", "--", "/dev/null", entry.path], at: repoPath)
        }

        if output.stdout.contains("Binary files") {
            return FileDiff(entry: entry, hunks: [], isBinary: true, rawText: output.stdout)
        }

        return FileDiff(entry: entry, hunks: parseUnifiedDiff(output.stdout), isBinary: false, rawText: output.stdout)
    }

    static func fileDiff(at repoPath: String, against branch: String, for entry: DiffFileEntry) async -> FileDiff {
        let output = await GitProcess.run(
            ["--no-optional-locks", "diff", "--no-ext-diff", branch, "--", entry.path],
            at: repoPath
        )
        return fileDiff(output: output, entry: entry)
    }

    static func fileDiff(at repoPath: String, from baseBranch: String, to targetBranch: String, for entry: DiffFileEntry) async -> FileDiff {
        let output = await GitProcess.run(
            ["--no-optional-locks", "diff", "--no-ext-diff", "\(baseBranch)...\(targetBranch)", "--", entry.path],
            at: repoPath
        )
        return fileDiff(output: output, entry: entry)
    }

    private static func fileDiff(output: GitProcess.Output, entry: DiffFileEntry) -> FileDiff {
        if output.stdout.contains("Binary files") {
            return FileDiff(entry: entry, hunks: [], isBinary: true, rawText: output.stdout)
        }
        return FileDiff(entry: entry, hunks: parseUnifiedDiff(output.stdout), isBinary: false, rawText: output.stdout)
    }

    // MARK: - "Salin perintah"

    /// Perintah untuk tombol "Salin Perintah" (bagian 17a apps-spec.md):
    /// kebalikan dari status saat ini — stage untuk unstaged/untracked,
    /// unstage untuk staged. Apps tidak pernah menjalankan ini sendiri,
    /// hanya menyalin ke clipboard untuk dijalankan manual di terminal.
    static func toggleStageCommand(for entry: DiffFileEntry) -> String {
        let quotedPath = shellQuoted(entry.path)
        switch entry.group {
        case .staged:
            return "git restore --staged \(quotedPath)"
        case .unstaged, .untracked:
            return "git add \(quotedPath)"
        case .ignored:
            return "git add -f \(quotedPath)"
        }
    }

    private static func shellQuoted(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func parseUnifiedDiff(_ text: String) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var currentHeader: String?
        var currentLines: [DiffLine] = []
        var oldLine = 0
        var newLine = 0

        func flushHunk() {
            if let header = currentHeader {
                hunks.append(DiffHunk(header: header, lines: currentLines))
            }
            currentHeader = nil
            currentLines = []
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("@@") {
                flushHunk()
                currentHeader = line
                let (o, n) = parseHunkHeader(line)
                oldLine = o
                newLine = n
            } else if currentHeader != nil {
                if line.hasPrefix("+") {
                    currentLines.append(DiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: newLine, text: String(line.dropFirst())))
                    newLine += 1
                } else if line.hasPrefix("-") {
                    currentLines.append(DiffLine(kind: .deletion, oldLineNumber: oldLine, newLineNumber: nil, text: String(line.dropFirst())))
                    oldLine += 1
                } else if line.hasPrefix("\\") {
                    // "\ No newline at end of file" — diabaikan, tidak memengaruhi nomor baris.
                    continue
                } else {
                    let text = line.isEmpty ? "" : String(line.dropFirst())
                    currentLines.append(DiffLine(kind: .context, oldLineNumber: oldLine, newLineNumber: newLine, text: text))
                    oldLine += 1
                    newLine += 1
                }
            }
        }
        flushHunk()
        return hunks
    }

    private static func parseHunkHeader(_ header: String) -> (old: Int, new: Int) {
        // Format: "@@ -<oldStart>[,<oldCount>] +<newStart>[,<newCount>] @@ ..."
        let scanner = Scanner(string: header)
        _ = scanner.scanUpToString("-")
        _ = scanner.scanString("-")
        let oldStart = scanner.scanInt() ?? 1
        _ = scanner.scanUpToString("+")
        _ = scanner.scanString("+")
        let newStart = scanner.scanInt() ?? 1
        return (oldStart, newStart)
    }
}
