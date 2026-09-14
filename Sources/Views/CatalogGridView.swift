import SwiftUI

/// The catalog overview and its titles share the same value-based path. Mixing
/// a view-based overview link with value-based poster links can discard a push.
struct CatalogGridRoute: Hashable {
    let id: UUID
    let title: String
    let source: CatalogPageSource?
    let items: [MetaItem]
    let nextSkip: Int
    let hasMore: Bool

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Opens on the parent catalog's stack, retaining its rail position on Back.
/// The raw server offset is passed separately from deduplicated/filtered titles.
struct CatalogGridView: View {
    let title: String
    let source: CatalogPageSource?
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SubtitleStyle.Key.hideWatched) private var hideWatched = false
    @AppStorage(SubtitleStyle.Key.hideUnreleased) private var hideUnreleased = false
    @AppStorage(SubtitleStyle.Key.posterScale) private var posterScale = 1.0
    @State private var items: [MetaItem]
    @State private var nextSkip: Int
    @State private var hasMore: Bool
    @State private var loading = false

    init(route: CatalogGridRoute) {
        self.init(title: route.title, source: route.source, initialItems: route.items,
                  nextSkip: route.nextSkip, hasMore: route.hasMore)
    }

    init(title: String, source: CatalogPageSource?, initialItems: [MetaItem], nextSkip: Int, hasMore: Bool) {
        self.title = title
        self.source = source
        _items = State(initialValue: MetaItem.unique(initialItems))
        _nextSkip = State(initialValue: nextSkip)
        _hasMore = State(initialValue: hasMore && source != nil)
    }

    private var visibleItems: [MetaItem] {
        let watched = Set(auth.libraryItems.filter {
            ($0.state?.flaggedWatched ?? 0) > 0 || $0.progressRatio >= 0.9
        }.map(\._id))
        let year = Calendar.current.component(.year, from: Date())
        return items.filter {
            if hideWatched && watched.contains($0.id) { return false }
            if hideUnreleased, let date = $0.releaseInfo, let release = Int(date.prefix(4)), release > year { return false }
            return true
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let available = max(1, geometry.size.width - 120)
            let scale = CGFloat(max(0.1, posterScale))
            let count = max(1, min(6, Int((available + 34) / (240 * scale + 34))))
            // PosterCard applies the user's size multiplier itself. Allocate
            // fewer columns for Large, then pass an unscaled width to the card.
            let width = (available - CGFloat(count - 1) * 34) / CGFloat(count) / scale
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    HStack(spacing: 24) {
                        Button { dismiss() } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(HarborNavigationTabStyle())
                            .accessibilityLabel("Back to catalogs")
                            .accessibilityIdentifier("catalog.grid.back")
                        HarborPageHeader(title: title, eyebrow: "All titles", count: visibleItems.count)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 34), count: count), spacing: 36) {
                        ForEach(visibleItems, id: \.contentKey) { item in
                            PosterCard(item: item, width: width)
                                .task {
                                    if item.contentKey == visibleItems.suffix(12).first?.contentKey { await loadMore() }
                                }
                        }
                    }
                    if visibleItems.isEmpty {
                        HarborEmptyState(icon: "square.grid.2x2", title: "No visible titles",
                                         message: "Your catalog filters may hide these titles.")
                    }
                    if hasMore {
                        Button(loading ? "Loading…" : "Load more titles") { Task { await loadMore() } }
                            .buttonStyle(HarborActionButtonStyle(tone: .secondary))
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                }
                .padding(.horizontal, 60).padding(.top, 30).padding(.bottom, 60)
            }
        }
        .background(HarborStageBackground())
        .toolbar(.hidden, for: .navigationBar)
        .preference(key: HarborDetailNavigationKey.self, value: true)
    }

    private func loadMore() async {
        guard !loading, hasMore, let source else { return }
        loading = true
        defer { loading = false }
        let page = await AddonService.catalog(source: source, skip: nextSkip)
        guard !Task.isCancelled else { return }
        let fresh = MetaItem.unique(page, excluding: items)
        nextSkip += page.count
        hasMore = !page.isEmpty && !fresh.isEmpty
        items.append(contentsOf: fresh)
    }
}
