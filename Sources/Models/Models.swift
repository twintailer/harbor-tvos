import Foundation

// Mirrors the subset of the Stremio "meta" object Harbor uses. Cinemeta and
// most catalog addons return this shape.
struct MetaItem: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let background: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: String?
    let genres: [String]?
    let runtime: String?
    let videos: [Video]?

    // Tolerant decoding: addons disagree on field names — Cinemeta-style uses
    // title/episode, TMDB-style meta addons use name/number, and some emit numbers
    // as strings. A strict decode of one odd video used to fail the WHOLE meta,
    // which surfaced as "the series has no episode list".
    struct Video: Codable, Hashable {
        let id: String?
        let title: String?
        let season: Int?
        let episode: Int?
        let thumbnail: String?
        let overview: String?
        let released: String?

        init(id: String?, title: String?, season: Int?, episode: Int?,
             thumbnail: String?, overview: String?, released: String?) {
            self.id = id; self.title = title; self.season = season; self.episode = episode
            self.thumbnail = thumbnail; self.overview = overview; self.released = released
        }

        enum CodingKeys: String, CodingKey {
            case id, title, name, season, episode, number, thumbnail, overview, description, released, firstAired
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try? c.decode(String.self, forKey: .id)
            title = (try? c.decode(String.self, forKey: .title)) ?? (try? c.decode(String.self, forKey: .name))
            season = Self.flexInt(c, .season)
            episode = Self.flexInt(c, .episode) ?? Self.flexInt(c, .number)
            thumbnail = try? c.decode(String.self, forKey: .thumbnail)
            overview = (try? c.decode(String.self, forKey: .overview)) ?? (try? c.decode(String.self, forKey: .description))
            released = (try? c.decode(String.self, forKey: .released)) ?? (try? c.decode(String.self, forKey: .firstAired))
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(id, forKey: .id)
            try c.encodeIfPresent(title, forKey: .title)
            try c.encodeIfPresent(season, forKey: .season)
            try c.encodeIfPresent(episode, forKey: .episode)
            try c.encodeIfPresent(thumbnail, forKey: .thumbnail)
            try c.encodeIfPresent(overview, forKey: .overview)
            try c.encodeIfPresent(released, forKey: .released)
        }

        private static func flexInt(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Int? {
            if let i = try? c.decode(Int.self, forKey: k) { return i }
            if let d = try? c.decode(Double.self, forKey: k) { return Int(d) }
            if let s = try? c.decode(String.self, forKey: k) { return Int(s) }
            return nil
        }
    }

    /// Copy with a replacement episode list (used for the Cinemeta fallback merge).
    func withVideos(_ v: [Video]) -> MetaItem {
        MetaItem(id: id, type: type, name: name, poster: poster, background: background,
                 description: description, releaseInfo: releaseInfo, imdbRating: imdbRating,
                 genres: genres, runtime: runtime, videos: v)
    }
}

struct CatalogResponse: Codable {
    let metas: [MetaItem]?
}

struct MetaResponse: Codable {
    let meta: MetaItem?
}

// A homogeneous focusable row of posters.
struct CatalogRow: Identifiable {
    let id = UUID()
    let title: String
    let items: [MetaItem]
}
