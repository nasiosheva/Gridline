//
//  LineNumberRulerView.swift
//  Gridline
//
//  Gutter nomor baris untuk viewer file read-only (bagian 7 apps-spec.md).
//  Indeks awal setiap baris dihitung sekali per perubahan teks (bukan per
//  frame saat scroll) supaya tetap responsif untuk file sampai 5 MB.
//

import AppKit

final class LineNumberRulerView: NSRulerView {
    private weak var codeTextView: NSTextView?
    private var lineStartOffsets: [Int] = [0]

    init(textView: NSTextView) {
        self.codeTextView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func rebuildLineIndex(text: String) {
        var offsets: [Int] = [0]
        let nsString = text as NSString
        var searchStart = 0
        while searchStart < nsString.length {
            let range = nsString.range(of: "\n", range: NSRange(location: searchStart, length: nsString.length - searchStart))
            guard range.location != NSNotFound else { break }
            offsets.append(range.location + 1)
            searchStart = range.location + 1
        }
        lineStartOffsets = offsets
        needsDisplay = true
    }

    private func lineNumber(forCharacterIndex index: Int) -> Int {
        var low = 0
        var high = lineStartOffsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStartOffsets[mid] <= index {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = codeTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = textView.enclosingScrollView else { return }

        let visibleRect = scrollView.contentView.bounds
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] _, _, _, glyphRangeForLine, _ in
            guard let self else { return }
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphRangeForLine.location)
            let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRangeForLine, in: textContainer)
            let y = lineRect.minY + textView.textContainerInset.height - visibleRect.minY
            let number = self.lineNumber(forCharacterIndex: charIndex)
            let numberString = "\(number)" as NSString
            let size = numberString.size(withAttributes: attributes)
            numberString.draw(
                at: NSPoint(x: self.ruleThickness - size.width - 6, y: y + (lineRect.height - size.height) / 2),
                withAttributes: attributes
            )
        }
    }
}
