import Foundation

/// 动作搜索：支持中文、别名、英文、全拼和拼音首字母（例如 “gwxl” 匹配 “高位下拉”）
enum SearchIndex {
    static func key(nameZh: String, aliases: [String], nameEn: String) -> String {
        var parts: [String] = []
        for zh in [nameZh] + aliases {
            let syllables = pinyinSyllables(zh)
            parts.append(zh)
            parts.append(syllables.joined())
            parts.append(syllables.compactMap(\.first).map(String.init).joined())
        }
        parts.append(nameEn)
        return normalize(parts.joined(separator: "|"))
    }

    static func pinyinSyllables(_ text: String) -> [String] {
        let s = NSMutableString(string: text) as CFMutableString
        CFStringTransform(s, nil, kCFStringTransformToLatin, false)
        CFStringTransform(s, nil, kCFStringTransformStripDiacritics, false)
        return (s as String)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: " ", with: "")
    }

    static func matches(key: String, query: String) -> Bool {
        let q = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return q.isEmpty || key.contains(q)
    }
}
