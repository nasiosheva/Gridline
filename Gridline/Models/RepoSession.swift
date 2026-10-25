//
//  RepoSession.swift
//  Gridline
//
//  Sesi runtime satu repo: daftar tab terminal dan tab aktif. Tidak Codable
//  dengan sengaja — sesi berisi proses hidup, bukan data yang dipersist
//  (bagian 12 apps-spec.md: konten terminal tidak disimpan).
//

import Combine
import Foundation

enum RepoAttentionStatus: Equatable {
    case completed
    case failed

    var accessibilityLabel: String {
        switch self {
        case .completed: String(localized: L10n.Repository.attentionCompleted)
        case .failed: String(localized: L10n.Repository.attentionFailed)
        }
    }

    static func forExitCode(_ exitCode: Int32?) -> Self {
        exitCode == 0 ? .completed : .failed
    }
}

enum RepoWorkStatus: Equatable {
    case idle
    case running(Int)
    case needsAttention

    var title: String {
        switch self {
        case .idle: String(localized: L10n.Repository.workStatusIdle)
        case .running(let count): L10n.format(L10n.Repository.workStatusRunning, Int64(count))
        case .needsAttention: String(localized: L10n.Repository.workStatusAttention)
        }
    }

    var systemImage: String {
        switch self {
        case .idle: "circle"
        case .running: "terminal"
        case .needsAttention: "exclamationmark.circle.fill"
        }
    }
}

@MainActor
final class RepoSession: ObservableObject {
    let repoPath: String
    private let terminalEndedNotifier: (String, String, Int32?) async -> Void

    @Published private(set) var tabs: [TerminalTab] = []
    @Published var activeTabID: UUID?
    @Published private(set) var attention: RepoAttentionStatus?

    var runningProcessCount: Int {
        tabs.filter(\.isRunning).count
    }

    var activeCommandCount: Int {
        tabs.filter(\.hasActiveCommand).count
    }

    var workStatus: RepoWorkStatus {
        Self.workStatus(attention: attention, runningProcessCount: runningProcessCount)
    }

    static func workStatus(attention: RepoAttentionStatus?, runningProcessCount: Int) -> RepoWorkStatus {
        if attention == .failed { return .needsAttention }
        if runningProcessCount > 0 { return .running(runningProcessCount) }
        return .idle
    }

    /// Diatur oleh `RepoPaneView` untuk membuka hasil Cmd+klik dari terminal
    /// manapun di repo ini lewat `TopAreaStore` (bagian 9 apps-spec.md).
    /// Diteruskan ke setiap tab, lama maupun baru.
    var openFileHandler: ((TerminalLinkTarget) -> Void)? {
        didSet { tabs.forEach { $0.onOpenPath = openFileHandler } }
    }

    init(
        repoPath: String,
        terminalEndedNotifier: @escaping (String, String, Int32?) async -> Void = { repoName, tabName, exitCode in
            await LocalNotificationService.notifyTerminalEnded(
                repoName: repoName,
                tabName: tabName,
                exitCode: exitCode
            )
        }
    ) {
        self.repoPath = repoPath
        self.terminalEndedNotifier = terminalEndedNotifier
        addTab()
    }

    @discardableResult
    func addTab() -> TerminalTab {
        let tab = TerminalTab(workingDirectory: repoPath)
        tab.onOpenPath = openFileHandler
        tab.onProcessTerminated = { [weak self, weak tab] exitCode in
            guard let self, let tab else { return }
            self.recordAttention(exitCode: exitCode)
            Task {
                await self.terminalEndedNotifier(
                    URL(fileURLWithPath: self.repoPath).lastPathComponent,
                    tab.title,
                    exitCode
                )
            }
        }
        tabs.append(tab)
        activeTabID = tab.id
        tab.startProcess()
        return tab
    }

    /// Menutup tab dan menghentikan prosesnya. Jika ini tab terakhir, shell
    /// baru otomatis dibuka di folder repo (bagian 8 apps-spec.md).
    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: index)
        tab.terminate()

        if tabs.isEmpty {
            addTab()
        } else if activeTabID == id {
            let newIndex = min(index, tabs.count - 1)
            activeTabID = tabs[newIndex].id
        }
    }

    func clearAttention() {
        attention = nil
    }

    private func recordAttention(exitCode: Int32?) {
        attention = RepoAttentionStatus.forExitCode(exitCode)
    }
}
