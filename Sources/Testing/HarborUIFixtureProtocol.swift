#if DEBUG
import Foundation

/// Explicit opt-in for UI tests. Release builds contain neither the protocol nor
/// the launch argument hook; navigation tests need no live provider or account.
final class HarborUIFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let type = url.path.contains("/series/") ? "series" : "movie"
        func meta(_ number: Int) -> [String: Any] {
            ["id": "fixture\(number)", "type": type, "name": "Spotlight title \(number)",
             "description": "A journey beyond the familiar. Ten stories to discover, one title at a time.",
             "releaseInfo": "2025", "imdbRating": "8.2"]
        }
        let payload: [String: Any]
        if url.path.contains("/catalog/") {
            payload = ["metas": url.path.contains("skip=") ? [] : (1...30).map(meta)]
        } else if url.path.contains("/meta/") {
            let number = Int(url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "fixture", with: "")) ?? 1
            payload = ["meta": meta(number)]
        } else { payload = [:] }
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
