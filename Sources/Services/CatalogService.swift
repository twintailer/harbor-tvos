import Foundation

// Talks to Stremio's default addon (Cinemeta) exactly like the web app's
// baseline: public JSON endpoints, no auth. Later rounds will add the user's
// installed addons and stream resolvers (Torrentio, debrid, …).
enum CatalogService {
    static let cinemeta = "https://v3-cinemeta.strem.io"

    private static let decoder = JSONDecoder()

    static func catalog(type: String, id: String, genre: String? = nil) async -> [MetaItem] {
        var path = "\(cinemeta)/catalog/\(type)/\(id)"
        if let genre, !genre.isEmpty,
           let enc = genre.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            path += "/genre=\(enc)"
        }
        path += ".json"
        guard let url = URL(string: path) else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return (try decoder.decode(CatalogResponse.self, from: data)).metas ?? []
        } catch {
            return []
        }
    }

    static func meta(type: String, id: String) async -> MetaItem? {
        guard let url = URL(string: "\(cinemeta)/meta/\(type)/\(id).json") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return (try decoder.decode(MetaResponse.self, from: data)).meta
        } catch {
            return nil
        }
    }

    static func search(query: String) async -> [MetaItem] {
        guard let enc = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              !enc.isEmpty else { return [] }
        async let movies = catalog(type: "movie", id: "top", genre: nil)
        // Cinemeta search endpoint.
        let movieHits = await fetchSearch(type: "movie", query: enc)
        let seriesHits = await fetchSearch(type: "series", query: enc)
        _ = await movies
        return movieHits + seriesHits
    }

    private static func fetchSearch(type: String, query: String) async -> [MetaItem] {
        guard let url = URL(string: "\(cinemeta)/catalog/\(type)/top/search=\(query).json") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return (try decoder.decode(CatalogResponse.self, from: data)).metas ?? []
        } catch {
            return []
        }
    }
}
