import Foundation

/// Correct only known, unambiguous German word spellings in display text.
/// Source metadata, content IDs and URLs remain untouched; no blanket oe→ö rule.
enum MetadataText {
    private static let words = try! NSRegularExpression(pattern: #"[\p{L}\p{M}]+"#)
    private static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 600
        cache.totalCostLimit = 1_048_576
        return cache
    }()
    private static let replacements: [String: String] = {
        guard let url = Bundle.main.url(forResource: "german-umlauts", withExtension: "json",
                                        subdirectory: "MetadataText"),
              let data = try? Data(contentsOf: url),
              let words = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return words
    }()

    static func prepare() { _ = replacements }

    static func display(_ source: String) -> String {
        if let cached = cache.object(forKey: source as NSString) { return cached as String }
        let text = source.precomposedStringWithCanonicalMapping
        let input = text as NSString
        let result = NSMutableString(string: text)
        for match in words.matches(in: text, range: NSRange(location: 0, length: input.length)).reversed() {
            let word = input.substring(with: match.range)
            let lower = word.lowercased()
            guard let replacement = replacements[lower] else { continue }
            let corrected: String
            if word == lower { corrected = replacement }
            else if word == word.uppercased() { corrected = replacement.uppercased() }
            else if word == word.prefix(1).uppercased() + word.dropFirst().lowercased() {
                corrected = replacement.prefix(1).uppercased() + replacement.dropFirst()
            } else {
                // Mixed-case names and brand spellings are intentional.
                continue
            }
            result.replaceCharacters(in: match.range, with: corrected)
        }
        let output = result as String
        cache.setObject(output as NSString, forKey: source as NSString,
                        cost: source.utf8.count + output.utf8.count)
        return output
    }
}
