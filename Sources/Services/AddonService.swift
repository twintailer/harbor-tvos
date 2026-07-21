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

    // Prefer a user meta-addon that actually serves this id (matching id-prefix), then any other
    // meta addon, then Cinemeta. This is what makes the user's own metadata addon win over Cinemeta.
    static func meta(addons: [Addon], type: String, id: String) async -> MetaItem? {
        let matching = addons.filter { $0.servesMeta(type: type, id: id) }
        let matchingBases = Set(matching.map { $0.base })
        let otherMeta = addons.filter { $0.hasMeta && !matchingBases.contains($0.base) }
        for addon in matching {
            if let m = await metaFrom(base: addon.base, type: type, id: id) { return m }
        }
        for addon in otherMeta {
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

/// One Continue Watching entry: the meta to navigate with, plus what the card shows.
struct CwItem: Identifiable {
    var id: String { meta.id }
    let meta: MetaItem
    let season: Int?
    let episode: Int?
    let progress: Double
}

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
            let video_id: String?
        }
        // Exact parity with Harbor's stremio.ts `isCwMember`: a positive timeOffset means it's a
        // member; a flaggedWatched item with no offset is finished and drops out. (The previous
        // `|| lastWatched not empty` check was wrong — it kept every ever-watched title forever,
        // which is why finished items lingered in Continue Watching.)
        var isContinueWatching: Bool {
            if (removed ?? false) && !(temp ?? false) { return false }
            guard let s = state else { return false }
            if (s.timeOffset ?? 0) > 0 { return true }
            if (s.flaggedWatched ?? 0) > 0 { return false }
            return false
        }
        /// 0…1 watched fraction for the progress bar.
        var progressRatio: Double {
            guard let off = state?.timeOffset, let d = state?.duration, d > 0 else { return 0 }
            return min(1, max(0, off / d))
        }
        var asMeta: MetaItem {
            MetaItem(id: _id, type: type ?? "movie", name: name ?? _id,
                     poster: poster, background: background, description: nil,
                     releaseInfo: nil, imdbRating: nil, genres: nil, runtime: nil, videos: nil)
        }

        /// Season/episode for the CW card: state fields first, else parsed from
        /// video_id ("tt1234:3:4"), matching Harbor's episodeFromVideoId.
        var seasonEpisode: (season: Int, episode: Int)? {
            if let s = state?.season, let e = state?.episode, s > 0 || e > 0 { return (s, e) }
            let parts = (state?.video_id ?? "").split(separator: ":")
            guard parts.count >= 3,
                  let s = Int(parts[parts.count - 2]), let e = Int(parts[parts.count - 1]),
                  s >= 0, e > 0 else { return nil }
            return (s, e)
        }

        var asCwItem: CwItem {
            let se = seasonEpisode
            return CwItem(meta: asMeta,
                          season: (type ?? "") == "movie" ? nil : se?.season,
                          episode: (type ?? "") == "movie" ? nil : se?.episode,
                          progress: progressRatio)
        }
    }

    static func continueWatching(authKey: String) async -> [LibraryItem] {
        // datastoreGet with all:true returns every library item in `result`. (The old two-step
        // datastoreMeta → datastoreGet path decoded the meta array as [[String]], but its second
        // element is a numeric mtime, so it threw and Continue Watching came back empty.)
        guard let items: [LibraryItem] = try? await postArray(
            "datastoreGet",
            ["authKey": authKey, "collection": "libraryItem", "ids": [], "all": true])
        else { return [] }
        return items
            .filter { $0.isContinueWatching }
            .sorted { ($0.state?.lastWatched ?? "") > ($1.state?.lastWatched ?? "") }
    }

    /// One library item (for a series detail page: current episode + progress). all:false = just this id.
    static func libraryItem(authKey: String, id: String) async -> LibraryItem? {
        guard let items: [LibraryItem] = try? await postArray(
            "datastoreGet",
            ["authKey": authKey, "collection": "libraryItem", "ids": [id], "all": false])
        else { return nil }
        return items.first { $0._id == id }
    }

    // datastore endpoints return a bare array in `result`.
    private static func postArray<T: Codable>(_ path: String, _ body: [String: Any]) async throws -> T {
        guard let url = URL(string: "\(api)/\(path)") else { throw Err.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let r = try JSONDecoder().decode(ResultEnvelope<T>.self, from: data).result else {
            throw Err.api("empty")
        }
        return r
    }
}

private struct ResultEnvelope<T: Codable>: Codable { let result: T? }
