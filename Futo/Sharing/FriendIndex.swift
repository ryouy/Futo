import Foundation

/// フレンドが多くなったときの、並べ方と探し方（頭文字ごとの見出し・検索）。
/// 漢字の読みは分からないので、漢字などは「他」にまとめる。かなは、行（あ・か・さ…）、英字は A〜Z。
enum FriendIndex {
    static let other = "他"

    private static let kanaRows: [(String, String)] = [
        ("あ", "ぁあぃいぅうぇえぉお"), ("か", "かがきぎくぐけげこご"), ("さ", "さざしじすずせぜそぞ"),
        ("た", "ただちぢっつづてでとど"), ("な", "なにぬねの"), ("は", "はばぱひびぴふぶぷへべぺほぼぽ"),
        ("ま", "まみむめも"), ("や", "ゃやゅゆょよ"), ("ら", "らりるれろ"), ("わ", "ゎわゐゑをん"),
    ]

    /// 検索・並べ替え用に、大文字小文字・全角半角・カタカナとひらがなの違いをなくした文字列
    static func folded(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hiragana = trimmed.applyingTransform(.hiraganaToKatakana, reverse: true) ?? trimmed
        return hiragana.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ja"))
    }

    /// 見出し（A〜Z、あ〜わ、他）
    static func key(for name: String) -> String {
        guard let first = folded(name).first else { return other }
        let s = String(first)
        if let ascii = s.unicodeScalars.first, ascii.isASCII, ascii.properties.isAlphabetic { return s.uppercased() }
        for (row, members) in kanaRows where members.contains(first) { return row }
        return other
    }

    /// 見出しの並び順：A〜Z → あ〜わ → 他
    static func order(of key: String) -> Int {
        if key == other { return 1_000 }
        if let index = kanaRows.firstIndex(where: { $0.0 == key }) { return 100 + index }
        return Int(key.unicodeScalars.first?.value ?? 999)
    }

    /// 見出しごとにまとめる（見出しの中は、名前順）
    static func grouped<T>(_ items: [T], name: (T) -> String) -> [(key: String, items: [T])] {
        var buckets: [String: [T]] = [:]
        for item in items { buckets[key(for: name(item)), default: []].append(item) }
        return buckets.keys.sorted { order(of: $0) < order(of: $1) }.map { key in
            (key, buckets[key]!.sorted { folded(name($0)).localizedStandardCompare(folded(name($1))) == .orderedAscending })
        }
    }

    /// 名前の一部で絞り込む。空の検索なら、すべて。
    static func filter<T>(_ items: [T], query: String, name: (T) -> String) -> [T] {
        let q = folded(query)
        guard !q.isEmpty else { return items }
        return items.filter { folded(name($0)).contains(q) }
    }
}
