import SwiftUI

struct HomeView: View {
    var onSearch: () -> Void = {}
    @EnvironmentObject private var auth: AuthStore
    @State private var rows: [CatalogRow] = []
    @State private var loading = true
    @State private var refreshRevision = 0
    @State private var loadedRevision: String?
    @State private var focusedPreview: MetaItem?
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
                        ContinueRowView(entries: auth.continueWatching, onFocus: { focusedPreview = $0 }) { entry in
                            Task { await auth.clearContinueWatching(entry.id) }
                        }
                    }

                    if loading {
                        HStack(spacing: 24) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: HarborTVDesign.cardRadius)
                                    .fill(HarborTVDesign.panel).frame(width: 350, height: 197)
                            }
                        }
                        .padding(.horizontal, 60)
                        .accessibilityLabel("Loading your catalogs")
                    } else if rows.isEmpty {
                        VStack(spacing: 0) {
                            HarborEmptyState(icon: "square.stack", title: "Your catalogs belong here",
                                             message: auth.addons.isEmpty
                                              ? "Sign in and add a metadata provider to build your home screen."
                                              : "No titles loaded. Check your connection or try again.")
                            Button("Try again") { refreshRevision += 1 }
                                .buttonStyle(HarborActionButtonStyle(tone: .primary))
                        }
                    }
                    ForEach(rows) { row in
                        CatalogRowView(row: row, onFocus: { focusedPreview = $0 })
                    }
                }
                .padding(.bottom, 84)
            }
            .scrollIndicators(.hidden)
            // No custom Back handler here: at the root, tvOS returns to Home.
            .navigationDestination(for: MetaItem.self) { item in
                DetailView(item: item)
            }
        }
        // Rebuild rows when the signed-in addons change.
        .task(id: contentRevision) {
            let revision = contentRevision
            // Returning from a title must preserve rails, pagination and focus.
            guard loadedRevision != revision else { return }
            focusedPreview = nil
            loading = rows.isEmpty
            let loaded = await AddonService.homeRows(addons: auth.addons)
            guard !Task.isCancelled else { return }
            rows = loaded
            loadedRevision = revision
            loading = false
        }
        .onChange(of: auth.continueWatching.map { $0.meta.contentKey }) { previous, current in
            if let key = focusedPreview?.contentKey, previous.contains(key), !current.contains(key) {
                focusedPreview = nil
            }
        }
    }

    private var addonRevision: String {
        auth.addons.map(\.transportUrl).joined(separator: "|")
    }

    private var contentRevision: String {
        "\(addonRevision)-\(showAllRows)-\(refreshRevision)"
    }

    private var featured: MetaItem? {
        focusedPreview ?? auth.continueWatching.first?.meta
            ?? rows.lazy.flatMap(\.items).first(where: { $0.background != nil })
            ?? rows.first?.items.first
    }
}

private struct HarborDesktopHero: View {
    let item: MetaItem
    let onSearch: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            HarborPreviewArtwork(item: item, maxPixelSize: 2200, hero: true)
                .id(item.contentKey)
                .frame(maxWidth: .infinity)
                .frame(height: 520)

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
                        .font(.system(size: 62, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: 720, alignment: .leading)

                HStack(spacing: 12) {
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
                        Label("Watch options", systemImage: "play.fill")
                    }
                    .buttonStyle(HarborActionButtonStyle(tone: .primary))
                }
            }
            .padding(.leading, HarborTVDesign.pageInset)
            .padding(.bottom, 58)
        }
        .frame(height: 520)
        .clipped()
        .accessibilityIdentifier("home.preview.\(item.contentKey)")
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
    var onFocus: (MetaItem) -> Void = { _ in }
    let onRemove: (CwItem) -> Void
    @FocusState private var focusedID: String?
    @State private var lastFocusedID: String?

    var body: some View {
        let previewID = TVFocusPresentation.previewID(focused: nil,
            previous: lastFocusedID, available: entries.map(\.id))
        VStack(alignment: .leading, spacing: 16) {
            HarborSectionHeading(title: "Continue Watching")
                .padding(.horizontal, 60)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 32) {
                        ForEach(entries) { entry in
                            let expanded = entry.id == previewID
                            ContinueCard(entry: entry, focus: $focusedID, width: expanded ? 560 : 210,
                                         compact: !expanded, onRemove: { onRemove(entry) })
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .onChange(of: lastFocusedID) { _, value in
                    // Recheck visibility after the focused card expands.
                    if let value, focusedID == value { proxy.scrollTo(value) }
                }
            }
        }
        .focusSection()
        .task(id: focusedID) {
            guard let focusedID else { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled,
                  let id = TVFocusPresentation.previewID(focused: focusedID,
                      previous: lastFocusedID, available: entries.map(\.id)),
                  let entry = entries.first(where: { $0.id == id }) else { return }
            lastFocusedID = id
            onFocus(entry.meta)
        }
    }
}

struct CatalogRowView: View {
    let row: CatalogRow
    let onFocus: (MetaItem) -> Void
    @EnvironmentObject private var auth: AuthStore
    @State private var loadedItems: [MetaItem]
    @State private var nextSkip: Int
    @State private var loadingMore = false
    @State private var hasMore: Bool
    @FocusState private var focusedID: String?
    @State private var previewItem: MetaItem?
    @AppStorage(SubtitleStyle.Key.rowTitleScale) private var titleScale = 1.0
    @AppStorage(SubtitleStyle.Key.hideWatched) private var hideWatched = false
    @AppStorage(SubtitleStyle.Key.hideUnreleased) private var hideUnreleased = false

    init(row: CatalogRow, onFocus: @escaping (MetaItem) -> Void = { _ in }) {
        self.row = row
        self.onFocus = onFocus
        _loadedItems = State(initialValue: MetaItem.unique(row.items))
        _nextSkip = State(initialValue: row.items.count)
        _hasMore = State(initialValue: row.source != nil && !row.items.isEmpty)
        _previewItem = State(initialValue: row.items.first)
    }

    private var visibleItems: [MetaItem] {
        let watched: Set<String> = hideWatched ? Set(auth.libraryItems.filter {
            ($0.state?.flaggedWatched ?? 0) > 0 || $0.progressRatio >= 0.9
        }.map(\._id)) : []
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
        let items = visibleItems
        let previewID = TVFocusPresentation.previewID(focused: nil,
            previous: previewItem?.contentKey, available: items.map(\.contentKey))
        let loadAheadID = items.suffix(4).first?.contentKey
        VStack(alignment: .leading, spacing: 16) {
            HarborSectionHeading(title: row.title,
                                 scale: CGFloat(titleScale))
                .padding(.horizontal, 60)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 26) {
                        ForEach(items, id: \.contentKey) { item in
                            // The focused title owns the wide preview; identity/order stay
                            // stable while the neighboring titles return to portrait size.
                            let wide = item.contentKey == previewID
                            NavigationLink(value: item) {
                                HarborCatalogArtwork(item: item, wide: wide)
                            }
                            .buttonStyle(HarborCardFocusStyle())
                            .focused($focusedID, equals: item.contentKey)
                            .id(item.contentKey)
                            .accessibilityIdentifier("catalog.title.\(item.contentKey)")
                            .accessibilityValue(wide ? "Expanded preview" : "Poster")
                            .onAppear {
                                if item.contentKey == loadAheadID {
                                    Task { await loadMore() }
                                }
                            }
                        }
                        if hasMore, row.source != nil {
                            Button {
                                Task { await loadMore() }
                            } label: {
                                VStack(spacing: 12) {
                                    if loadingMore { ProgressView() }
                                    else { Image(systemName: "plus.circle").font(.system(size: 34)) }
                                    Text(loadingMore ? "Loading…" : "More titles")
                                }
                                .frame(width: 190, height: 270)
                            }
                            .buttonStyle(HarborCardFocusStyle())
                            // Remains focusable at the edge while the next batch loads.
                            .task { await loadMore() }
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .onChange(of: previewID) { _, value in
                    if let value, focusedID == value { proxy.scrollTo(value) }
                }
            }
            if let item = items.first(where: { $0.contentKey == previewID }) {
                HarborRailSynopsis(item: item)
                    .padding(.horizontal, 60)
            }
        }
        .focusSection()
        .task(id: focusedID) {
            guard let focusedID else { return }
            // Fast repeat-presses don't repeatedly replace large text subtrees.
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            let currentItems = visibleItems
            guard let id = TVFocusPresentation.previewID(focused: focusedID,
                      previous: previewItem?.contentKey, available: currentItems.map(\.contentKey)),
                  let item = currentItems.first(where: { $0.contentKey == id }) else { return }
            if previewItem?.contentKey != item.contentKey { previewItem = item }
            onFocus(item)
        }
    }

    private func loadMore() async {
        guard !loadingMore, hasMore, let source = row.source else { return }
        loadingMore = true
        let page = await AddonService.catalog(source: source, skip: nextSkip)
        guard !Task.isCancelled else { loadingMore = false; return }
        let fresh = MetaItem.unique(page, excluding: loadedItems)
        nextSkip += page.count
        if page.isEmpty || fresh.isEmpty {
            hasMore = false
        } else {
            loadedItems.append(contentsOf: fresh)
        }
        loadingMore = false
    }
}

private struct HarborCatalogArtwork: View {
    let item: MetaItem
    let wide: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if wide {
                HarborPreviewArtwork(item: item, maxPixelSize: 1200)
                LinearGradient(colors: [.clear, .black.opacity(0.86)],
                               startPoint: .center, endPoint: .bottom)
                Text(item.name)
                    .font(.system(size: 29, weight: .bold))
                    .lineLimit(2).padding(22)
            } else {
                HarborArtworkImage(url: item.poster, maxPixelSize: 640, fallbackText: item.name)
            }
        }
        .frame(width: wide ? 480 : 180, height: 270)
        .clipShape(RoundedRectangle(cornerRadius: HarborTVDesign.cardRadius))
        .accessibilityLabel(item.name)
    }
}

private struct HarborRailSynopsis: View {
    let item: MetaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                Text(item.name).fontWeight(.semibold).foregroundStyle(.white)
                Text(item.type == "movie" ? "Movie" : (item.type == "anime" ? "Anime" : "Series"))
                if let year = item.releaseInfo, !year.isEmpty { Text("·  \(year)") }
                if let rating = item.imdbRating, !rating.isEmpty { ImdbBadge(rating: rating) }
            }
            .font(.system(size: 18)).foregroundStyle(HarborTVDesign.secondaryText)
            .lineLimit(1)
            Text(item.description ?? "Explore this title for episodes and watch options.")
                .font(.system(size: 21)).foregroundStyle(HarborTVDesign.secondaryText)
                .lineLimit(2).lineSpacing(3)
        }
        .frame(maxWidth: 1040, alignment: .leading)
        .frame(height: 92, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}
