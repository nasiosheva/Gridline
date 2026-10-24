//
//  TerminalAppearance.swift
//  Gridline
//
//  Palet terminal gelap yang konsisten dengan contoh Codex. ANSI 16 warna
//  dipasang lewat SwiftTerm; warna 256/truecolor dari program terminal tetap
//  didukung oleh engine.
//

import AppKit
import SwiftTerm

enum TerminalAppearance {
    private static let foreground = NSColor(srgbRed: 0.88, green: 0.89, blue: 0.92, alpha: 1)
    private static let background = NSColor.black

    private static let ansiPalette: [SwiftTerm.Color] = [
        color(0x000000), // black
        color(0xf7768e), // red
        color(0x9ece6a), // green
        color(0xe0af68), // yellow
        color(0x7aa2f7), // blue
        color(0xbb9af7), // magenta
        color(0x7dcfff), // cyan
        color(0xd9dce5), // white
        color(0x5c6178), // bright black
        color(0xff899d), // bright red
        color(0xb9f27c), // bright green
        color(0xffca7a), // bright yellow
        color(0x89b4fa), // bright blue
        color(0xd5a5ff), // bright magenta
        color(0xa4e4ff), // bright cyan
        color(0xffffff), // bright white
    ]

    static func apply(to terminalView: GridlineTerminalView) {
        terminalView.nativeForegroundColor = foreground
        terminalView.nativeBackgroundColor = background
        terminalView.caretColor = foreground
        terminalView.installColors(ansiPalette)
    }

    private static func color(_ hex: UInt32) -> SwiftTerm.Color {
        SwiftTerm.Color(
            red8: UInt16((hex >> 16) & 0xff),
            green8: UInt16((hex >> 8) & 0xff),
            blue8: UInt16(hex & 0xff)
        )
    }
}
