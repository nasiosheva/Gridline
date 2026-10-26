import Foundation

/// Menyusun daftar file diff yang flat jadi hierarki folder untuk mode
/// tampilan "Tree" di `DiffAreaView`. Folder diurutkan lebih dulu (alfabet),
/// lalu file (alfabet berdasarkan nama tampilan), sama seperti kebanyakan
/// file browser.
enum DiffFileTreePolicy {
    struct Node: Identifiable {
        enum Content {
            case folder
            case file(DiffFileEntry)
        }

        let id: String
        let name: String
        let content: Content
        let children: [Node]
    }

    /// Urutan file persis seperti traversal depth-first pohon yang dirender
    /// (folder lebih dulu, lalu file, alfabet di tiap level) — dipakai untuk
    /// menyinkronkan navigasi keyboard ↑/↓ dengan urutan visual mode "Tree",
    /// yang berbeda dari urutan flat `DiffFileEntry` aslinya.
    static func orderedEntries(from entries: [DiffFileEntry]) -> [DiffFileEntry] {
        tree(from: entries).flatMap(leafEntries)
    }

    private static func leafEntries(in node: Node) -> [DiffFileEntry] {
        switch node.content {
        case .file(let entry):
            return [entry]
        case .folder:
            return node.children.flatMap(leafEntries)
        }
    }

    static func tree(from entries: [DiffFileEntry]) -> [Node] {
        let root = Builder()
        for entry in entries {
            var components = entry.path.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            let fileComponent = components.removeLast()
            var current = root
            for component in components {
                if let next = current.folders[component] {
                    current = next
                } else {
                    let next = Builder()
                    current.folders[component] = next
                    current = next
                }
            }
            current.files.append((fileComponent, entry))
        }
        return build(root, pathPrefix: "")
    }

    private final class Builder {
        var folders: [String: Builder] = [:]
        var files: [(name: String, entry: DiffFileEntry)] = []
    }

    private static func build(_ builder: Builder, pathPrefix: String) -> [Node] {
        let folderNodes = builder.folders.keys.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }.map { name -> Node in
            let childPath = pathPrefix.isEmpty ? name : "\(pathPrefix)/\(name)"
            return compactedFolderNode(name: name, builder: builder.folders[name]!, path: childPath)
        }
        let fileNodes = builder.files.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }.map { Node(id: $0.entry.id, name: $0.name, content: .file($0.entry), children: []) }
        return folderNodes + fileNodes
    }

    /// Memadatkan rantai folder yang hanya punya satu sub-folder dan tidak
    /// ada file langsung di dalamnya menjadi satu baris "a/b/c", mengikuti
    /// pola "Compact Folders" di file browser seperti VS Code — monorepo
    /// dengan banyak folder pembungkus tunggal (mis. `services/x/src/x`)
    /// jadi tidak membuat indentasi Tree view bertambah dalam tanpa guna.
    private static func compactedFolderNode(name: String, builder: Builder, path: String) -> Node {
        if builder.files.isEmpty,
           builder.folders.count == 1,
           let onlyChildName = builder.folders.keys.first,
           let onlyChildBuilder = builder.folders[onlyChildName] {
            let childPath = "\(path)/\(onlyChildName)"
            let compactedChild = compactedFolderNode(name: onlyChildName, builder: onlyChildBuilder, path: childPath)
            return Node(
                id: compactedChild.id,
                name: "\(name)/\(compactedChild.name)",
                content: .folder,
                children: compactedChild.children
            )
        }
        return Node(
            id: "folder:\(path)",
            name: name,
            content: .folder,
            children: build(builder, pathPrefix: path)
        )
    }
}
