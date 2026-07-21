import SwiftUI

struct DiscoverView: View {
    @State private var type = "movie"
    @State private var items: [MetaItem] = []
    @State private var loading = true

    private let genres = ["", "Action", "Comedy", "Drama", "Thriller", "Sci-Fi", "Horror", "Animation"]
    @State private var genre = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Discover").font(.system(size: 52, weight: .bold))
                        .padding(.horizontal, 60).padding(.top, 30)

                    HStack(spacing: 16) {
                        Picker("Type", selection: $type) {
                            Text("Movies").tag("movie")
                            Text("Series").tag("series")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 400)
                    }
                    .padding(.horizontal, 60)

                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            ForEach(genres, id: \.self) { g in
                                Button(g.isEmpty ? "All" : g) { genre = g }
                                    .buttonStyle(.bordered)
                                    .tint(genre == g ? .white : .gray)
                            }
                        }
                        .padding(.horizontal, 60)
                    }

                    if loading { ProgressView().padding(.horizontal, 60) }

                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(items) { item in
                            PosterCard(item: item, width: 200)
                        }
                    }
                    .padding(.horizontal, 60)
                }
                .padding(.bottom, 60)
            }
            .navigationDestination(for: MetaItem.self) { DetailView(item: $0) }
        }
        .task(id: "\(type)-\(genre)") { await load() }
    }

    @EnvironmentObject private var auth: AuthStore

    private func load() async {
        loading = true
        // Use a catalog addon that serves this type, else Cinemeta.
        let addon = auth.addons.first {
            !($0.manifest?.catalogs ?? []).isEmpty && ($0.manifest?.types?.contains(type) ?? false)
        }
        let base = addon?.base ?? CatalogService.cinemeta
        let catId = addon?.manifest?.catalogs?.first { $0.type == type }?.id ?? "top"
        let result = await AddonService.catalog(base: base, type: type, id: catId, genre: genre)
        await MainActor.run { items = result; loading = false }
    }
}
