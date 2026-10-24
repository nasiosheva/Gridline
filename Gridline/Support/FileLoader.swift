//
//  FileLoader.swift
//  Gridline
//
//  Memuat isi file untuk viewer read-only, dengan batas ukuran dari bagian 7
//  apps-spec.md: teks sampai 5 MB, gambar/PDF sampai 20 MB. File di luar itu
//  atau jenis biner lain tidak dibuka sebagai teks. File fingerprint dan
//  indeks awal baris ikut dihitung di worker saat load berlangsung.
//

import AppKit
import Foundation

enum FileContent {
    case loading
    case text(String)
    case image(NSImage)
    case pdf(URL)
    case tooLarge(sizeBytes: Int64, isMedia: Bool)
    case unsupportedBinary
    case notFound
    case error(String)
}

struct FileFingerprint: Equatable {
    let sizeBytes: Int64
    let modificationDate: Date?
    let fileNumber: UInt64?
}

struct FileLoadResult {
    let id = UUID()
    let content: FileContent
    let fingerprint: FileFingerprint?
    let lineStartOffsets: [UInt32]
}

enum FileLoader {
    static let maxTextBytes: Int64 = 5 * 1024 * 1024
    static let maxMediaBytes: Int64 = 20 * 1024 * 1024

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "webp"
    ]

    static func fingerprint(path: String) -> FileFingerprint? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let attributes = try? fm.attributesOfItem(atPath: path) else { return nil }
        return makeFingerprint(from: attributes)
    }

    static func load(path: String) -> FileLoadResult {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return FileLoadResult(content: .notFound, fingerprint: nil, lineStartOffsets: [0])
        }
        guard let attributes = try? fm.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int64 else {
            return FileLoadResult(
                content: .error(String(localized: L10n.Viewer.readAttributesFailed)),
                fingerprint: nil,
                lineStartOffsets: [0]
            )
        }
        let fingerprint = makeFingerprint(from: attributes)

        let ext = (path as NSString).pathExtension.lowercased()

        if imageExtensions.contains(ext) {
            guard size <= maxMediaBytes else {
                return FileLoadResult(content: .tooLarge(sizeBytes: size, isMedia: true), fingerprint: fingerprint, lineStartOffsets: [0])
            }
            guard let image = NSImage(contentsOfFile: path) else {
                return FileLoadResult(content: .error(String(localized: L10n.Viewer.imageLoadFailed)), fingerprint: fingerprint, lineStartOffsets: [0])
            }
            return FileLoadResult(content: .image(image), fingerprint: fingerprint, lineStartOffsets: [0])
        }

        if ext == "pdf" {
            guard size <= maxMediaBytes else {
                return FileLoadResult(content: .tooLarge(sizeBytes: size, isMedia: true), fingerprint: fingerprint, lineStartOffsets: [0])
            }
            return FileLoadResult(content: .pdf(URL(fileURLWithPath: path)), fingerprint: fingerprint, lineStartOffsets: [0])
        }

        guard size <= maxTextBytes else {
            return FileLoadResult(content: .tooLarge(sizeBytes: size, isMedia: false), fingerprint: fingerprint, lineStartOffsets: [0])
        }
        guard let data = fm.contents(atPath: path) else {
            return FileLoadResult(content: .error(String(localized: L10n.Viewer.readContentsFailed)), fingerprint: fingerprint, lineStartOffsets: [0])
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return FileLoadResult(content: .unsupportedBinary, fingerprint: fingerprint, lineStartOffsets: [0])
        }
        return FileLoadResult(
            content: .text(text),
            fingerprint: fingerprint,
            lineStartOffsets: lineStartOffsets(in: text)
        )
    }

    private static func makeFingerprint(from attributes: [FileAttributeKey: Any]) -> FileFingerprint? {
        guard let size = attributes[.size] as? Int64 else { return nil }
        let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        return FileFingerprint(
            sizeBytes: size,
            modificationDate: attributes[.modificationDate] as? Date,
            fileNumber: fileNumber
        )
    }

    private static func lineStartOffsets(in text: String) -> [UInt32] {
        var offsets: [UInt32] = [0]
        for (index, codeUnit) in text.utf16.enumerated() where codeUnit == 10 {
            offsets.append(UInt32(index + 1))
        }
        return offsets
    }
}
