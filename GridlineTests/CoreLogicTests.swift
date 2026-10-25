import AppKit
import XCTest
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
        let onlyMatch = try directory.write("Sources/Unique.swift", contents: "")
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
        try directory.write("Nested/Only.swift", contents: "")
        try directory.write(".hidden/Secret.swift", contents: "")

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

        guard case .text(let text) = result.content else { return XCTFail("Expected text") }
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

        let entry = DiffFileEntry(path: "Sources/File.swift", group: .staged, status: .modified)
        XCTAssertEqual(entry.id, "staged:Sources/File.swift")
        XCTAssertEqual(entry.displayName, "File.swift")
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

        try directory.write("Sources/README.txt", contents: "updated with more bytes\n")
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
