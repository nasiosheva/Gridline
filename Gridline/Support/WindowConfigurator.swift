//
//  WindowConfigurator.swift
//  Gridline
//
//  Menyimpan dan memulihkan ukuran/posisi jendela utama lewat mekanisme
//  autosave NSWindow bawaan (bagian 4 & 12 apps-spec.md).
//

import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let autosaveName: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.setFrameAutosaveName(autosaveName)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
