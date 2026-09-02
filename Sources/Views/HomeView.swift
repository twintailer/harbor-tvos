import SwiftUI

struct HomeView: View {
    var onRootBack: () -> Void = {}
    var onSearch: () -> Void = {}
    @EnvironmentObject private var auth: AuthStore
    @State private var rows: [CatalogRow] = []
    @State private var loading = true
    @AppStorage(SubtitleStyle.Key.homeShowAllRows) private var showAllRows = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 46) {
                    if let featured {
                        HarborDesktopHero(item: featured, onSearch: onSearch)
                    } else {
                        HarborHeroPlaceholder(onSearch: onSearch)
                    }

                    if !auth.continueWatching.isEmpty {
                        ContinueRowView(entries: auth.continueWatching) { entry in
                            Task { await auth.clearContinueWatching(entry.id) }
                        }
                    }

                    if loading { ProgressView().padding(.horizontal, 60) }
                    ForEach(rows) { row in
                        CatalogRowView(row: row)
                    }
                }
                .padding(.bottom, 84)
            }
            .onExitCommand(perform: onRootBack)
            .navigationDestination(for: MetaItem.self) { item in
                DetailView(item: item)
            }
        }
        // Rebuild rows when the signed-in addons change.
        .task(id: "\(addonRevision)-\(showAllRows)") {
            await auth.loadLibrary()
            await auth.loadContinueWatching()
            rows = await AddonService.homeRows(addons: auth.addons)
            loading = false
        }
    }

    private var addonRevision: String {
        auth.addons.map(\.transportUrl).joined(separator: "|")
    }

    private var featured: MetaItem? {
        rows.lazy.flatMap(\.items).first(where: { $0.background != nil })
            ?? rows.first?.items.first
    }
}

private struct HarborDesktopHero: View {
    let item: MetaItem
    let onSearch: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            HarborArtworkImage(url: item.background ?? item.poster, maxPixelSize: 2200)
                .frame(maxWidth: .infinity)
                .frame(height: 610)

            LinearGradient(
                stops: [
                    .init(color: HarborTVDesign.canvas.opacity(0.99), location: 0),
                    .init(color: .black.opacity(0.72), location: 0.35),
                    .init(color: .black.opacity(0.16), location: 0.72),
                    .init(color: .black.opacity(0.05), location: 1),
                ], startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(colors: [.black.opacity(0.08), .clear, HarborTVDesign.canvas],
                           startPoint: .top, endPoint: .bottom)

            HStack {
                HStack(spacing: 9) {
                    Rectangle()
                        .fill(HarborTVDesign.cinemaRed)
                        .frame(width: 4, height: 20)
                    Text("HARBOR  /  HOME")
                        .font(.system(size: 15, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(.white.opacity(0.72))
                }
                Spacer()
                searchChip
            }
            .padding(.horizontal, HarborTVDesign.pageInset)
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                Text("HARBOR SPOTLIGHT")
                    .font(.system(size: 15, weight: .heavy))
                    .tracking(2.4)
                    .foregroundStyle(HarborTVDesign.cinemaRed)
                Text(item.name)
                    .font(.system(size: 68, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: 720, alignment: .leading)

                HStack(spacing: 12) {
                    Text("98% Match")
                        .foregroundStyle(HarborTVDesign.success)
                    if let release = item.releaseInfo, !release.isEmpty { Text(release) }
                    Text(item.type == "movie" ? "MOVIE" : (item.type == "anime" ? "ANIME" : "SERIES"))
                        .font(.system(size: 13, weight: .heavy))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.42), lineWidth: 1))
                    if let rating = item.imdbRating, !rating.isEmpty { ImdbBadge(rating: rating) }
                    if let runtime = item.runtime, !runtime.isEmpty { Text(runtime) }
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))

                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(3)
                        .lineSpacing(3)
                        .frame(maxWidth: 720, alignment: .leading)
                }

                HStack(spacing: 14) {
                    NavigationLink(value: item) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(HarborActionButtonStyle(tone: .primary))
                    NavigationLink(value: item) {
                        Label("More Info", systemImage: "info.circle")
                    }
                    .buttonStyle(HarborActionButtonStyle(tone: .secondary))
                }
            }
            .padding(.leading, HarborTVDesign.pageInset)
            .padding(.bottom, 58)
        }
        .frame(height: 610)
        .clipped()
    }

    private var searchChip: some View {
        Button(action: onSearch) {
            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass")
                Text("Search")
            }
            .frame(minWidth: 145)
        }
        .buttonStyle(HarborActionButtonStyle(tone: .quiet))
    }
}

private struct HarborHeroPlaceholder: View {
    let onSearch: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            HarborStageBackground()
            Button(action: onSearch) {
                Label("Search movies, shows, people…", systemImage: "magnifyingglass")
            }
            .buttonStyle(HarborActionButtonStyle(tone: .quiet))
            .padding(.top, 70)
        }
        .frame(height: 260)
    }
}

struct ContinueRowView: View {
    let entries: [CwItem]
    let onRemove: (CwItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HarborSectionHeading(title: "Continue Watching", subtitle: "Pick up where you left off")
                .padding(.horizontal, 60)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 32) {
                    ForEach(entries) { entry in
                        ContinueCard(entry: entry, onRemove: { onRemove(entry) })
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 12)
            }
        }
        .focusSection()
    }
}

struct CatalogRowView: View {
    let row: CatalogRow
    @EnvironmentObject private var auth: AuthStore
    @State private var loadedItems: [MetaItem]
    @State private var nextSkip: Int
    @State private var loadingMore = false
    @State private var hasMore: Bool
    @AppStorage(SubtitleStyle.Key.rowTitleScale) private var titleScale = 1.0
    @AppStorage(SubtitleStyle.Key.hideWatched) private var hideWatched = false
    @AppStorage(SubtitleStyle.Key.hideUnreleased) private var hideUnreleased = false

    init(row: CatalogRow) {
        self.row = row
        _loadedItems = State(initialValue: row.items)
        _nextSkip = State(initialValue: row.items.count)
        _hasMore = State(initialValue: row.source != nil && !row.items.isEmpty)
    }

    private var visibleItems: [MetaItem] {
        let watched = Set(auth.libraryItems.filter {
            ($0.state?.flaggedWatched ?? 0) > 0 || $0.progressRatio >= 0.9
        }.map(\._id))
        let currentYear = Calendar.current.component(.year, from: Date())
        return loadedItems.filter { item in
            if hideWatched && watched.contains(item.id) { return false }
            if hideUnreleased,
               let text = item.releaseInfo,
               let year = Int(text.prefix(4)), year > currentYear { return false }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HarborSectionHeading(title: row.title,
                                 subtitle: visibleItems.isEmpty ? nil : "\(visibleItems.count)+ titles",
                                 scale: CGFloat(titleScale))
                .padding(.horizontal, 60)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 26) {
                    ForEach(visibleItems) { item in
                        HarborLandscapeCard(item: item)
                    }
                    if hasMore, row.source != nil {
                        ProgressView()
                            .controlSize(.large)
                            .frame(width: 120, height: 235)
                            .task { await loadMore() }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 12)
            }
        }
        .focusSection()
    }

    private func loadMore() async {
        guard !loadingMore, hasMore, let source = row.source else { return }
        loadingMore = true
        let page = await AddonService.catalog(source: source, skip: nextSkip)
        let existing = Set(loadedItems.map { "\($0.type):\($0.id)" })
        let fresh = page.filter { !existing.contains("\($0.type):\($0.id)") }
        nextSkip += page.count
        if page.isEmpty || fresh.isEmpty {
            hasMore = false
        } else {
            loadedItems.append(contentsOf: fresh)
        }
        loadingMore = false
    }
}
