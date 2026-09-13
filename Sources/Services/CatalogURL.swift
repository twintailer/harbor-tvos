import Foundation

enum CatalogURL {
    /// Stremio extras are key=value pairs inside a path segment. Path-allowed
    /// characters such as &, = and / still delimit those pairs and must be escaped.
    static func encodeExtra(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#&=+%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
