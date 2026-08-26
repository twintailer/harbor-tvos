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
                    Text("Catalogs")
                        .font(.system(size: 52, weight: .bold))
                        .padding(.horizontal, 60).padding(.top, 30)
                    if loading { ProgressView().padding(.horizontal, 60) }
                    ForEach(rows) { CatalogRowView(row: $0) }
                    if !loading && rows.isEmpty {
                        ContentUnavailableView("No catalogs available",
                                               systemImage: "square.grid.2x2",
                                               description: Text("Refresh your Stremio add-ons in Settings."))
                    }
                }
                .padding(.bottom, 60)
            }
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(title).font(.system(size: 52, weight: .bold))
                    if loading { ProgressView() }
                    if !loading && items.isEmpty {
                        ContentUnavailableView("No \(title.lowercased()) catalog found",
                                               systemImage: "film.stack",
                                               description: Text("Install a compatible catalog add-on in Stremio."))
                    } else {
                        LazyVGrid(columns: columns, spacing: 40) {
                            ForEach(items) { PosterCard(item: $0, width: 200) }
                        }
                    }
                }
                .padding(.horizontal, 60).padding(.vertical, 36)
            }
            .onExitCommand(perform: onRootBack)
            .navigationDestination(for: MetaItem.self) { DetailView(item: $0) }
        }
        .task(id: addonRevision) { await load() }
    }

    private func load() async {
        loading = true
        let candidates = auth.addons.flatMap { addon in
            (addon.manifest?.catalogs ?? []).filter { $0.type == type }.map { (addon, $0) }
        }
        if let first = candidates.first {
            let addonItems = await AddonService.catalog(
                base: first.0.base, type: first.1.type, id: first.1.id)
            items = addonItems.isEmpty ? [] : addonItems
            if items.isEmpty { items = await fallbackItems() }
        } else {
            items = await fallbackItems()
        }
        loading = false
    }

    private var addonRevision: String {
        auth.addons.map(\.transportUrl).joined(separator: "|")
    }

    private func fallbackItems() async -> [MetaItem] {
        if type == "anime" {
            return await CatalogService.catalog(
                type: "series", id: "top", genre: fallbackGenre ?? "Animation")
        }
        return await CatalogService.catalog(type: type, id: "top")
    }
}
