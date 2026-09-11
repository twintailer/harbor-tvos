import SwiftUI

struct CatalogsView: View {
    var onRootBack: () -> Void = {}
    @EnvironmentObject private var auth: AuthStore
    @State private var rows: [CatalogRow] = []
    @State private var loading = true
    @AppStorage(SubtitleStyle.Key.homeShowAllRows) private var showAllRows = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    HarborPageHeader(title: "Catalogs", eyebrow: "Browse",
                                     subtitle: "Collections from your connected Stremio add-ons",
                                     count: rows.count)
                        .padding(.horizontal, 60).padding(.top, 30)
                    if loading { ProgressView().padding(.horizontal, 60) }
                    ForEach(rows) { CatalogRowView(row: $0) }
                    if !loading && rows.isEmpty {
                        HarborEmptyState(icon: "square.grid.2x2",
                                         title: "No catalogs available",
                                         message: "Refresh your Stremio add-ons in Settings.")
                    }
                }
                .padding(.bottom, 60)
            }
            .background(HarborStageBackground())
            .onExitCommand(perform: onRootBack)
            .navigationDestination(for: MetaItem.self) { DetailView(item: $0) }
        }
        .task(id: "\(addonRevision)-\(showAllRows)") {
            loading = true
            let result = await AddonService.homeRows(addons: auth.addons)
            guard !Task.isCancelled else { return }
            rows = result
            loading = false
        }
    }

    private var addonRevision: String {
        auth.addons.map(\.transportUrl).joined(separator: "|")
    }
}

struct MediaBrowseView: View {
    let title: String
    let type: String
    var fallbackGenre: String? = nil
    var onRootBack: () -> Void = {}
    @EnvironmentObject private var auth: AuthStore
    @State private var items: [MetaItem] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = false
    @State private var nextSkip = 0
    @State private var pageSource: CatalogPageSource?
    @State private var loadedRevision: String?
    @State private var pageGeneration = UUID()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HarborPageHeader(title: title,
                                     eyebrow: type == "anime" ? "Animation" : "Browse",
                                     subtitle: browseSubtitle,
                                     count: items.count)
                    if loading { ProgressView() }
                    if !loading && items.isEmpty {
                        HarborEmptyState(icon: "film.stack",
                                         title: "No \(title.lowercased()) catalog found",
                                         message: "Install a compatible catalog add-on in Stremio.")
                    } else {
                        LazyVGrid(columns: columns, spacing: 40) {
                            ForEach(items, id: \.contentKey) { item in
                                PosterCard(item: item, width: 205)
                                    .onAppear {
                                        if item.contentKey == items.suffix(12).first?.contentKey {
                                            Task { await loadMore() }
                                        }
                                    }
                            }
                        }
                        if hasMore {
                            Button(loadingMore ? "Loading…" : "Load more titles") { Task { await loadMore() } }
                                .buttonStyle(HarborActionButtonStyle(tone: .secondary))
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                        }
                    }
                }
                .padding(.horizontal, 60).padding(.vertical, 36)
            }
            .background(HarborStageBackground())
            .onExitCommand(perform: onRootBack)
            .navigationDestination(for: MetaItem.self) { DetailView(item: $0) }
        }
        .task(id: addonRevision) { if loadedRevision != addonRevision { await load() } }
    }

    private func load() async {
        let requestedRevision = addonRevision
        pageGeneration = UUID()
        loading = true
        loadingMore = false
        hasMore = false
        nextSkip = 0
        items = []
        let candidates = auth.addons.flatMap { addon in
            (addon.manifest?.catalogs ?? []).filter { $0.type == type }.map { (addon, $0) }
        }
        var source: CatalogPageSource
        var result: [MetaItem]
        if let first = candidates.first {
            source = CatalogPageSource(base: first.0.base, type: first.1.type,
                                       catalogID: first.1.id)
            result = await AddonService.catalog(source: source, skip: 0)
            if result.isEmpty {
                source = fallbackSource
                result = await AddonService.catalog(source: source, skip: 0)
            }
        } else {
            source = fallbackSource
            result = await AddonService.catalog(source: source, skip: 0)
        }
        guard !Task.isCancelled, requestedRevision == addonRevision else { return }
        items = MetaItem.unique(result)
        pageSource = source
        nextSkip = result.count
        hasMore = !result.isEmpty
        loading = false
        loadedRevision = requestedRevision
    }

    private var addonRevision: String {
        auth.addons.map(\.transportUrl).joined(separator: "|")
    }

    private var browseSubtitle: String {
        switch type {
        case "movie": return "Films selected from your preferred catalogs"
        case "anime": return "Anime and animation, ready for the big screen"
        default: return "Series from your connected catalogs"
        }
    }

    private var fallbackSource: CatalogPageSource {
        if type == "anime" {
            return CatalogPageSource(base: CatalogService.cinemeta, type: "series",
                                     catalogID: "top", genre: fallbackGenre ?? "Animation")
        }
        return CatalogPageSource(base: CatalogService.cinemeta, type: type, catalogID: "top")
    }

    private func loadMore() async {
        guard !loadingMore, hasMore, let pageSource else { return }
        let requestedRevision = addonRevision
        let generation = pageGeneration
        loadingMore = true
        defer { if generation == pageGeneration { loadingMore = false } }
        let page = await AddonService.catalog(source: pageSource, skip: nextSkip)
        guard !Task.isCancelled, generation == pageGeneration,
              requestedRevision == addonRevision, self.pageSource == pageSource else { return }
        let fresh = MetaItem.unique(page, excluding: items)
        nextSkip += page.count
        if page.isEmpty || fresh.isEmpty { hasMore = false }
        else { items.append(contentsOf: fresh) }
        loadingMore = false
    }
}
