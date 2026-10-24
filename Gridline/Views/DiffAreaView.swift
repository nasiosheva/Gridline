//
//  DiffAreaView.swift
//  Gridline
//
//  Panel diff: daftar file (staged/unstaged/untracked) di kiri, isi diff di
//  kanan. ↑/↓ memilih file, ⌥↑/⌥↓ pindah hunk, mode split/unified bisa
//  dipilih (bagian 6 apps-spec.md).
//

import AppKit
import SwiftUI

enum DiffViewMode: String {
    case split
    case unified
}

struct DiffAreaView: View {
    @ObservedObject var store: RepoDiffStore
    /// Dipanggil saat pengguna double-click file di daftar untuk membukanya
    /// di viewer. Entry point sementara sebelum Cmd+klik (M2 langkah 7) ada.
    var onOpenFile: (String) -> Void = { _ in }
    var showsFileList = true
    @AppStorage("gridline.diffViewMode") private var modeRawValue: String = DiffViewMode.split.rawValue

    private var mode: DiffViewMode {
        DiffViewMode(rawValue: modeRawValue) ?? .split
    }

    var body: some View {
        Group {
            if !store.isGitAvailable {
                GitUnavailableView()
            } else if store.isFocusMode || !showsFileList {
                DiffContentView(
                    store: store,
                    mode: mode,
                    onToggleMode: { modeRawValue = $0.rawValue },
                    onToggleFocus: { store.isFocusMode = false },
                    showsFocusToggle: showsFileList
                )
            } else {
                HSplitView {
                    DiffFileListView(store: store, onOpenFile: onOpenFile)
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
                    DiffContentView(
                        store: store,
                        mode: mode,
                        onToggleMode: { modeRawValue = $0.rawValue },
                        onToggleFocus: { store.isFocusMode = true },
                        showsFocusToggle: showsFileList
                    )
                    .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
                }
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
    let onOpenFile: (String) -> Void
    @State private var showRecentOnly = false
    @State private var hideLargeFiles = false
    @State private var showsBranchComparison = false
    @State private var showsBranchPicker = false

    private var filteredEntries: [DiffFileEntry] {
        store.displayedEntries.filter { entry in
            (!showRecentOnly || store.isComparingBranches || DiffVisibilityPolicy.isRecent(entry))
                && (!hideLargeFiles || !DiffVisibilityPolicy.isLarge(entry))
        }
    }

    var body: some View {
        let visibleEntries = filteredEntries
        let visibleStaged = visibleEntries.filter { $0.group == .staged }
        let visibleUnstaged = visibleEntries.filter { $0.group == .unstaged }
        let visibleUntracked = visibleEntries.filter { $0.group == .untracked }

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    showsBranchPicker = true
                } label: {
                    Label(comparisonLabel, systemImage: "arrow.triangle.branch")
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)
                .help(L10n.Diff.compareBranchHelp)
                .popover(isPresented: $showsBranchPicker, arrowEdge: .bottom) {
                    DiffBranchPickerPopover(store: store) {
                        showsBranchPicker = false
                        DispatchQueue.main.async {
                            showsBranchComparison = true
                        }
                    }
                }

                if !store.isComparingBranches {
                    Toggle(L10n.Diff.tenMinutes, isOn: $showRecentOnly)
                        .toggleStyle(.button)
                        .help(L10n.Diff.recentFilterHelp)
                }
                Toggle(L10n.Diff.hideLargeFiles, isOn: $hideLargeFiles)
                    .toggleStyle(.button)
                    .help(L10n.Diff.hideLargeFilesHelp)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)

            List(selection: Binding(
                get: { store.selectedFileID },
                set: { newValue in
                    if let newValue, let entry = visibleEntries.first(where: { $0.id == newValue }) {
                        store.select(entry)
                    }
                }
            )) {
                if let baseBranch = store.comparisonBaseBranch, let targetBranch = store.comparisonTargetBranch {
                    section(title: L10n.format(L10n.Diff.comparedBranches, targetBranch, baseBranch), entries: visibleEntries)
                } else if let comparisonBranch = store.comparisonBranch {
                    section(title: L10n.format(L10n.Diff.comparedWithBranch, comparisonBranch), entries: visibleEntries)
                } else {
                    section(title: String(localized: DiffChangeGroup.staged.label), entries: visibleStaged)
                    section(title: String(localized: DiffChangeGroup.unstaged.label), entries: visibleUnstaged)
                    section(title: String(localized: DiffChangeGroup.untracked.label), entries: visibleUntracked)
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if visibleEntries.isEmpty {
                    Text(emptyListMessage)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
        }
        .sheet(isPresented: $showsBranchComparison) {
            BranchComparisonPickerView(store: store)
        }
    }

    private var comparisonLabel: String {
        if let baseBranch = store.comparisonBaseBranch, let targetBranch = store.comparisonTargetBranch {
            return L10n.format(L10n.Diff.branchComparisonLabel, baseBranch, targetBranch)
        }
        return store.comparisonBranch ?? String(localized: L10n.Diff.localChanges)
    }

    private var emptyListMessage: String {
        if store.isRefreshing { return String(localized: L10n.Diff.loading) }
        if store.displayedEntries.isEmpty {
            let isComparison = store.comparisonBranch != nil || store.isComparingBranches
            return String(localized: isComparison ? L10n.Diff.noBranchDifferences : L10n.Diff.noChanges)
        }
        return String(localized: L10n.Diff.noFilesMatchFilter)
    }

    @ViewBuilder
    private func section(title: String, entries: [DiffFileEntry]) -> some View {
        if !entries.isEmpty {
            Section(title) {
                ForEach(entries) { entry in
                    DiffFileRow(entry: entry, repoPath: store.repoPath)
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
        .onAppear { searchText = "" }
    }
}

private struct DiffFileRow: View {
    let entry: DiffFileEntry
    let repoPath: String

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.status.letter)
                .font(.caption.monospaced())
                .foregroundStyle(statusColor)
                .frame(width: 14)

            Text(entry.displayName)
                .lineLimit(1)
                .help(entry.path)

            Spacer()

            if let additions = entry.additions, additions > 0 {
                Text("+\(additions)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.green)
            }
            if let deletions = entry.deletions, deletions > 0 {
                Text("-\(deletions)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.red)
            }
        }
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
        }
    }
}

// MARK: - Isi diff

private struct DiffContentView: View {
    @ObservedObject var store: RepoDiffStore
    let mode: DiffViewMode
    var onToggleMode: (DiffViewMode) -> Void
    var onToggleFocus: () -> Void
    var showsFocusToggle: Bool

    @State private var selectedHunkID: DiffHunk.ID?

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
            } else {
                Text(L10n.Diff.selectFile)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .focusable()
        .onKeyPress(.upArrow, phases: .down) { press in
            if press.modifiers.contains(.option) {
                moveHunk(offset: -1)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.downArrow, phases: .down) { press in
            if press.modifiers.contains(.option) {
                moveHunk(offset: 1)
                return .handled
            }
            return .ignored
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
                Button(L10n.Diff.copyPath) {
                    NSPasteboard.copyString((store.repoPath as NSString).appendingPathComponent(diff.entry.path))
                }
                Button(L10n.Diff.copyCommand) {
                    NSPasteboard.copyString(GitDiffService.toggleStageCommand(for: diff.entry))
                }
                Button(L10n.Common.copyDiff) {
                    NSPasteboard.copyString(diff.rawText)
                }
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

            Picker(L10n.Diff.mode, selection: Binding(get: { mode }, set: { onToggleMode($0 == mode ? mode : $0) })) {
                Text(L10n.Diff.splitMode).tag(DiffViewMode.split)
                Text(L10n.Diff.unifiedMode).tag(DiffViewMode.unified)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .labelsHidden()
        }
        .padding(6)
    }

    private func hunkScrollView(diff: FileDiff) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(diff.hunks) { hunk in
                        DiffHunkView(hunk: hunk, mode: mode)
                            .id(hunk.id)
                            .background(hunk.id == selectedHunkID ? Color.accentColor.opacity(0.08) : Color.clear)
                    }
                }
            }
            .onAppear {
                selectedHunkID = diff.hunks.first?.id
            }
            .onChange(of: selectedHunkID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(newValue, anchor: .top)
                }
            }
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
}

private struct DiffHunkView: View {
    let hunk: DiffHunk
    let mode: DiffViewMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))

            switch mode {
            case .unified:
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(hunk.lines) { line in
                        UnifiedDiffLineView(line: line)
                    }
                }
            case .split:
                SplitDiffLinesView(lines: hunk.lines)
            }
        }
    }
}

private struct UnifiedDiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            Text(line.oldLineNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(line.text.isEmpty ? " " : line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
        }
        .font(.system(size: 11, design: .monospaced))
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
}

/// Mode split: baris lama dan baru digabung per pasangan sederhana —
/// konteks tampil di kedua kolom, tambah/hapus berurutan ditampilkan sejajar
/// bila jumlahnya sama, selain itu ditumpuk berurutan di kolom masing-masing.
private struct SplitDiffLinesView: View {
    let lines: [DiffLine]

    var body: some View {
        let rows = Self.pairRows(from: lines)
        LazyVStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                SplitDiffRow(left: rows[index].0, right: rows[index].1)
            }
        }
    }

    private static func pairRows(from lines: [DiffLine]) -> [(DiffLine?, DiffLine?)] {
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

private struct SplitDiffRow: View {
    let left: DiffLine?
    let right: DiffLine?

    var body: some View {
        HStack(spacing: 0) {
            lineColumn(left)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            lineColumn(right)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11, design: .monospaced))
    }

    @ViewBuilder
    private func lineColumn(_ line: DiffLine?) -> some View {
        HStack(spacing: 0) {
            Text(line?.oldLineNumber.map(String.init) ?? (line?.newLineNumber.map(String.init) ?? ""))
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(.secondary)
            Text(line?.text ?? "")
                .padding(.leading, 6)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor(for: line))
    }

    private func backgroundColor(for line: DiffLine?) -> Color {
        guard let line else { return .clear }
        switch line.kind {
        case .addition: return Color.green.opacity(0.15)
        case .deletion: return Color.red.opacity(0.15)
        case .context: return .clear
        }
    }
}
