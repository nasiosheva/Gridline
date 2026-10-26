//
//  QuickSwitcherView.swift
//  Gridline
//

import SwiftUI

struct QuickSwitcherFile: Identifiable, Hashable {
    let repoID: UUID
    let repoName: String
    let path: String

    var id: String { "\(repoID.uuidString):\(path)" }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

enum QuickSwitcherSearchPolicy {
    static func filteredRepos(_ repos: [Repo], query: String) -> [Repo] {
        guard !query.isEmpty else { return repos }
        return repos.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.path.localizedCaseInsensitiveContains(query)
        }
    }

    static func filteredFiles(_ files: [QuickSwitcherFile], query: String) -> [QuickSwitcherFile] {
        guard !query.isEmpty else { return files }
        return files.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.path.localizedCaseInsensitiveContains(query)
                || $0.repoName.localizedCaseInsensitiveContains(query)
        }
    }
}

struct QuickSwitcherView: View {
    let repos: [Repo]
    let files: [QuickSwitcherFile]
    var onSelectRepo: (Repo) -> Void
    var onSelectFile: (QuickSwitcherFile) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchIsFocused: Bool
    @State private var query = ""

    private var filteredRepos: [Repo] {
        QuickSwitcherSearchPolicy.filteredRepos(repos, query: query)
    }

    private var filteredFiles: [QuickSwitcherFile] {
        QuickSwitcherSearchPolicy.filteredFiles(files, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(L10n.QuickSwitcher.searchPlaceholder, text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchIsFocused)
                .padding(12)

            List {
                if !filteredRepos.isEmpty {
                    Section(L10n.QuickSwitcher.repositories) {
                        ForEach(filteredRepos) { repo in
                            Button {
                                onSelectRepo(repo)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label {
                                        Text(repo.name)
                                    } icon: {
                                        Circle()
                                            .fill(RepoIdentityColor.color(for: repo))
                                            .frame(width: 8, height: 8)
                                    }
                                    Text(repo.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !filteredFiles.isEmpty {
                    Section(L10n.QuickSwitcher.openFiles) {
                        ForEach(filteredFiles) { file in
                            Button {
                                onSelectFile(file)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(file.name, systemImage: "doc.text")
                                    Text("\(file.repoName) · \(file.path)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if filteredRepos.isEmpty && filteredFiles.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 560, height: 480)
        .onAppear { searchIsFocused = true }
    }
}
