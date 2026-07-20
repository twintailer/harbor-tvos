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

    struct Video: Codable, Hashable {
        let id: String?
        let title: String?
        let season: Int?
        let episode: Int?
        let thumbnail: String?
        let overview: String?
        let released: String?
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
