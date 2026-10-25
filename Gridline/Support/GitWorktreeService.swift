import CryptoKit
import Foundation

struct GitBranchChoices {
    let branches: [String]
    let currentBranch: String?
}

struct GitWorktreeDestination {
    let path: String
    let displayName: String
    let sourceRepoID: UUID
    let branch: String
}

enum GitWorktreeError: Error {
    case commandFailed(String)
    case pathAlreadyExists
}

enum GitWorktreeService {
    private struct ExistingWorktree {
        let path: String
        let branch: String?
    }

    static func branchChoices(at repoPath: String) async -> GitBranchChoices? {
        async let branchesOutput = GitProcess.run(
            ["--no-optional-locks", "branch", "--format=%(refname:short)"],
            at: repoPath
        )
        async let currentOutput = GitProcess.run(
            ["--no-optional-locks", "branch", "--show-current"],
            at: repoPath
        )
        let (branches, current) = await (branchesOutput, currentOutput)
        guard branches.exitCode == 0, current.exitCode == 0 else { return nil }
        let currentBranch = current.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitBranchChoices(
            branches: branches.stdout
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.isEmpty }
                .sorted(),
            currentBranch: currentBranch.isEmpty ? nil : currentBranch
        )
    }

    static func openOrCreateWorktree(
        branch: String,
        from repo: Repo
    ) async throws -> GitWorktreeDestination {
        async let worktreeRequest = GitProcess.run(
            ["--no-optional-locks", "worktree", "list", "--porcelain", "-z"],
            at: repo.path
        )
        async let commonDirectoryRequest = commonGitDirectory(for: repo.path)
        let (worktreeOutput, commonDirectory) = try await (worktreeRequest, commonDirectoryRequest)
        guard worktreeOutput.exitCode == 0 else {
            throw GitWorktreeError.commandFailed(worktreeOutput.stderr)
        }

        let listedWorktrees = existingWorktrees(in: worktreeOutput.stdout)
        if let worktree = listedWorktrees.first(where: {
            $0.branch == branch && FileManager.default.fileExists(atPath: $0.path)
        }) {
            return destination(path: worktree.path, commonGitDirectory: commonDirectory, sourceRepoID: repo.id, branch: branch)
        }

        if let missingWorktree = listedWorktrees.first(where: {
            $0.branch == branch && !FileManager.default.fileExists(atPath: $0.path)
        }) {
            // Git can retain metadata for a worktree whose folder was removed externally.
            // Remove only the selected worktree's stale metadata.
            let removeResult = await GitProcess.run(
                ["worktree", "remove", "--force", missingWorktree.path],
                at: repo.path
            )
            guard removeResult.exitCode == 0 else {
                throw GitWorktreeError.commandFailed(removeResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        let targetURL = worktreeURL(commonGitDirectory: commonDirectory, branch: branch)
        guard !FileManager.default.fileExists(atPath: targetURL.path) else {
            throw GitWorktreeError.pathAlreadyExists
        }
        do {
            try FileManager.default.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw GitWorktreeError.commandFailed(error.localizedDescription)
        }

        let result = await GitProcess.run(
            ["worktree", "add", "--quiet", targetURL.path, branch],
            at: repo.path
        )
        guard result.exitCode == 0 else {
            throw GitWorktreeError.commandFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return destination(path: targetURL.path, commonGitDirectory: commonDirectory, sourceRepoID: repo.id, branch: branch)
    }

    private static func existingWorktrees(in output: String) -> [ExistingWorktree] {
        var worktrees: [ExistingWorktree] = []
        var path: String?
        var branch: String?

        func appendCurrent() {
            if let path {
                worktrees.append(ExistingWorktree(path: path, branch: branch))
            }
        }

        for rawField in output.split(separator: "\0", omittingEmptySubsequences: false) {
            let field = String(rawField)
            if field.isEmpty {
                appendCurrent()
                path = nil
                branch = nil
            } else if field.hasPrefix("worktree ") {
                path = String(field.dropFirst("worktree ".count))
            } else if field.hasPrefix("branch refs/heads/") {
                branch = String(field.dropFirst("branch refs/heads/".count))
            }
        }
        appendCurrent()
        return worktrees
    }

    private static func commonGitDirectory(for repoPath: String) async throws -> URL {
        let output = await GitProcess.run(
            ["--no-optional-locks", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            at: repoPath
        )
        let value = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.exitCode == 0, !value.isEmpty else {
            throw GitWorktreeError.commandFailed(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return URL(fileURLWithPath: value).standardizedFileURL
    }

    private static func worktreeURL(commonGitDirectory: URL, branch: String) -> URL {
        let repositoryKey = digest(commonGitDirectory.path)
        let branchSlug = branch.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                return String(scalar)
            }
            return "-"
        }.joined()
        let folderName = "\(branchSlug.prefix(48))_\(digest(branch).prefix(12))"
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gridline", isDirectory: true)
            .appendingPathComponent("Worktrees", isDirectory: true)
            .appendingPathComponent(repositoryKey, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private static func destination(
        path: String,
        commonGitDirectory: URL,
        sourceRepoID: UUID,
        branch: String
    ) -> GitWorktreeDestination {
        let repositoryName = commonGitDirectory.deletingLastPathComponent().lastPathComponent
        let displayName = L10n.format(L10n.Repository.worktreeDisplayName, repositoryName, branch)
        return GitWorktreeDestination(path: path, displayName: displayName, sourceRepoID: sourceRepoID, branch: branch)
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
