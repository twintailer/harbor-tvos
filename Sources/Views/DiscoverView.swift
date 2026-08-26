import SwiftUI

struct DiscoverView: View {
    var onRootBack: () -> Void = {}
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
            .onExitCommand(perform: onRootBack)
            .navigationDestination(for: MetaItem.self) { DetailView(item: $0) }
        }
        .task(id: "\(type)-\(genre)-\(addonRevision)") { await load() }
    }

    @EnvironmentObject private var auth: AuthStore

    private var addonRevision: String {
        auth.addons.map(\.transportUrl).joined(separator: "|")
    }

    private func load() async {
        loading = true
        // Use a catalog addon that serves this type, else Cinemeta.
        let choice: (Addon, Addon.CatalogDef)? = auth.addons.lazy.compactMap { addon in
            guard let catalog = addon.manifest?.catalogs?.first(where: { $0.type == type }) else { return nil }
            return (addon, catalog)
        }.first
        let result: [MetaItem]
        if let (addon, catalog) = choice {
            let addonItems = await AddonService.catalog(
                base: addon.base, type: type, id: catalog.id, genre: genre)
            if addonItems.isEmpty {
                result = await CatalogService.catalog(type: type, id: "top", genre: genre)
            } else {
                result = addonItems
            }
        } else {
            result = await CatalogService.catalog(type: type, id: "top", genre: genre)
        }
        await MainActor.run { items = result; loading = false }
    }
}
