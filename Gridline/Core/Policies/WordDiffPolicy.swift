import Foundation

/// Highlight level-kata di dalam satu pasangan baris hapus/tambah (baris yang
/// sama secara konseptual tapi isinya diedit), mirip tampilan git client lain
/// seperti Fork. Token dipisah per kelompok karakter sejenis (kata vs bukan
/// kata) lalu dicocokkan lewat longest common subsequence; token yang tidak
/// cocok di kedua sisi dianggap berubah dan digabung jadi rentang yang
/// berdekatan untuk mengurangi jumlah potongan highlight.
enum WordDiffPolicy {
    /// Baris lebih panjang dari ini tidak dihitung word-diff-nya (biar DP
    /// O(n*m) tidak jadi beban) — seluruh baris ditandai berubah sebagai
    /// fallback, sama seperti sebelum fitur ini ada.
    private static let maxTokens = 256

    static func changedRanges(old: String, new: String) -> (old: [Range<Int>], new: [Range<Int>]) {
        guard old != new else { return ([], []) }

        let oldTokens = tokenize(old)
        let newTokens = tokenize(new)
        guard !oldTokens.isEmpty, !newTokens.isEmpty,
              oldTokens.count <= maxTokens, newTokens.count <= maxTokens else {
            return ([0..<old.count], [0..<new.count])
        }

        let matched = matchedIndices(oldTokens.map(\.text), newTokens.map(\.text))
        return (
            mergedChangedRanges(tokens: oldTokens, matchedIndices: matched.lhs),
            mergedChangedRanges(tokens: newTokens, matchedIndices: matched.rhs)
        )
    }

    private struct Token {
        let text: String
        let range: Range<Int>
    }

    private enum CharacterClass: Equatable {
        case word
        case other
    }

    private static func characterClass(_ character: Character) -> CharacterClass {
        character.isLetter || character.isNumber || character == "_" ? .word : .other
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var offset = 0
        var index = text.startIndex
        while index < text.endIndex {
            let startOffset = offset
            let kind = characterClass(text[index])
            var token = String(text[index])
            index = text.index(after: index)
            offset += 1
            while index < text.endIndex, characterClass(text[index]) == kind {
                token.append(text[index])
                index = text.index(after: index)
                offset += 1
            }
            tokens.append(Token(text: token, range: startOffset..<offset))
        }
        return tokens
    }

    /// LCS standar lewat tabel DP, lalu ditelusuri balik untuk indeks token
    /// yang cocok (bukan berubah) di kedua sisi.
    private static func matchedIndices(_ lhs: [String], _ rhs: [String]) -> (lhs: Set<Int>, rhs: Set<Int>) {
        let n = lhs.count
        let m = rhs.count
        var table = [[Int32]](repeating: [Int32](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = lhs[i] == rhs[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var matchedLHS = Set<Int>()
        var matchedRHS = Set<Int>()
        var i = 0
        var j = 0
        while i < n, j < m {
            if lhs[i] == rhs[j] {
                matchedLHS.insert(i)
                matchedRHS.insert(j)
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return (matchedLHS, matchedRHS)
    }

    private static func mergedChangedRanges(tokens: [Token], matchedIndices: Set<Int>) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var pending: Range<Int>?
        for (index, token) in tokens.enumerated() {
            guard !matchedIndices.contains(index) else {
                if let current = pending {
                    ranges.append(current)
                    pending = nil
                }
                continue
            }
            if let current = pending {
                pending = current.lowerBound..<token.range.upperBound
            } else {
                pending = token.range
            }
        }
        if let pending {
            ranges.append(pending)
        }
        return ranges
    }
}
