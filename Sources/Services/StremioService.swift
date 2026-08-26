import Foundation

// Stremio account API — same endpoints the Harbor web/iOS app uses.
enum StremioService {
    static let api = "https://api.strem.io/api"

    struct LoginResult: Codable { let authKey: String; let user: StremioUser? }
    struct StremioUser: Codable { let _id: String?; let email: String? }
    private struct Envelope<T: Codable>: Codable { let result: T?; let error: APIError? }
    private struct APIError: Codable { let message: String? }

    private static func post<T: Codable>(_ path: String, _ body: [String: Any]) async throws -> T {
        guard let url = URL(string: "\(api)/\(path)") else { throw Err.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let env = try JSONDecoder().decode(Envelope<T>.self, from: data)
        if let e = env.error { throw Err.api(e.message ?? "Request failed") }
        guard let r = env.result else { throw Err.api("Empty response") }
        return r
    }

    static func login(email: String, password: String) async throws -> LoginResult {
        try await post("login", ["email": email, "password": password, "facebook": false])
    }

    // The user's installed addons (Cinemeta, Torrentio, debrid, …).
    static func userAddons(authKey: String) async -> [Addon] {
        guard let result = await postRaw("addonCollectionGet", [
            "authKey": authKey, "type": "user", "update": false,
        ]) as? [String: Any], let objects = result["addons"] as? [[String: Any]] else { return [] }
        return objects.compactMap { object in
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
            return try? JSONDecoder().decode(Addon.self, from: data)
        }
    }

    static func installAddon(authKey: String, from input: String) async -> Bool {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("stremio://") {
            value = "https://" + String(value.dropFirst("stremio://".count))
        }
        if !value.hasSuffix("manifest.json") { value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/manifest.json" }
        guard let url = URL(string: value),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let manifestID = manifest["id"] as? String, !manifestID.isEmpty,
              manifest["name"] is String,
              var addons = await rawUserAddons(authKey: authKey)
        else { return false }

        let clashesWithProtected = addons.contains { object in
            let existingID = (object["manifest"] as? [String: Any])?["id"] as? String
            let flags = object["flags"] as? [String: Any]
            let protected = flags?["official"] as? Bool == true || flags?["protected"] as? Bool == true
            return existingID == manifestID && protected
        }
        guard !clashesWithProtected else { return false }
        addons.removeAll { object in
            let existingID = (object["manifest"] as? [String: Any])?["id"] as? String
            return object["transportUrl"] as? String == value || existingID == manifestID
        }
        addons.append([
            "transportUrl": value,
            "transportName": "",
            "flags": ["official": false, "protected": false],
            "manifest": manifest,
        ])
        return await setRawUserAddons(authKey: authKey, addons: addons)
    }

    static func removeAddon(authKey: String, transportURL: String) async -> Bool {
        guard var addons = await rawUserAddons(authKey: authKey) else { return false }
        let oldCount = addons.count
        addons.removeAll { object in
            guard object["transportUrl"] as? String == transportURL else { return false }
            let flags = object["flags"] as? [String: Any]
            return flags?["official"] as? Bool != true && flags?["protected"] as? Bool != true
        }
        guard addons.count < oldCount else { return false }
        return await setRawUserAddons(authKey: authKey, addons: addons)
    }

    private static func rawUserAddons(authKey: String) async -> [[String: Any]]? {
        guard let result = await postRaw("addonCollectionGet", [
            "authKey": authKey, "type": "user", "update": false,
        ]) as? [String: Any] else { return nil }
        return result["addons"] as? [[String: Any]]
    }

    private static func setRawUserAddons(authKey: String, addons: [[String: Any]]) async -> Bool {
        await postRaw("addonCollectionSet", [
            "authKey": authKey, "type": "user", "addons": addons,
        ]) != nil
    }

    private static func postRaw(_ path: String, _ body: [String: Any]) async -> Any? {
        guard let url = URL(string: "\(api)/\(path)"),
              let encoded = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = encoded
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              envelope["error"] == nil
        else { return nil }
        return envelope["result"]
    }

    enum Err: Error, LocalizedError {
        case badURL, api(String)
        var errorDescription: String? {
            switch self {
            case .badURL: return "Bad URL"
            case .api(let m): return m
            }
        }
    }
}

// --- Addon + stream models -------------------------------------------------

struct Addon: Codable {
    let transportUrl: String
    let transportName: String?
    let flags: Flags?
    let manifest: Manifest?
    struct Flags: Codable {
        let official: Bool?
        let protected: Bool?
    }
    struct Manifest: Codable {
        let id: String?
        let name: String?
        let resources: [Resource]?
        let types: [String]?
        let catalogs: [CatalogDef]?
        let idPrefixes: [String]?
    }
    struct CatalogDef: Codable, Hashable {
        let type: String
        let id: String
        let name: String?
    }
    // resources can be plain strings ("stream") or objects ({name:"stream", types, idPrefixes}).
    struct Resource: Codable {
        let name: String
        let types: [String]?
        let idPrefixes: [String]?
        init(from decoder: Decoder) throws {
            if let s = try? decoder.singleValueContainer().decode(String.self) {
                name = s; types = nil; idPrefixes = nil
            } else {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                types = try? c.decode([String].self, forKey: .types)
                idPrefixes = try? c.decode([String].self, forKey: .idPrefixes)
            }
        }
        enum CodingKeys: String, CodingKey { case name, types, idPrefixes }
    }

    var base: String {
        transportUrl.replacingOccurrences(of: "/manifest.json", with: "")
    }
    var hasStream: Bool { hasResource("stream") }
    var hasMeta: Bool { hasResource("meta") }
    func hasResource(_ r: String) -> Bool {
        (manifest?.resources ?? []).contains { $0.name == r }
    }
    // id-prefixes this addon serves for meta (resource-level first, else manifest-level).
    var metaIdPrefixes: [String] {
        ((manifest?.resources ?? []).first { $0.name == "meta" }?.idPrefixes)
            ?? manifest?.idPrefixes ?? []
    }
    /// Does this addon claim to serve meta for `id` of `type`? A matching id-prefix is a strong
    /// signal; when the addon lists no prefixes, fall back to a type match.
    func servesMeta(type: String, id: String) -> Bool {
        guard hasMeta else { return false }
        let prefixes = metaIdPrefixes
        if !prefixes.isEmpty { return prefixes.contains { id.hasPrefix($0) } }
        return manifest?.types?.contains(type) ?? true
    }
}

struct StreamOption: Codable, Identifiable {
    var id: String { [url, infoHash, name, title, behaviorHints?.filename, behaviorHints?.fileName].compactMap { $0 }.joined(separator: "|") }
    let url: String?
    let name: String?
    let title: String?
    let description: String?
    let infoHash: String?
    let behaviorHints: BehaviorHints?

    struct BehaviorHints: Codable {
        let filename: String?
        let fileName: String?
        let videoSize: Double?
        let notWebReady: Bool?
        let proxyHeaders: ProxyHeaders?
        let headers: [String: String]?
    }
    struct ProxyHeaders: Codable {
        let request: [String: String]?
    }

    private enum CodingKeys: String, CodingKey {
        case url, name, title, description, infoHash, behaviorHints
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try? container.decode(String.self, forKey: .url)
        name = try? container.decode(String.self, forKey: .name)
        title = try? container.decode(String.self, forKey: .title)
        description = try? container.decode(String.self, forKey: .description)
        infoHash = try? container.decode(String.self, forKey: .infoHash)
        behaviorHints = try? container.decode(BehaviorHints.self, forKey: .behaviorHints)
    }
    // MPVKit can play direct HTTP(S)/HLS/MKV links. Magnet/torrent-only results
    // still need a debrid or remote server URL because tvOS has no local engine.
    var isPlayable: Bool {
        guard let u = url else { return false }
        return u.hasPrefix("http")
    }
    var isResolvable: Bool { isPlayable || (infoHash != nil && TorrServerService.isConfigured) }
    var displayName: String {
        [name, title].compactMap { $0 }.joined(separator: "  ·  ")
            .replacingOccurrences(of: "\n", with: " ")
    }
    var detailText: String {
        (description ?? "").replacingOccurrences(of: "\n", with: " ")
    }
    var filename: String? {
        behaviorHints?.filename ?? behaviorHints?.fileName ??
            url.flatMap { URL(string: $0)?.lastPathComponent }
    }
    var searchText: String {
        [displayName, detailText, filename ?? ""].joined(separator: " ")
    }
    var requestHeaders: [String: String] {
        var result = behaviorHints?.headers ?? [:]
        for (key, value) in behaviorHints?.proxyHeaders?.request ?? [:] { result[key] = value }
        return result
    }
}

enum StreamResolver {
    struct StreamsResponse: Codable { let streams: [StreamOption]? }

    // Query every stream-capable addon for this media and merge the results.
    static func streams(addons: [Addon], type: String, id: String) async -> [StreamOption] {
        let streamAddons = addons.filter { $0.hasStream }
        if UserDefaults.standard.string(forKey: SubtitleStyle.Key.streamSort) == "addon" {
            var ordered: [StreamOption] = []
            for addon in streamAddons {
                ordered.append(contentsOf: await fetch(base: addon.base, type: type, id: id))
            }
            return applyFilter(unique(ordered))
        }
        var all: [StreamOption] = []
        await withTaskGroup(of: [StreamOption].self) { group in
            for addon in streamAddons {
                group.addTask { await fetch(base: addon.base, type: type, id: id) }
            }
            for await result in group { all.append(contentsOf: result) }
        }
        return applyFilter(unique(all)).sorted { rank($0) > rank($1) }
    }

    private static func unique(_ streams: [StreamOption]) -> [StreamOption] {
        var seen = Set<String>()
        return streams.filter { seen.insert($0.id).inserted }
    }

    private static func applyFilter(_ streams: [StreamOption]) -> [StreamOption] {
        let level = UserDefaults.standard.string(forKey: SubtitleStyle.Key.streamFilter) ?? "strict"
        guard level != "off" else { return streams }
        let blocked = level == "strict"
            ? ["password", ".exe", "sample", "fake", "camrip"]
            : ["password", ".exe", "fake"]
        return streams.filter { stream in
            let text = stream.searchText.lowercased()
            return !blocked.contains { text.contains($0) }
        }
    }

    private static func rank(_ stream: StreamOption) -> Int {
        let text = stream.searchText.lowercased()
        var score = stream.isPlayable ? 10_000 : 0
        if text.contains("2160") || text.contains("4k") { score += 800 }
        else if text.contains("1440") { score += 600 }
        else if text.contains("1080") { score += 500 }
        else if text.contains("720") { score += 300 }
        if text.contains("hdr") || text.contains("dolby vision") || text.contains(" dv ") { score += 80 }
        if text.contains("cached") || text.contains("debrid") { score += 120 }
        if text.contains("cam") || text.contains("telesync") { score -= 900 }
        let audioLanguage = UserDefaults.standard.string(forKey: SubtitleStyle.Key.audioLang) ?? ""
        let languageNames: [String: [String]] = [
            "eng": ["english", " eng "], "ger": ["german", "deutsch", " ger "],
            "spa": ["spanish", "español", " spa "], "fre": ["french", "français", " fre "],
            "ita": ["italian", "italiano", " ita "], "jpn": ["japanese", "jpn", "dual audio"],
            "por": ["portuguese", "português"], "ara": ["arabic", "العربية"],
            "kor": ["korean", "kor"], "chi": ["chinese", "mandarin"],
        ]
        if let needles = languageNames[audioLanguage], needles.contains(where: { text.contains($0) }) {
            score += 160
        }
        let bandwidth = UserDefaults.standard.double(forKey: SubtitleStyle.Key.bandwidthMbps)
        if bandwidth > 0 {
            if bandwidth < 50 && (text.contains("2160") || text.contains("4k")) { score -= 1_200 }
            if bandwidth < 30 && text.contains("1440") { score -= 700 }
        }
        return score
    }

    private static func fetch(base: String, type: String, id: String) async -> [StreamOption] {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: "\(base)/stream/\(type)/\(enc).json") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return (try JSONDecoder().decode(StreamsResponse.self, from: data)).streams ?? []
        } catch {
            return []
        }
    }
}
