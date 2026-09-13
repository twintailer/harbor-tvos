import Foundation

@main
struct CatalogURLTests {
    static func main() {
        let titles = ["Tom & Jerry", "WALL/E", "Who?", "#Alive", "A=B+C", "100%", "Die Königin"]
        for title in titles {
            let encoded = CatalogURL.encodeExtra(title)
            precondition(encoded.removingPercentEncoding == title, "Title must round-trip intact")
            precondition(!encoded.contains(where: { "/?#&=+".contains($0) }), "Title must stay in one extra")
            let url = URL(string: "https://example.com/catalog/movie/top/search=\(encoded).json")!
            precondition(url.query == nil && url.fragment == nil, "Title must never create a query or fragment")
            precondition(url.absoluteString.hasSuffix("search=\(encoded).json"), "Keep the complete Stremio extra")
        }
        precondition(CatalogURL.encodeExtra("Drama") == "Drama")
        precondition(CatalogURL.encodeExtra("Science Fiction & Fantasy") == "Science%20Fiction%20%26%20Fantasy")
        print("Catalog URL regression checks passed: \(titles.count * 4 + 2)")
    }
}
