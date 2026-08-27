import SwiftUI

struct SearchView: View {
    var onRootBack: () -> Void = {}
    @EnvironmentObject private var auth: AuthStore
    @State private var query = ""
    @State private var results: [MetaItem] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 40) {
                    ForEach(results) { item in
                        PosterCard(item: item, width: 200)
                    }
                }
                .padding(60)
            }
            .onExitCommand(perform: onRootBack)
            .navigationDestination(for: MetaItem.self) { DetailView(item: $0) }
        }
        .searchable(text: $query, prompt: "Search movies & series")
        .task(id: "\(query)|\(addonRevision)") {
            let requestedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard requestedQuery.count >= 2 else { results = []; return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let hits = await AddonService.search(addons: auth.addons, query: requestedQuery)
            // A cancelled network request can still finish after the next query.
            // Never let those stale results replace the current search.
            guard !Task.isCancelled,
                  requestedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            await MainActor.run { results = hits }
        }
    }

    private var addonRevision: String {
        auth.addons.map(\.transportUrl).joined(separator: "|")
    }
}
