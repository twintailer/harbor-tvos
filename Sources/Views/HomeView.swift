import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var rows: [CatalogRow] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    Text("Harbor")
                        .font(.system(size: 56, weight: .bold))
                        .padding(.horizontal, 60)
                        .padding(.top, 40)

                    if !auth.continueWatching.isEmpty {
                        CatalogRowView(row: CatalogRow(title: "Continue Watching",
                                                       items: auth.continueWatching))
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
        .task(id: auth.addons.count) {
            await auth.loadContinueWatching()
            rows = await AddonService.homeRows(addons: auth.addons)
            loading = false
        }
    }
}

struct CatalogRowView: View {
    let row: CatalogRow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(row.title)
                .font(.system(size: 30, weight: .semibold))
                .padding(.horizontal, 60)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 32) {
                    ForEach(row.items) { item in
                        NavigationLink(value: item) {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 12)
            }
        }
    }
}
