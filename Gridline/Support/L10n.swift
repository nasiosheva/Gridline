import Foundation

/// Stable localization keys. User-facing copy lives in Localizable.xcstrings.
/// The system language selects Indonesian or English for the app.
enum L10n {
    static func format(_ resource: LocalizedStringResource, _ arguments: CVarArg...) -> String {
        String(format: String(localized: resource), locale: .current, arguments: arguments)
    }

    enum Common {
        static let ok: LocalizedStringResource = "common.ok"
        static let cancel: LocalizedStringResource = "common.cancel"
        static let close: LocalizedStringResource = "common.close"
        static let clearSearch: LocalizedStringResource = "common.clear_search"
        static let done: LocalizedStringResource = "common.done"
        static let searchBranches: LocalizedStringResource = "common.search_branches"
        static let noMatchingBranches: LocalizedStringResource = "common.no_matching_branches"
        static let openRepository: LocalizedStringResource = "common.open_repository"
        static let copyPath: LocalizedStringResource = "common.copy_path"
        static let copyDiff: LocalizedStringResource = "common.copy_diff"
        static let openInFinder: LocalizedStringResource = "common.open_in_finder"
    }

    enum Menu {
        static let quit: LocalizedStringResource = "menu.quit"
        static let findInViewer: LocalizedStringResource = "menu.find_in_viewer"
        static let clearTerminal: LocalizedStringResource = "menu.clear_terminal"
        static let repository: LocalizedStringResource = "menu.repository"
        static let openRepository: LocalizedStringResource = "menu.open_repository"
        static let searchRepositoryOrFile: LocalizedStringResource = "menu.search_repository_or_file"
        static let manageRepositories: LocalizedStringResource = "menu.manage_repositories"
        static let closeActiveRepository: LocalizedStringResource = "menu.close_active_repository"
        static let closeAllRepositories: LocalizedStringResource = "menu.close_all_repositories"
        static let pane: LocalizedStringResource = "menu.pane"
        static let addPane: LocalizedStringResource = "menu.add_pane"
        static let focusPane: LocalizedStringResource = "menu.focus_pane"
        static let focusLeft: LocalizedStringResource = "menu.focus_left"
        static let focusRight: LocalizedStringResource = "menu.focus_right"
        static let focusUp: LocalizedStringResource = "menu.focus_up"
        static let focusDown: LocalizedStringResource = "menu.focus_down"
        static let maximizePane: LocalizedStringResource = "menu.maximize_pane"
        static let maximizeTerminal: LocalizedStringResource = "menu.maximize_terminal"
        static let focusDiff: LocalizedStringResource = "menu.focus_diff"
        static let help: LocalizedStringResource = "menu.help"
        static let exportLog: LocalizedStringResource = "menu.export_log"
        static let keyboardShortcuts: LocalizedStringResource = "menu.keyboard_shortcuts"
    }

    enum Repository {
        static let openTitle: LocalizedStringResource = "repository.open_title"
        static let openPrompt: LocalizedStringResource = "repository.open_prompt"
        static let invalidRepositoryMessage: LocalizedStringResource = "repository.invalid_message"
        static let closeAction: LocalizedStringResource = "repository.close_action"
        static let identityColor: LocalizedStringResource = "repository.identity_color"
        static let workStatusHelp: LocalizedStringResource = "repository.work_status_help"
        static let workStatusIdle: LocalizedStringResource = "repository.work_status_idle"
        static let workStatusRunning: LocalizedStringResource = "repository.work_status_running"
        static let workStatusAttention: LocalizedStringResource = "repository.work_status_attention"
        static let attentionCompleted: LocalizedStringResource = "repository.attention_completed"
        static let attentionFailed: LocalizedStringResource = "repository.attention_failed"
        static let detachedHead: LocalizedStringResource = "repository.detached_head"
        static let ahead: LocalizedStringResource = "repository.ahead"
        static let behind: LocalizedStringResource = "repository.behind"
        static let pullAction: LocalizedStringResource = "repository.pull_action"
        static let pullHelp: LocalizedStringResource = "repository.pull_help"
        static let pullConfirmationTitle: LocalizedStringResource = "repository.pull_confirmation_title"
        static let pullConfirmationMessage: LocalizedStringResource = "repository.pull_confirmation_message"
        static let pullInProgress: LocalizedStringResource = "repository.pull_in_progress"
        static let pullSucceededTitle: LocalizedStringResource = "repository.pull_succeeded_title"
        static let pullSucceededMessage: LocalizedStringResource = "repository.pull_succeeded_message"
        static let pullFailedTitle: LocalizedStringResource = "repository.pull_failed_title"
        static let pullFailedMessage: LocalizedStringResource = "repository.pull_failed_message"
        static let pullSkippedTitle: LocalizedStringResource = "repository.pull_skipped_title"
        static let pullSkippedMessage: LocalizedStringResource = "repository.pull_skipped_message"
        static let gitUnavailable: LocalizedStringResource = "repository.git_unavailable"
        static let chooseFolderAgain: LocalizedStringResource = "repository.choose_folder_again"
        static let worktreeDisplayName: LocalizedStringResource = "repository.worktree_display_name"
    }

    enum Pane {
        static let actions: LocalizedStringResource = "pane.actions"
        static let openInTerminal: LocalizedStringResource = "pane.open_in_terminal"
        static let selectRepository: LocalizedStringResource = "pane.select_repository"
        static let close: LocalizedStringResource = "pane.close"
        static let accessibilityLabel: LocalizedStringResource = "pane.accessibility_label"
        static let emptyMessage: LocalizedStringResource = "pane.empty_message"
        static let maximize: LocalizedStringResource = "pane.maximize"
        static let restoreGrid: LocalizedStringResource = "pane.restore_grid"
        static let terminalOnly: LocalizedStringResource = "pane.terminal_only"
        static let showTopArea: LocalizedStringResource = "pane.show_top_area"
        static let attentionCount: LocalizedStringResource = "pane.attention_count"
    }

    enum Layout {
        static let menuLabel: LocalizedStringResource = "layout.menu_label"
        static let menuHelp: LocalizedStringResource = "layout.menu_help"
        static let onePaneOption: LocalizedStringResource = "layout.one_pane_option"
        static let manyPanesOption: LocalizedStringResource = "layout.many_panes_option"
        static let hideWithActiveTerminalCommandsTitle: LocalizedStringResource = "layout.hide_with_active_terminal_commands_title"
        static let hideWithActiveTerminalCommandsMessage: LocalizedStringResource = "layout.hide_with_active_terminal_commands_message"
        static let changeLayout: LocalizedStringResource = "layout.change_layout"

        static func paneCountOption(_ count: Int) -> String {
            count == 1
                ? String(localized: onePaneOption)
                : L10n.format(manyPanesOption, Int64(count))
        }
    }

    enum Terminal {
        static let newTab: LocalizedStringResource = "terminal.new_tab"
        static let tabNamePlaceholder: LocalizedStringResource = "terminal.tab_name_placeholder"
        static let closeTab: LocalizedStringResource = "terminal.close_tab"
        static let closeRunningTabTitle: LocalizedStringResource = "terminal.close_running_tab_title"
        static let closeRunningTabMessage: LocalizedStringResource = "terminal.close_running_tab_message"
        static let openTabs: LocalizedStringResource = "terminal.open_tabs"
        static let decreaseTextSize: LocalizedStringResource = "terminal.decrease_text_size"
        static let increaseTextSize: LocalizedStringResource = "terminal.increase_text_size"
        static let finishedNotification: LocalizedStringResource = "terminal.finished_notification"
        static let failedNotification: LocalizedStringResource = "terminal.failed_notification"
    }

    enum QuickSwitcher {
        static let searchPlaceholder: LocalizedStringResource = "quick_switcher.search_placeholder"
        static let repositories: LocalizedStringResource = "quick_switcher.repositories"
        static let openFiles: LocalizedStringResource = "quick_switcher.open_files"
    }

    nonisolated enum Viewer {
        static let tooLargeTitle: LocalizedStringResource = "viewer.too_large_title"
        static let tooLargeMessage: LocalizedStringResource = "viewer.too_large_message"
        static let mediaLimit: LocalizedStringResource = "viewer.media_limit"
        static let textLimit: LocalizedStringResource = "viewer.text_limit"
        static let unsupportedTitle: LocalizedStringResource = "viewer.unsupported_title"
        static let unsupportedMessage: LocalizedStringResource = "viewer.unsupported_message"
        static let notFoundTitle: LocalizedStringResource = "viewer.not_found_title"
        static let openFailedTitle: LocalizedStringResource = "viewer.open_failed_title"
        static let readAttributesFailed: LocalizedStringResource = "viewer.read_attributes_failed"
        static let imageLoadFailed: LocalizedStringResource = "viewer.image_load_failed"
        static let readContentsFailed: LocalizedStringResource = "viewer.read_contents_failed"
    }

    enum Diff {
        static let localChanges: LocalizedStringResource = "diff.local_changes"
        static let compareBranchHelp: LocalizedStringResource = "diff.compare_branch_help"
        static let compareBranches: LocalizedStringResource = "diff.compare_branches"
        static let branchComparisonExplanation: LocalizedStringResource = "diff.branch_comparison_explanation"
        static let branchComparisonLabel: LocalizedStringResource = "diff.branch_comparison_label"
        static let baseBranch: LocalizedStringResource = "diff.base_branch"
        static let targetBranch: LocalizedStringResource = "diff.target_branch"
        static let swapBranches: LocalizedStringResource = "diff.swap_branches"
        static let applyBranchComparison: LocalizedStringResource = "diff.apply_branch_comparison"
        static let notEnoughBranches: LocalizedStringResource = "diff.not_enough_branches"
        static let recentFilterHelp: LocalizedStringResource = "diff.recent_filter_help"
        static let hideLargeFiles: LocalizedStringResource = "diff.hide_large_files"
        static let hideLargeFilesHelp: LocalizedStringResource = "diff.hide_large_files_help"
        static let comparedWithBranch: LocalizedStringResource = "diff.compared_with_branch"
        static let comparedBranches: LocalizedStringResource = "diff.compared_branches"
        static let loading: LocalizedStringResource = "diff.loading"
        static let noChanges: LocalizedStringResource = "diff.no_changes"
        static let noBranchDifferences: LocalizedStringResource = "diff.no_branch_differences"
        static let noFilesMatchFilter: LocalizedStringResource = "diff.no_files_match_filter"
        static let staged: LocalizedStringResource = "diff.staged"
        static let unstaged: LocalizedStringResource = "diff.unstaged"
        static let untracked: LocalizedStringResource = "diff.untracked"
        static let ignored: LocalizedStringResource = "diff.ignored"
        static let allChanges: LocalizedStringResource = "diff.all_changes"
        static let fileListView: LocalizedStringResource = "diff.file_list_view"
        static let viewAsTree: LocalizedStringResource = "diff.view_as_tree"
        static let viewAsList: LocalizedStringResource = "diff.view_as_list"
        static let viewAsCombinedList: LocalizedStringResource = "diff.view_as_combined_list"
        static let hideUntrackedFiles: LocalizedStringResource = "diff.hide_untracked_files"
        static let hideUntrackedFilesHelp: LocalizedStringResource = "diff.hide_untracked_files_help"
        static let showIgnoredFiles: LocalizedStringResource = "diff.show_ignored_files"
        static let showIgnoredFilesHelp: LocalizedStringResource = "diff.show_ignored_files_help"
        static let selectFile: LocalizedStringResource = "diff.select_file"
        static let keyboardNavigationHint: LocalizedStringResource = "diff.keyboard_navigation_hint"
        static let focus: LocalizedStringResource = "diff.focus"
        static let restoreFileList: LocalizedStringResource = "diff.restore_file_list"
        static let textSize: LocalizedStringResource = "diff.text_size"
        static let increaseTextSize: LocalizedStringResource = "diff.increase_text_size"
        static let decreaseTextSize: LocalizedStringResource = "diff.decrease_text_size"
        static let resetTextSize: LocalizedStringResource = "diff.reset_text_size"
        static let gitNotFound: LocalizedStringResource = "diff.git_not_found"
        static let installCommandLineTools: LocalizedStringResource = "diff.install_command_line_tools"
        static let tenMinutes: LocalizedStringResource = "diff.ten_minutes"
        static let noBinaryPreview: LocalizedStringResource = "diff.no_binary_preview"
        static let noChangesToDisplay: LocalizedStringResource = "diff.no_changes_to_display"
        static let copyPath: LocalizedStringResource = "diff.copy_path"
        static let copyCommand: LocalizedStringResource = "diff.copy_command"
    }

    enum Worktree {
        static let openBranchInNewPane: LocalizedStringResource = "worktree.open_branch_in_new_pane"
        static let title: LocalizedStringResource = "worktree.title"
        static let alertTitle: LocalizedStringResource = "worktree.alert_title"
        static let loadingBranches: LocalizedStringResource = "worktree.loading_branches"
        static let openingBranch: LocalizedStringResource = "worktree.opening_branch"
        static let noOtherBranches: LocalizedStringResource = "worktree.no_other_branches"
        static let loadFailed: LocalizedStringResource = "worktree.load_failed"
        static let operationFailed: LocalizedStringResource = "worktree.operation_failed"
        static let paneUnavailable: LocalizedStringResource = "worktree.pane_unavailable"
        static let pathAlreadyExists: LocalizedStringResource = "worktree.path_already_exists"
        static let chooseBranchAgain: LocalizedStringResource = "worktree.choose_branch_again"
    }

    enum TopArea {
        static let diffTab: LocalizedStringResource = "top_area.diff_tab"
        static let openTabs: LocalizedStringResource = "top_area.open_tabs"
        static let searchOpenTabs: LocalizedStringResource = "top_area.search_open_tabs"
        static let closeOtherTabs: LocalizedStringResource = "top_area.close_other_tabs"
        static let showViewerAsTab: LocalizedStringResource = "top_area.show_viewer_as_tab"
        static let showViewerBesideDiff: LocalizedStringResource = "top_area.show_viewer_beside_diff"
    }

    enum Toast {
        static let repositoryClosed: LocalizedStringResource = "toast.repository_closed"
        static let reopen: LocalizedStringResource = "toast.reopen"
        static let repositoryClosedAccessibility: LocalizedStringResource = "toast.repository_closed_accessibility"
    }

    enum Settings {
        static let terminal: LocalizedStringResource = "settings.terminal"
        static let scrollbackLimit: LocalizedStringResource = "settings.scrollback_limit"
        static let diagnostics: LocalizedStringResource = "settings.diagnostics"
        static let diagnosticsInfo: LocalizedStringResource = "settings.diagnostics_info"
        static let scrollbackChangeInfo: LocalizedStringResource = "settings.scrollback_change_info"
    }

    enum Picker {
        static let ambiguousFilesTitle: LocalizedStringResource = "picker.ambiguous_files_title"
    }

    enum Shortcut {
        static let helpTitle: LocalizedStringResource = "shortcut.help_title"
        static let openRepository: LocalizedStringResource = "shortcut.open_repository"
        static let searchRepositoryOrFile: LocalizedStringResource = "shortcut.search_repository_or_file"
        static let openTerminalTab: LocalizedStringResource = "shortcut.open_terminal_tab"
        static let closeActiveTab: LocalizedStringResource = "shortcut.close_active_tab"
        static let closeRepository: LocalizedStringResource = "shortcut.close_repository"
        static let focusPane: LocalizedStringResource = "shortcut.focus_pane"
        static let focusNearestPane: LocalizedStringResource = "shortcut.focus_nearest_pane"
        static let maximizePane: LocalizedStringResource = "shortcut.maximize_pane"
        static let maximizeTerminal: LocalizedStringResource = "shortcut.maximize_terminal"
        static let findInViewer: LocalizedStringResource = "shortcut.find_in_viewer"
        static let clearTerminal: LocalizedStringResource = "shortcut.clear_terminal"
        static let quit: LocalizedStringResource = "shortcut.quit"
    }

    enum Notification {
    }

    enum Diagnostics {
        static let exportFailedTitle: LocalizedStringResource = "diagnostics.export_failed_title"
        static let reportTitle: LocalizedStringResource = "diagnostics.report_title"
        static let generated: LocalizedStringResource = "diagnostics.generated"
        static let appVersion: LocalizedStringResource = "diagnostics.app_version"
        static let macOSVersion: LocalizedStringResource = "diagnostics.macos_version"
        static let gitVersion: LocalizedStringResource = "diagnostics.git_version"
        static let events: LocalizedStringResource = "diagnostics.events"
        static let unknown: LocalizedStringResource = "diagnostics.unknown"
    }

    enum Workspace {
        static let closeRepositoryTitle: LocalizedStringResource = "workspace.close_repository_title"
        static let repositoryClosedMessage: LocalizedStringResource = "workspace.repository_closed_message"
        static let batchCloseTitle: LocalizedStringResource = "workspace.batch_close_title"
        static let batchCloseMessage: LocalizedStringResource = "workspace.batch_close_message"
        static let stopAndCloseRepository: LocalizedStringResource = "workspace.stop_and_close_repository"
        static let keepRepositoryOpen: LocalizedStringResource = "workspace.keep_repository_open"
        static let quitTitle: LocalizedStringResource = "workspace.quit_title"
        static let quitMessage: LocalizedStringResource = "workspace.quit_message"
        static let cannotOpenRepository: LocalizedStringResource = "workspace.cannot_open_repository"
        static let folderPermissionTitle: LocalizedStringResource = "workspace.folder_permission_title"
        static let openSystemSettings: LocalizedStringResource = "workspace.open_system_settings"
        static let folderPermissionMessage: LocalizedStringResource = "workspace.folder_permission_message"
        static let minimumWindowSize: LocalizedStringResource = "workspace.minimum_window_size"
        static let emptyPaneTitle: LocalizedStringResource = "workspace.empty_pane_title"
        static let recentRepositories: LocalizedStringResource = "workspace.recent_repositories"
        static let clearRecentRepositories: LocalizedStringResource = "workspace.clear_recent_repositories"
        static let noRecentRepositories: LocalizedStringResource = "workspace.no_recent_repositories"
        static let repositoryManagerTitle: LocalizedStringResource = "workspace.repository_manager_title"
        static let searchSavedRepositories: LocalizedStringResource = "workspace.search_saved_repositories"
        static let clearUnavailableRepositories: LocalizedStringResource = "workspace.clear_unavailable_repositories"
        static let noSavedRepositories: LocalizedStringResource = "workspace.no_saved_repositories"
        static let removeSavedRepositoryTitle: LocalizedStringResource = "workspace.remove_saved_repository_title"
        static let removeSavedRepositoryMessage: LocalizedStringResource = "workspace.remove_saved_repository_message"
        static let clearUnavailableRepositoriesTitle: LocalizedStringResource = "workspace.clear_unavailable_repositories_title"
        static let clearUnavailableRepositoriesMessage: LocalizedStringResource = "workspace.clear_unavailable_repositories_message"
        static let removeFromGridline: LocalizedStringResource = "workspace.remove_from_gridline"
        static let unavailableRepository: LocalizedStringResource = "workspace.unavailable_repository"
        static let actionsMenu: LocalizedStringResource = "workspace.actions_menu"
        static let showSingleRepository: LocalizedStringResource = "workspace.show_single_repository"
        static let chooseRepositoryForActivePane: LocalizedStringResource = "workspace.choose_repository_for_active_pane"
        static let openRepository: LocalizedStringResource = "workspace.open_repository"
        static let missingRepository: LocalizedStringResource = "workspace.missing_repository"
        static let openedOutsideRepository: LocalizedStringResource = "workspace.opened_outside_repository"
        static let fileNotFound: LocalizedStringResource = "workspace.file_not_found"
    }
}
