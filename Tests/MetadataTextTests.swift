import Foundation

@main
struct MetadataTextTests {
    static func main() throws {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }

        let examples = [
            ("Der Koenig der Loewen", "Der König der Löwen"),
            ("Die Schoene und das Biest", "Die Schöne und das Biest"),
            ("Zurueck in die Zukunft", "Zurück in die Zukunft"),
            ("Fuer fuenf Maedchen aus Muenchen.", "Für fünf Mädchen aus München."),
            ("KOENIG, KOENIGIN, LOEWEN", "KÖNIG, KÖNIGIN, LÖWEN"),
            ("Sein groesstes Abenteuer fuehrt ihn zurueck.", "Sein größtes Abenteuer führt ihn zurück."),
            ("Goethe, Noel, Coen, Phoenix, Phoebe und Zoe", "Goethe, Noel, Coen, Phoenix, Phoebe und Zoe"),
            ("Ein neues, teures Abenteuer. Feuer und Steuern.", "Ein neues, teures Abenteuer. Feuer und Steuern."),
            ("KOeNIG und iPhone", "KOeNIG und iPhone"),
            ("Grüße, Mädchen und Löwen — 日本語 🎬", "Grüße, Mädchen und Löwen — 日本語 🎬"),
            ("Fu\u{308}r die Koenigin!", "Für die Königin!"),
            ("Masse, Busse, Fussball", "Masse, Busse, Fussball"),
        ]
        for (input, expected) in examples {
            expect(MetadataText.display(input) == expected, "Unexpected metadata spelling for: \(input)")
            expect(MetadataText.display(expected) == expected, "Display correction must be idempotent")
        }
        let data = Data(#"{"id":"koenig:oe","type":"movie","name":"Der Koenig","description":"Fuer Maedchen.","poster":"https://example.com/koenig.jpg","videos":[{"name":"Zurueck","description":"Fuer fuenf Freunde."}]}"#.utf8)
        let meta = try JSONDecoder().decode(MetaItem.self, from: data)
        expect(meta.name == "Der König" && meta.description == "Für Mädchen.",
               "All catalog and detail screens receive corrected display text")
        expect(meta.videos?.first?.title == "Zurück" && meta.videos?.first?.overview == "Für fünf Freunde.",
               "Episode metadata uses the same display correction")
        expect(meta.id == "koenig:oe" && meta.poster == "https://example.com/koenig.jpg",
               "Identifiers and artwork addresses must never be transliterated")
        let copied = meta.withVideos(meta.videos ?? [])
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(copied)) as! [String: Any]
        expect(encoded["name"] as? String == "Der Koenig" && encoded["description"] as? String == "Fuer Maedchen.",
               "Source spelling survives encoding and metadata copies")
        let episodes = encoded["videos"] as! [[String: Any]]
        expect(episodes.first?["title"] as? String == "Zurueck", "Episode source spelling is preserved")
        print("Metadata text regression checks passed: \(checks)")
    }
}
