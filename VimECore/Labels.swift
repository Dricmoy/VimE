/// Hint label generation.
public enum Labels {
    /// Vimium's default hint characters: home row first.
    public static let defaultAlphabet: [Character] = Array("sadfjklewcmpgh")

    /// Returns `count` prefix-free labels, as short as possible (Vimium's algorithm).
    /// Prefix-free means typing a full label never also matches a longer one.
    public static func make(count: Int, alphabet: [Character] = defaultAlphabet) -> [String] {
        guard count > 0, alphabet.count > 1 else { return [] }
        // Breadth-first expansion of a trie: hints[offset...] are always the unexpanded leaves.
        var hints = [""]
        var offset = 0
        while hints.count - offset < count || hints.count == 1 {
            let hint = hints[offset]
            offset += 1
            for c in alphabet { hints.append(String(c) + hint) }
        }
        // Built by prepending, so leaves are suffix-free; reversing makes them prefix-free.
        return hints[offset..<offset + count].map { String($0.reversed()) }
    }
}
