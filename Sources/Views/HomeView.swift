import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var rows: [CatalogRow] = []
    @State private var loading = true
    @AppStorage(SubtitleStyle.Key.homeShowAllRows) private var showAllRows = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    Text("Home")
                        .font(.system(size: 48, weight: .bold))
                        .padding(.horizontal, 60)
                        .padding(.top, 40)

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
