import SwiftUI

struct DiscoverView: View {
    var onRootBack: () -> Void = {}
    @State private var type = "movie"
    @State private var items: [MetaItem] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var nextSkip = 0
    @State private var pageSource: CatalogPageSource?

    private let genres = ["", "Action", "Comedy", "Drama", "Thriller", "Sci-Fi", "Horror", "Animation"]
    @State private var genre = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HarborPageHeader(title: "Discover", eyebrow: "Explore",
                                     subtitle: "Find something new by format and genre",
                                     count: items.count)
                        .padding(.horizontal, 60).padding(.top, 30)

                    HStack(spacing: 16) {
                        Button("Movies") { type = "movie" }
                            .buttonStyle(HarborFilterPillStyle(selected: type == "movie"))
                        Button("Series") { type = "series" }
                            .buttonStyle(HarborFilterPillStyle(selected: type == "series"))
                    }
                    .padding(.horizontal, 60)

                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            ForEach(genres, id: \.self) { g in
                                Button(g.isEmpty ? "All" : g) { genre = g }
                                    .buttonStyle(HarborFilterPillStyle(selected: genre == g))
                            }
                        }
                        .padding(.horizontal, 60)
                    }

                    if loading { ProgressView().padding(.horizontal, 60) }

                    LazyVGrid(columns: columns, spacing: 40) {
                        ForEach(items) { item in
                            PosterCard(item: item, width: 205)
                        }
                    }
                    .padding(.horizontal, 60)

                    if !loading && items.isEmpty {
                        HarborEmptyState(icon: "safari",
                                         title: "Nothing matched this filter",
                                         message: "Try a different genre or switch between movies and series.")
                    }

                    if hasMore {
                        HStack { Spacer(); ProgressView().controlSize(.large); Spacer() }
                            .frame(height: 100)
                            .task { await loadMore() }
                    }
                }
                .padding(.bottom, 60)
            }
            .background(HarborStageBackground())
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
        loadingMore = false
        hasMore = false
        nextSkip = 0
        items = []
        // Use a catalog addon that serves this type, else Cinemeta.
        let choice: (Addon, Addon.CatalogDef)? = auth.addons.lazy.compactMap { addon in
            guard let catalog = addon.manifest?.catalogs?.first(where: { $0.type == type }) else { return nil }
            return (addon, catalog)
        }.first
        var source: CatalogPageSource
        var result: [MetaItem]
        if let (addon, catalog) = choice {
            source = CatalogPageSource(base: addon.base, type: type,
                                       catalogID: catalog.id, genre: genre)
            result = await AddonService.catalog(source: source, skip: 0)
            if result.isEmpty {
                source = CatalogPageSource(base: CatalogService.cinemeta, type: type,
                                           catalogID: "top", genre: genre)
                result = await AddonService.catalog(source: source, skip: 0)
            }
        } else {
            source = CatalogPageSource(base: CatalogService.cinemeta, type: type,
                                       catalogID: "top", genre: genre)
            result = await AddonService.catalog(source: source, skip: 0)
        }
        pageSource = source
        items = result
        nextSkip = result.count
        hasMore = !result.isEmpty
        loading = false
    }

    private func loadMore() async {
        guard !loadingMore, hasMore, let pageSource else { return }
        loadingMore = true
        let page = await AddonService.catalog(source: pageSource, skip: nextSkip)
        let existing = Set(items.map { "\($0.type):\($0.id)" })
        let fresh = page.filter { !existing.contains("\($0.type):\($0.id)") }
        nextSkip += page.count
        if page.isEmpty || fresh.isEmpty { hasMore = false }
        else { items.append(contentsOf: fresh) }
        loadingMore = false
    }
}
