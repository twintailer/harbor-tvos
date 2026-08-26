import Foundation

/// tvOS cannot host a BitTorrent engine. When configured, Harbor hands torrent
/// sources to a TorrServer on the local network and plays its direct HTTP stream.
enum TorrServerService {
    enum Result { case success(URL), notConfigured, failed(String) }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    static var isConfigured: Bool {
        UserDefaults.standard.bool(forKey: SubtitleStyle.Key.torrServerEnabled)
            && normalizedBase != nil
    }

    static func ping() async -> Bool {
        guard let base = normalizedBase,
              let url = URL(string: "\(base)/echo"),
              let (_, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    static func resolve(infoHash: String, season: Int?, episode: Int?) async -> Result {
        guard let base = normalizedBase,
              UserDefaults.standard.bool(forKey: SubtitleStyle.Key.torrServerEnabled) else {
            return .notConfigured
        }
        let magnet = "magnet:?xt=urn:btih:\(infoHash)"
        do {
            let acceptedHash = try await add(base: base, magnet: magnet) ?? infoHash
            var files: [TorrentFile] = []
            for _ in 0..<10 {
                files = try await files(base: base, hash: acceptedHash)
                if !files.isEmpty { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard let file = select(files, season: season, episode: episode) else {
                return .failed("TorrServer returned no playable video file")
            }
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            let encoded = magnet.addingPercentEncoding(withAllowedCharacters: allowed) ?? magnet
            guard let url = URL(string: "\(base)/stream?link=\(encoded)&index=\(file.id)&play") else {
                return .failed("TorrServer returned an invalid stream URL")
            }
            return .success(url)
        } catch {
            return .failed("Can't reach TorrServer at \(base)")
        }
    }

    private static var normalizedBase: String? {
        var raw = (UserDefaults.standard.string(forKey: SubtitleStyle.Key.torrServerURL) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return raw
    }

    private static func add(base: String, magnet: String) async throws -> String? {
        let data = try await post(base: base, body: [
            "action": "add", "link": magnet, "save_to_db": false,
        ])
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["hash"] as? String
    }

    private static func files(base: String, hash: String) async throws -> [TorrentFile] {
        let data = try await post(base: base, body: ["action": "get", "hash": hash])
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let values = object["file_stats"] as? [[String: Any]] else { return [] }
        return values.enumerated().map { offset, item in
            TorrentFile(
                id: (item["id"] as? Int) ?? offset + 1,
                path: (item["path"] as? String) ?? "",
                size: (item["length"] as? NSNumber)?.int64Value ?? 0)
        }
    }

    private static func post(base: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(base)/torrents") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private struct TorrentFile { let id: Int; let path: String; let size: Int64 }
    private static let videoExtensions = Set(["mkv", "mp4", "avi", "mov", "m4v", "ts", "webm"])

    private static func select(_ files: [TorrentFile], season: Int?, episode: Int?) -> TorrentFile? {
        let videos = files.filter { videoExtensions.contains(($0.path as NSString).pathExtension.lowercased()) }
        let candidates = videos.isEmpty ? files : videos
        if let season, let episode {
            let patterns = [
                String(format: "s%02de%02d", season, episode),
                String(format: "%dx%02d", season, episode),
                String(format: "s%02d.e%02d", season, episode),
            ]
            if let match = candidates.first(where: { file in
                patterns.contains { file.path.lowercased().contains($0) }
            }) { return match }
        }
        return candidates.max(by: { $0.size < $1.size })
    }
}
