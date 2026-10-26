//
//  DiffAreaView.swift
//  Gridline
//
//  Panel diff: daftar file (staged/unstaged/untracked) di kiri, isi diff di
//  kanan (satu kolom, unified). ↑/↓ memilih file, ⌥↑/⌥↓ pindah hunk
//  (bagian 6 apps-spec.md).
//

import AppKit
import SwiftUI

@MainActor
private final class DiffKeyboardEventMonitor {
    var isEnabled = false
    var visibleEntryIDs: [String]?
    var onMoveFile: (Int) -> Void = { _ in }
    var onMoveHunk: (Int) -> Void = { _ in }

    private var eventMonitor: Any?

    func start() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, isEnabled else { return event }
            let offset: Int
            switch event.keyCode {
            case 126: offset = -1 // Up
            case 125: offset = 1  // Down
            default: return event
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasOption = modifiers.contains(.option)
            let hasOtherNavigationModifier = modifiers.contains(.command)
                || modifiers.contains(.control)
                || modifiers.contains(.shift)

            // macOS marks arrow keys with `.numericPad`; that is a key-origin
            // flag, not a user modifier, so it must not block navigation.
            if hasOption && !hasOtherNavigationModifier {
                onMoveHunk(offset)
                return nil
            }
            guard !hasOption, !hasOtherNavigationModifier else { return event }
            onMoveFile(offset)
            return nil
        }
    }

    func stop() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
        isEnabled = false
    }
}

/// Mode tampilan daftar file diff (menu "Tree/List/Combined List" di
/// toolbar `DiffFileListView`, mirip git client lain seperti Fork).
enum DiffFileListMode: String {
    /// Tiap bagian (Staged/Unstaged/Untracked/Ignored) sebagai daftar flat —
    /// perilaku lama sebelum fitur ini ada, tetap jadi default.
    case list
    /// Tiap bagian disusun sebagai hierarki folder yang bisa dilipat.
    case tree
    /// Semua entri digabung jadi satu daftar tanpa header bagian.
    case combinedList
}

enum DiffFontMetrics {
    private static let tabByte: UInt8 = 0x09
    private static let tabColumns = 8
    private static let textInset: CGFloat = 6

    static func gutterWidth(for fontSize: Int) -> CGFloat {
        36 * CGFloat(fontSize) / CGFloat(GridlinePreferences.defaultDiffFontSize)
    }

    static func layout(maximumColumns: Int, fontSize: Int, viewportWidth: CGFloat) -> DiffTextLayout {
        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        let characterWidth = ("W" as NSString).size(withAttributes: [.font: font]).width
        let textWidth = ceil(CGFloat(maximumColumns) * characterWidth)
        let gutter = gutterWidth(for: fontSize)
        let contentWidth = max(viewportWidth, 2 * gutter + textInset + textWidth)
        return DiffTextLayout(fontSize: fontSize, contentWidth: contentWidth)
    }

    static func maximumColumns(in diff: FileDiff) -> Int {
        var maximumColumns = 0
        for hunk in diff.hunks {
            maximumColumns = max(maximumColumns, displayColumns(in: hunk.header))
            for line in hunk.lines {
                maximumColumns = max(maximumColumns, displayColumns(in: line.text))
            }
        }
        return maximumColumns
    }

    private static func displayColumns(in text: String) -> Int {
        text.utf8.reduce(0) { columns, byte in
            columns + (byte == tabByte ? tabColumns : 1)
        }
    }
}

final class DiffColumnCountCache {
    private var rawText: String?
    private var maximumColumns = 0

    func count(for diff: FileDiff) -> Int {
        guard rawText != diff.rawText else { return maximumColumns }
        maximumColumns = DiffFontMetrics.maximumColumns(in: diff)
        rawText = diff.rawText
        return maximumColumns
    }
}

/// Cache highlight word-level per baris (lihat `WordDiffPolicy`), diinvalidasi
/// memakai `rawText` yang sama seperti `DiffColumnCountCache` supaya tidak
/// dihitung ulang di setiap render selama isi diff tidak berubah.
final class WordDiffHighlightCache {
    /// Batas jumlah pasangan baris hapus/tambah yang diberi word-diff per
    /// file — `WordDiffPolicy` sudah membatasi biaya per baris (`maxTokens`),
    /// tapi file dengan ribuan baris berubah (refactor besar, file generated)
    /// tetap bisa membuat total perhitungan memblokir main thread saat ganti
    /// file/branch. Pasangan di luar batas ini tidak diberi highlight kata,
    /// kembali ke tampilan warna baris biasa seperti sebelum fitur ini ada.
    private static let maxPairsPerFile = 2000

    private var rawText: String?
    private var highlightsByLineID: [DiffLine.ID: [Range<Int>]] = [:]

    func highlights(for diff: FileDiff) -> [DiffLine.ID: [Range<Int>]] {
        guard rawText != diff.rawText else { return highlightsByLineID }
        rawText = diff.rawText
        highlightsByLineID = Self.compute(for: diff)
        return highlightsByLineID
    }

    private static func compute(for diff: FileDiff) -> [DiffLine.ID: [Range<Int>]] {
        var result: [DiffLine.ID: [Range<Int>]] = [:]
        var processedPairs = 0
        for hunk in diff.hunks {
            for pair in DiffLinePairingPolicy.pairs(in: hunk.lines) {
                guard let oldLine = pair.0, let newLine = pair.1,
                      oldLine.kind == .deletion, newLine.kind == .addition else { continue }
                guard processedPairs < maxPairsPerFile else { continue }
                processedPairs += 1
                let changed = WordDiffPolicy.changedRanges(old: oldLine.text, new: newLine.text)
                result[oldLine.id] = changed.old
                result[newLine.id] = changed.new
            }
        }
        return result
    }
}

/// Merender teks baris diff dengan highlight word-level sebagai background
/// pada rentang yang berubah. Memakai satu `Text(AttributedString)` (bukan
/// beberapa `Text` yang disusun) supaya tetap ringan dirender dan perilaku
/// `.lineLimit`/`.fixedSize` sama seperti sebelum highlight ditambahkan.
private func highlightedLineText(_ text: String, ranges: [Range<Int>], highlightColor: Color) -> Text {
    let content = text.isEmpty ? " " : text
    guard !ranges.isEmpty else { return Text(content) }

    var attributed = AttributedString(content)
    for range in ranges {
        guard range.lowerBound >= 0, range.upperBound <= content.count,
              let lower = attributed.characters.index(attributed.startIndex, offsetBy: range.lowerBound, limitedBy: attributed.endIndex),
              let upper = attributed.characters.index(attributed.startIndex, offsetBy: range.upperBound, limitedBy: attributed.endIndex)
        else { continue }
        attributed[lower..<upper].backgroundColor = highlightColor
    }
    return Text(attributed)
}

struct DiffTextLayout {
    let fontSize: Int
    let contentWidth: CGFloat
}

struct DiffAreaView: View {
    @ObservedObject var store: RepoDiffStore
    /// Dipanggil saat pengguna double-click file di daftar untuk membukanya
    /// di viewer. Entry point sementara sebelum Cmd+klik (M2 langkah 7) ada.
    var onOpenFile: (String) -> Void = { _ in }
    var showsFileList = true
    @AppStorage(GridlinePreferences.diffFontSizeKey)
    private var fontSize = GridlinePreferences.defaultDiffFontSize
    @State private var selectedHunkID: DiffHunk.ID?
    @FocusState private var diffHasKeyboardFocus: Bool
    @State private var keyboardMonitor = DiffKeyboardEventMonitor()

    var body: some View {
        Group {
            if !store.isGitAvailable {
                GitUnavailableView()
            } else if store.isFocusMode || !showsFileList {
                DiffContentView(
                    store: store,
                    selectedHunkID: $selectedHunkID,
                    fontSize: fontSize,
                    onToggleFocus: { store.isFocusMode = false },
                    showsFocusToggle: showsFileList
                )
            } else {
                HSplitView {
                    DiffFileListView(
                        store: store,
                        fontSize: fontSize,
                        onOpenFile: onOpenFile,
                        onVisibleEntriesChange: { ids in
                            reconcileSelection(withVisibleEntryIDs: ids)
                        },
                        isKeyboardFocused: diffHasKeyboardFocus,
                        onRequestKeyboardFocus: {
                            diffHasKeyboardFocus = true
                            keyboardMonitor.isEnabled = true
                        }
                    )
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
                    DiffContentView(
                        store: store,
                        selectedHunkID: $selectedHunkID,
                        fontSize: fontSize,
                        onToggleFocus: { store.isFocusMode = true },
                        showsFocusToggle: showsFileList
                    )
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .focusable()
        .focused($diffHasKeyboardFocus)
        .simultaneousGesture(TapGesture().onEnded {
            diffHasKeyboardFocus = true
        })
        .onChange(of: diffHasKeyboardFocus) { _, isFocused in
            keyboardMonitor.isEnabled = isFocused
        }
        .onAppear {
            keyboardMonitor.onMoveFile = { offset in
                let entries: [DiffFileEntry]
                if let visibleEntryIDs = keyboardMonitor.visibleEntryIDs {
                    let entriesByID = Dictionary(uniqueKeysWithValues: store.visibleEntries.map { ($0.id, $0) })
                    entries = visibleEntryIDs.compactMap { entriesByID[$0] }
                } else {
                    entries = store.visibleEntries
                }
                store.selectAdjacent(offset: offset, within: entries)
            }
            keyboardMonitor.onMoveHunk = moveHunk
            keyboardMonitor.start()
            keyboardMonitor.isEnabled = diffHasKeyboardFocus
        }
        .onDisappear {
            keyboardMonitor.stop()
        }
    }

    private func moveHunk(offset: Int) {
        guard let diff = store.selectedDiff, !diff.hunks.isEmpty else { return }
        guard let currentIndex = diff.hunks.firstIndex(where: { $0.id == selectedHunkID }) else {
            selectedHunkID = diff.hunks.first?.id
            return
        }
        let newIndex = max(0, min(diff.hunks.count - 1, currentIndex + offset))
        selectedHunkID = diff.hunks[newIndex].id
    }

    private func reconcileSelection(withVisibleEntryIDs ids: [DiffFileEntry.ID]) {
        keyboardMonitor.visibleEntryIDs = ids
        if let selectedFileID = store.selectedFileID, ids.contains(selectedFileID) { return }

        // Avoid publishing state during SwiftUI's view update. Filtering removes
        // a selected row and its preview together, then chooses the next visible row.
        Task { @MainActor in
            await Task.yield()
            guard keyboardMonitor.visibleEntryIDs == ids else { return }
            if let currentSelection = store.selectedFileID, ids.contains(currentSelection) { return }
            let visibleIDSet = Set(ids)
            if let nextEntry = store.displayedEntries.first(where: { visibleIDSet.contains($0.id) }) {
                store.select(nextEntry)
            } else {
                store.clearSelection()
            }
        }
    }
}

private struct GitUnavailableView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(L10n.Diff.gitNotFound)
                .font(.headline)
            Text(L10n.Diff.installCommandLineTools)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Daftar file

private struct DiffFileListView: View {
    @ObservedObject var store: RepoDiffStore
    let fontSize: Int
    let onOpenFile: (String) -> Void
    let onVisibleEntriesChange: ([String]) -> Void
    let isKeyboardFocused: Bool
    let onRequestKeyboardFocus: () -> Void
    @State private var showsBranchComparison = false
    @State private var showsBranchPicker = false
    @AppStorage("gridline.diffFileListMode") private var fileListModeRawValue: String = DiffFileListMode.list.rawValue
    /// Folder yang sengaja dilipat pengguna di mode "Tree" (kosong = semua
    /// expand, default-nya). Dikelola terpusat di sini, bukan `@State` per
    /// baris, karena baris Tree sekarang di-flatten jadi satu `ForEach` (lihat
    /// `flattenedTreeRows`) supaya indentasinya tidak ikut ditambah otomatis
    /// oleh indentasi hierarki bawaan `.listStyle(.sidebar)`.
    @State private var collapsedFolderIDs: Set<String> = []

    private var fileListMode: DiffFileListMode {
        DiffFileListMode(rawValue: fileListModeRawValue) ?? .list
    }

    private func orderedForNavigation(_ entries: [DiffFileEntry]) -> [DiffFileEntry] {
        fileListMode == .tree ? DiffFileTreePolicy.orderedEntries(from: entries) : entries
    }

    /// Fungsi biasa (bukan langsung `if/else` di `body`) karena `body` dibaca
    /// sebagai `@ViewBuilder` — `if/else` telanjang di sana ditransformasi
    /// jadi konstruksi View, bukan sekadar cabang nilai biasa.
    private func navigationOrder(
        visibleEntries: [DiffFileEntry],
        visibleStaged: [DiffFileEntry],
        visibleUnstaged: [DiffFileEntry],
        visibleUntracked: [DiffFileEntry],
        visibleIgnored: [DiffFileEntry]
    ) -> [DiffFileEntry] {
        if store.comparisonBaseBranch != nil && store.comparisonTargetBranch != nil {
            return orderedForNavigation(visibleEntries)
        } else if store.comparisonBranch != nil {
            return orderedForNavigation(visibleEntries)
        } else if fileListMode == .combinedList {
            return visibleEntries
        } else {
            return orderedForNavigation(visibleStaged)
                + orderedForNavigation(visibleUnstaged)
                + orderedForNavigation(visibleUntracked)
                + orderedForNavigation(visibleIgnored)
        }
    }

    var body: some View {
        let visibleEntries = store.visibleEntries
        let visibleStaged = visibleEntries.filter { $0.group == .staged }
        let visibleUnstaged = visibleEntries.filter { $0.group == .unstaged }
        let visibleUntracked = visibleEntries.filter { $0.group == .untracked }
        let visibleIgnored = visibleEntries.filter { $0.group == .ignored }
        // Mode "Tree" merender file dalam urutan traversal folder, bukan
        // urutan flat `visibleEntries` — navigasi keyboard ↑/↓ harus mengikuti
        // urutan yang benar-benar tampil, bukan urutan data mentahnya.
        let navOrder = navigationOrder(
            visibleEntries: visibleEntries,
            visibleStaged: visibleStaged,
            visibleUnstaged: visibleUnstaged,
            visibleUntracked: visibleUntracked,
            visibleIgnored: visibleIgnored
        )

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                comparisonControls

                if !store.isComparingBranches {
                    Toggle(isOn: $store.showRecentOnly) {
                        Label(L10n.Diff.tenMinutes, systemImage: "clock")
                    }
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
                    .help(L10n.Diff.recentFilterHelp)
                    .accessibilityLabel(L10n.Diff.tenMinutes)
                }

                Toggle(isOn: $store.hideLargeFiles) {
                    Label(L10n.Diff.hideLargeFiles, systemImage: "doc.badge.ellipsis")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .help(L10n.Diff.hideLargeFilesHelp)
                .accessibilityLabel(L10n.Diff.hideLargeFiles)

                fileListViewMenu
                Spacer(minLength: 0)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            List(selection: Binding(
                get: { store.selectedFileID },
                set: { newValue in
                    if let newValue, let entry = visibleEntries.first(where: { $0.id == newValue }) {
                        Task { @MainActor in
                            await Task.yield()
                            store.select(entry)
                        }
                    }
                }
            )) {
                if let baseBranch = store.comparisonBaseBranch, let targetBranch = store.comparisonTargetBranch {
                    fileListSection(title: L10n.format(L10n.Diff.comparedBranches, targetBranch, baseBranch), entries: visibleEntries)
                } else if let comparisonBranch = store.comparisonBranch {
                    fileListSection(title: L10n.format(L10n.Diff.comparedWithBranch, comparisonBranch), entries: visibleEntries)
                } else if fileListMode == .combinedList {
                    fileListSection(title: String(localized: L10n.Diff.allChanges), entries: visibleEntries)
                } else {
                    fileListSection(title: String(localized: DiffChangeGroup.staged.label), entries: visibleStaged)
                    fileListSection(title: String(localized: DiffChangeGroup.unstaged.label), entries: visibleUnstaged)
                    fileListSection(title: String(localized: DiffChangeGroup.untracked.label), entries: visibleUntracked)
                    fileListSection(title: String(localized: DiffChangeGroup.ignored.label), entries: visibleIgnored)
                }
            }
            .onChange(of: navOrder.map(\.id), initial: true) { _, ids in
                onVisibleEntriesChange(ids)
            }
            .listStyle(.sidebar)
            .focusable()
            .simultaneousGesture(TapGesture().onEnded { onRequestKeyboardFocus() })
            .overlay {
                if visibleEntries.isEmpty {
                    Text(emptyListMessage)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.accentColor.opacity(isKeyboardFocused ? 0.7 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }

            if isKeyboardFocused, !visibleEntries.isEmpty {
                Text(L10n.Diff.keyboardNavigationHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
            }
        }
        .sheet(isPresented: $showsBranchComparison) {
            BranchComparisonPickerView(store: store)
        }
    }

    @ViewBuilder
    private var comparisonControls: some View {
        Group {
            if let comparedBranch = store.comparisonBranch {
                HStack(spacing: 5) {
                    branchPickerButton(currentBranchName, color: .cyan, showsBranchIcon: true)
                    swapBranchesButton
                    branchPickerButton(comparedBranch, color: .orange)
                }
            } else if let baseBranch = store.comparisonBaseBranch,
                      let targetBranch = store.comparisonTargetBranch {
                // Dua branch dibandingkan langsung (dasar → target), bukan
                // "branch aktif" vs "branch pembanding" — apps-spec.md
                // mendokumentasikan keduanya memakai warna yang sama di sini,
                // beda dari pasangan warna asimetris di mode satu branch di atas.
                HStack(spacing: 5) {
                    branchPickerButton(baseBranch, color: .cyan, showsBranchIcon: true)
                    swapBranchesButton
                    branchPickerButton(targetBranch, color: .cyan)
                }
            } else {
                Button {
                    showsBranchPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(.secondary)
                        Text(L10n.Diff.localChanges)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.borderless)
                .help(L10n.Diff.compareBranchHelp)
                .accessibilityLabel(comparisonLabel)
            }
        }
        .popover(isPresented: $showsBranchPicker, arrowEdge: .bottom) {
            DiffBranchPickerPopover(store: store) {
                showsBranchPicker = false
                DispatchQueue.main.async {
                    showsBranchComparison = true
                }
            }
        }
    }

    private var swapBranchesButton: some View {
        Button {
            store.swapComparisonBranches()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(L10n.Diff.swapBranches)
        .accessibilityLabel(L10n.Diff.swapBranches)
        .disabled(!store.isComparingBranches && store.headerStatus?.branch == nil)
    }

    private func branchPickerButton(_ branch: String, color: Color, showsBranchIcon: Bool = false) -> some View {
        Button {
            showsBranchPicker = true
        } label: {
            HStack(spacing: 5) {
                if showsBranchIcon {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.secondary)
                }
                Text(branch)
                    .foregroundStyle(color)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .buttonStyle(.borderless)
        .help(L10n.Diff.compareBranchHelp)
        .accessibilityLabel(comparisonLabel)
    }

    private var comparisonLabel: String {
        if let baseBranch = store.comparisonBaseBranch, let targetBranch = store.comparisonTargetBranch {
            return L10n.format(L10n.Diff.branchComparisonLabel, baseBranch, targetBranch)
        }
        if let comparisonBranch = store.comparisonBranch {
            return L10n.format(L10n.Diff.comparedWithBranch, comparisonBranch)
        }
        return String(localized: L10n.Diff.localChanges)
    }

    private var currentBranchName: String {
        if let branch = store.headerStatus?.branch { return branch }
        if store.headerStatus?.isDetached == true {
            return String(localized: L10n.Repository.detachedHead)
        }
        return "—"
    }

    private var emptyListMessage: String {
        if store.isRefreshing || store.isLoadingComparison { return String(localized: L10n.Diff.loading) }
        if store.displayedEntries.isEmpty {
            let isComparison = store.comparisonBranch != nil || store.isComparingBranches
            return String(localized: isComparison ? L10n.Diff.noBranchDifferences : L10n.Diff.noChanges)
        }
        return String(localized: L10n.Diff.noFilesMatchFilter)
    }

    private var fileListViewMenu: some View {
        Menu {
            Picker(selection: Binding(
                get: { fileListMode },
                set: { fileListModeRawValue = $0.rawValue }
            )) {
                Text(L10n.Diff.viewAsTree).tag(DiffFileListMode.tree)
                Text(L10n.Diff.viewAsList).tag(DiffFileListMode.list)
                Text(L10n.Diff.viewAsCombinedList).tag(DiffFileListMode.combinedList)
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)

            Divider()

            Toggle(isOn: $store.hideUntrackedFiles) {
                Text(L10n.Diff.hideUntrackedFiles)
            }
            .help(L10n.Diff.hideUntrackedFilesHelp)

            Toggle(isOn: $store.showIgnoredFiles) {
                Text(L10n.Diff.showIgnoredFiles)
            }
            .help(L10n.Diff.showIgnoredFilesHelp)
        } label: {
            Image(systemName: "list.bullet.indent")
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24, height: 24)
        .help(L10n.Diff.fileListView)
        .accessibilityLabel(L10n.Diff.fileListView)
    }

    @ViewBuilder
    private func fileListSection(title: String, entries: [DiffFileEntry]) -> some View {
        if !entries.isEmpty {
            Section(title) {
                if fileListMode == .tree {
                    let rows = flattenedTreeRows(
                        DiffFileTreePolicy.tree(from: entries),
                        depth: 0,
                        collapsedFolderIDs: collapsedFolderIDs
                    )
                    ForEach(rows) { row in
                        DiffFileTreeRow(
                            row: row,
                            repoPath: store.repoPath,
                            fontSize: fontSize,
                            selectedFileID: store.selectedFileID,
                            onOpenFile: onOpenFile,
                            isCollapsed: collapsedFolderIDs.contains(row.id),
                            onToggleCollapse: { toggleFolderCollapse(row.id) }
                        )
                    }
                } else {
                    ForEach(entries) { entry in
                        DiffFileRow(
                            entry: entry,
                            repoPath: store.repoPath,
                            fontSize: fontSize,
                            isSelected: store.selectedFileID == entry.id
                        )
                        .tag(entry.id)
                        .onTapGesture(count: 2) {
                            let absolutePath = (store.repoPath as NSString).appendingPathComponent(entry.path)
                            onOpenFile(absolutePath)
                        }
                    }
                }
            }
        }
    }

    private func toggleFolderCollapse(_ id: String) {
        if collapsedFolderIDs.contains(id) {
            collapsedFolderIDs.remove(id)
        } else {
            collapsedFolderIDs.insert(id)
        }
    }

    /// Meratakan pohon jadi satu daftar baris urut tampilan (folder lalu
    /// anaknya, kecuali folder itu sedang dilipat), supaya baris Tree bisa
    /// dirender lewat satu `ForEach` biasa tanpa `DisclosureGroup` bersarang
    /// — itu caranya indentasi antar level cuma dari `leadingIndent` kita
    /// sendiri, bukan ditambah lagi oleh indentasi hierarki bawaan List.
    private func flattenedTreeRows(
        _ nodes: [DiffFileTreePolicy.Node],
        depth: Int,
        collapsedFolderIDs: Set<String>
    ) -> [DiffTreeDisplayRow] {
        nodes.flatMap { node -> [DiffTreeDisplayRow] in
            switch node.content {
            case .file(let entry):
                return [DiffTreeDisplayRow(id: node.id, depth: depth, kind: .file(entry))]
            case .folder:
                let header = DiffTreeDisplayRow(id: node.id, depth: depth, kind: .folder(name: node.name))
                guard !collapsedFolderIDs.contains(node.id) else { return [header] }
                return [header] + flattenedTreeRows(node.children, depth: depth + 1, collapsedFolderIDs: collapsedFolderIDs)
            }
        }
    }
}

/// Satu baris hasil `flattenedTreeRows`, dipakai sebagai item `ForEach` di
/// mode "Tree" — baik baris file maupun header folder.
private struct DiffTreeDisplayRow: Identifiable {
    enum Kind {
        case file(DiffFileEntry)
        case folder(name: String)
    }

    let id: String
    let depth: Int
    let kind: Kind
}

/// Satu baris di mode "Tree": folder sebagai header dengan chevron yang bisa
/// di-tap untuk dilipat/dibuka, file sebagai `DiffFileRow` biasa (tetap bisa
/// diseleksi/dibuka lewat double-click seperti mode List). Indentasi dihitung
/// manual lewat `leadingIndent(for:)`, bukan lewat nesting `DisclosureGroup`,
/// supaya tidak kena indentasi hierarki tambahan dari `.listStyle(.sidebar)`.
private struct DiffFileTreeRow: View {
    let row: DiffTreeDisplayRow
    let repoPath: String
    let fontSize: Int
    let selectedFileID: DiffFileEntry.ID?
    let onOpenFile: (String) -> Void
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void

    var body: some View {
        switch row.kind {
        case .file(let entry):
            DiffFileRow(
                entry: entry,
                repoPath: repoPath,
                fontSize: fontSize,
                isSelected: selectedFileID == entry.id
            )
            .tag(entry.id)
            .padding(.leading, Self.leadingIndent(for: row.depth))
            .listRowInsets(Self.rowInsets)
            .onTapGesture(count: 2) {
                let absolutePath = (repoPath as NSString).appendingPathComponent(entry.path)
                onOpenFile(absolutePath)
            }
        case .folder(let name):
            Button(action: onToggleCollapse) {
                HStack(spacing: 4) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: CGFloat(fontSize) - 3))
                        .foregroundStyle(.secondary)
                        .frame(width: 10, alignment: .center)
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(name).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: CGFloat(fontSize + 2)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, Self.leadingIndent(for: row.depth))
            .listRowInsets(Self.rowInsets)
        }
    }

    /// Insets baris yang lebih rapat dari bawaan `.listStyle(.sidebar)`,
    /// supaya jarak vertikal antar baris Tree (termasuk antar level
    /// folder/file) tidak terlalu renggang.
    private static let rowInsets = EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8)

    /// Dibatasi di kedalaman tertentu supaya folder yang sangat bersarang
    /// (meski sudah dipadatkan oleh `DiffFileTreePolicy`) tidak sampai
    /// menghabiskan seluruh lebar sidebar dan membuat nama file/badge
    /// `+N`/`-N` hilang — lihat `DiffFileRow`. Nilainya sengaja kecil karena
    /// ini satu-satunya sumber indentasi (tidak ada lagi indentasi hierarki
    /// bawaan List, lihat `flattenedTreeRows`).
    private static func leadingIndent(for depth: Int) -> CGFloat {
        CGFloat(min(depth, 6)) * 6
    }
}

private struct DiffBranchPickerPopover: View {
    @ObservedObject var store: RepoDiffStore
    let onCompareBranches: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredBranches: [String] {
        guard !searchText.isEmpty else { return store.availableComparisonBranches }
        return store.availableComparisonBranches.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.Common.searchBranches, text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help(L10n.Common.clearSearch)
                    .accessibilityLabel(L10n.Common.clearSearch)
                }
            }
            .padding(10)

            List {
                Button {
                    store.selectComparisonBranch(nil)
                    dismiss()
                } label: {
                    HStack {
                        Text(L10n.Diff.localChanges)
                        Spacer()
                        if store.comparisonBranch == nil && !store.isComparingBranches {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !filteredBranches.isEmpty {
                    Section {
                        ForEach(filteredBranches, id: \.self) { branch in
                            Button {
                                store.selectComparisonBranch(branch)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(branch)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    if store.comparisonBranch == branch {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(branch)
                        }
                    }
                } else if !searchText.isEmpty {
                    ContentUnavailableView(
                        String(localized: L10n.Common.noMatchingBranches),
                        systemImage: "magnifyingglass"
                    )
                }
            }
            .listStyle(.plain)

            Divider()
            Button {
                dismiss()
                onCompareBranches()
            } label: {
                Label(L10n.Diff.compareBranches, systemImage: "arrow.left.arrow.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .frame(width: 360, height: 420)
        .onAppear {
            searchText = ""
            store.refreshGitMetadata()
        }
    }
}

private struct DiffFileRow: View {
    let entry: DiffFileEntry
    let repoPath: String
    let fontSize: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.status.letter)
                .font(.system(size: CGFloat(fontSize), design: .monospaced))
                .foregroundStyle(statusColor)
                .frame(width: 14)

            Text(entry.displayName)
                .font(.system(size: CGFloat(fontSize + 2)))
                .lineLimit(1)
                .layoutPriority(1)
                .help(entry.path)

            Spacer()

            if let additions = entry.additions, additions > 0 {
                Text("+\(additions)")
                    .font(.system(size: CGFloat(fontSize - 1), design: .monospaced))
                    .foregroundStyle(.green)
            }
            if let deletions = entry.deletions, deletions > 0 {
                Text("-\(deletions)")
                    .font(.system(size: CGFloat(fontSize - 1), design: .monospaced))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.22))
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(L10n.Diff.copyPath) {
                NSPasteboard.copyString((repoPath as NSString).appendingPathComponent(entry.path))
            }
            Button(L10n.Diff.copyCommand) {
                NSPasteboard.copyString(GitDiffService.toggleStageCommand(for: entry))
            }
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .added: return .green
        case .deleted: return .red
        case .modified: return .yellow
        case .renamed, .copied: return .blue
        case .untracked: return .secondary
        case .unmerged: return .orange
        case .typeChanged: return .purple
        case .ignored: return .secondary
        }
    }
}

// MARK: - Isi diff

private struct DiffContentView: View {
    @ObservedObject var store: RepoDiffStore
    @Binding var selectedHunkID: DiffHunk.ID?
    let fontSize: Int
    @State private var columnCountCache = DiffColumnCountCache()
    @State private var wordDiffCache = WordDiffHighlightCache()
    var onToggleFocus: () -> Void
    var showsFocusToggle: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let diff = store.selectedDiff {
                if diff.isBinary {
                    Text(L10n.Diff.noBinaryPreview)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if diff.hunks.isEmpty {
                    Text(L10n.Diff.noChangesToDisplay)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    hunkScrollView(diff: diff)
                }
            } else if store.isLoadingComparison {
                ProgressView(String(localized: L10n.Diff.loading))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(L10n.Diff.selectFile)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .focusable()
        .onChange(of: store.selectedDiff?.entry.id) { _, _ in
            selectedHunkID = store.selectedDiff?.hunks.first?.id
        }
    }

    private var toolbar: some View {
        HStack {
            Text(store.selectedDiff?.entry.path ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if let diff = store.selectedDiff {
                Button {
                    NSPasteboard.copyString((store.repoPath as NSString).appendingPathComponent(diff.entry.path))
                } label: {
                    Label(L10n.Diff.copyPath, systemImage: "doc.on.clipboard")
                }
                .labelStyle(.iconOnly)
                .help(L10n.Diff.copyPath)
                .accessibilityLabel(L10n.Diff.copyPath)

                Button {
                    NSPasteboard.copyString(GitDiffService.toggleStageCommand(for: diff.entry))
                } label: {
                    Label(L10n.Diff.copyCommand, systemImage: "terminal")
                }
                .labelStyle(.iconOnly)
                .help(L10n.Diff.copyCommand)
                .accessibilityLabel(L10n.Diff.copyCommand)

                Button {
                    NSPasteboard.copyString(diff.rawText)
                } label: {
                    Label(L10n.Common.copyDiff, systemImage: "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .help(L10n.Common.copyDiff)
                .accessibilityLabel(L10n.Common.copyDiff)
                .disabled(diff.rawText.isEmpty)
            }

            if showsFocusToggle {
                Button {
                    onToggleFocus()
                } label: {
                    Image(systemName: store.isFocusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .help(store.isFocusMode ? L10n.Diff.restoreFileList : L10n.Diff.focus)
                .accessibilityLabel(store.isFocusMode ? L10n.Diff.restoreFileList : L10n.Diff.focus)
            }

            Menu {
                Button(L10n.Diff.increaseTextSize) {
                    GridlinePreferences.adjustDiffFontSize(by: 1)
                }
                .disabled(fontSize >= GridlinePreferences.maximumDiffFontSize)

                Button(L10n.Diff.decreaseTextSize) {
                    GridlinePreferences.adjustDiffFontSize(by: -1)
                }
                .disabled(fontSize <= GridlinePreferences.minimumDiffFontSize)

                Divider()

                Button(L10n.Diff.resetTextSize) {
                    GridlinePreferences.resetDiffFontSize()
                }
                .disabled(fontSize == GridlinePreferences.defaultDiffFontSize)
            } label: {
                Image(systemName: "textformat.size")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help(L10n.Diff.textSize)
            .accessibilityLabel(L10n.Diff.textSize)
        }
        .padding(6)
    }

    private func hunkScrollView(diff: FileDiff) -> some View {
        GeometryReader { geometry in
            let layout = DiffFontMetrics.layout(
                maximumColumns: columnCountCache.count(for: diff),
                fontSize: fontSize,
                viewportWidth: geometry.size.width
            )
            let wordDiffHighlights = wordDiffCache.highlights(for: diff)
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diff.hunks) { hunk in
                            DiffHunkView(hunk: hunk, layout: layout, wordDiffHighlights: wordDiffHighlights)
                                .id(hunk.id)
                                .background(hunk.id == selectedHunkID ? Color.accentColor.opacity(0.08) : Color.clear)
                        }
                    }
                    .frame(width: layout.contentWidth, alignment: .leading)
                }
                .onAppear {
                    selectedHunkID = diff.hunks.first?.id
                }
                .onChange(of: selectedHunkID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newValue, anchor: .topLeading)
                    }
                }
            }
        }
    }
}

private struct DiffHunkView: View {
    let hunk: DiffHunk
    let layout: DiffTextLayout
    let wordDiffHighlights: [DiffLine.ID: [Range<Int>]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
                .font(.system(size: CGFloat(layout.fontSize), design: .monospaced))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(width: layout.contentWidth, alignment: .leading)
                .background(Color.secondary.opacity(0.1))

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(hunk.lines) { line in
                    DiffLineView(line: line, layout: layout, highlightRanges: wordDiffHighlights[line.id] ?? [])
                }
            }
        }
    }
}

private struct DiffLineView: View {
    let line: DiffLine
    let layout: DiffTextLayout
    let highlightRanges: [Range<Int>]

    var body: some View {
        HStack(spacing: 0) {
            Text(line.oldLineNumber.map(String.init) ?? "")
                .frame(width: DiffFontMetrics.gutterWidth(for: layout.fontSize), alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: DiffFontMetrics.gutterWidth(for: layout.fontSize), alignment: .trailing)
                .foregroundStyle(.secondary)
            highlightedLineText(line.text, ranges: highlightRanges, highlightColor: wordHighlightColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, 6)
        }
        .font(.system(size: CGFloat(layout.fontSize), design: .monospaced))
        .frame(width: layout.contentWidth, alignment: .leading)
        .padding(.vertical, 1)
        .background(backgroundColor)
    }

    private var backgroundColor: Color {
        switch line.kind {
        case .addition: return Color.green.opacity(0.15)
        case .deletion: return Color.red.opacity(0.15)
        case .context: return Color.clear
        }
    }

    private var wordHighlightColor: Color {
        switch line.kind {
        case .addition: return Color.green.opacity(0.35)
        case .deletion: return Color.red.opacity(0.35)
        case .context: return Color.clear
        }
    }
}

