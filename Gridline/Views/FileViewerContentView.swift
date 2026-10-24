//
//  FileViewerContentView.swift
//  Gridline
//
//  Isi tab viewer: teks dengan nomor baris, gambar, PDF, atau pesan error
//  sesuai batas ukuran (bagian 7 apps-spec.md). Tombol "Salin Path" dan
//  "Buka di Finder" selalu tersedia di toolbar.
//

import AppKit
import SwiftUI

struct FileViewerContentView: View {
    @ObservedObject var tab: FileViewerTab

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            contentView
        }
    }

    private var toolbar: some View {
        HStack {
            Text(tab.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer()

            Button(L10n.Common.copyPath) {
                NSPasteboard.copyString(tab.path)
            }
            Button(L10n.Common.openInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tab.path)])
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .padding(6)
    }

    @ViewBuilder
    private var contentView: some View {
        switch tab.content {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .text(let text):
            ReadOnlyTextView(text: text, scrollToLine: tab.pendingScrollLine) {
                tab.pendingScrollLine = nil
            }

        case .image(let image):
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            }

        case .pdf(let url):
            PDFKitView(url: url)

        case .tooLarge(let size, let isMedia):
            MessageView(
                systemImage: "doc.text.magnifyingglass",
                title: String(localized: L10n.Viewer.tooLargeTitle),
                message: L10n.format(
                    L10n.Viewer.tooLargeMessage,
                    ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                    String(localized: isMedia ? L10n.Viewer.mediaLimit : L10n.Viewer.textLimit)
                ),
                actionTitle: String(localized: L10n.Common.openInFinder),
                action: openInFinder
            )

        case .unsupportedBinary:
            MessageView(
                systemImage: "doc.questionmark",
                title: String(localized: L10n.Viewer.unsupportedTitle),
                message: String(localized: L10n.Viewer.unsupportedMessage),
                actionTitle: String(localized: L10n.Common.openInFinder),
                action: openInFinder
            )

        case .notFound:
            MessageView(
                systemImage: "questionmark.folder",
                title: String(localized: L10n.Viewer.notFoundTitle),
                message: tab.path,
                actionTitle: nil,
                action: nil
            )

        case .error(let message):
            MessageView(
                systemImage: "exclamationmark.triangle",
                title: String(localized: L10n.Viewer.openFailedTitle),
                message: message,
                actionTitle: nil,
                action: nil
            )
        }
    }

    private func openInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tab.path)])
    }
}

private struct MessageView: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
