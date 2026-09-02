import SwiftUI

struct SearchView: View {
    var onRootBack: () -> Void = {}
    @EnvironmentObject private var auth: AuthStore
    @State private var query = ""
    @State private var results: [MetaItem] = []
    @State private var searching = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    HarborPageHeader(title: "Search", eyebrow: "Find your next story",
                                     subtitle: searchSubtitle,
                                     count: trimmedQuery.isEmpty ? nil : results.count)

                    if trimmedQuery.isEmpty {
                        HarborSearchWelcome()
                    } else if searching && results.isEmpty {
                        HStack(spacing: 16) {
                            ProgressView().controlSize(.large)
                            Text("Searching every connected catalog…")
                                .font(.system(size: 21, weight: .medium))
                                .foregroundStyle(HarborTVDesign.secondaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                    } else if results.isEmpty {
                        HarborEmptyState(icon: "magnifyingglass",
                                         title: "No results for “\(trimmedQuery)”",
                                         message: "Check the spelling or try a shorter title.")
                    } else {
                        LazyVGrid(columns: columns, spacing: 40) {
                            ForEach(results) { item in
                                PosterCard(item: item, width: 205)
                            }
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 36)
            }
            .background(HarborStageBackground())
            .onExitCommand(perform: onRootBack)
            .navigationDestination(for: MetaItem.self) { DetailView(item: $0) }
        }
        .searchable(text: $query, prompt: "Search movies & series")
        .task(id: "\(query)|\(addonRevision)") {
            let requestedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard requestedQuery.count >= 2 else { results = []; searching = false; return }
            searching = true
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let hits = await AddonService.search(addons: auth.addons, query: requestedQuery)
            // A cancelled network request can still finish after the next query.
            // Never let those stale results replace the current search.
            guard !Task.isCancelled,
                  requestedQuery == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            await MainActor.run { results = hits; searching = false }
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchSubtitle: String {
        trimmedQuery.isEmpty
            ? "Movies, series, anime and people across all of your add-ons"
            : "Results for “\(trimmedQuery)”"
    }

    private var addonRevision: String {
        auth.addons.map(\.transportUrl).joined(separator: "|")
    }
}

private struct HarborSearchWelcome: View {
    var body: some View {
        HStack(spacing: 26) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(HarborTVDesign.cinemaRed)
                .frame(width: 108, height: 108)
                .background(Circle().fill(.white.opacity(0.07)))
            VStack(alignment: .leading, spacing: 9) {
                Text("Start typing to search")
                    .font(.system(size: 30, weight: .bold))
                Text("Try a title, actor, franchise or anime name. Results update automatically.")
                    .font(.system(size: 20))
                    .foregroundStyle(HarborTVDesign.secondaryText)
            }
        }
        .padding(32)
        .frame(maxWidth: 980, alignment: .leading)
        .background(HarborTVDesign.panel,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}
