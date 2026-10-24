import SwiftUI

struct OpenTabsView: View {
    @ObservedObject var store: TopAreaStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchIsFocused: Bool
    @State private var query = ""

    private var selectedFileID: UUID? {
        guard case .file(let id) = store.selection else { return nil }
        return id
    }

    private var filteredTabs: [FileViewerTab] {
        guard !query.isEmpty else { return store.openFiles }
        return store.openFiles.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.path.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(L10n.TopArea.searchOpenTabs, text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchIsFocused)
                .padding(12)

            List {
                ForEach(filteredTabs) { tab in
                    Button {
                        store.selection = .file(tab.id)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tab.displayName)
                                    .lineLimit(1)
                                Text(tab.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            if selectedFileID == tab.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if filteredTabs.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .listStyle(.inset)

            HStack {
                Button(L10n.TopArea.closeOtherTabs, systemImage: "xmark.circle") {
                    guard let selectedFileID else { return }
                    store.closeOtherFiles(keeping: selectedFileID)
                    dismiss()
                }
                .disabled(selectedFileID == nil || store.openFiles.count < 2)

                Spacer()

                Button(L10n.Common.done) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 480)
        .onAppear { searchIsFocused = true }
    }
}
