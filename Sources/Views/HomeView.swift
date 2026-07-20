import SwiftUI

struct HomeView: View {
    @State private var rows: [CatalogRow] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    Text("Harbor")
                        .font(.system(size: 56, weight: .bold))
                        .padding(.horizontal, 60)
                        .padding(.top, 40)

                    if loading {
                        ProgressView().padding(.horizontal, 60)
                    }
                    ForEach(rows) { row in
                        CatalogRowView(row: row)
                    }
                }
                .padding(.bottom, 60)
            }
            .navigationDestination(for: MetaItem.self) { item in
                DetailView(item: item)
            }
        }
        .task {
            if rows.isEmpty { await load() }
        }
    }

    private func load() async {
        async let trendingMovies = CatalogService.catalog(type: "movie", id: "top")
        async let trendingSeries = CatalogService.catalog(type: "series", id: "top")
        async let popularMovies = CatalogService.catalog(type: "movie", id: "imdbRating")
        let built: [CatalogRow] = [
            CatalogRow(title: "Trending Movies", items: await trendingMovies),
            CatalogRow(title: "Trending Series", items: await trendingSeries),
            CatalogRow(title: "Top Rated", items: await popularMovies),
        ].filter { !$0.items.isEmpty }
        await MainActor.run {
            rows = built
            loading = false
        }
    }
}

struct CatalogRowView: View {
    let row: CatalogRow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(row.title)
                .font(.system(size: 30, weight: .semibold))
                .padding(.horizontal, 60)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 32) {
                    ForEach(row.items) { item in
                        NavigationLink(value: item) {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 12)
            }
        }
    }
}
