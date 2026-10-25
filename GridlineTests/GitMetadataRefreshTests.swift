import XCTest
@testable import Gridline

@MainActor
final class GitMetadataRefreshTests: XCTestCase {
    func testGitAndCommonDirectoriesResolveRegularAndLinkedWorktrees() throws {
        let repository = try TemporaryGitRepository()
        let gitDirectory = repository.url.appendingPathComponent(".git", isDirectory: true)
        XCTAssertEqual(GitMetadataWatcher.gitDirectory(for: repository.url.path), gitDirectory.standardizedFileURL)
        XCTAssertEqual(GitMetadataWatcher.commonDirectory(for: gitDirectory), gitDirectory.standardizedFileURL)

        let commonDirectory = repository.url.appendingPathComponent("common", isDirectory: true)
        try FileManager.default.createDirectory(at: commonDirectory, withIntermediateDirectories: true)
        try Data("../common\n".utf8).write(to: gitDirectory.appendingPathComponent("commondir"))
        XCTAssertEqual(GitMetadataWatcher.commonDirectory(for: gitDirectory), commonDirectory.standardizedFileURL)

        let linkedWorktree = repository.url.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: linkedWorktree, withIntermediateDirectories: true)
        let worktreeMetadata = gitDirectory.appendingPathComponent("worktrees/linked", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreeMetadata, withIntermediateDirectories: true)
        try Data("gitdir: ../.git/worktrees/linked\n".utf8).write(to: linkedWorktree.appendingPathComponent(".git"))
        XCTAssertEqual(GitMetadataWatcher.gitDirectory(for: linkedWorktree.path), worktreeMetadata.standardizedFileURL)

        let invalidWorktree = repository.url.appendingPathComponent("invalid", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidWorktree, withIntermediateDirectories: true)
        try Data("not a gitdir file\n".utf8).write(to: invalidWorktree.appendingPathComponent(".git"))
        XCTAssertNil(GitMetadataWatcher.gitDirectory(for: invalidWorktree.path))
        XCTAssertNil(GitMetadataWatcher.gitDirectory(for: invalidWorktree.appendingPathComponent("missing").path))
    }

    func testIndexOnlyChangeRefreshesStagedStatus() async throws {
        let repository = try TemporaryGitRepository()
        let store = RepoDiffStore(repoPath: repository.url.path)
        store.setWatching(true)
        defer { store.setWatching(false) }

        try await waitUntil { store.hasLoadedInitialStatus }
        XCTAssertTrue(store.staged.isEmpty)

        try repository.git("update-index", "--chmod=+x", "tracked.txt")

        try await waitUntil {
            store.staged.contains { $0.path == "tracked.txt" }
        }
    }

    func testCurrentBranchRefChangeRefreshesWithoutChangingHeadFile() async throws {
        let repository = try TemporaryGitRepository()
        let headURL = repository.url.appendingPathComponent(".git/HEAD")
        let headBefore = try Data(contentsOf: headURL)
        let changed = expectation(description: "current branch ref change is observed")
        let watcher = try XCTUnwrap(GitMetadataWatcher(
            repoPath: repository.url.path,
            watchedBranches: { [] },
            onChange: { changed.fulfill() }
        ))
        defer { watcher.stop() }

        try repository.advanceBranch("main")
        XCTAssertEqual(try Data(contentsOf: headURL), headBefore)

        await fulfillment(of: [changed], timeout: 4)
    }

    func testWatchedComparisonBranchRefChangeIsObserved() async throws {
        let repository = try TemporaryGitRepository()
        try repository.git("branch", "comparison")
        let changed = expectation(description: "comparison branch ref change is observed")
        let watcher = try XCTUnwrap(GitMetadataWatcher(
            repoPath: repository.url.path,
            watchedBranches: { ["comparison"] },
            onChange: { changed.fulfill() }
        ))
        defer { watcher.stop() }

        try repository.advanceBranch("comparison")

        await fulfillment(of: [changed], timeout: 4)
    }

    func testBranchRefChangeReloadsSelectedDiffWhenCountsStayEqual() async throws {
        let repository = try TemporaryGitRepository()
        try repository.git("branch", "comparison")
        try repository.advanceBranch("comparison", fileContents: "first version\n")

        let store = RepoDiffStore(repoPath: repository.url.path)
        store.setWatching(true)
        defer { store.setWatching(false) }

        try await waitUntil { store.availableComparisonBranches.contains("comparison") }
        store.selectComparisonBranches(from: "main", to: "comparison")
        try await waitUntil { store.selectedDiff?.rawText.contains("+first version") == true }
        let originalEntry = try XCTUnwrap(store.comparisonEntries.first)

        try repository.advanceBranch("comparison", fileContents: "updated version\n")

        try await waitUntil { store.selectedDiff?.rawText.contains("+updated version") == true }
        let updatedEntry = try XCTUnwrap(store.comparisonEntries.first)
        XCTAssertEqual(updatedEntry.additions, originalEntry.additions)
        XCTAssertEqual(updatedEntry.deletions, originalEntry.deletions)
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("The expected Git status did not arrive before the timeout.")
    }
}

@MainActor
final class RepoDiffStoreTests: XCTestCase {
    func testRefreshPartitionsStatusAndSelectsFilesWithinBounds() async throws {
        let repository = try TemporaryGitRepository()
        try Data("staged version\n".utf8).write(to: repository.url.appendingPathComponent("tracked.txt"))
        try repository.git("add", "tracked.txt")
        try Data("working version\n".utf8).write(to: repository.url.appendingPathComponent("tracked.txt"))
        try Data("new file\n".utf8).write(to: repository.url.appendingPathComponent("new.txt"))

        let store = RepoDiffStore(repoPath: repository.url.path)
        await store.refresh()

        XCTAssertEqual(store.staged.map(\.path), ["tracked.txt"])
        XCTAssertEqual(store.unstaged.map(\.path), ["tracked.txt"])
        XCTAssertEqual(store.untracked.map(\.path), ["new.txt"])
        XCTAssertEqual(store.totalChangedFileCount, 2)
        XCTAssertEqual(store.displayedEntries.count, 3)
        XCTAssertNotNil(store.headerStatus)
        XCTAssertNotNil(store.selectedDiff)

        store.selectAdjacent(offset: -10)
        XCTAssertEqual(store.selectedFileID, store.displayedEntries.first?.id)
        store.selectAdjacent(offset: 10)
        XCTAssertEqual(store.selectedFileID, store.displayedEntries.last?.id)
        store.selectAdjacent(offset: 1)
        XCTAssertEqual(store.selectedFileID, store.displayedEntries.last?.id)
        store.selectAdjacent(offset: -1, within: [])
        XCTAssertEqual(store.selectedFileID, store.displayedEntries.last?.id)
    }

    func testInitialComparisonBranchIsAppliedAndConsumedOnce() async throws {
        let repository = try TemporaryGitRepository()
        try repository.git("branch", "comparison")
        try repository.advanceBranch("comparison", fileContents: "comparison version\n")
        let store = RepoDiffStore(repoPath: repository.url.path, initialComparisonBranch: "comparison")
        var consumedCount = 0
        var selectionChanges: [DiffComparisonSelection] = []
        store.onInitialComparisonBranchConsumed = { consumedCount += 1 }
        store.onComparisonSelectionChanged = { selectionChanges.append($0) }

        await store.refresh()

        XCTAssertEqual(store.availableComparisonBranches, ["comparison", "main"])
        XCTAssertEqual(store.comparisonBranch, "comparison")
        XCTAssertEqual(store.displayedEntries, store.comparisonEntries)
        XCTAssertEqual(consumedCount, 1)
        XCTAssertEqual(selectionChanges.count, 1)
        XCTAssertEqual(selectionChanges.first, .againstBranch("comparison"))
        try await waitUntil { store.selectedDiff?.rawText.contains("comparison version") == true }

        await store.refresh()
        XCTAssertEqual(consumedCount, 1)
    }

    func testSavedSelectionWinsAndInvalidComparisonFallsBackToLocalChanges() async throws {
        let repository = try TemporaryGitRepository()
        try repository.git("branch", "comparison")
        let saved = RepoDiffStore(
            repoPath: repository.url.path,
            initialComparisonBranch: "comparison",
            savedComparisonSelection: .localChanges
        )
        var consumedSavedDefault = 0
        saved.onInitialComparisonBranchConsumed = { consumedSavedDefault += 1 }
        await saved.refresh()
        XCTAssertNil(saved.comparisonBranch)
        XCTAssertEqual(consumedSavedDefault, 1)

        let invalid = RepoDiffStore(repoPath: repository.url.path, savedComparisonSelection: .againstBranch("missing"))
        var changes: [DiffComparisonSelection] = []
        invalid.onComparisonSelectionChanged = { changes.append($0) }
        await invalid.refresh()
        XCTAssertNil(invalid.comparisonBranch)
        XCTAssertTrue(invalid.comparisonEntries.isEmpty)
        XCTAssertEqual(changes.last, .localChanges)
    }

    func testSelectBranchesRejectsInvalidPairsAndLoadsValidComparison() async throws {
        let repository = try TemporaryGitRepository()
        try repository.git("branch", "comparison")
        try repository.advanceBranch("comparison", fileContents: "branch diff\n")
        let store = RepoDiffStore(repoPath: repository.url.path)
        await store.refresh()

        store.selectComparisonBranches(from: "main", to: "missing")
        XCTAssertFalse(store.isComparingBranches)
        store.selectComparisonBranches(from: "main", to: "main")
        XCTAssertFalse(store.isComparingBranches)
        store.selectComparisonBranches(from: "main", to: "comparison")
        XCTAssertTrue(store.isComparingBranches)
        XCTAssertEqual(store.comparisonBaseBranch, "main")
        XCTAssertEqual(store.comparisonTargetBranch, "comparison")
        try await waitUntil { store.selectedDiff?.rawText.contains("branch diff") == true }

        store.selectComparisonBranch(nil)
        try await waitUntil { !store.isComparingBranches }
        XCTAssertNil(store.comparisonBranch)
    }

    func testSelectionAndMetadataRefreshUpdateDiff() async throws {
        let repository = try TemporaryGitRepository()
        try Data("changed\n".utf8).write(to: repository.url.appendingPathComponent("tracked.txt"))
        let store = RepoDiffStore(repoPath: repository.url.path)
        await store.refresh()
        let entry = try XCTUnwrap(store.allEntries.first)
        store.select(entry)
        try await waitUntil { store.selectedDiff?.rawText.contains("changed") == true }
        store.select(entry)
        XCTAssertEqual(store.selectedFileID, entry.id)

        store.selectComparisonBranch("main")
        try await waitUntil { store.comparisonBranch == "main" }
        store.refreshGitMetadata()
        try await waitUntil { store.hasLoadedInitialStatus }
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("The expected diff store state did not arrive before the timeout.")
    }
}

@MainActor
final class GitWorktreeServiceTests: XCTestCase {
    func testBranchChoicesAreSortedAndExposeCurrentBranch() async throws {
        let repository = try TemporaryGitRepository()
        try repository.git("branch", "zeta")
        try repository.git("branch", "alpha")

        let result = await GitWorktreeService.branchChoices(at: repository.url.path)
        let choices = try XCTUnwrap(result)

        XCTAssertEqual(choices.branches, ["alpha", "main", "zeta"])
        XCTAssertEqual(choices.currentBranch, "main")
    }

    func testCreatesAndReopensExistingWorktree() async throws {
        let repository = try TemporaryGitRepository()
        let branch = "coverage-create-\(UUID().uuidString.prefix(8))"
        try repository.git("branch", branch)
        let source = Repo(path: repository.url.path)

        let created = try await GitWorktreeService.openOrCreateWorktree(branch: branch, from: source)
        defer { _ = try? repository.git("worktree", "remove", "--force", created.path) }

        XCTAssertEqual(created.branch, branch)
        XCTAssertEqual(created.sourceRepoID, source.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: created.path).appendingPathComponent(".git").path))
        XCTAssertTrue(created.displayName.contains(branch))

        let reopened = try await GitWorktreeService.openOrCreateWorktree(branch: branch, from: source)
        XCTAssertEqual(reopened.path, created.path)
    }

    func testRecreatesWorktreeWhenItsFolderWasRemoved() async throws {
        let repository = try TemporaryGitRepository()
        let branch = "coverage-stale-\(UUID().uuidString.prefix(8))"
        try repository.git("branch", branch)
        let source = Repo(path: repository.url.path)
        let first = try await GitWorktreeService.openOrCreateWorktree(branch: branch, from: source)

        try FileManager.default.removeItem(atPath: first.path)
        let recreated = try await GitWorktreeService.openOrCreateWorktree(branch: branch, from: source)
        defer { _ = try? repository.git("worktree", "remove", "--force", recreated.path) }

        XCTAssertEqual(recreated.path, first.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recreated.path))
        let worktrees = try repository.git("worktree", "list", "--porcelain")
        XCTAssertEqual(worktrees.components(separatedBy: "branch refs/heads/\(branch)").count - 1, 1)
    }

    func testReportsPathAlreadyExistsAndInvalidRepositoryErrors() async throws {
        let repository = try TemporaryGitRepository()
        let branch = "coverage-existing-\(UUID().uuidString.prefix(8))"
        try repository.git("branch", branch)
        let source = Repo(path: repository.url.path)
        let first = try await GitWorktreeService.openOrCreateWorktree(branch: branch, from: source)
        try repository.git("worktree", "remove", "--force", first.path)
        try FileManager.default.createDirectory(atPath: first.path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: first.path) }

        do {
            _ = try await GitWorktreeService.openOrCreateWorktree(branch: branch, from: source)
            XCTFail("Expected pathAlreadyExists")
        } catch GitWorktreeError.pathAlreadyExists {
            // Expected.
        }

        let invalid = Repo(path: repository.url.appendingPathComponent("missing").path)
        let choices = await GitWorktreeService.branchChoices(at: invalid.path)
        XCTAssertNil(choices)
        do {
            _ = try await GitWorktreeService.openOrCreateWorktree(branch: branch, from: invalid)
            XCTFail("Expected commandFailed")
        } catch GitWorktreeError.commandFailed {
            // Expected.
        }
    }
}

@MainActor
final class GitDiffServiceTests: XCTestCase {
    func testStatusSnapshotHandlesRenamesUntrackedTabsAndBinaryFiles() async throws {
        let repository = try TemporaryGitRepository()
        try repository.git("mv", "tracked.txt", "renamed.txt")
        let tabbedPath = "new\tfile.txt"
        try Data("new file\n".utf8).write(to: repository.url.appendingPathComponent(tabbedPath))
        try Data([0, 1, 2, 3]).write(to: repository.url.appendingPathComponent("binary.bin"))

        let snapshot = await GitDiffService.statusSnapshot(at: repository.url.path)
        let renamed = try XCTUnwrap(snapshot.entries.first {
            $0.path == "renamed.txt" && $0.group == .staged
        })
        guard case .renamed(let original) = renamed.status else {
            return XCTFail("Expected a staged rename")
        }
        XCTAssertEqual(original, "tracked.txt")
        XCTAssertTrue(snapshot.entries.contains { $0.path == tabbedPath && $0.group == .untracked })
        let binary = try XCTUnwrap(snapshot.entries.first { $0.path == "binary.bin" })
        XCTAssertNil(binary.additions)
        XCTAssertNil(binary.deletions)
    }

    func testFileDiffCoversGroupsAndShellSafeStageCommands() async throws {
        let repository = try TemporaryGitRepository()
        try Data("working\n".utf8).write(to: repository.url.appendingPathComponent("tracked.txt"))
        try Data("staged\n".utf8).write(to: repository.url.appendingPathComponent("staged.txt"))
        try repository.git("add", "staged.txt")
        try Data([0, 1, 2]).write(to: repository.url.appendingPathComponent("binary.bin"))

        let unstagedEntry = DiffFileEntry(path: "tracked.txt", group: .unstaged, status: .modified)
        let stagedEntry = DiffFileEntry(path: "staged.txt", group: .staged, status: .added)
        let untrackedEntry = DiffFileEntry(path: "binary.bin", group: .untracked, status: .untracked)
        let unstagedDiff = await GitDiffService.fileDiff(at: repository.url.path, for: unstagedEntry)
        let stagedDiff = await GitDiffService.fileDiff(at: repository.url.path, for: stagedEntry)
        let binaryDiff = await GitDiffService.fileDiff(at: repository.url.path, for: untrackedEntry)

        XCTAssertFalse(unstagedDiff.hunks.isEmpty)
        XCTAssertFalse(stagedDiff.hunks.isEmpty)
        XCTAssertTrue(binaryDiff.isBinary)
        let quoted = DiffFileEntry(path: "dir/O'Reilly.txt", group: .unstaged, status: .modified)
        XCTAssertEqual(GitDiffService.toggleStageCommand(for: quoted), "git add 'dir/O'\\''Reilly.txt'")
        XCTAssertEqual(GitDiffService.toggleStageCommand(for: stagedEntry), "git restore --staged 'staged.txt'")
    }

    func testComparisonBranchesEntriesAndInvalidRepository() async throws {
        let repository = try TemporaryGitRepository()
        try repository.git("branch", "comparison")
        try repository.advanceBranch("comparison", fileContents: "comparison\n")

        let branches = await GitDiffService.comparisonBranches(at: repository.url.path)
        let invalidBranches = await GitDiffService.comparisonBranches(at: "/tmp/not-a-repository")
        XCTAssertEqual(branches, ["comparison", "main"])
        XCTAssertEqual(invalidBranches, [])

        let entries = await GitDiffService.comparisonEntries(at: repository.url.path, from: "main", to: "comparison")
        let entry = try XCTUnwrap(entries.first { $0.path == "tracked.txt" })
        let diff = await GitDiffService.fileDiff(at: repository.url.path, from: "main", to: "comparison", for: entry)
        XCTAssertTrue(diff.rawText.contains("comparison"))
        XCTAssertFalse(diff.hunks.isEmpty)
    }
}

private final class TemporaryGitRepository {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GridlineGitMetadataTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try git("init", "--quiet", "-b", "main")
        try git("config", "user.name", "Gridline Tests")
        try git("config", "user.email", "gridline-tests@example.invalid")
        try Data("initial\n".utf8).write(to: url.appendingPathComponent("tracked.txt"))
        try git("add", "tracked.txt")
        try git("commit", "--quiet", "-m", "initial")
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func advanceBranch(_ branch: String, fileContents: String? = nil) throws {
        let tree: String
        if let fileContents {
            let blob = try runGit(["hash-object", "-w", "--stdin"], input: Data(fileContents.utf8))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let treeEntry = "100644 blob \(blob)\ttracked.txt\n"
            tree = try runGit(["mktree"], input: Data(treeEntry.utf8))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            tree = try git("rev-parse", "\(branch)^{tree}").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let parent = try git("rev-parse", branch).trimmingCharacters(in: .whitespacesAndNewlines)
        let commit = try git(
            "commit-tree", tree, "-p", parent, "-m", "metadata watcher \(UUID().uuidString)"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        try git("update-ref", "refs/heads/\(branch)", commit)
    }

    @discardableResult
    func git(_ arguments: String...) throws -> String {
        try runGit(arguments)
    }

    @discardableResult
    private func runGit(_ arguments: [String], input: Data? = nil) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = input.map { _ in Pipe() }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", url.path] + arguments
        if let stdin {
            process.standardInput = stdin
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        if let input, let stdin {
            stdin.fileHandleForWriting.write(input)
            try stdin.fileHandleForWriting.close()
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: error, encoding: .utf8) ?? "Unknown Git error"
            throw NSError(domain: "GridlineGitMetadataTests", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
        return String(data: output, encoding: .utf8) ?? ""
    }
}
