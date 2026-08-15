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
        let showAll = UserDefaults.standard.bool(forKey: SubtitleStyle.Key.homeShowAllRows)
        var requests: [(index: Int, base: String, type: String, id: String, title: String)] = []
        for addon in catalogAddons {
            let catalogs = addon.manifest?.catalogs ?? []
            for cat in showAll ? catalogs[...] : catalogs.prefix(6) {
                requests.append((requests.count, addon.base, cat.type, cat.id,
                                 cat.name ?? "\(cat.type.capitalized) · \(cat.id)"))
            }
        }
        var indexedRows: [(Int, CatalogRow)] = []
        await withTaskGroup(of: (Int, CatalogRow?).self) { group in
            for request in requests {
                group.addTask {
                    let items = await catalog(base: request.base, type: request.type, id: request.id)
                    let row = items.isEmpty ? nil : CatalogRow(title: request.title, items: items)
                    return (request.index, row)
                }
            }
            for await (index, row) in group {
                if let row { indexedRows.append((index, row)) }
            }
        }
        let rows = indexedRows.sorted { $0.0 < $1.0 }.map { $0.1 }
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

    static func search(addons: [Addon], query: String) async -> [MetaItem] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        let sources = addons.flatMap { addon in
            (addon.manifest?.catalogs ?? []).filter {
                ["movie", "series", "anime"].contains($0.type)
            }.prefix(8).map { (addon.base, $0.type, $0.id) }
        }
        guard !sources.isEmpty else { return await CatalogService.search(query: query) }
        var combined: [MetaItem] = []
        await withTaskGroup(of: [MetaItem].self) { group in
            for (base, type, id) in sources {
                group.addTask {
                    guard let url = URL(string: "\(base)/catalog/\(type)/\(id)/search=\(encoded).json"),
                          let (data, _) = try? await URLSession.shared.data(from: url),
                          let response = try? JSONDecoder().decode(CatalogResponse.self, from: data)
                    else { return [] }
                    return response.metas ?? []
                }
            }
            for await result in group { combined.append(contentsOf: result) }
        }
        var seen = Set<String>()
        let unique = combined.filter { seen.insert("\($0.type):\($0.id)").inserted }
        return unique.isEmpty ? await CatalogService.search(query: query) : unique
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
        let releaseInfo: String?
        let year: String?
        let removed: Bool?
        let temp: Bool?
        let _ctime: String?
        let _mtime: String?
        let isAnime: Bool?
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
                     releaseInfo: releaseInfo ?? year, imdbRating: nil,
                     genres: nil, runtime: nil, videos: nil)
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

    static func library(authKey: String) async -> [LibraryItem] {
        guard let items: [LibraryItem] = try? await postArray(
            "datastoreGet",
            ["authKey": authKey, "collection": "libraryItem", "ids": [], "all": true])
        else { return [] }
        return items.filter { !($0.removed ?? false) || ($0.temp ?? false) }
    }

    static func saveProgress(authKey: String, meta: MetaItem, videoId: String,
                             season: Int?, episode: Int?, position: Double,
                             duration: Double, existing: LibraryItem?) async {
        guard duration > 0, position >= 0 else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let watched = position / duration >= 0.9
        let creditsReached = position / duration >= 0.98
        let libraryType = season != nil || episode != nil
            ? "series" : (meta.type == "anime" ? "movie" : meta.type)
        let raw = await rawLibraryItem(authKey: authKey, id: meta.id)
        if existing != nil && raw == nil { return }
        var change = raw ?? [
            "_id": meta.id,
            "type": libraryType,
            "name": meta.name,
            "posterShape": "poster",
            // Playback creates a temporary history entry; only the explicit Library
            // button turns it into a bookmark.
            "removed": true,
            "temp": true,
            "_ctime": existing?._ctime ?? now,
            "behaviorHints": [
                "defaultVideoId": NSNull(),
                "featuredVideoId": NSNull(),
                "hasScheduledVideos": false,
            ],
        ]
        var state = (change["state"] as? [String: Any]) ?? [:]
        let oldVideoId = state["video_id"] as? String
        let videoChanged = oldVideoId != nil && oldVideoId != videoId
        let oldTimeWatched = numeric(state["timeWatched"])
        let oldOverall = numeric(state["overallTimeWatched"])
        let oldTimesWatched = Int(numeric(state["timesWatched"]))
        let oldFlagged = Int(numeric(state["flaggedWatched"]))
        state["timeOffset"] = creditsReached ? 0 : Int(position * 1000)
        state["duration"] = Int(duration * 1000)
        state["timeWatched"] = Int(position * 1000)
        state["overallTimeWatched"] = oldOverall + (videoChanged ? oldTimeWatched : 0)
        state["timesWatched"] = watched && (videoChanged || oldFlagged == 0)
            ? oldTimesWatched + 1 : oldTimesWatched
        state["flaggedWatched"] = watched ? 1 : (videoChanged ? 0 : oldFlagged)
        state["video_id"] = videoId
        state["lastWatched"] = now
        if state["watched"] == nil { state["watched"] = "" }
        if state["noNotif"] == nil { state["noNotif"] = false }
        if let season { state["season"] = season }
        if let episode { state["episode"] = episode }
        change["type"] = libraryType
        change["name"] = meta.name
        if change["removed"] == nil { change["removed"] = true }
        if change["temp"] == nil { change["temp"] = existing?.temp ?? true }
        change["_mtime"] = now
        change["state"] = state
        if let poster = meta.poster { change["poster"] = poster }
        if let background = meta.background { change["background"] = background }
        await putLibraryChange(authKey: authKey, change: change)
    }

    static func setBookmarked(authKey: String, meta: MetaItem, existing: LibraryItem?,
                              bookmarked: Bool) async {
        let now = ISO8601DateFormatter().string(from: Date())
        let libraryType = (meta.videos?.isEmpty == false)
            ? "series" : (meta.type == "anime" ? "movie" : meta.type)
        var change: [String: Any]
        if let object = await rawLibraryItem(authKey: authKey, id: meta.id) {
            change = object
        } else if existing != nil {
            return
        } else {
            change = [
                "_id": meta.id,
                "type": libraryType,
                "name": meta.name,
                "posterShape": "poster",
                "_ctime": now,
                "state": [
                    "timeOffset": 0, "duration": 0, "timeWatched": 0,
                    "overallTimeWatched": 0, "timesWatched": 0,
                    "flaggedWatched": 0, "watched": "", "noNotif": false,
                ],
                "behaviorHints": [
                    "defaultVideoId": NSNull(),
                    "featuredVideoId": NSNull(),
                    "hasScheduledVideos": false,
                ],
            ]
            if let poster = meta.poster { change["poster"] = poster }
            if let background = meta.background { change["background"] = background }
        }
        let state = change["state"] as? [String: Any]
        let hasProgress = numeric(state?["timeOffset"]) > 0 ||
            numeric(state?["flaggedWatched"]) > 0
        change["removed"] = !bookmarked
        change["temp"] = bookmarked ? false : hasProgress
        change["_mtime"] = now

        await putLibraryChange(authKey: authKey, change: change)
    }

    /// One library item (for a series detail page: current episode + progress). all:false = just this id.
    static func libraryItem(authKey: String, id: String) async -> LibraryItem? {
        guard let items: [LibraryItem] = try? await postArray(
            "datastoreGet",
            ["authKey": authKey, "collection": "libraryItem", "ids": [id], "all": false])
        else { return nil }
        return items.first { $0._id == id }
    }

    private static func rawLibraryItem(authKey: String, id: String) async -> [String: Any]? {
        guard let url = URL(string: "\(api)/datastoreGet") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "authKey": authKey,
            "collection": "libraryItem",
            "ids": [id],
            "all": false,
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = envelope["result"] as? [[String: Any]]
        else { return nil }
        return items.first { ($0["_id"] as? String) == id }
    }

    private static func putLibraryChange(authKey: String, change: [String: Any]) async {
        guard let url = URL(string: "\(api)/datastorePut") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "authKey": authKey,
            "collection": "libraryItem",
            "changes": [change],
        ])
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func numeric(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return 0
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
