//
//  TerminalTab.swift
//  Gridline
//
//  Satu tab terminal = satu shell di pseudo-terminal (SwiftTerm). Instance
//  `LocalProcessTerminalView` dibuat sekali di sini dan disimpan selama tab
//  ini ada, bukan dibuat ulang oleh SwiftUI — ini yang membuat proses tetap
//  hidup walau tampilannya disembunyikan/dipindah (D6).
//

import AppKit
import Combine
import SwiftTerm

final class TerminalTab: Identifiable, ObservableObject {
    let id = UUID()
    let workingDirectory: String
    let terminalView: GridlineTerminalView

    @Published var customTitle: String?
    @Published private(set) var shellTitle: String
    @Published private(set) var isRunning = false
    @Published private(set) var attention: RepoAttentionStatus?
    /// cwd tab ini, diperbarui lewat OSC 7 kalau shell-nya zsh (lihat
    /// `ShellIntegration`). Default ke `workingDirectory` selama belum ada
    /// laporan OSC 7 (misalnya shell bukan zsh) — fallback sesuai bagian 9
    /// apps-spec.md.
    @Published private(set) var currentDirectory: String

    /// Dipanggil dengan hasil resolusi Cmd+klik sebuah path di terminal ini
    /// (bagian 9 apps-spec.md). Diatur oleh `RepoSession` lewat
    /// `openFileHandler`, bukan di sini, supaya tab tidak perlu tahu soal
    /// `TopAreaStore`.
    var onOpenPath: ((TerminalLinkTarget) -> Void)?
    var onProcessTerminated: ((Int32?) -> Void)?

    private let delegateProxy: LocalProcessDelegateProxy
    private let shellName: String
    private let commandStateFileURL: URL
    private var scrollbackPreferenceObserver: NSObjectProtocol?
    private var hasStartedProcess = false
    private var hasRecordedTermination = false

    var title: String {
        customTitle ?? shellTitle
    }

    var hasActiveCommand: Bool {
        guard isRunning else { return false }
        guard shellName == "zsh" else { return true }
        guard let data = try? Data(contentsOf: commandStateFileURL),
              let state = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return true
        }
        return state != "idle"
    }

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
        self.currentDirectory = workingDirectory
        let view = GridlineTerminalView(frame: .zero)
        self.terminalView = view
        TerminalAppearance.apply(to: view)

        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shellPath as NSString).lastPathComponent
        self.shellName = shellName
        self.shellTitle = shellName
        let commandStateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Gridline-command-state-\(id.uuidString)")
        self.commandStateFileURL = commandStateURL
        FileManager.default.createFile(
            atPath: commandStateURL.path,
            contents: Data("idle\n".utf8),
            attributes: [.posixPermissions: 0o600]
        )

        let proxy = LocalProcessDelegateProxy()
        self.delegateProxy = proxy
        view.processDelegate = proxy
        view.changeScrollback(GridlinePreferences.scrollbackLimit())
        scrollbackPreferenceObserver = NotificationCenter.default.addObserver(
            forName: GridlinePreferences.scrollbackLimitChanged,
            object: nil,
            queue: .main
        ) { [weak view] notification in
            guard let limit = notification.userInfo?[GridlinePreferences.scrollbackLimitUserInfoKey] as? Int else { return }
            view?.changeScrollback(limit)
        }

        proxy.onTitleChange = { [weak self] title in
            self?.shellTitle = title
        }
        proxy.onTerminated = { [weak self] exitCode in
            self?.recordTermination(exitCode)
        }
        proxy.onDirectoryChange = { [weak self] directory in
            self?.currentDirectory = directory
        }

        view.onOpenLink = { [weak self] raw in
            guard let self else { return }
            let cwd = self.currentDirectory
            let repoPath = self.workingDirectory
            Task.detached(priority: .userInitiated) {
                let target = TerminalLinkResolver.resolve(raw: raw, cwd: cwd, repoPath: repoPath)
                await MainActor.run {
                    self.onOpenPath?(target)
                }
            }
        }

    }

    /// Start only after RepoSession installs lifecycle callbacks. A process
    /// that exits immediately must not outrun its owner and disappear without
    /// updating session state.
    func startProcess() {
        guard !hasStartedProcess else { return }
        hasStartedProcess = true

        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let environmentOverrides = ShellIntegration.environmentOverrides(
            forShellNamed: shellName,
            commandStatePath: commandStateFileURL.path
        )
        let environment = environmentOverrides.isEmpty
            ? nil
            : Terminal.getEnvironmentVariables(termName: "xterm-256color") + environmentOverrides
        terminalView.startProcess(
            executable: shellPath,
            args: ["-l"],
            environment: environment,
            execName: shellName,
            currentDirectory: workingDirectory
        )

        guard terminalView.process.running else {
            recordStartFailure()
            return
        }
        isRunning = true
    }

    private func recordStartFailure() {
        guard !hasRecordedTermination else { return }
        hasRecordedTermination = true
        isRunning = false
        attention = .failed
        DiagnosticLog.shared.record(.terminalStartFailed)
        onProcessTerminated?(nil)
    }

    private func recordTermination(_ exitCode: Int32?) {
        guard !hasRecordedTermination else { return }
        hasRecordedTermination = true
        isRunning = false
        attention = exitCode == 0 ? .completed : .failed
        DiagnosticLog.shared.record(.terminalExited(exitCode))
        onProcessTerminated?(exitCode)
    }

    func rename(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        customTitle = trimmed.isEmpty ? nil : trimmed
    }

    func terminate() {
        onProcessTerminated = nil
        terminalView.terminate()
    }

    func clearTerminal() {
        terminalView.clearScrollback()
        // Program layar penuh belum tentu menggambar ulang setelah Ctrl+L.
        guard !terminalView.terminal.isCurrentBufferAlternate else { return }
        terminalView.send(txt: "\u{000C}")
    }

    deinit {
        if let scrollbackPreferenceObserver {
            NotificationCenter.default.removeObserver(scrollbackPreferenceObserver)
        }
        try? FileManager.default.removeItem(at: commandStateFileURL)
    }

}

/// `processDelegate` perlu objek terpisah (bukan `TerminalTab` langsung) karena
/// protokol SwiftTerm mensyaratkan `AnyObject` yang hidup lepas dari closure yang menangkapnya.
private final class LocalProcessDelegateProxy: NSObject, LocalProcessTerminalViewDelegate {
    var onTitleChange: ((String) -> Void)?
    var onTerminated: ((Int32?) -> Void)?
    var onDirectoryChange: ((String) -> Void)?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        onTitleChange?(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, let path = ShellIntegration.parseOSC7(directory) else { return }
        onDirectoryChange?(path)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        onTerminated?(exitCode)
    }
}
