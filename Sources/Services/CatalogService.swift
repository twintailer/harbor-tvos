import Foundation

// Cinemeta fallback used when the signed-in account has no compatible catalog
// or metadata add-on. User add-ons are resolved by AddonService.
enum CatalogService {
    static let cinemeta = "https://v3-cinemeta.strem.io"

    static func catalog(type: String, id: String, genre: String? = nil,
                        skip: Int = 0) async -> [MetaItem] {
        var path = "\(cinemeta)/catalog/\(type)/\(id)"
        var extras: [String] = []
        if let genre, !genre.isEmpty,
           let enc = genre.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            extras.append("genre=\(enc)")
        }
        if skip > 0 { extras.append("skip=\(skip)") }
        if !extras.isEmpty { path += "/" + extras.joined(separator: "&") }
        path += ".json"
        guard let url = URL(string: path) else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return (try JSONDecoder().decode(CatalogResponse.self, from: data)).metas ?? []
        } catch {
            return []
        }
    }

    static func meta(type: String, id: String) async -> MetaItem? {
        guard let url = URL(string: "\(cinemeta)/meta/\(type)/\(id).json") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return (try JSONDecoder().decode(MetaResponse.self, from: data)).meta
        } catch {
            return nil
        }
    }

    static func search(query: String) async -> [MetaItem] {
        guard let enc = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              !enc.isEmpty else { return [] }
        async let movieHits = fetchSearch(type: "movie", query: enc)
        async let seriesHits = fetchSearch(type: "series", query: enc)
        let (movies, series) = await (movieHits, seriesHits)
        let normalizedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                            locale: .current)
        let tokens = normalizedQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var seen = Set<String>()
        return (movies + series).filter { item in
            let name = item.name.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                         locale: .current)
            return item.name != "#DUPE#"
                && tokens.allSatisfy { name.contains($0) }
                && seen.insert("\(item.type):\(item.id)").inserted
        }
    }

    private static func fetchSearch(type: String, query: String) async -> [MetaItem] {
        guard let url = URL(string: "\(cinemeta)/catalog/\(type)/top/search=\(query).json") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return (try JSONDecoder().decode(CatalogResponse.self, from: data)).metas ?? []
        } catch {
            return []
        }
    }
}
