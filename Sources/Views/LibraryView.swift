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
                        Text("Library").font(.system(size: 52, weight: .bold))
                        Spacer()
                        if auth.isSignedIn {
                            Button {
                                loading = true
                                Task { await auth.loadLibrary(); loading = false }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .disabled(loading)
                        }
                    }

                    Picker("Section", selection: $scope) {
                        Text("Watchlist").tag("watchlist")
                        Text("History").tag("history")
                        Text("All").tag("all")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 660)

                    Picker("Type", selection: $type) {
                        Text("All").tag("all")
                        Text("Movies").tag("movie")
                        Text("Series").tag("series")
                        Text("Anime").tag("anime")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 660)

                    if !auth.isSignedIn {
                        ContentUnavailableView("Sign in to load your library",
                                               systemImage: "person.crop.circle",
                                               description: Text("Use Settings › Account to sign in."))
                    } else if loading && auth.libraryItems.isEmpty {
                        ProgressView().controlSize(.large).frame(maxWidth: .infinity)
                    } else if items.isEmpty {
                        ContentUnavailableView("Nothing here yet",
                                               systemImage: "books.vertical",
                                               description: Text(scope == "history" ? "Finished and in-progress titles appear here." : "Save titles in Stremio and they will sync here."))
                    } else {
                        LazyVGrid(columns: columns, spacing: 40) {
                            ForEach(items, id: \._id) { item in
                                PosterCard(item: item.asMeta, width: 200)
                            }
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 36)
            }
            .onExitCommand(perform: onRootBack)
            .navigationDestination(for: MetaItem.self) { DetailView(item: $0) }
        }
        .task { if auth.isSignedIn && auth.libraryItems.isEmpty { loading = true; await auth.loadLibrary(); loading = false } }
    }
}
