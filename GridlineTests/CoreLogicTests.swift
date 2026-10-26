import AppKit
import PDFKit
import XCTest
import UserNotifications
import SwiftUI
@testable import Gridline

@MainActor
final class TerminalLinkResolverTests: XCTestCase {
    func testParsesPlainPathAndLineAndColumnSuffixes() {
        XCTAssertEqual(TerminalLinkResolver.parse("Sources/File.swift").pathText, "Sources/File.swift")
        XCTAssertNil(TerminalLinkResolver.parse("Sources/File.swift").line)

        let line = TerminalLinkResolver.parse("Sources/File.swift:42")
        XCTAssertEqual(line.pathText, "Sources/File.swift")
        XCTAssertEqual(line.line, 42)

        let lineAndColumn = TerminalLinkResolver.parse("/tmp/a:b/File.swift:12:4")
        XCTAssertEqual(lineAndColumn.pathText, "/tmp/a:b/File.swift")
        XCTAssertEqual(lineAndColumn.line, 12)
    }

    func testKeepsMalformedSuffixAndParsesWindowsDriveLetter() {
        let malformed = TerminalLinkResolver.parse("File.swift:line")
        XCTAssertEqual(malformed.pathText, "File.swift:line")
        XCTAssertNil(malformed.line)

        let drivePath = TerminalLinkResolver.parse("C:\\work\\File.swift:9")
        XCTAssertEqual(drivePath.pathText, "C:\\work\\File.swift")
        XCTAssertEqual(drivePath.line, 9)
    }

    func testResolvesExistingRelativeAndAbsolutePaths() throws {
        let directory = try TemporaryTestDirectory()
        let file = try directory.write("Sources/File.swift", contents: "let value = 1\n")

        XCTAssertEqual(
            TerminalLinkResolver.resolve(raw: "Sources/File.swift:7", cwd: directory.url.path, repoPath: directory.url.path),
            .file(path: file.path, line: 7, isOutsideRepo: false)
        )
        XCTAssertEqual(
            TerminalLinkResolver.resolve(raw: file.path, cwd: "/", repoPath: directory.url.path),
            .file(path: file.path, line: nil, isOutsideRepo: false)
        )
    }

    func testMarksExistingFileOutsideRepository() throws {
        let repo = try TemporaryTestDirectory()
        let outside = try TemporaryTestDirectory()
        let file = try outside.write("External.swift", contents: "")

        XCTAssertEqual(
            TerminalLinkResolver.resolve(raw: file.path, cwd: repo.url.path, repoPath: repo.url.path),
            .file(path: file.path, line: nil, isOutsideRepo: true)
        )
    }

    func testFindsOneNestedBasenameAndReportsAmbiguousBasenames() throws {
        let directory = try TemporaryTestDirectory()
        _ = try directory.write("Sources/Unique.swift", contents: "")
        let uniqueResult = TerminalLinkResolver.resolve(raw: "Unique.swift:3", cwd: directory.url.path, repoPath: directory.url.path)
        guard case .file(let uniquePath, let uniqueLine, let uniqueIsOutsideRepo) = uniqueResult else {
            return XCTFail("Expected the unique basename to resolve")
        }
        XCTAssertTrue(uniquePath.hasSuffix("Sources/Unique.swift"))
        XCTAssertEqual(uniqueLine, 3)
        XCTAssertFalse(uniqueIsOutsideRepo)

        let first = try directory.write("One/Shared.swift", contents: "")
        let second = try directory.write("Two/Shared.swift", contents: "")
        let result = TerminalLinkResolver.resolve(raw: "Shared.swift:8", cwd: directory.url.path, repoPath: directory.url.path)
        guard case .ambiguous(let candidates, let line) = result else {
            return XCTFail("Expected duplicate basenames to be ambiguous")
        }
        XCTAssertEqual(Set(candidates.map { URL(fileURLWithPath: $0).lastPathComponent }), Set([first.lastPathComponent, second.lastPathComponent]))
        XCTAssertEqual(Set(candidates.map { URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent }), Set(["One", "Two"]))
        XCTAssertEqual(line, 8)
    }

    func testDoesNotSearchPathFragmentsAndSkipsHiddenFiles() throws {
        let directory = try TemporaryTestDirectory()
        _ = try directory.write("Nested/Only.swift", contents: "")
        _ = try directory.write(".hidden/Secret.swift", contents: "")

        XCTAssertEqual(
            TerminalLinkResolver.resolve(raw: "Nested/Missing.swift", cwd: directory.url.path, repoPath: directory.url.path),
            .notFound(text: "Nested/Missing.swift")
        )
        XCTAssertEqual(
            TerminalLinkResolver.resolve(raw: "Secret.swift", cwd: directory.url.path, repoPath: directory.url.path),
            .notFound(text: "Secret.swift")
        )
        XCTAssertEqual(
            TerminalLinkResolver.resolve(raw: "Missing.swift", cwd: directory.url.path, repoPath: directory.url.path),
            .notFound(text: "Missing.swift")
        )
    }
}

@MainActor
final class FileLoaderTests: XCTestCase {
    func testMissingPathsAndDirectoriesReturnNotFound() throws {
        let directory = try TemporaryTestDirectory()
        XCTAssertNil(FileLoader.fingerprint(path: directory.url.appendingPathComponent("missing.txt").path))

        let missing = FileLoader.load(path: directory.url.appendingPathComponent("missing.txt").path)
        guard case .notFound = missing.content else { return XCTFail("Expected notFound") }
        XCTAssertNil(missing.fingerprint)
        XCTAssertEqual(missing.lineStartOffsets, [0])

        let folder = FileLoader.load(path: directory.url.path)
        guard case .notFound = folder.content else { return XCTFail("Expected directory to be notFound") }
    }

    func testLoadsUtf8TextAndBuildsUtf16LineOffsetsAndFingerprint() throws {
        let directory = try TemporaryTestDirectory()
        let file = try directory.write("text.txt", contents: "a\n😀b\n")
        let result = FileLoader.load(path: file.path)
        let resultID = result.id

        guard case .text(let text) = result.content else { return XCTFail("Expected text") }
        XCTAssertEqual(result.id, resultID)
        XCTAssertEqual(text, "a\n😀b\n")
        XCTAssertEqual(result.lineStartOffsets, [0, 2, 6])
        XCTAssertEqual(result.fingerprint?.sizeBytes, 8)
        XCTAssertNotNil(FileLoader.fingerprint(path: file.path))
    }

    func testUnsupportedBinaryAndOversizedText() throws {
        let directory = try TemporaryTestDirectory()
        let binary = try directory.write("binary.txt", data: Data([0xFF, 0xFE, 0xFD]))
        guard case .unsupportedBinary = FileLoader.load(path: binary.path).content else {
            return XCTFail("Expected unsupported binary")
        }

        let largeText = try directory.writeSparse("large.txt", size: FileLoader.maxTextBytes + 1)
        guard case .tooLarge(let size, let isMedia) = FileLoader.load(path: largeText.path).content else {
            return XCTFail("Expected oversized text")
        }
        XCTAssertEqual(size, FileLoader.maxTextBytes + 1)
        XCTAssertFalse(isMedia)
    }

    func testLoadsPdfAndRejectsOversizedMedia() throws {
        let directory = try TemporaryTestDirectory()
        let pdf = try directory.write("small.pdf", data: Data("not parsed here".utf8))
        guard case .pdf(let url) = FileLoader.load(path: pdf.path).content else {
            return XCTFail("Expected PDF URL")
        }
        XCTAssertEqual(url, pdf)

        let largePDF = try directory.writeSparse("large.pdf", size: FileLoader.maxMediaBytes + 1)
        guard case .tooLarge(let size, let isMedia) = FileLoader.load(path: largePDF.path).content else {
            return XCTFail("Expected oversized PDF")
        }
        XCTAssertEqual(size, FileLoader.maxMediaBytes + 1)
        XCTAssertTrue(isMedia)
    }

    func testLoadsValidImageAndReportsInvalidImage() throws {
        let directory = try TemporaryTestDirectory()
        let pngBytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/pysAAAAASUVORK5CYII=")!
        let image = try directory.write("pixel.png", data: pngBytes)
        guard case .image(let loadedImage) = FileLoader.load(path: image.path).content else {
            return XCTFail("Expected a valid PNG image")
        }
        XCTAssertGreaterThan(loadedImage.size.width, 0)

        let invalidImage = try directory.write("invalid.png", data: Data("not an image".utf8))
        guard case .error = FileLoader.load(path: invalidImage.path).content else {
            return XCTFail("Expected image loading error")
        }
    }
}

@MainActor
final class GitServiceTests: XCTestCase {
    func testParsesBranchAheadBehindAndChangedRecordCount() {
        let records: [Substring] = [
            "# branch.oid abc123",
            "# branch.head main",
            "# branch.ab +4 -2",
            "1 .M N... 100644 100644 100644 a b file.txt",
            "? untracked.txt",
            "2 R. N... 100644 100644 100644 a b R100 new.txt",
            "old.txt",
            "u UU N... 100644 100644 100644 100644 a b c conflict.txt",
        ]

        let status = GitService.headerStatus(from: records)
        XCTAssertEqual(status.branch, "main")
        XCTAssertEqual(status.ahead, 4)
        XCTAssertEqual(status.behind, 2)
        XCTAssertEqual(status.changedFileCount, 4)
        XCTAssertFalse(status.isDetached)
    }

    func testParsesDetachedAndMalformedAheadBehindRecords() {
        let detached = GitService.headerStatus(from: ["# branch.head (detached)", "# branch.ab +bad -3"])
        XCTAssertNil(detached.branch)
        XCTAssertTrue(detached.isDetached)
        XCTAssertEqual(detached.ahead, 0)
        XCTAssertEqual(detached.behind, 3)

        let empty = GitService.headerStatus(from: [])
        XCTAssertNil(empty.branch)
        XCTAssertEqual(empty.changedFileCount, 0)
    }
}

@MainActor
final class DiffModelTests: XCTestCase {
    func testStatusLettersAndEntryIdentity() {
        XCTAssertEqual(DiffFileStatus.added.letter, "A")
        XCTAssertEqual(DiffFileStatus.deleted.letter, "D")
        XCTAssertEqual(DiffFileStatus.modified.letter, "M")
        XCTAssertEqual(DiffFileStatus.renamed(from: "old").letter, "R")
        XCTAssertEqual(DiffFileStatus.copied(from: "old").letter, "C")
        XCTAssertEqual(DiffFileStatus.untracked.letter, "U")
        XCTAssertEqual(DiffFileStatus.unmerged.letter, "!")
        XCTAssertEqual(DiffFileStatus.typeChanged.letter, "T")
        XCTAssertEqual(DiffFileStatus.ignored.letter, "I")

        let entry = DiffFileEntry(path: "Sources/File.swift", group: .staged, status: .modified)
        XCTAssertEqual(entry.id, "staged:Sources/File.swift")
        XCTAssertEqual(entry.displayName, "File.swift")
    }

    func testDiffLineAndHunkIdentityAndGroupLabels() {
        let line = DiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 1, text: "+new")
        let hunk = DiffHunk(header: "@@ -0,0 +1 @@", lines: [line])
        XCTAssertNotEqual(line.id, UUID())
        XCTAssertNotEqual(hunk.id, UUID())
        XCTAssertEqual(DiffChangeGroup.allCases.map(\.label).count, 4)
    }

    func testRecentAndLargePoliciesAtBoundaries() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var entry = DiffFileEntry(path: "file.txt", group: .unstaged, status: .modified)
        XCTAssertFalse(DiffVisibilityPolicy.isRecent(entry, now: now))
        entry.modificationDate = now.addingTimeInterval(-DiffVisibilityPolicy.recentChangeWindow)
        XCTAssertTrue(DiffVisibilityPolicy.isRecent(entry, now: now))
        entry.modificationDate = now.addingTimeInterval(-DiffVisibilityPolicy.recentChangeWindow - 1)
        XCTAssertFalse(DiffVisibilityPolicy.isRecent(entry, now: now))

        XCTAssertFalse(DiffVisibilityPolicy.isLarge(entry))
        entry.fileSizeBytes = DiffVisibilityPolicy.largeFileByteLimit
        XCTAssertTrue(DiffVisibilityPolicy.isLarge(entry))
        entry.fileSizeBytes = nil
        entry.additions = DiffVisibilityPolicy.largeChangeLineLimit
        XCTAssertTrue(DiffVisibilityPolicy.isLarge(entry))
    }
}

@MainActor
final class WordDiffPolicyTests: XCTestCase {
    func testUnchangedLinesHaveNoChangedRanges() {
        XCTAssertEqual(WordDiffPolicy.changedRanges(old: "same line", new: "same line").old, [])
        XCTAssertEqual(WordDiffPolicy.changedRanges(old: "same line", new: "same line").new, [])
    }

    func testChangedWordsProduceSeparateRangesAndPreserveMatchingTokens() {
        let ranges = WordDiffPolicy.changedRanges(old: "keep old value = 1", new: "keep new value = 2")

        XCTAssertEqual(ranges.old, [5..<8, 17..<18])
        XCTAssertEqual(ranges.new, [5..<8, 17..<18])
    }

    func testUnicodeRangesUseCharacterOffsets() {
        let ranges = WordDiffPolicy.changedRanges(old: "café_value9!", new: "café_value8!")

        XCTAssertEqual(ranges.old, [0..<11])
        XCTAssertEqual(ranges.new, [0..<11])
    }

    func testInsertedTokenLeavesUnchangedSideWithoutRanges() {
        let ranges = WordDiffPolicy.changedRanges(old: "value", new: "value!")

        XCTAssertTrue(ranges.old.isEmpty)
        XCTAssertEqual(ranges.new, [5..<6])
    }

    func testEmptySideFallsBackToWholeLineRanges() {
        let insertion = WordDiffPolicy.changedRanges(old: "", new: "text")
        XCTAssertEqual(insertion.old, [0..<0])
        XCTAssertEqual(insertion.new, [0..<4])

        let deletion = WordDiffPolicy.changedRanges(old: "text", new: "")
        XCTAssertEqual(deletion.old, [0..<4])
        XCTAssertEqual(deletion.new, [0..<0])
    }

    func testLinesOverTokenLimitUseWholeLineFallback() {
        let old = String(repeating: "a ", count: 128) + "a"
        let new = String(repeating: "b ", count: 128) + "b"

        let ranges = WordDiffPolicy.changedRanges(old: old, new: new)

        XCTAssertEqual(ranges.old, [0..<old.count])
        XCTAssertEqual(ranges.new, [0..<new.count])
    }

    func testMaximumTokenCountStillUsesWordDiff() {
        let suffix = String(repeating: "a ", count: 127)
        let old = "a " + suffix
        let new = "b " + suffix

        let ranges = WordDiffPolicy.changedRanges(old: old, new: new)

        XCTAssertEqual(old.count, 256)
        XCTAssertEqual(ranges.old, [0..<1])
        XCTAssertEqual(ranges.new, [0..<1])
    }
}

@MainActor
final class DiffLinePairingPolicyTests: XCTestCase {
    func testPairsContextsChangesAndUnmatchedAdditions() {
        let contextBefore = DiffLine(kind: .context, oldLineNumber: 1, newLineNumber: 1, text: "before")
        let deletionOne = DiffLine(kind: .deletion, oldLineNumber: 2, newLineNumber: nil, text: "old one")
        let deletionTwo = DiffLine(kind: .deletion, oldLineNumber: 3, newLineNumber: nil, text: "old two")
        let addition = DiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 2, text: "new")
        let contextAfter = DiffLine(kind: .context, oldLineNumber: 4, newLineNumber: 3, text: "after")
        let trailingAddition = DiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 4, text: "trailing")

        let pairs = DiffLinePairingPolicy.pairs(in: [
            contextBefore, deletionOne, deletionTwo, addition, contextAfter, trailingAddition
        ])

        XCTAssertEqual(pairs.count, 5)
        XCTAssertEqual(pairs[0].0?.id, contextBefore.id)
        XCTAssertEqual(pairs[0].1?.id, contextBefore.id)
        XCTAssertEqual(pairs[1].0?.id, deletionOne.id)
        XCTAssertEqual(pairs[1].1?.id, addition.id)
        XCTAssertEqual(pairs[2].0?.id, deletionTwo.id)
        XCTAssertNil(pairs[2].1)
        XCTAssertEqual(pairs[3].0?.id, contextAfter.id)
        XCTAssertEqual(pairs[3].1?.id, contextAfter.id)
        XCTAssertNil(pairs[4].0)
        XCTAssertEqual(pairs[4].1?.id, trailingAddition.id)
    }

    func testPairsExtraAdditionsAndEmptyInput() {
        let deletion = DiffLine(kind: .deletion, oldLineNumber: 1, newLineNumber: nil, text: "old")
        let firstAddition = DiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 1, text: "new one")
        let secondAddition = DiffLine(kind: .addition, oldLineNumber: nil, newLineNumber: 2, text: "new two")

        let pairs = DiffLinePairingPolicy.pairs(in: [deletion, firstAddition, secondAddition])

        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].0?.id, deletion.id)
        XCTAssertEqual(pairs[0].1?.id, firstAddition.id)
        XCTAssertNil(pairs[1].0)
        XCTAssertEqual(pairs[1].1?.id, secondAddition.id)
        XCTAssertTrue(DiffLinePairingPolicy.pairs(in: []).isEmpty)
    }
}

@MainActor
final class RepositoryAndShellModelTests: XCTestCase {
    func testDiffGroupsAndRepositoryMetadataRoundTrip() throws {
        XCTAssertEqual(DiffChangeGroup.allCases.map(\.rawValue), ["staged", "unstaged", "untracked", "ignored"])
        XCTAssertEqual(Set(DiffChangeGroup.allCases.map(\.id)), Set(["staged", "unstaged", "untracked", "ignored"]))

        let directory = try TemporaryTestDirectory()
        let gitDirectory = directory.url.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        let repo = Repo(path: directory.url.path)
        XCTAssertEqual(repo.name, directory.url.lastPathComponent)
        XCTAssertEqual(repo.url, directory.url)
        XCTAssertTrue(repo.existsOnDisk)

        let selection: DiffComparisonSelection = .betweenBranches(base: "main", target: "feature/test")
        var persisted = repo
        persisted.diffComparisonSelection = selection
        let data = try JSONEncoder().encode(persisted)
        let decoded = try JSONDecoder().decode(Repo.self, from: data)
        XCTAssertEqual(decoded, persisted)
        XCTAssertEqual(decoded.diffComparisonSelection, selection)
    }

    func testRepositoryMissingMetadataAndShellLinkParsing() throws {
        let missing = Repo(path: "/tmp/gridline-missing", displayName: "Readable name")
        XCTAssertEqual(missing.name, "Readable name")
        XCTAssertFalse(missing.existsOnDisk)

        XCTAssertEqual(
            ShellIntegration.parseOSC7("file://localhost/Users/test%20user/Repo"),
            "/Users/test user/Repo"
        )
        XCTAssertNil(ShellIntegration.parseOSC7("https://example.com/repo"))
        XCTAssertNil(ShellIntegration.parseOSC7("not a URL"))
        XCTAssertEqual(ShellIntegration.environmentOverrides(forShellNamed: "bash", commandStatePath: "/tmp/state"), [])
    }
}

@MainActor
final class ProcessAndSessionTests: XCTestCase {
    func testGitProcessReportsSuccessAndFailure() async {
        let version = await GitProcess.run(["--version"], at: NSHomeDirectory())
        XCTAssertEqual(version.exitCode, 0)
        XCTAssertTrue(version.stdout.contains("git version"))

        let gitVersion = await GitProcess.version()
        XCTAssertTrue(gitVersion.hasPrefix("git version"))

        let missing = await GitProcess.run(["status"], at: "/tmp/gridline-path-that-does-not-exist")
        XCTAssertNotEqual(missing.exitCode, 0)
        XCTAssertFalse(missing.stderr.isEmpty)
        XCTAssertTrue(GitProcess.isGitAvailable)
    }

    func testRepoSessionKeepsAtLeastOneTabAndPropagatesHandlers() throws {
        let directory = try TemporaryTestDirectory()
        let session = RepoSession(repoPath: directory.url.path)
        defer { session.tabs.forEach { $0.terminate() } }
        XCTAssertEqual(session.tabs.count, 1)
        XCTAssertEqual(session.repoPath, directory.url.path)
        XCTAssertEqual(session.runningProcessCount, session.tabs.filter(\.isRunning).count)
        XCTAssertEqual(session.activeCommandCount, session.tabs.filter(\.hasActiveCommand).count)
        XCTAssertEqual(session.workStatus, RepoSession.workStatus(
            attention: session.attention,
            runningProcessCount: session.runningProcessCount
        ))

        var openedPath = false
        session.openFileHandler = { target in
            if case .file(let path, _, _) = target, path.hasSuffix("README.md") {
                openedPath = true
            }
        }
        let second = session.addTab()
        XCTAssertEqual(session.tabs.count, 2)
        XCTAssertNotNil(session.tabs[0].onOpenPath)
        XCTAssertNotNil(second.onOpenPath)

        _ = try directory.write("README.md", contents: "read me")
        if case .file(let path, _, _) = TerminalLinkResolver.resolve(
            raw: "README.md", cwd: directory.url.path, repoPath: directory.url.path
        ) {
            second.onOpenPath?(.file(path: path, line: nil, isOutsideRepo: false))
        }
        XCTAssertTrue(openedPath)

        let firstID = session.tabs[0].id
        session.closeTab(id: firstID)
        XCTAssertEqual(session.tabs.count, 1)
        XCTAssertNotEqual(session.activeTabID, firstID)
        session.closeTab(id: UUID())
        session.clearAttention()
        XCTAssertNil(session.attention)
    }

    func testRepoSessionNotifiesAfterRecordingTerminalExit() async throws {
        let directory = try TemporaryTestDirectory()
        let delivered = expectation(description: "terminal exit notification")
        var received: (String, String, Int32?)?
        let session = RepoSession(repoPath: directory.url.path) { repoName, tabName, exitCode in
            received = (repoName, tabName, exitCode)
            delivered.fulfill()
        }
        defer { session.tabs.forEach { $0.terminate() } }

        session.tabs[0].onProcessTerminated?(9)
        XCTAssertEqual(session.attention, .failed)
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(received?.0, directory.url.lastPathComponent)
        XCTAssertEqual(received?.2, 9)
    }

    func testRepoSessionClosingActiveAndLastTabsMaintainsSelection() throws {
        let directory = try TemporaryTestDirectory()
        let session = RepoSession(repoPath: directory.url.path)
        defer { session.tabs.forEach { $0.terminate() } }
        let first = try XCTUnwrap(session.tabs.first)
        let second = session.addTab()

        session.closeTab(id: second.id)
        XCTAssertEqual(session.activeTabID, first.id)
        session.closeTab(id: first.id)
        XCTAssertEqual(session.tabs.count, 1)
        XCTAssertNotEqual(session.activeTabID, first.id)
    }
}

@MainActor
final class TopAreaStoreTests: XCTestCase {
    func testOpeningDuplicateSelectsExistingFileAndClosingResetsSelection() throws {
        let directory = try TemporaryTestDirectory()
        let file = try directory.write("README.md", contents: "line one\nline two\n")
        let store = TopAreaStore()

        let first = store.openFile(path: file.path, scrollToLine: 2)
        let duplicate = store.openFile(path: file.path, scrollToLine: 1)
        XCTAssertEqual(first.id, duplicate.id)
        XCTAssertEqual(store.openFiles.count, 1)
        XCTAssertEqual(store.selection, .file(first.id))
        XCTAssertEqual(first.pendingScrollLine, 1)

        store.closeFile(id: first.id)
        XCTAssertTrue(store.openFiles.isEmpty)
        XCTAssertEqual(store.selection, .diff)
    }

    func testCloseOtherFilesKeepsRequestedTabAndIgnoresUnknownID() throws {
        let directory = try TemporaryTestDirectory()
        let first = try directory.write("one.txt", contents: "one")
        let second = try directory.write("two.txt", contents: "two")
        let store = TopAreaStore()
        let firstTab = store.openFile(path: first.path)
        let secondTab = store.openFile(path: second.path)

        store.closeOtherFiles(keeping: UUID())
        XCTAssertEqual(store.openFiles.map(\.id), [firstTab.id, secondTab.id])

        store.closeOtherFiles(keeping: firstTab.id)
        XCTAssertEqual(store.openFiles.map(\.id), [firstTab.id])
        XCTAssertEqual(store.selection, .file(firstTab.id))
    }
}

@MainActor
final class DiagnosticAndTerminalTests: XCTestCase {
    func testDiagnosticEventMessagesAndReportContainRecordedEvents() {
        XCTAssertEqual(DiagnosticEvent.appLaunched.message, "app.launched")
        XCTAssertEqual(DiagnosticEvent.terminalStartFailed.message, "terminal.start_failed")
        XCTAssertEqual(DiagnosticEvent.terminalExited(nil).message, "terminal.exited exit_code=unknown")
        XCTAssertEqual(DiagnosticEvent.terminalExited(0).message, "terminal.exited exit_code=0")
        XCTAssertEqual(DiagnosticEvent.gitStatusFailed(7).message, "git.status_failed exit_code=7")
        XCTAssertEqual(DiagnosticEvent.logExportRequested.message, "diagnostics.export_requested")
        XCTAssertEqual(DiagnosticEvent.logExported.message, "diagnostics.exported")
        XCTAssertEqual(DiagnosticEvent.logExportFailed.message, "diagnostics.export_failed")

        DiagnosticLog.shared.record(.appLaunched)
        DiagnosticLog.shared.record(.logExported)
        let report = DiagnosticLog.shared.report(gitVersion: "git version test")
        XCTAssertTrue(report.contains("app.launched"))
        XCTAssertTrue(report.contains("diagnostics.exported"))
        XCTAssertTrue(report.contains("git version test"))
    }

    func testTerminalTabRenameAndIdleState() {
        let tab = TerminalTab(workingDirectory: "/tmp")
        defer { tab.terminate() }

        XCTAssertFalse(tab.isRunning)
        XCTAssertFalse(tab.hasActiveCommand)
        tab.rename(to: "  Build  ")
        XCTAssertEqual(tab.title, "Build")
        tab.rename(to: "   ")
        XCTAssertNil(tab.customTitle)
        tab.startProcess()
        let running = tab.isRunning
        tab.startProcess()
        XCTAssertEqual(tab.isRunning, running)
    }

    func testTerminalCommandDetectionHandlesShellAndCommandState() {
        XCTAssertFalse(TerminalTab.hasActiveCommand(isRunning: false, shellName: "zsh", commandState: nil))
        XCTAssertTrue(TerminalTab.hasActiveCommand(isRunning: true, shellName: "bash", commandState: nil))
        XCTAssertTrue(TerminalTab.hasActiveCommand(isRunning: true, shellName: "zsh", commandState: nil))
        XCTAssertTrue(TerminalTab.hasActiveCommand(
            isRunning: true,
            shellName: "zsh",
            commandState: Data("running\n".utf8)
        ))
        XCTAssertFalse(TerminalTab.hasActiveCommand(
            isRunning: true,
            shellName: "zsh",
            commandState: Data(" idle\n".utf8)
        ))
        XCTAssertTrue(TerminalTab.hasActiveCommand(
            isRunning: true,
            shellName: "zsh",
            commandState: Data([0xFF])
        ))
    }

    func testTerminalTabRecordsOnlyTheFirstLifecycleResult() {
        let tab = TerminalTab(workingDirectory: "/tmp")
        defer { tab.terminate() }
        var exitCodes: [Int32?] = []
        tab.onProcessTerminated = { exitCodes.append($0) }

        tab.recordTermination(0)
        XCTAssertFalse(tab.isRunning)
        XCTAssertEqual(tab.attention, .completed)
        XCTAssertEqual(exitCodes.count, 1)
        XCTAssertEqual(exitCodes.first!, 0)

        tab.recordTermination(1)
        XCTAssertEqual(exitCodes.count, 1)
        XCTAssertEqual(tab.attention, .completed)

        let failedTab = TerminalTab(workingDirectory: "/tmp")
        defer { failedTab.terminate() }
        var startFailureCount = 0
        failedTab.onProcessTerminated = { exitCode in
            XCTAssertNil(exitCode)
            startFailureCount += 1
        }
        failedTab.recordStartFailure()
        failedTab.recordStartFailure()
        XCTAssertEqual(startFailureCount, 1)
        XCTAssertFalse(failedTab.isRunning)
        XCTAssertEqual(failedTab.attention, .failed)
    }

    func testTerminalDelegateProxyForwardsLifecycleUpdates() {
        let tab = TerminalTab(workingDirectory: "/tmp")
        defer { tab.terminate() }
        let proxy = tab.delegateProxy
        var exitCode: Int32?
        tab.onProcessTerminated = { exitCode = $0 }

        proxy.sizeChanged(source: tab.terminalView, newCols: 80, newRows: 24)
        proxy.setTerminalTitle(source: tab.terminalView, title: "Build")
        proxy.hostCurrentDirectoryUpdate(source: tab.terminalView, directory: "file:///tmp/Repo")
        proxy.hostCurrentDirectoryUpdate(source: tab.terminalView, directory: "https://example.com")
        proxy.processTerminated(source: tab.terminalView, exitCode: 7)

        XCTAssertEqual(tab.title, "Build")
        XCTAssertEqual(tab.currentDirectory, "/tmp/Repo")
        XCTAssertEqual(exitCode, 7)
        XCTAssertEqual(tab.attention, .failed)
    }

    func testTerminalTabResolvesOpenedLinkAgainstItsCurrentDirectory() async throws {
        let directory = try TemporaryTestDirectory()
        let expectedFile = try directory.write("Sources/App.swift", contents: "let app = true")
        let tab = TerminalTab(workingDirectory: directory.url.path)
        defer { tab.terminate() }
        let opened = expectation(description: "terminal file link")
        var target: TerminalLinkTarget?
        tab.onOpenPath = {
            target = $0
            opened.fulfill()
        }

        tab.terminalView.requestOpenLink(
            source: tab.terminalView,
            link: "Sources/App.swift:4",
            params: [:]
        )
        await fulfillment(of: [opened], timeout: 2)
        XCTAssertEqual(target, .file(path: expectedFile.path, line: 4, isOutsideRepo: false))
    }

    func testRepoWorkStatusTitlesAndIcons() {
        XCTAssertEqual(RepoWorkStatus.idle.systemImage, "circle")
        XCTAssertEqual(RepoWorkStatus.running(2).systemImage, "terminal")
        XCTAssertEqual(RepoWorkStatus.needsAttention.systemImage, "exclamationmark.circle.fill")
        XCTAssertEqual(RepoWorkStatus.idle.title, String(localized: L10n.Repository.workStatusIdle))
        XCTAssertEqual(RepoWorkStatus.running(2).title, L10n.format(L10n.Repository.workStatusRunning, Int64(2)))
        XCTAssertEqual(RepoWorkStatus.needsAttention.title, String(localized: L10n.Repository.workStatusAttention))
    }

    func testRepoAttentionAndWorkStatusMappings() {
        XCTAssertEqual(RepoAttentionStatus.forExitCode(0), .completed)
        XCTAssertEqual(RepoAttentionStatus.forExitCode(1), .failed)
        XCTAssertEqual(RepoAttentionStatus.forExitCode(nil), .failed)
        XCTAssertEqual(RepoAttentionStatus.completed.accessibilityLabel, String(localized: L10n.Repository.attentionCompleted))
        XCTAssertEqual(RepoAttentionStatus.failed.accessibilityLabel, String(localized: L10n.Repository.attentionFailed))

        XCTAssertEqual(RepoSession.workStatus(attention: nil, runningProcessCount: 0), .idle)
        XCTAssertEqual(RepoSession.workStatus(attention: .completed, runningProcessCount: 2), .running(2))
        XCTAssertEqual(RepoSession.workStatus(attention: .failed, runningProcessCount: 2), .needsAttention)
    }

    func testNotificationContentUsesRepositoryTabAndExitStatus() {
        let completed = LocalNotificationService.makeContent(repoName: "Gridline", tabName: "Build", exitCode: 0)
        XCTAssertEqual(completed.title, "Gridline — Build")
        XCTAssertEqual(completed.body, String(localized: L10n.Terminal.finishedNotification))
        XCTAssertNotNil(completed.sound)

        let failed = LocalNotificationService.makeContent(repoName: "Gridline", tabName: "Tests", exitCode: 1)
        XCTAssertEqual(failed.title, "Gridline — Tests")
        XCTAssertEqual(failed.body, String(localized: L10n.Terminal.failedNotification))
    }

    func testNotificationAuthorizationMapsSystemStatuses() {
        XCTAssertEqual(LocalNotificationAuthorizationStatus.map(.notDetermined), .notDetermined)
        XCTAssertEqual(LocalNotificationAuthorizationStatus.map(.authorized), .authorized)
        XCTAssertEqual(LocalNotificationAuthorizationStatus.map(.provisional), .provisional)
        XCTAssertEqual(LocalNotificationAuthorizationStatus.map(.denied), .denied)
    }

    func testNotificationDeliveryRequestsPermissionAndHonorsAuthorization() async {
        let alreadyAuthorized = StubLocalNotificationClient(status: .authorized)
        await LocalNotificationService.notifyTerminalEnded(
            repoName: "Gridline",
            tabName: "Build",
            exitCode: 0,
            using: alreadyAuthorized
        )
        XCTAssertEqual(alreadyAuthorized.authorizationRequestCount, 0)
        XCTAssertEqual(alreadyAuthorized.requests.count, 1)
        XCTAssertEqual(alreadyAuthorized.requests.first?.content.title, "Gridline — Build")

        let newlyAuthorized = StubLocalNotificationClient(status: .notDetermined, afterRequest: .provisional)
        await LocalNotificationService.notifyTerminalEnded(
            repoName: "Gridline",
            tabName: "Tests",
            exitCode: 1,
            using: newlyAuthorized
        )
        XCTAssertEqual(newlyAuthorized.authorizationRequestCount, 1)
        XCTAssertEqual(newlyAuthorized.requests.count, 1)
        XCTAssertEqual(newlyAuthorized.requests.first?.content.body, String(localized: L10n.Terminal.failedNotification))

        let deniedAfterRequest = StubLocalNotificationClient(status: .notDetermined, afterRequest: .denied)
        await LocalNotificationService.notifyTerminalEnded(
            repoName: "Gridline",
            tabName: "Denied",
            exitCode: nil,
            using: deniedAfterRequest
        )
        XCTAssertEqual(deniedAfterRequest.authorizationRequestCount, 1)
        XCTAssertTrue(deniedAfterRequest.requests.isEmpty)

        let denied = StubLocalNotificationClient(status: .denied)
        await LocalNotificationService.notifyTerminalEnded(
            repoName: "Gridline",
            tabName: "Blocked",
            exitCode: nil,
            using: denied
        )
        XCTAssertEqual(denied.authorizationRequestCount, 0)
        XCTAssertTrue(denied.requests.isEmpty)
    }
}

@MainActor
private final class StubLocalNotificationClient: LocalNotificationClient {
    private(set) var status: LocalNotificationAuthorizationStatus
    private let afterRequest: LocalNotificationAuthorizationStatus
    private(set) var authorizationRequestCount = 0
    private(set) var requests: [UNNotificationRequest] = []

    init(status: LocalNotificationAuthorizationStatus, afterRequest: LocalNotificationAuthorizationStatus = .authorized) {
        self.status = status
        self.afterRequest = afterRequest
    }

    func authorizationStatus() async -> LocalNotificationAuthorizationStatus {
        status
    }

    func requestAuthorization() async {
        authorizationRequestCount += 1
        status = afterRequest
    }

    func add(_ request: UNNotificationRequest) async {
        requests.append(request)
    }
}

@MainActor
final class StoreRegistryTests: XCTestCase {
    func testTopAreaRegistryReusesStoresAndListsOpenFiles() throws {
        let directory = try TemporaryTestDirectory()
        let firstFile = try directory.write("one.txt", contents: "one")
        let secondFile = try directory.write("two.txt", contents: "two")
        let firstRepo = Repo(path: directory.url.path, displayName: "First")
        let secondRepo = Repo(path: directory.url.path, displayName: "Second")
        let unopenedRepo = Repo(path: "/tmp/unopened-repository", displayName: "Unopened")
        let registry = TopAreaStoreRegistry()

        let firstStore = registry.store(for: firstRepo)
        XCTAssertTrue(firstStore === registry.store(for: firstRepo))
        registry.selectFile(path: firstFile.path, in: firstRepo)
        registry.selectFile(path: secondFile.path, in: secondRepo)

        XCTAssertTrue(registry.openFiles(for: [unopenedRepo]).isEmpty)
        registry.selectFile(path: firstFile.path, in: unopenedRepo)
        XCTAssertEqual(registry.openFiles(for: [unopenedRepo]).count, 1)
        let files = registry.openFiles(for: [firstRepo, secondRepo])
        XCTAssertEqual(files.map(\.path), [firstFile.path, secondFile.path])
        XCTAssertEqual(files.map(\.repoName), ["First", "Second"])
        registry.setVisibleRepoIDs([firstRepo.id, secondRepo.id, unopenedRepo.id])
        registry.setVisibleRepoIDs([firstRepo.id, secondRepo.id, unopenedRepo.id])
        registry.setVisibleRepoIDs([])
    }

    func testRepoSessionStoreCachesAndTerminatesSessions() {
        let repo = Repo(path: FileManager.default.temporaryDirectory.path)
        let store = RepoSessionStore()
        let session = store.session(for: repo)

        XCTAssertTrue(session === store.session(for: repo))
        XCTAssertTrue(session === store.existingSession(for: repo))
        store.terminateAllProcesses()
        store.terminateSession(for: repo)
        XCTAssertNil(store.existingSession(for: repo))
        store.terminateSession(for: repo)
    }
}

@MainActor
final class RepoDiffStoreRegistryTests: XCTestCase {
    func testRegistryReusesStoresAndForwardsSelectionLifecycle() {
        let repo = Repo(path: "/tmp/gridline-registry-fixture", worktreeBaseBranch: "main")
        let registry = RepoDiffStoreRegistry()
        var consumedRepoIDs: [UUID] = []
        var changes: [DiffComparisonSelection] = []
        registry.onWorktreeBaseBranchConsumed = { consumedRepoIDs.append($0) }
        registry.onComparisonSelectionChanged = { _, selection in changes.append(selection) }

        let store = registry.store(for: repo)
        XCTAssertTrue(store === registry.store(for: repo))
        registry.setVisibleRepoIDs([repo.id])
        registry.setVisibleRepoIDs([repo.id])
        registry.setVisibleRepoIDs([repo.id], refreshExisting: true)

        store.selectComparisonBranch(nil)
        store.selectComparisonBranch(nil)
        registry.setVisibleRepoIDs([])

        XCTAssertEqual(consumedRepoIDs, [repo.id])
        XCTAssertEqual(changes, [.localChanges, .localChanges])
    }
}

@MainActor
final class GridlinePreferencesTests: XCTestCase {
    func testDefaultsAndInvalidValuesFallBack() throws {
        let defaults = try makeDefaults()
        XCTAssertEqual(GridlinePreferences.scrollbackLimit(from: defaults), GridlinePreferences.defaultScrollbackLimit)
        XCTAssertEqual(GridlinePreferences.terminalFontSize(from: defaults), GridlinePreferences.defaultTerminalFontSize)
        XCTAssertEqual(GridlinePreferences.diffFontSize(from: defaults), GridlinePreferences.defaultDiffFontSize)

        defaults.set(123, forKey: GridlinePreferences.scrollbackLimitKey)
        defaults.set(GridlinePreferences.minimumTerminalFontSize - 1, forKey: GridlinePreferences.terminalFontSizeKey)
        defaults.set(GridlinePreferences.maximumDiffFontSize + 1, forKey: GridlinePreferences.diffFontSizeKey)
        XCTAssertEqual(GridlinePreferences.scrollbackLimit(from: defaults), GridlinePreferences.defaultScrollbackLimit)
        XCTAssertEqual(GridlinePreferences.terminalFontSize(from: defaults), GridlinePreferences.defaultTerminalFontSize)
        XCTAssertEqual(GridlinePreferences.diffFontSize(from: defaults), GridlinePreferences.defaultDiffFontSize)
    }

    func testAdjustmentsClampAndTerminalFontPostsOnlyOnChange() async throws {
        let defaults = try makeDefaults()
        let changed = expectation(description: "terminal font notification")
        let observer = NotificationCenter.default.addObserver(
            forName: GridlinePreferences.terminalFontSizeChanged,
            object: nil,
            queue: .main
        ) { _ in changed.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }

        defaults.set(GridlinePreferences.defaultTerminalFontSize, forKey: GridlinePreferences.terminalFontSizeKey)
        GridlinePreferences.adjustTerminalFontSize(by: 1, defaults: defaults)
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(
            GridlinePreferences.terminalFontSize(from: defaults),
            GridlinePreferences.defaultTerminalFontSize + 1
        )

        defaults.set(GridlinePreferences.maximumTerminalFontSize, forKey: GridlinePreferences.terminalFontSizeKey)
        GridlinePreferences.adjustTerminalFontSize(by: 1, defaults: defaults)
        XCTAssertEqual(GridlinePreferences.terminalFontSize(from: defaults), GridlinePreferences.maximumTerminalFontSize)

        defaults.set(GridlinePreferences.minimumTerminalFontSize, forKey: GridlinePreferences.terminalFontSizeKey)
        GridlinePreferences.adjustTerminalFontSize(by: -1, defaults: defaults)
        XCTAssertEqual(GridlinePreferences.terminalFontSize(from: defaults), GridlinePreferences.minimumTerminalFontSize)

        defaults.set(GridlinePreferences.maximumDiffFontSize, forKey: GridlinePreferences.diffFontSizeKey)
        GridlinePreferences.adjustDiffFontSize(by: 1, defaults: defaults)
        XCTAssertEqual(GridlinePreferences.diffFontSize(from: defaults), GridlinePreferences.maximumDiffFontSize)
        GridlinePreferences.adjustDiffFontSize(by: -100, defaults: defaults)
        XCTAssertEqual(GridlinePreferences.diffFontSize(from: defaults), GridlinePreferences.minimumDiffFontSize)
        GridlinePreferences.resetDiffFontSize(defaults: defaults)
        XCTAssertEqual(GridlinePreferences.diffFontSize(from: defaults), GridlinePreferences.defaultDiffFontSize)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "GridlineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

@MainActor
final class PaneLayoutTests: XCTestCase {
    func testGridShapeAndPositionsForDifferentPaneCounts() {
        XCTAssertEqual(PaneGridShape(paneCount: 0).rowLengths, [1])
        XCTAssertEqual(PaneGridShape(paneCount: 1).rowLengths, [1])
        XCTAssertEqual(PaneGridShape(paneCount: 4).rowLengths, [2, 2])
        XCTAssertEqual(PaneGridShape(paneCount: 5).rowLengths, [3, 2])
        XCTAssertEqual(PaneGridShape(paneCount: 6).positions.count, 6)
        XCTAssertEqual(PaneDividerRole.columns(row: 2).storageKey, "columns.2")
        XCTAssertEqual(PaneDividerRole.rows.storageKey, "rows")
    }

    func testInitializationClampsAndRepairsInvalidPaneReferences() {
        let first = PaneSlot()
        let layout = PaneLayout(
            slots: [first], displayPaneCount: 10, activePaneID: UUID(),
            topColumnFraction: 0, bottomColumnFraction: 1, rowFraction: 0.5,
            gridDividerFractions: ["columns.0": [-1, 0.4, 1]],
            maximizedPaneID: UUID(), terminalOnlyPaneID: UUID()
        )
        XCTAssertEqual(layout.displayPaneCount, 1)
        XCTAssertEqual(layout.activePaneID, first.id)
        XCTAssertEqual(layout.topColumnFraction, 0.1)
        XCTAssertEqual(layout.bottomColumnFraction, 0.9)
        XCTAssertEqual(layout.gridDividerFractions["columns.0"], [0.1, 0.4, 0.9])
        XCTAssertNil(layout.maximizedPaneID)
        XCTAssertNil(layout.terminalOnlyPaneID)

        let empty = PaneLayout(slots: [], displayPaneCount: 0)
        XCTAssertEqual(empty.slots.count, 1)
        XCTAssertEqual(empty.displayPaneCount, 1)
    }

    func testDisplayedSlotsKeepActivePaneVisibleAndResizeAddsSlots() {
        var layout = PaneLayout(slots: (0..<4).map { _ in PaneSlot() }, displayPaneCount: 2)
        layout.activePaneID = layout.slots[3].id
        XCTAssertEqual(layout.displayedSlots.map(\.id), [layout.slots[0].id, layout.slots[3].id])

        layout.setDisplayPaneCount(0)
        XCTAssertEqual(layout.displayPaneCount, 1)
        XCTAssertNil(layout.maximizedPaneID)
        layout.setDisplayPaneCount(5)
        XCTAssertEqual(layout.displayPaneCount, 5)
        XCTAssertEqual(layout.slots.count, 5)
    }

    func testAddRemoveAndAssignPanePaths() {
        let repoA = UUID()
        let repoB = UUID()
        var layout = PaneLayout(slots: [PaneSlot()])
        let firstPane = layout.slots[0].id
        XCTAssertEqual(layout.assign(repoID: repoA), firstPane)
        XCTAssertEqual(layout.assign(repoID: repoA), firstPane)

        let secondPane = layout.assign(repoID: repoB)
        XCTAssertNotEqual(secondPane, firstPane)
        XCTAssertEqual(layout.slots.count, 2)
        XCTAssertEqual(layout.displayPaneCount, 2)
        XCTAssertFalse(layout.removePane(UUID()))
        XCTAssertTrue(layout.removePane(secondPane))
        XCTAssertFalse(layout.removePane(firstPane))

        let newPane = layout.addPane()
        XCTAssertEqual(layout.activePaneID, newPane)
        XCTAssertEqual(layout.assign(repoID: UUID(), preferNewPane: true), layout.activePaneID)
    }

    func testClearRestoreAndSelectRepoPreservePaneModes() {
        let repoA = UUID()
        let repoB = UUID()
        var layout = PaneLayout(slots: [PaneSlot(repoID: repoA), PaneSlot()])
        let first = layout.slots[0].id
        layout.toggleMaximizedPane(first)
        layout.selectRepo(repoB, in: first)
        let selectedPane = layout.activePaneID
        XCTAssertEqual(layout.maximizedPaneID, selectedPane)
        XCTAssertEqual(layout.activeSlot.repoID, repoB)

        layout.toggleTerminalOnlyPane(selectedPane)
        layout.selectRepo(repoA, in: selectedPane)
        let paneWithRepoA = layout.activePaneID
        XCTAssertEqual(layout.terminalOnlyPaneID, paneWithRepoA)
        XCTAssertEqual(layout.activeSlot.repoID, repoA)

        layout.clearRepo(in: paneWithRepoA)
        XCTAssertNil(layout.activeSlot.repoID)
        XCTAssertNil(layout.terminalOnlyPaneID)
        layout.restoreRepo(repoB, in: paneWithRepoA)
        XCTAssertEqual(layout.activePaneID, selectedPane)
        layout.restoreRepo(repoA, in: UUID())
        XCTAssertFalse(layout.slots.contains(where: { $0.repoID == repoA }))
        layout.restoreRepo(repoA, in: selectedPane)
        XCTAssertTrue(layout.slots.contains(where: { $0.repoID == repoA }))
    }

    func testTransientModesRemoveReferencesAndFocusNavigation() {
        let repos = (0..<4).map { _ in UUID() }
        var layout = PaneLayout(slots: repos.map { PaneSlot(repoID: $0) })
        let first = layout.slots[0].id
        let second = layout.slots[1].id
        let last = layout.slots[3].id

        layout.toggleMaximizedPane(first)
        XCTAssertEqual(layout.maximizedPaneID, first)
        layout.toggleTerminalOnlyPane(second)
        XCTAssertNil(layout.maximizedPaneID)
        XCTAssertEqual(layout.terminalOnlyPaneID, second)
        layout.toggleTerminalOnlyPane(second)
        XCTAssertNil(layout.terminalOnlyPaneID)
        layout.toggleMaximizedPane(UUID())
        layout.toggleTerminalOnlyPane(first)
        layout.removeRepoReference(repos[0])
        XCTAssertNil(layout.terminalOnlyPaneID)

        layout.activePaneID = second
        layout.focus(.left)
        XCTAssertEqual(layout.activePaneID, first)
        layout.focus(.down)
        XCTAssertEqual(layout.activePaneID, layout.slots[2].id)
        layout.focusPane(at: 3)
        XCTAssertEqual(layout.activePaneID, last)
        layout.focus(.right)
        XCTAssertEqual(layout.activePaneID, last)
    }

    func testSlotFractionsAndDividerFallbacksAndSavedValues() {
        var layout = PaneLayout(slots: (0..<5).map { _ in PaneSlot() })
        let slot = layout.slots[0].id
        layout.setTopFraction(2, for: slot)
        layout.setViewerAsSidePanel(true, for: slot)
        XCTAssertEqual(layout.slots[0].topFraction, 0.9)
        XCTAssertTrue(layout.slots[0].viewerAsSidePanel)
        layout.setTopFraction(0.2, for: UUID())

        let fallback = layout.dividerFractions(for: 5)
        XCTAssertEqual(fallback[.columns(row: 0)], [1.0 / 3.0, 2.0 / 3.0])
        XCTAssertEqual(fallback[.columns(row: 1)], [0.5])
        XCTAssertEqual(fallback[.rows], [0.5])
        layout.setDividerFractions([0.3, 0.7], for: .columns(row: 0))
        layout.setDividerFractions([0.2], for: .rows)
        XCTAssertEqual(layout.dividerFractions(for: 5)[.columns(row: 0)], [0.3, 0.7])
        XCTAssertEqual(layout.dividerFractions(for: 5)[.rows], [0.2])

        var twoPanes = PaneLayout(slots: [PaneSlot(), PaneSlot()])
        twoPanes.setDividerFractions([0.3], for: .columns(row: 0))
        XCTAssertEqual(twoPanes.topColumnFraction, 0.3)
    }

    func testCodableCompatibilityAndTransientModeNormalization() throws {
        let slotID = UUID()
        let slotJSON = "{\"id\":\"\(slotID.uuidString)\"}"
        let slot = try JSONDecoder().decode(PaneSlot.self, from: Data(slotJSON.utf8))
        XCTAssertEqual(slot.topFraction, 0.6)
        XCTAssertFalse(slot.viewerAsSidePanel)

        let layoutJSON = "{\"slots\":[{\"id\":\"\(slotID.uuidString)\"}],\"maximizedPaneID\":\"\(slotID.uuidString)\",\"terminalOnlyPaneID\":\"\(slotID.uuidString)\"}"
        let layout = try JSONDecoder().decode(PaneLayout.self, from: Data(layoutJSON.utf8))
        XCTAssertEqual(layout.maximizedPaneID, slotID)
        XCTAssertNil(layout.terminalOnlyPaneID)
        XCTAssertEqual(layout.activeSlot.id, slotID)

        let legacy = PaneLayout.migrated(activeRepoID: UUID(), topFraction: 0.25)
        XCTAssertEqual(legacy.slots.count, 2)
        XCTAssertEqual(legacy.activeSlot.topFraction, 0.25)
        let roundTrip = try JSONDecoder().decode(PaneLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(roundTrip, layout)
    }

    func testRemovingActivePaneAndChangingDisplayCountNormalizeModes() {
        let first = PaneSlot(repoID: UUID())
        let active = PaneSlot(repoID: UUID())
        var layout = PaneLayout(slots: [first, active], displayPaneCount: 2)
        layout.activePaneID = active.id
        layout.maximizedPaneID = active.id
        layout.terminalOnlyPaneID = active.id

        XCTAssertTrue(layout.removePane(active.id))
        XCTAssertEqual(layout.activePaneID, first.id)
        XCTAssertNil(layout.maximizedPaneID)
        XCTAssertNil(layout.terminalOnlyPaneID)

        layout.maximizedPaneID = UUID()
        layout.terminalOnlyPaneID = UUID()
        layout.setDisplayPaneCount(2)
        XCTAssertNil(layout.maximizedPaneID)
        XCTAssertNil(layout.terminalOnlyPaneID)
        XCTAssertTrue(layout.removePane(layout.slots.last!.id))
        XCTAssertFalse(layout.removePane(first.id))
    }

    func testSelectingAndRestoringExistingReposPreservesPaneModes() {
        let repoA = UUID()
        let repoB = UUID()
        let first = PaneSlot(repoID: repoA)
        let second = PaneSlot()
        var layout = PaneLayout(slots: [first, second])
        layout.toggleMaximizedPane(first.id)

        layout.selectRepo(repoB, in: first.id)
        XCTAssertEqual(layout.maximizedPaneID, layout.activePaneID)
        XCTAssertEqual(layout.activeSlot.repoID, repoB)

        layout.restoreRepo(repoA, in: UUID())
        XCTAssertEqual(layout.activeSlot.repoID, repoA)
        layout.restoreRepo(repoB, in: UUID())
        XCTAssertEqual(layout.activeSlot.repoID, repoB)
    }
}

@MainActor
final class AppStateStoreTests: XCTestCase {
    func testLoadsMissingAndMalformedStateAndPersistsRoundTrips() throws {
        let directory = try TemporaryTestDirectory()
        let stateURL = directory.url.appendingPathComponent("state.json")
        let emptyStore = AppStateStore(fileURL: stateURL)
        XCTAssertTrue(emptyStore.state.savedRepos.isEmpty)

        let malformedURL = directory.url.appendingPathComponent("bad.json")
        try Data("not json".utf8).write(to: malformedURL)
        XCTAssertTrue(AppStateStore(fileURL: malformedURL).state.savedRepos.isEmpty)

        let repo = emptyStore.addRepo(path: "/tmp/first")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertEqual(AppStateStore(fileURL: stateURL).state.savedRepos, [repo])
    }

    func testDecodeRepairsRecentRepositoryIDsAndUsesLegacyDefaults() throws {
        let first = Repo(path: "/tmp/first")
        let second = Repo(path: "/tmp/second")
        let savedRepos = try JSONEncoder().encode([first, second])
        let savedReposJSON = String(decoding: savedRepos, as: UTF8.self)
        let recentIDs = [first.id, first.id, UUID(), second.id]
            .map { "\"\($0.uuidString)\"" }
            .joined(separator: ",")
        let json = "{\"savedRepos\":\(savedReposJSON),\"recentRepoIDs\":[\(recentIDs)]}"

        let state = try JSONDecoder().decode(AppState.self, from: Data(json.utf8))

        XCTAssertEqual(state.formatVersion, 4)
        XCTAssertEqual(state.recentRepoIDs, [first.id, second.id])
        XCTAssertEqual(state.paneLayout.slots.count, 2)
        XCTAssertEqual(state.paneLayout.activeSlot.repoID, nil)
    }

    func testOpeningKnownRepositoryReplacesRequestedPaneAndIgnoresMissingIDs() throws {
        let store = AppStateStore(fileURL: try temporaryStateURL())
        let source = store.addRepo(path: "/tmp/source")
        let targetPane = store.state.paneLayout.slots[1].id
        XCTAssertTrue(store.openRepoInNewPane(
            path: "/tmp/./source",
            displayName: "Source",
            replacingPaneID: targetPane
        ))
        XCTAssertEqual(store.state.paneLayout.activeSlot.repoID, source.id)
        let stateBeforeNoop = store.state
        store.openRepo(id: UUID(), inNewPane: true)
        XCTAssertEqual(store.state.savedRepos, stateBeforeNoop.savedRepos)
        XCTAssertEqual(store.state.recentRepoIDs, stateBeforeNoop.recentRepoIDs)
    }

    func testRecentRepositoryLimitAndNoopClear() throws {
        let store = AppStateStore(fileURL: try temporaryStateURL())
        let repos = (0..<5).map { store.addRepo(path: "/tmp/repo-\($0)") }
        XCTAssertEqual(store.recentRepositories.map(\.id), Array(repos.suffix(3).reversed()).map(\.id))
        store.clearRecentRepositories()
        XCTAssertTrue(store.recentRepositories.isEmpty)
        store.clearRecentRepositories()
    }

    func testOpenExistingNewPaneRemoveAndRecentOrdering() throws {
        let store = AppStateStore(fileURL: try temporaryStateURL())
        let first = store.addRepo(path: "/tmp/first")
        let second = store.addRepo(path: "/tmp/second")
        store.openRepo(id: first.id, inNewPane: true)
        XCTAssertEqual(store.state.paneLayout.slots.count, 2)
        store.openRepo(id: second.id, in: store.state.paneLayout.slots[0].id)
        XCTAssertEqual(store.state.paneLayout.activeSlot.repoID, second.id)
        store.removeRepo(id: second.id)
        XCTAssertFalse(store.state.savedRepos.contains(where: { $0.id == second.id }))
        XCTAssertFalse(store.state.recentRepoIDs.contains(second.id))
        XCTAssertFalse(store.state.paneLayout.slots.contains(where: { $0.repoID == second.id }))
    }

    func testOpenRepoInNewPaneNormalizesAndUpdatesExistingWorktree() throws {
        let store = AppStateStore(fileURL: try temporaryStateURL())
        let source = store.addRepo(path: "/tmp/source")
        XCTAssertTrue(store.openRepoInNewPane(path: "/tmp/./worktree", displayName: "Initial", sourceRepoID: source.id, branch: "one", baseBranch: "main"))
        let worktreeID = try XCTUnwrap(store.state.savedRepos.first(where: { $0.displayName == "Initial" })?.id)
        XCTAssertTrue(store.openRepoInNewPane(path: "/tmp/worktree", displayName: "Updated", branch: "two", baseBranch: "develop"))
        let updated = store.state.savedRepos.first(where: { $0.id == worktreeID })
        XCTAssertEqual(updated?.displayName, "Updated")
        XCTAssertEqual(updated?.worktreeBranch, "two")
        XCTAssertEqual(updated?.worktreeBaseBranch, "develop")
        XCTAssertEqual(store.state.savedRepos.filter { $0.path == "/tmp/worktree" }.count, 1)
        XCTAssertFalse(store.openRepoInNewPane(path: "/tmp/elsewhere", displayName: "Invalid", replacingPaneID: UUID()))
    }

    func testSelectionRestoreRemovalAndComparisonSettings() throws {
        let store = AppStateStore(fileURL: try temporaryStateURL())
        let first = store.addRepo(path: "/tmp/first")
        let second = store.addRepo(path: "/tmp/second")
        let pane = store.state.paneLayout.slots[0].id
        store.selectRepo(id: second.id, in: UUID())
        store.selectRepo(id: second.id, in: pane)
        store.restoreRepo(id: first.id, in: pane)
        store.consumeWorktreeBaseBranch(for: second.id)
        store.setDiffComparisonSelection(.againstBranch("main"), for: second.id)
        XCTAssertEqual(store.state.savedRepos.first(where: { $0.id == second.id })?.diffComparisonSelection, .againstBranch("main"))
        store.clearRepo(in: pane)
        store.restoreRepo(id: UUID(), in: pane)
        store.removePane(id: UUID())
        XCTAssertEqual(store.state.savedRepos.count, 2)
    }

    func testPaneLimitsFocusModesAndDividerPersistence() async throws {
        let url = try temporaryStateURL()
        let store = AppStateStore(fileURL: url)
        _ = store.addRepo(path: "/tmp/a")
        _ = store.addRepo(path: "/tmp/b")
        _ = store.addRepo(path: "/tmp/c")
        XCTAssertFalse(store.canAddPane)
        XCTAssertEqual(store.paneCountLimit, 3)
        store.removePane(id: store.state.paneLayout.slots.last!.id)
        XCTAssertTrue(store.canAddPane)
        store.addPane()
        XCTAssertFalse(store.canAddPane)
        store.setDisplayPaneCount(2)
        store.focusPane(at: 99)
        store.focusPane(.left)
        let pane = store.state.paneLayout.activePaneID
        store.focusPane(id: UUID())
        store.toggleMaximizedPane(id: pane)
        store.toggleMaximizedActivePane()
        store.toggleTerminalOnlyPane(id: pane)
        store.toggleTerminalOnlyActivePane()
        store.setPaneSplitTopFraction(0.4, paneID: pane)
        store.setPaneSplitTopFraction(0.4005, paneID: pane)
        store.setViewerAsSidePanel(true, paneID: pane)
        store.setViewerAsSidePanel(true, paneID: pane)
        store.setGridDividerFractions([0.3], role: .columns(row: 0))
        store.setGridDividerFractions([0.3], role: .columns(row: 0))
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    private var directory: TemporaryTestDirectory?

    private func temporaryStateURL() throws -> URL {
        let directory = try TemporaryTestDirectory()
        self.directory = directory
        return directory.url.appendingPathComponent("state.json")
    }
}

@MainActor
final class FileViewerTabTests: XCTestCase {
    func testLoadReloadScrollRequestAndMissingFileState() async throws {
        let directory = try TemporaryTestDirectory()
        let file = try directory.write("Sources/README.txt", contents: "first\nline\n")
        let tab = FileViewerTab(path: file.path, scrollToLine: 2, isWatching: false)
        try await waitUntil { tab.loadedFile != nil }

        XCTAssertEqual(tab.displayName, "README.txt")
        XCTAssertEqual(tab.pendingScrollLine, 2)
        guard case .text(let firstText) = tab.content else { return XCTFail("Expected loaded text") }
        XCTAssertEqual(firstText, "first\nline\n")
        XCTAssertEqual(tab.lineStartOffsets, [0, 6, 11])
        tab.scrollToLine(1)
        XCTAssertEqual(tab.pendingScrollLine, 1)
        tab.setWatching(false)

        _ = try directory.write("Sources/README.txt", contents: "updated with more bytes\n")
        await tab.reload()
        guard case .text(let updatedText) = tab.content else { return XCTFail("Expected reloaded text") }
        XCTAssertEqual(updatedText, "updated with more bytes\n")

        try FileManager.default.removeItem(at: file)
        await tab.reload()
        guard case .notFound = tab.content else { return XCTFail("Expected deleted file state") }
    }

    func testWatchingCanBeEnabledAndDisabled() async throws {
        let directory = try TemporaryTestDirectory()
        let file = try directory.write("watch.txt", contents: "watch me")
        let tab = FileViewerTab(path: file.path, isWatching: false)
        tab.setWatching(true)
        tab.setWatching(true)
        try await waitUntil { tab.loadedFile != nil }
        tab.setWatching(false)
        tab.setWatching(false)
        guard case .text(let text) = tab.content else { return XCTFail("Expected watched text") }
        XCTAssertEqual(text, "watch me")
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("The file viewer did not reach the expected state.")
    }
}

@MainActor
final class PermissionAndRepositoryErrorTests: XCTestCase {
    func testTCCProtectedDirectoryBoundariesAndReadablePaths() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for folder in ["Desktop", "Documents", "Downloads"] {
            XCTAssertTrue(TCCPermission.isProtectedByTCC(path: "\(home)/\(folder)"))
            XCTAssertTrue(TCCPermission.isProtectedByTCC(path: "\(home)/\(folder)/nested/file.txt"))
            XCTAssertFalse(TCCPermission.isProtectedByTCC(path: "\(home)/\(folder)-backup"))
        }

        let directory = try TemporaryTestDirectory()
        let file = try directory.write("file.txt", contents: "content")
        XCTAssertTrue(TCCPermission.canReadDirectory(path: directory.url.path))
        XCTAssertFalse(TCCPermission.canReadDirectory(path: file.path))
        XCTAssertFalse(TCCPermission.canReadDirectory(path: directory.url.appendingPathComponent("missing").path))
        XCTAssertFalse(TCCPermission.isProtectedByTCC(path: file.path))
    }

    func testRepositoryOpenErrorIncludesInvalidPath() {
        let path = "/tmp/not-a-repository"
        let error = RepoOpenError.notAGitRepo(path: path)
        XCTAssertEqual(error.errorDescription, L10n.format(L10n.Repository.invalidRepositoryMessage, path))
    }

    func testRepositorySelectionValidationHandlesCancelValidAndInvalidFolders() throws {
        XCTAssertNil(RepoOpener.validatedResult(for: nil))

        let directory = try TemporaryTestDirectory()
        try FileManager.default.createDirectory(
            at: directory.url.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        guard case .success(let validPath)? = RepoOpener.validatedResult(for: directory.url) else {
            return XCTFail("Expected a directory with .git to be accepted")
        }
        XCTAssertEqual(validPath, directory.url.path)

        let invalidURL = directory.url.appendingPathComponent("ordinary-folder")
        try FileManager.default.createDirectory(at: invalidURL, withIntermediateDirectories: true)
        guard case .failure(.notAGitRepo(let invalidPath))? = RepoOpener.validatedResult(for: invalidURL) else {
            return XCTFail("Expected a directory without .git to be rejected")
        }
        XCTAssertEqual(invalidPath, invalidURL.path)
    }

    func testRepositoryPanelSelectionHandlesCancelMissingURLAndAcceptedFolder() throws {
        let directory = try TemporaryTestDirectory()
        try FileManager.default.createDirectory(
            at: directory.url.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )

        XCTAssertNil(RepoOpener.selectionResult(response: .cancel, url: directory.url))
        XCTAssertNil(RepoOpener.selectionResult(response: .OK, url: nil))
        guard case .success(let path)? = RepoOpener.selectionResult(response: .OK, url: directory.url) else {
            return XCTFail("Expected the accepted repository folder")
        }
        XCTAssertEqual(path, directory.url.path)
    }
}

@MainActor
final class ZeroCoverageViewTests: XCTestCase {
    func testShortcutQuickSwitcherAndPickerViewBodiesBuild() {
        _ = ShortcutHelpView().body

        let repo = Repo(path: "/tmp/example", displayName: "Example")
        let file = QuickSwitcherFile(repoID: repo.id, repoName: repo.name, path: "/tmp/example/README.md")
        _ = QuickSwitcherView(repos: [repo], files: [file], onSelectRepo: { _ in }, onSelectFile: { _ in }).body
        _ = QuickSwitcherView(repos: [], files: [], onSelectRepo: { _ in }, onSelectFile: { _ in }).body

        let ambiguous = AmbiguousLinkPicker(candidates: ["/repo/A/File.swift", "/repo/B/File.swift"], line: 12)
        _ = AmbiguousFilePickerView(picker: ambiguous, repoPath: "/repo", onPick: { _ in }).body
        _ = AmbiguousFilePickerView(picker: ambiguous, repoPath: "/other", onPick: { _ in }).body
    }

    func testBranchAndOpenTabsViewBodiesBuildForEmptyAndPopulatedStates() throws {
        let directory = try TemporaryTestDirectory()
        let store = RepoDiffStore(repoPath: directory.url.path)
        _ = BranchComparisonPickerView(store: store).body

        let stateURL = directory.url.appendingPathComponent("state.json")
        let appState = AppStateStore(fileURL: stateURL)
        _ = appState.addRepo(path: directory.url.path)
        _ = WorktreeBranchPickerView(repo: Repo(path: directory.url.path), replacingPaneID: nil).body

        _ = RepositoryManagerView(repos: [], onRemoveRepositories: { _ in }).body
        let unavailable = Repo(path: "/tmp/missing-repository")
        _ = RepositoryManagerView(repos: [unavailable], onRemoveRepositories: { _ in }).body

        let tabsStore = TopAreaStore()
        _ = OpenTabsView(store: tabsStore).body

        let file = try directory.write("README.md", contents: "read me")
        _ = tabsStore.openFile(path: file.path)
        _ = OpenTabsView(store: tabsStore).body
    }

    func testFileViewerContentBodyCoversEveryLoadState() async throws {
        let directory = try TemporaryTestDirectory()
        let missingPath = directory.url.appendingPathComponent("missing.txt").path
        let loadingTab = FileViewerTab(path: missingPath, isWatching: false)
        _ = FileViewerContentView(tab: loadingTab).body
        try await waitUntil { loadingTab.loadedFile != nil }
        _ = FileViewerContentView(tab: loadingTab).body

        let textFile = try directory.write("text.txt", contents: "line one\nline two\n")
        let textTab = FileViewerTab(path: textFile.path, isWatching: false)
        try await waitUntil { textTab.loadedFile != nil }
        _ = FileViewerContentView(tab: textTab).body

        let imageBytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/pysAAAAASUVORK5CYII=")!
        let imageFile = try directory.write("pixel.png", data: imageBytes)
        let imageTab = FileViewerTab(path: imageFile.path, isWatching: false)
        try await waitUntil { imageTab.loadedFile != nil }
        _ = FileViewerContentView(tab: imageTab).body

        let pdfFile = try directory.write("document.pdf", contents: "%PDF-1.4")
        let pdfTab = FileViewerTab(path: pdfFile.path, isWatching: false)
        try await waitUntil { pdfTab.loadedFile != nil }
        _ = FileViewerContentView(tab: pdfTab).body

        let largeFile = try directory.writeSparse("large.pdf", size: FileLoader.maxMediaBytes + 1)
        let largeTab = FileViewerTab(path: largeFile.path, isWatching: false)
        try await waitUntil { largeTab.loadedFile != nil }
        _ = FileViewerContentView(tab: largeTab).body

        let binaryFile = try directory.write("binary.txt", data: Data([0xFF, 0xFE]))
        let binaryTab = FileViewerTab(path: binaryFile.path, isWatching: false)
        try await waitUntil { binaryTab.loadedFile != nil }
        _ = FileViewerContentView(tab: binaryTab).body

        let invalidImage = try directory.write("invalid.png", contents: "not png")
        let errorTab = FileViewerTab(path: invalidImage.path, isWatching: false)
        try await waitUntil { errorTab.loadedFile != nil }
        _ = FileViewerContentView(tab: errorTab).body
    }

    func testReadOnlyTextCoordinatorAndTerminalLocalLinkCallback() {
        let textView = ReadOnlyTextView(text: "text", lineStartOffsets: [0], contentVersion: UUID())
        XCTAssertNil(textView.makeCoordinator().textView)

        let terminal = GridlineTerminalView(frame: .zero)
        var openedLink: String?
        terminal.onOpenLink = { openedLink = $0 }
        terminal.requestOpenLink(source: terminal, link: "Sources/App.swift:9", params: [:])
        XCTAssertEqual(openedLink, "Sources/App.swift:9")
    }

    func testSettingsViewMountsInsideHostedHierarchy() {
        let hostingView = NSHostingView(rootView: GridlineSettingsView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        XCTAssertFalse(hostingView.subviews.isEmpty)
    }

    func testPaneToastAppearsAndExpiresInHostedHierarchy() async throws {
        var toast: PaneToast? = PaneToast(message: "File opened")
        let binding = Binding<PaneToast?>(get: { toast }, set: { toast = $0 })
        let hostingView = NSHostingView(rootView: Text("content").paneToast(binding, duration: .milliseconds(20)))
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        try await waitUntil(timeout: .seconds(2)) { toast == nil }
    }

    func testClosedRepoToastRestoresItsRepository() throws {
        let repository = Repo(path: "/tmp/example", displayName: "Example")
        var restoredName: String?
        let hostingView = NSHostingView(rootView: ClosedRepoToastView(repoName: repository.name) {
            restoredName = repository.name
        })
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 100)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        let button = try XCTUnwrap(descendantView(of: NSButton.self, in: hostingView))
        button.performClick(nil)

        XCTAssertEqual(restoredName, repository.name)
    }

    func testReadOnlyTextViewMountsUpdatesAndConsumesScrollRequests() async throws {
        let consumedScroll = expectation(description: "scroll request is consumed")
        let hostingView = NSHostingView(rootView: ReadOnlyTextView(
            text: "first line\nsecond line\n",
            lineStartOffsets: [0, 11],
            contentVersion: UUID()
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        let scrollView = try XCTUnwrap(descendantView(of: NSScrollView.self, in: hostingView))
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        XCTAssertEqual(textView.string, "first line\nsecond line\n")
        XCTAssertTrue(scrollView.hasVerticalRuler)
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertTrue(scrollView.hasHorizontalScroller)
        let ruler = try XCTUnwrap(scrollView.verticalRulerView as? LineNumberRulerView)
        ruler.drawHashMarksAndLabels(in: ruler.bounds)

        hostingView.rootView = ReadOnlyTextView(
            text: "updated line\nlast line\n",
            lineStartOffsets: [0, 13],
            contentVersion: UUID(),
            scrollToLine: 2,
            onDidConsumeScrollRequest: { consumedScroll.fulfill() }
        )
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        XCTAssertEqual(textView.string, "updated line\nlast line\n")
        ruler.drawHashMarksAndLabels(in: ruler.bounds)
        await fulfillment(of: [consumedScroll], timeout: 2)
    }

    func testClipboardAndLineNumberRulerSetup() {
        let pasteboard = NSPasteboard.general
        let previousValue = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let previousValue {
                pasteboard.setString(previousValue, forType: .string)
            }
        }
        NSPasteboard.copyString("Gridline test")
        XCTAssertEqual(pasteboard.string(forType: .string), "Gridline test")

        let scrollView = NSScrollView(frame: .zero)
        let textView = NSTextView(frame: .zero)
        scrollView.documentView = textView
        let ruler = LineNumberRulerView(textView: textView)
        ruler.setLineStartOffsets([0, 4, 12])
        XCTAssertEqual(ruler.ruleThickness, 44)
    }

    func testPDFKitViewMountsAndUpdatesItsDocument() throws {
        let directory = try TemporaryTestDirectory()
        let firstFile = try directory.write("preview.pdf", contents: "%PDF-1.4")
        let secondFile = try directory.write("updated.pdf", contents: "%PDF-1.4")
        let pdfView = PDFKitView.makePDFView(url: firstFile)
        XCTAssertTrue(pdfView.autoScales)

        let hostingView = NSHostingView(rootView: PDFKitView(url: firstFile))
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let hostedPDFView = try XCTUnwrap(descendantView(of: PDFView.self, in: hostingView))
        XCTAssertTrue(hostedPDFView.autoScales)

        hostingView.rootView = PDFKitView(url: secondFile)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        XCTAssertTrue(hostedPDFView.autoScales)
    }

    func testDiffAndTopAreaBodiesCoverLocalFocusAndViewerBranches() async throws {
        let directory = try TemporaryTestDirectory()
        let repository = Repo(path: directory.url.path, displayName: "Example")
        let diffStore = RepoDiffStore(repoPath: directory.url.path)
        await diffStore.refresh()

        _ = DiffAreaView(store: diffStore).body
        diffStore.isFocusMode = true
        _ = DiffAreaView(store: diffStore).body
        _ = DiffAreaView(store: diffStore, showsFileList: false).body

        let topStore = TopAreaStore()
        _ = TopAreaView(topAreaStore: topStore, diffStore: diffStore, viewerAsSidePanel: false, onToggleViewerAsSidePanel: {}).body
        let file = try directory.write("README.md", contents: "read me")
        _ = topStore.openFile(path: file.path)
        topStore.selection = .file(topStore.openFiles[0].id)
        _ = TopAreaView(topAreaStore: topStore, diffStore: diffStore, viewerAsSidePanel: true, onToggleViewerAsSidePanel: {}).body

        _ = RepoPaneHeaderView(
            repo: repository,
            availableRepos: [repository],
            diffStore: diffStore,
            attention: .completed,
            workStatus: .needsAttention,
            isMaximized: false,
            isTerminalOnly: false,
            onSelectRepo: { _ in },
            onManageRepositories: {},
            onClose: {},
            canClosePane: true,
            onClosePane: {},
            onToggleMaximize: {},
            onToggleTerminalOnly: {}
        ).body
    }

    func testDiffFontMetricsHandleTabsAndBothLayouts() {
        let diff = FileDiff(
            entry: DiffFileEntry(path: "file.txt", group: .unstaged, status: .modified),
            hunks: [DiffHunk(
                header: "@@",
                lines: [DiffLine(kind: .context, oldLineNumber: 1, newLineNumber: 1, text: "a\tb")]
            )],
            isBinary: false,
            rawText: "raw"
        )
        XCTAssertEqual(DiffFontMetrics.maximumColumns(in: diff), 10)
        XCTAssertEqual(DiffFontMetrics.gutterWidth(for: GridlinePreferences.defaultDiffFontSize), 36)

        let layout = DiffFontMetrics.layout(maximumColumns: 10, fontSize: 14, viewportWidth: 100)
        XCTAssertEqual(layout.fontSize, 14)
        XCTAssertGreaterThanOrEqual(layout.contentWidth, 100)

        let cache = DiffColumnCountCache()
        XCTAssertEqual(cache.count(for: diff), 10)
        XCTAssertEqual(cache.count(for: diff), 10)
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("The view model did not reach the expected content state.")
    }

    private func descendantView<View: NSView>(of type: View.Type, in root: NSView) -> View? {
        if let match = root as? View { return match }
        for child in root.subviews {
            if let match = descendantView(of: type, in: child) { return match }
        }
        return nil
    }
}

@MainActor
final class NestedPaneSplitViewTests: XCTestCase {
    func testRootControllerBuildsBalancedGridAndUpdatesVisibleHostsInPlace() {
        let paneIDs = (0..<4).map { _ in UUID() }
        let items = paneIDs.enumerated().map { index, id in
            PaneGridItem(id: id, content: AnyView(Text("Pane \(index)")))
        }
        let coordinator = NestedPaneSplitView(
            items: [],
            retainedPaneIDs: [],
            dividerFractions: [:],
            onDividerChanged: { _, _ in }
        ).makeCoordinator()
        let controller = PaneGridRootViewController()
        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 1_600, height: 1_000)

        controller.update(items: items, retainedPaneIDs: paneIDs, coordinator: coordinator)
        controller.view.layoutSubtreeIfNeeded()

        let initialSplitControllers = splitControllers(in: controller)
        XCTAssertEqual(initialSplitControllers.filter { $0.splitView.isVertical }.count, 2)
        XCTAssertEqual(initialSplitControllers.filter { !$0.splitView.isVertical }.count, 1)
        XCTAssertEqual(hostingControllerCount(in: controller), 4)
        let existingGridController = controller.children.first

        let updatedItems = paneIDs.enumerated().map { index, id in
            PaneGridItem(id: id, content: AnyView(Text("Updated pane \(index)")))
        }
        controller.update(items: updatedItems, retainedPaneIDs: paneIDs, coordinator: coordinator)

        XCTAssertTrue(controller.children.first === existingGridController)
        controller.applyDividerFractions([
            .columns(row: 0): [0.35],
            .columns(row: 1): [0.65],
            .rows: [0.55],
        ])
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(hostingControllerCount(in: controller), 4)

        controller.update(items: [updatedItems[0]], retainedPaneIDs: paneIDs, coordinator: coordinator)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertTrue(splitControllers(in: controller).isEmpty)
        XCTAssertEqual(hostingControllerCount(in: controller), 1)

        controller.update(items: updatedItems, retainedPaneIDs: paneIDs, coordinator: coordinator)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(splitControllers(in: controller).count, 3)
        XCTAssertEqual(hostingControllerCount(in: controller), 4)
    }

    func testCoordinatorReportsFractionsAndRemovesResizeObservers() async {
        let report = expectation(description: "split fraction is reported")
        var changes: [(PaneDividerRole, [CGFloat])] = []
        let coordinator = NestedPaneSplitView(
            items: [],
            retainedPaneIDs: [],
            dividerFractions: [:],
            onDividerChanged: { role, fractions in
                changes.append((role, fractions))
                report.fulfill()
            }
        ).makeCoordinator()
        let splitView = NSSplitView(frame: NSRect(x: 0, y: 0, width: 100, height: 80))
        splitView.isVertical = true
        let left = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 80))
        let right = NSView(frame: NSRect(x: 40, y: 0, width: 60, height: 80))
        splitView.addSubview(left)
        splitView.addSubview(right)
        left.frame = NSRect(x: 0, y: 0, width: 40, height: 80)
        right.frame = NSRect(x: 40, y: 0, width: 60, height: 80)

        coordinator.observe([(splitView, .columns(row: 0))])
        NotificationCenter.default.post(name: NSSplitView.didResizeSubviewsNotification, object: splitView)

        await fulfillment(of: [report], timeout: 2)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.0, .columns(row: 0))
        XCTAssertEqual(changes.first?.1, [0.4])

        coordinator.stopObserving()
        NotificationCenter.default.post(name: NSSplitView.didResizeSubviewsNotification, object: splitView)
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(changes.count, 1)
    }

    private func splitControllers(in root: NSViewController) -> [NSSplitViewController] {
        var result: [NSSplitViewController] = []
        if let splitController = root as? NSSplitViewController {
            result.append(splitController)
        }
        for child in root.children {
            result.append(contentsOf: splitControllers(in: child))
        }
        return result
    }

    private func hostingControllerCount(in root: NSViewController) -> Int {
        (root is NSHostingController<AnyView> ? 1 : 0)
            + root.children.reduce(0) { $0 + hostingControllerCount(in: $1) }
    }
}

final class SearchAndBranchSelectionPolicyTests: XCTestCase {
    func testQuickSwitcherSearchFiltersRepositoriesByNameOrPathCaseInsensitively() {
        let gridline = Repo(path: "/Users/test/Projects/Gridline")
        let displayNamed = Repo(path: "/tmp/custom-path", displayName: "Personal Notes")
        let repos = [gridline, displayNamed]

        XCTAssertEqual(QuickSwitcherSearchPolicy.filteredRepos(repos, query: ""), repos)
        XCTAssertEqual(QuickSwitcherSearchPolicy.filteredRepos(repos, query: "GRIDLINE"), [gridline])
        XCTAssertEqual(QuickSwitcherSearchPolicy.filteredRepos(repos, query: "CUSTOM-PATH"), [displayNamed])
        XCTAssertTrue(QuickSwitcherSearchPolicy.filteredRepos(repos, query: "missing").isEmpty)
    }

    func testQuickSwitcherSearchFiltersFilesByNamePathOrRepositoryName() {
        let repoID = UUID()
        let file = QuickSwitcherFile(repoID: repoID, repoName: "Gridline", path: "/tmp/Notes.md")
        let files = [file]

        XCTAssertEqual(QuickSwitcherSearchPolicy.filteredFiles(files, query: ""), files)
        XCTAssertEqual(QuickSwitcherSearchPolicy.filteredFiles(files, query: "notes"), files)
        XCTAssertEqual(QuickSwitcherSearchPolicy.filteredFiles(files, query: "/TMP"), files)
        XCTAssertEqual(QuickSwitcherSearchPolicy.filteredFiles(files, query: "GRIDLINE"), files)
        XCTAssertTrue(QuickSwitcherSearchPolicy.filteredFiles(files, query: "missing").isEmpty)
    }

    func testBranchPickerInitialSelectionUsesSavedValuesOrFirstDistinctBranches() {
        XCTAssertEqual(
            BranchComparisonPickerPolicy.initialSelection(branches: ["main", "feature"], savedBase: nil, savedTarget: nil).base,
            "main"
        )
        XCTAssertEqual(
            BranchComparisonPickerPolicy.initialSelection(branches: ["main", "feature"], savedBase: nil, savedTarget: nil).target,
            "feature"
        )
        let saved = BranchComparisonPickerPolicy.initialSelection(
            branches: ["main", "feature"],
            savedBase: "feature",
            savedTarget: "main"
        )
        XCTAssertEqual(saved.base, "feature")
        XCTAssertEqual(saved.target, "main")
        XCTAssertEqual(BranchComparisonPickerPolicy.initialSelection(branches: [], savedBase: nil, savedTarget: nil).base, "")
    }

    func testBranchPickerRepairsRemovedOrDuplicateSelectionsAndValidatesComparison() {
        XCTAssertEqual(
            BranchComparisonPickerPolicy.repairedSelection(branches: [], base: "saved-base", target: "saved-target").base,
            "saved-base"
        )
        let removed = BranchComparisonPickerPolicy.repairedSelection(
            branches: ["main", "feature"],
            base: "removed",
            target: "feature"
        )
        XCTAssertEqual(removed.base, "main")
        XCTAssertEqual(removed.target, "feature")

        let duplicate = BranchComparisonPickerPolicy.repairedSelection(
            branches: ["main", "feature"],
            base: "main",
            target: "main"
        )
        XCTAssertEqual(duplicate.base, "main")
        XCTAssertEqual(duplicate.target, "feature")
        XCTAssertTrue(BranchComparisonPickerPolicy.canCompare(base: "main", target: "feature"))
        XCTAssertFalse(BranchComparisonPickerPolicy.canCompare(base: "", target: "feature"))
        XCTAssertFalse(BranchComparisonPickerPolicy.canCompare(base: "main", target: ""))
        XCTAssertFalse(BranchComparisonPickerPolicy.canCompare(base: "main", target: "main"))
    }

    func testPaneCountPolicyAppliesSafeChangesWithoutPrompting() {
        let layout = PaneLayout(slots: [PaneSlot(repoID: UUID()), PaneSlot(repoID: UUID())], displayPaneCount: 2)
        var inspectedRepoIDs: [UUID] = []

        let increase = PaneCountChangePolicy.decision(
            paneCount: 3,
            layout: layout,
            visiblePaneSlots: layout.displayedSlots
        ) { repoID in
            inspectedRepoIDs.append(repoID)
            return 1
        }
        XCTAssertEqual(increase, .applyImmediately(3))
        XCTAssertTrue(inspectedRepoIDs.isEmpty)

        let decreaseWithoutCommands = PaneCountChangePolicy.decision(
            paneCount: 1,
            layout: layout,
            visiblePaneSlots: layout.displayedSlots
        ) { _ in 0 }
        XCTAssertEqual(decreaseWithoutCommands, .applyImmediately(1))
    }

    func testPaneCountPolicyCountsCommandsInAllHiddenRepositories() {
        let repoIDs = (0..<3).map { _ in UUID() }
        let layout = PaneLayout(slots: repoIDs.map { PaneSlot(repoID: $0) }, displayPaneCount: 3)

        let decision = PaneCountChangePolicy.decision(
            paneCount: 1,
            layout: layout,
            visiblePaneSlots: layout.displayedSlots
        ) { repoID in
            repoID == repoIDs[1] ? 2 : (repoID == repoIDs[2] ? 3 : 0)
        }

        XCTAssertEqual(decision, .confirm(paneCount: 1, activeCommandCount: 5))
    }
}

@MainActor
private final class TemporaryTestDirectory {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("GridlineCoreTests-\(UUID().uuidString)", isDirectory: true)

    init() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ relativePath: String, contents: String) throws -> URL {
        try write(relativePath, data: Data(contents.utf8))
    }

    func write(_ relativePath: String, data: Data) throws -> URL {
        let file = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
        return file.resolvingSymlinksInPath()
    }

    func writeSparse(_ relativePath: String, size: Int64) throws -> URL {
        let file = url.appendingPathComponent(relativePath)
        _ = FileManager.default.createFile(atPath: file.path, contents: Data())
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
        return file
    }
}
