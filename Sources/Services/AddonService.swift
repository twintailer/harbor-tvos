import Foundation

// Catalogs + metadata resolved through the USER's installed addons (the ones
// they configured in Stremio), not hard-coded Cinemeta. Falls back to Cinemeta
// when signed out.
enum AddonService {
    // Home rows built from every catalog the user's addons expose.
    static func homeRows(addons: [Addon]) async -> [CatalogRow] {
        let catalogAddons = addons.filter { !($0.manifest?.catalogs ?? []).isEmpty }
        if catalogAddons.isEmpty {
            return await CinemetaRows()
        }
        var rows: [CatalogRow] = []
        for addon in catalogAddons {
            for cat in (addon.manifest?.catalogs ?? []).prefix(6) {
                let items = await catalog(base: addon.base, type: cat.type, id: cat.id)
                if !items.isEmpty {
                    let label = cat.name ?? "\(cat.type.capitalized) · \(cat.id)"
                    rows.append(CatalogRow(title: label, items: items))
                }
            }
        }
        return rows.isEmpty ? await CinemetaRows() : rows
    }

    private static func CinemetaRows() async -> [CatalogRow] {
        async let m = catalog(base: CatalogService.cinemeta, type: "movie", id: "top")
        async let s = catalog(base: CatalogService.cinemeta, type: "series", id: "top")
        return [
            CatalogRow(title: "Trending Movies", items: await m),
            CatalogRow(title: "Trending Series", items: await s),
        ].filter { !$0.items.isEmpty }
    }

    static func catalog(base: String, type: String, id: String, genre: String? = nil) async -> [MetaItem] {
        var path = "\(base)/catalog/\(type)/\(id)"
        if let genre, !genre.isEmpty,
           let enc = genre.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            path += "/genre=\(enc)"
        }
        path += ".json"
        guard let url = URL(string: path) else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return (try JSONDecoder().decode(CatalogResponse.self, from: data)).metas ?? []
        } catch { return [] }
    }

    // Prefer a user meta-addon that serves this type; fall back to Cinemeta.
    static func meta(addons: [Addon], type: String, id: String) async -> MetaItem? {
        let metaAddons = addons.filter { $0.hasMeta && ($0.manifest?.types?.contains(type) ?? true) }
        for addon in metaAddons {
            if let m = await metaFrom(base: addon.base, type: type, id: id) { return m }
        }
        return await metaFrom(base: CatalogService.cinemeta, type: type, id: id)
    }

    private static func metaFrom(base: String, type: String, id: String) async -> MetaItem? {
        guard let url = URL(string: "\(base)/meta/\(type)/\(id).json") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return (try JSONDecoder().decode(MetaResponse.self, from: data)).meta
        } catch { return nil }
    }
}

// --- Continue Watching (Stremio library) -----------------------------------

extension StremioService {
    struct LibraryItem: Codable {
        let _id: String
        let type: String?
        let name: String?
        let poster: String?
        let background: String?
        let removed: Bool?
        let temp: Bool?
        let state: State?
        struct State: Codable {
            let timeOffset: Double?
            let duration: Double?
            let season: Int?
            let episode: Int?
            let flaggedWatched: Int?
            let lastWatched: String?
        }
        var isContinueWatching: Bool {
            if (removed ?? false) && !(temp ?? false) { return false }
            guard let s = state else { return false }
            if (s.flaggedWatched ?? 0) > 0 { return false }
            guard let off = s.timeOffset, off > 0 else { return false }
            if let d = s.duration, d > 0, off / d >= 0.9 { return false }
            return true
        }
        var asMeta: MetaItem {
            MetaItem(id: _id, type: type ?? "movie", name: name ?? _id,
                     poster: poster, background: background, description: nil,
                     releaseInfo: nil, imdbRating: nil, genres: nil, runtime: nil, videos: nil)
        }
    }

    static func continueWatching(authKey: String) async -> [LibraryItem] {
        // datastoreMeta returns [[id, hash], …]
        guard let ids: [[String]] = try? await postArray(
            "datastoreMeta", ["authKey": authKey, "collection": "libraryItem"]),
            !ids.isEmpty else { return [] }
        let idList = ids.compactMap { $0.first }
        guard let items: [LibraryItem] = try? await postArray(
            "datastoreGet",
            ["authKey": authKey, "collection": "libraryItem", "ids": idList, "all": true])
        else { return [] }
        return items
            .filter { $0.isContinueWatching }
            .sorted { ($0.state?.lastWatched ?? "") > ($1.state?.lastWatched ?? "") }
    }

    // datastore endpoints return a bare array in `result`.
    private static func postArray<T: Codable>(_ path: String, _ body: [String: Any]) async throws -> T {
        guard let url = URL(string: "\(api)/\(path)") else { throw Err.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        struct Env: Codable { let result: T? }
        guard let r = try JSONDecoder().decode(Env.self, from: data).result else {
            throw Err.api("empty")
        }
        return r
    }
}
