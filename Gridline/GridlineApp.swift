//
//  GridlineApp.swift
//  Gridline
//
//  Created by Mories Hutapea on 22/10/26.
//

import AppKit
import SwiftUI

@main
struct GridlineApp: App {
    @NSApplicationDelegateAdaptor(GridlineAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppStateStore()
    @StateObject private var sessionStore = RepoSessionStore()
    @StateObject private var diffStoreRegistry = RepoDiffStoreRegistry()
    @StateObject private var topAreaStoreRegistry = TopAreaStoreRegistry()

    init() {
        DiagnosticLog.shared.record(.appLaunched)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(sessionStore)
                .environmentObject(diffStoreRegistry)
                .environmentObject(topAreaStoreRegistry)
                .task {
                    appDelegate.sessionStore = sessionStore
                }
        }
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button(L10n.Menu.quit) {
                    NotificationCenter.default.post(name: .gridlineRequestQuit, object: nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button(L10n.Menu.findInViewer) {
                    let sender = NSMenuItem()
                    sender.tag = NSTextFinder.Action.showFindInterface.rawValue
                    NSApp.sendAction(Selector(("performFindPanelAction:")), to: nil, from: sender)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button(L10n.Menu.clearTerminal) {
                    NotificationCenter.default.post(name: .gridlineClearTerminal, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
            CommandMenu(L10n.Menu.repository) {
                Button(L10n.Menu.openRepository) {
                    NotificationCenter.default.post(name: .gridlineOpenRepo, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button(L10n.Menu.searchRepositoryOrFile) {
                    NotificationCenter.default.post(name: .gridlineQuickSwitcher, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)

                Button(L10n.Menu.manageRepositories) {
                    NotificationCenter.default.post(name: .gridlineManageRepositories, object: nil)
                }

                Divider()

                Button(L10n.Menu.closeActiveRepository) {
                    NotificationCenter.default.post(name: .gridlineCloseActiveRepo, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])

                Divider()

                Button(L10n.Menu.closeAllRepositories) {
                    NotificationCenter.default.post(name: .gridlineCloseAllRepositories, object: nil)
                }
                .disabled(!appState.state.paneLayout.slots.contains(where: { $0.repoID != nil }))
            }
            CommandMenu(L10n.Menu.pane) {
                Button(L10n.Menu.addPane) {
                    appState.addPane()
                }
                .disabled(!appState.canAddPane)

                Divider()

                ForEach(0..<min(appState.state.paneLayout.displayPaneCount, 4), id: \.self) { index in
                    Button(L10n.format(L10n.Menu.focusPane, Int64(index + 1))) {
                        appState.focusPane(at: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }

                Divider()

                Button(L10n.Menu.focusLeft) {
                    appState.focusPane(.left)
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

                Button(L10n.Menu.focusRight) {
                    appState.focusPane(.right)
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])

                Button(L10n.Menu.focusUp) {
                    appState.focusPane(.up)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])

                Button(L10n.Menu.focusDown) {
                    appState.focusPane(.down)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

                Divider()

                Button(L10n.Menu.maximizePane) {
                    appState.toggleMaximizedActivePane()
                }
                .keyboardShortcut("m", modifiers: [.control, .command])

                Button(L10n.Menu.maximizeTerminal) {
                    appState.toggleTerminalOnlyActivePane()
                }
                .keyboardShortcut("m", modifiers: [.option, .command])

                Button(L10n.Menu.focusDiff) {
                    NotificationCenter.default.post(name: .gridlineToggleDiffFocus, object: nil)
                }
            }
            CommandMenu(L10n.Menu.help) {
                Button(L10n.Menu.exportLog) {
                    NotificationCenter.default.post(name: .gridlineExportDiagnostics, object: nil)
                }

                Divider()

                Button(L10n.Menu.keyboardShortcuts) {
                    NotificationCenter.default.post(name: .gridlineShortcutHelp, object: nil)
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }
        Settings {
            GridlineSettingsView()
        }
    }
}

@MainActor
final class GridlineAppDelegate: NSObject, NSApplicationDelegate {
    weak var sessionStore: RepoSessionStore?

    func applicationWillTerminate(_ notification: Notification) {
        sessionStore?.terminateAllProcesses()
    }
}

extension Notification.Name {
    static let gridlineOpenRepo = Notification.Name("gridlineOpenRepo")
    static let gridlineCloseActiveRepo = Notification.Name("gridlineCloseActiveRepo")
    static let gridlineCloseAllRepositories = Notification.Name("gridlineCloseAllRepositories")
    static let gridlineManageRepositories = Notification.Name("gridlineManageRepositories")
    static let gridlineRequestQuit = Notification.Name("gridlineRequestQuit")
    static let gridlineQuickSwitcher = Notification.Name("gridlineQuickSwitcher")
    static let gridlineShortcutHelp = Notification.Name("gridlineShortcutHelp")
    static let gridlineClearTerminal = Notification.Name("gridlineClearTerminal")
    static let gridlineToggleDiffFocus = Notification.Name("gridlineToggleDiffFocus")
    static let gridlineExportDiagnostics = Notification.Name("gridlineExportDiagnostics")
}
