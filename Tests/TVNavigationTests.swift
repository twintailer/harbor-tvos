import Foundation

/// Pure navigation rules run on macOS CI and Linux without an Apple TV SDK.
/// Remote focus geometry and system Home transitions still need a device.
@main
struct TVNavigationTests {
    static func main() {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }

        expect(HarborSection.home.backDestination == nil,
               "Home must leave Back to tvOS rather than consume the command")
        for section in HarborSection.allCases where section != .home {
            expect(section.backDestination == .home,
                   "Back from a top-level section returns to Home in one step")
        }
        expect(Set(HarborSection.topTabs).count == HarborSection.topTabs.count,
               "Top tabs have unique focus identities")
        let reachable = Set(HarborSection.topTabs + [.discover, .addons, .settings])
        expect(reachable == Set(HarborSection.allCases), "Every section remains reachable")

        let titles = ["movie:a", "movie:b", "series:a"]
        var previous: String?
        func preview(_ focused: String?, available: [String] = titles) -> String? {
            let result = TVFocusPresentation.previewID(focused: focused,
                                                      previous: previous, available: available)
            previous = result
            return result
        }
        expect(preview(nil) == "movie:a", "Initial preview uses the first available title")
        expect(preview("movie:b") == "movie:b", "Moving right expands the selected second title")
        expect(preview("series:a") == "series:a", "Movie and series with the same ID stay distinct")
        expect(preview(nil) == "series:a", "Leaving a rail retains its last preview")
        expect(preview("movie:b") == "movie:b", "Moving left restores that title, not the first")
        expect(preview(nil, available: titles + ["movie:c"]) == "movie:b",
               "Appending a catalog page does not reset selection")
        expect(preview("movie:c", available: titles + ["movie:c"]) == "movie:c",
               "A paginated title can own the preview")
        expect(preview("missing", available: titles + ["movie:c"]) == "movie:c",
               "Stale focus does not replace a still-visible preview")
        expect(preview(nil, available: titles) == "movie:a",
               "Removing or filtering the selected item restores a valid preview")
        expect(preview(nil, available: []) == nil, "An empty rail has no stale preview")
        expect(preview(nil, available: ["movie:b"]) == "movie:b",
               "A refreshed rail selects from its new contents")

        var settings = Set<SettingsRoute>()
        for category in SettingsCategory.allCases {
            expect(!category.routes.isEmpty && category.routes.count <= 6,
                   "Every dashboard category fits at most three rows of two tiles")
            expect(Set(category.routes).count == category.routes.count,
                   "No duplicate focus identities within a settings category")
            settings.formUnion(category.routes)
        }
        expect(settings == Set(SettingsRoute.allCases), "Every settings panel is reachable")
        print("TV navigation regression checks passed: \(checks)")
    }
}
