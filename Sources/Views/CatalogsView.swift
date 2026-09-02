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
            rows = await AddonService.homeRows(addons: auth.addons)
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
                            ForEach(items) { PosterCard(item: $0, width: 205) }
                        }
                        if hasMore {
                            HStack {
                                Spacer()
                                ProgressView().controlSize(.large)
                                Spacer()
                            }
                            .frame(height: 100)
                            .task { await loadMore() }
                        }
                    }
                }
                .padding(.horizontal, 60).padding(.vertical, 36)
            }
            .background(HarborStageBackground())
            .onExitCommand(perform: onRootBack)
            .navigationDestination(for: MetaItem.self) { DetailView(item: $0) }
        }
        .task(id: addonRevision) { await load() }
    }

    private func load() async {
        loading = true
        loadingMore = false
        hasMore = false
        nextSkip = 0
        items = []
        let candidates = auth.addons.flatMap { addon in
            (addon.manifest?.catalogs ?? []).filter { $0.type == type }.map { (addon, $0) }
        }
        var source: CatalogPageSource
        if let first = candidates.first {
            source = CatalogPageSource(base: first.0.base, type: first.1.type,
                                       catalogID: first.1.id)
            items = await AddonService.catalog(source: source, skip: 0)
            if items.isEmpty {
                source = fallbackSource
                items = await AddonService.catalog(source: source, skip: 0)
            }
        } else {
            source = fallbackSource
            items = await AddonService.catalog(source: source, skip: 0)
        }
        pageSource = source
        nextSkip = items.count
        hasMore = !items.isEmpty
        loading = false
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
