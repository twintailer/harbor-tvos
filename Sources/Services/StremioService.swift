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
        struct R: Codable { let addons: [Addon]? }
        let r: R? = try? await post("addonCollectionGet",
                                    ["authKey": authKey, "type": "user", "update": false])
        return r?.addons ?? []
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
    let manifest: Manifest?
    struct Manifest: Codable {
        let id: String?
        let name: String?
        let resources: [Resource]?
        let types: [String]?
        let catalogs: [CatalogDef]?
    }
    struct CatalogDef: Codable, Hashable {
        let type: String
        let id: String
        let name: String?
    }
    // resources can be plain strings ("stream") or objects ({name:"stream"}).
    struct Resource: Codable {
        let name: String
        init(from decoder: Decoder) throws {
            if let s = try? decoder.singleValueContainer().decode(String.self) {
                name = s
            } else {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
            }
        }
        enum CodingKeys: String, CodingKey { case name }
    }

    var base: String {
        transportUrl.replacingOccurrences(of: "/manifest.json", with: "")
    }
    var hasStream: Bool { hasResource("stream") }
    var hasMeta: Bool { hasResource("meta") }
    func hasResource(_ r: String) -> Bool {
        (manifest?.resources ?? []).contains { $0.name == r }
    }
}

struct StreamOption: Codable, Identifiable, Hashable {
    var id: String { (url ?? infoHash ?? UUID().uuidString) + (title ?? name ?? "") }
    let url: String?
    let name: String?
    let title: String?
    let infoHash: String?
    // Only direct http(s) links are playable by AVPlayer; magnet/torrent
    // (infoHash without url) needs a torrent client we don't have on tvOS yet.
    var isPlayable: Bool {
        guard let u = url else { return false }
        return u.hasPrefix("http")
    }
    var displayName: String {
        [name, title].compactMap { $0 }.joined(separator: "  ·  ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

enum StreamResolver {
    struct StreamsResponse: Codable { let streams: [StreamOption]? }

    // Query every stream-capable addon for this media and merge the results.
    static func streams(addons: [Addon], type: String, id: String) async -> [StreamOption] {
        let streamAddons = addons.filter { $0.hasStream }
        var all: [StreamOption] = []
        await withTaskGroup(of: [StreamOption].self) { group in
            for addon in streamAddons {
                group.addTask { await fetch(base: addon.base, type: type, id: id) }
            }
            for await result in group { all.append(contentsOf: result) }
        }
        // Playable (debrid/HLS) first.
        return all.sorted { $0.isPlayable && !$1.isPlayable }
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
