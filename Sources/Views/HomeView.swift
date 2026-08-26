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
                LazyVStack(alignment: .leading, spacing: 44) {
                    if let featured {
                        HarborDesktopHero(item: featured, onSearch: onSearch)
                    } else {
                        HarborHeroPlaceholder(onSearch: onSearch)
                    }

                    if !auth.continueWatching.isEmpty {
                        ContinueRowView(entries: auth.continueWatching)
                    }

                    if loading { ProgressView().padding(.horizontal, 60) }
                    ForEach(rows) { row in
                        CatalogRowView(row: row)
                    }
                }
                .padding(.bottom, 60)
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
                .frame(height: 530)

            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.045, green: 0.05, blue: 0.052).opacity(0.98), location: 0),
                    .init(color: .black.opacity(0.70), location: 0.34),
                    .init(color: .clear, location: 0.72),
                ], startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(colors: [.clear, .black.opacity(0.10), Color(red: 0.045, green: 0.05, blue: 0.052)],
                           startPoint: .top, endPoint: .bottom)

            searchChip

            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Text(item.name)
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: 680, alignment: .leading)

                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(3)
                        .frame(maxWidth: 690, alignment: .leading)
                }

                HStack(spacing: 14) {
                    if let release = item.releaseInfo, !release.isEmpty {
                        Text(release).foregroundStyle(.white.opacity(0.58))
                    }
                    if let rating = item.imdbRating, !rating.isEmpty { ImdbBadge(rating: rating) }
                    if let runtime = item.runtime, !runtime.isEmpty {
                        Text(runtime).foregroundStyle(.white.opacity(0.58))
                    }
                }
                .font(.system(size: 18, weight: .semibold))

                NavigationLink(value: item) {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 21, weight: .bold))
                        .padding(.horizontal, 25).padding(.vertical, 13)
                }
                .buttonStyle(HarborHeroButtonStyle())
            }
            .padding(.leading, 64)
            .padding(.bottom, 38)
        }
        .frame(height: 530)
        .clipped()
    }

    private var searchChip: some View {
        HStack {
            Spacer()
            Button(action: onSearch) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                    Text("Search movies, shows, people…")
                }
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .frame(width: 350, height: 46, alignment: .leading)
                .padding(.horizontal, 18)
                .background(Capsule().fill(.black.opacity(0.42)))
                .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 22)
    }
}

private struct HarborHeroPlaceholder: View {
    let onSearch: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.045, green: 0.05, blue: 0.052)
            Button(action: onSearch) {
                Label("Search movies, shows, people…", systemImage: "magnifyingglass")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 24).frame(height: 50)
                    .background(Capsule().fill(.white.opacity(0.055)))
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
        }
        .frame(height: 190)
    }
}

private struct HarborHeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HarborHeroButtonBody(configuration: configuration)
    }
}

private struct HarborHeroButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .foregroundStyle(focused ? .black : .white)
            .background(Capsule().fill(focused ? .white : .black.opacity(0.52)))
            .overlay(Capsule().stroke(.white.opacity(focused ? 0 : 0.24), lineWidth: 1))
            .scaleEffect(focused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

struct ContinueRowView: View {
    let entries: [CwItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Continue Watching")
                .font(.system(size: 30, weight: .semibold))
                .padding(.horizontal, 60)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 32) {
                    ForEach(entries) { entry in
                        ContinueCard(entry: entry)
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
    @AppStorage(SubtitleStyle.Key.rowTitleScale) private var titleScale = 1.0
    @AppStorage(SubtitleStyle.Key.hideWatched) private var hideWatched = false
    @AppStorage(SubtitleStyle.Key.hideUnreleased) private var hideUnreleased = false

    private var visibleItems: [MetaItem] {
        let watched = Set(auth.libraryItems.filter {
            ($0.state?.flaggedWatched ?? 0) > 0 || $0.progressRatio >= 0.9
        }.map(\._id))
        let currentYear = Calendar.current.component(.year, from: Date())
        return row.items.filter { item in
            if hideWatched && watched.contains(item.id) { return false }
            if hideUnreleased,
               let text = item.releaseInfo,
               let year = Int(text.prefix(4)), year > currentYear { return false }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(row.title)
                .font(.system(size: 30 * titleScale, weight: .semibold))
                .padding(.horizontal, 60)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 32) {
                    ForEach(visibleItems) { item in
                        PosterCard(item: item)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 12)
            }
        }
        .focusSection()
    }
}
