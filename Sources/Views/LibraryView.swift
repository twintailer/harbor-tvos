import SwiftUI

struct LibraryView: View {
    var onRootBack: () -> Void = {}
    @EnvironmentObject private var auth: AuthStore
    @AppStorage(SubtitleStyle.Key.libraryBookmarkedOnly) private var bookmarkedOnly = true
    @AppStorage(SubtitleStyle.Key.librarySort) private var sort = "recent"
    @State private var type = "all"
    @State private var scope = "watchlist"
    @State private var loading = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 6)

    private var items: [StremioService.LibraryItem] {
        var value = auth.libraryItems.filter { item in
            if type == "anime" {
                let anime = item.type == "anime" || item.isAnime == true || item._id.hasPrefix("kitsu:") || item._id.hasPrefix("mal:")
                if !anime { return false }
            } else if type != "all" && item.type != type { return false }
            let progress = item.progressRatio
            let hasHistory = (item.state?.flaggedWatched ?? 0) > 0 || progress > 0
            switch scope {
            case "history": return hasHistory
            case "all": return !(item.removed ?? false) || (item.temp ?? false)
            default:
                if item.removed ?? false { return false }
                if bookmarkedOnly && (item.temp ?? false) { return false }
                return !hasHistory
            }
        }
        switch sort {
        case "title": value.sort { ($0.name ?? "") < ($1.name ?? "") }
        case "year": value.sort { ($0.asMeta.releaseInfo ?? "") > ($1.asMeta.releaseInfo ?? "") }
        default: value.sort { ($0.state?.lastWatched ?? $0._mtime ?? "") > ($1.state?.lastWatched ?? $1._mtime ?? "") }
        }
        return value
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        HarborPageHeader(title: "My Library", eyebrow: "Saved for you",
                                         subtitle: "Your watchlist and viewing history",
                                         count: items.count)
                        Spacer()
                        if auth.isSignedIn {
                            Button {
                                loading = true
                                Task { await auth.loadLibrary(); loading = false }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(HarborActionButtonStyle(tone: .secondary))
                            .disabled(loading)
                        }
                    }

                    HStack(spacing: 14) {
                        Button("Watchlist") { scope = "watchlist" }
                            .buttonStyle(HarborFilterPillStyle(selected: scope == "watchlist"))
                        Button("History") { scope = "history" }
                            .buttonStyle(HarborFilterPillStyle(selected: scope == "history"))
                        Button("All") { scope = "all" }
                            .buttonStyle(HarborFilterPillStyle(selected: scope == "all"))
                    }

                    HStack(spacing: 14) {
                        Button("All titles") { type = "all" }
                            .buttonStyle(HarborFilterPillStyle(selected: type == "all"))
                        Button("Movies") { type = "movie" }
                            .buttonStyle(HarborFilterPillStyle(selected: type == "movie"))
                        Button("Series") { type = "series" }
                            .buttonStyle(HarborFilterPillStyle(selected: type == "series"))
                        Button("Anime") { type = "anime" }
                            .buttonStyle(HarborFilterPillStyle(selected: type == "anime"))
                    }

                    if !auth.isSignedIn {
                        HarborEmptyState(icon: "person.crop.circle",
                                         title: "Sign in to load your library",
                                         message: "Use Settings › Account to sign in.")
                    } else if loading && auth.libraryItems.isEmpty {
                        ProgressView().controlSize(.large).frame(maxWidth: .infinity)
                    } else if items.isEmpty {
                        HarborEmptyState(icon: "books.vertical",
                                         title: "Nothing here yet",
                                         message: scope == "history" ? "Finished and in-progress titles appear here." : "Save titles in Stremio and they will sync here.")
                    } else {
                        LazyVGrid(columns: columns, spacing: 40) {
                            ForEach(items, id: \._id) { item in
                                PosterCard(
                                    item: item.asMeta,
                                    width: 205,
                                    onRemoveFromHistory: scope == "history" ? {
                                        Task { await auth.removeFromHistory(item._id) }
                                    } : nil)
                            }
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 36)
            }
            .background(HarborStageBackground())
            .onExitCommand(perform: onRootBack)
            .navigationDestination(for: MetaItem.self) { DetailView(item: $0) }
        }
        .task { if auth.isSignedIn && auth.libraryItems.isEmpty { loading = true; await auth.loadLibrary(); loading = false } }
    }
}
