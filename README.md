# Gridline

Gridline is a native macOS workspace for reviewing and working across several Git repositories in one window. Each pane combines a repository diff, a read-only file viewer, and a multi-tab terminal.

> Gridline is a work in progress and is currently intended for personal use.

## Features

- Arrange up to four repositories in a resizable pane grid.
- Review staged, unstaged, and untracked changes, or compare the working tree with a local branch.
- Open files in a read-only viewer, including paths selected from terminal output with Command-click.
- Run independent shell sessions in terminal tabs. ANSI 16/256-color and truecolor output are supported.
- Switch between repositories and open files with the quick switcher.
- Keep repository layout and recent repository shortcuts between launches.
- Use the interface in Indonesian or English, following the macOS language preference.

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
