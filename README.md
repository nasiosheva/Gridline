# Gridline

Gridline is a native macOS workspace for reviewing and working across several Git repositories in one window. Each pane combines a repository diff, a read-only file viewer, and a multi-tab terminal.

> Gridline is a work in progress and is currently intended for personal use.

## Features

- Keep repository panes in the workspace while switching between a single-pane view and larger grids. Previously displayed pane views and terminal sessions stay alive while hidden, until the pane is explicitly closed.
- Choose which saved repositories appear in visible panes; selecting a repository already assigned to another pane moves that pane into view without closing either repository.
- Review staged, unstaged, and untracked changes, or compare the working tree with a local branch.
- Compare two local branches and open another branch beside the current repository in a separate Git worktree.
- Search branches while choosing a comparison or worktree; restore a missing worktree by choosing a branch from its source repository.
- Keep each repository's last diff branch comparison when reopening the app.
- Update the displayed branch after a Git checkout while the app stays open.
- Prefer panes with an open repository when reducing the layout, while keeping the active repository when possible.
- Show repositories in a scrollable multi-row grid; pane view choices grow with the repositories saved in Gridline.
- Close a pane directly with its top-right X button while keeping its repository terminal session available.
- Confirm before a smaller layout hides repositories with active terminal commands; idle zsh prompts do not trigger confirmation.
- Close repositories from every pane in sequence; each pane with active terminal commands gets its own stop-or-keep confirmation.
- Open files in a read-only viewer, including paths selected from terminal output with Command-click.
- Run independent shell sessions in terminal tabs. ANSI 16/256-color and truecolor output are supported.
- Switch between repositories and open files with the quick switcher.
- Keep repository layout and recent repository shortcuts between launches.
- Manage saved repositories, remove individual entries, and clear unavailable paths without deleting repository folders or worktrees.
- Use the interface in Indonesian or English, following the macOS language preference.

Gridline pauses file and diff watchers for panes that are not visible while keeping terminal sessions alive. Large diffs and file lists load incrementally to keep scrolling responsive.

Gridline's Git status and diff views are read-only. Actions such as staging changes are copied as commands for the user to run in the terminal.

## Requirements

- macOS 26 or later
- Apple silicon (arm64)
- Xcode with the Swift toolchain

## Build

Open `Gridline.xcodeproj` in Xcode, select the **Gridline** scheme and **My Mac** destination, then choose **Product → Build**.

Or build from Terminal:

```sh
xcodebuild \
  -project Gridline.xcodeproj \
  -scheme Gridline \
  -configuration Debug \
  -skipPackagePluginValidation \
  build
```

The first Xcode build may ask you to trust the SwiftTerm package build plugin. The command-line flag above skips that validation prompt.

## Data and permissions

Gridline stores repository paths and workspace layout in:

```text
~/Library/Application Support/Gridline/state.json
```

App Sandbox is disabled so Gridline can launch the user's shell and run read-only Git commands in selected folders. Terminal commands are entered and controlled by the user.

## Languages

Gridline's interface currently supports Indonesian and English. The app follows the preferred language configured in macOS.
