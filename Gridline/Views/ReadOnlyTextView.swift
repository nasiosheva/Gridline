//
//  ReadOnlyTextView.swift
//  Gridline
//
//  Pembungkus NSTextView read-only dengan nomor baris untuk viewer file
//  (bagian 7 apps-spec.md). Word wrap dimatikan (satu baris sumber = satu
//  baris tampilan) supaya gutter nomor baris tetap sederhana dan akurat.
//  Pencarian ⌘F memakai find bar bawaan AppKit (`usesFindBar`), dan
//  scroll-ke-baris memakai `showFindIndicator` untuk efek "sorot sebentar".
//

import AppKit
import SwiftUI

struct ReadOnlyTextView: NSViewRepresentable {
    let text: String
    var scrollToLine: Int?
    var onDidConsumeScrollRequest: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder

        let ruler = LineNumberRulerView(textView: textView)
        ruler.rebuildLineIndex(text: text)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.lastText = text

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if context.coordinator.lastText != text {
            textView.string = text
            context.coordinator.ruler?.rebuildLineIndex(text: text)
            context.coordinator.lastText = text
        }

        if let line = scrollToLine {
            scrollAndHighlight(line: line, in: textView)
            DispatchQueue.main.async {
                onDidConsumeScrollRequest()
            }
        }

        context.coordinator.ruler?.needsDisplay = true
    }

    private func scrollAndHighlight(line: Int, in textView: NSTextView) {
        let nsString = textView.string as NSString
        guard nsString.length > 0 else { return }

        var currentLine = 1
        var targetLocation = 0
        nsString.enumerateSubstrings(in: NSRange(location: 0, length: nsString.length), options: .byLines) { _, range, _, stop in
            if currentLine == line {
                targetLocation = range.location
                stop.pointee = true
            }
            currentLine += 1
        }

        let lineRange = nsString.lineRange(for: NSRange(location: targetLocation, length: 0))
        textView.scrollRangeToVisible(lineRange)
        textView.showFindIndicator(for: lineRange)
    }

    final class Coordinator {
        var textView: NSTextView?
        var ruler: LineNumberRulerView?
        var lastText: String = ""
    }
}
