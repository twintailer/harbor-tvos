import SwiftUI

/// Independent of Continue Watching and rail focus. The catalog's first ten
/// unique titles retain their ranking while richer artwork is fetched on demand.
struct HarborSpotlight: View {
    let items: [MetaItem]
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var visible = false
    @State private var manualRevision = 0
    @State private var enriched: [String: MetaItem] = [:]
    @State private var logo: UIImage?
    @FocusState private var focused: Control?

    private enum Control: Hashable { case details, previous, next, page(Int) }
    private var currentIndex: Int { min(index, max(0, items.count - 1)) }
    private var item: MetaItem { items[currentIndex] }
    private var meta: MetaItem { enriched[item.contentKey] ?? item }
    private var canAutoRotate: Bool {
        visible && scenePhase == .active && focused == nil && !reduceMotion && items.count > 1
    }
    private var timerKey: String {
        items.map(\.contentKey).joined(separator: "|") + "|\(manualRevision)|\(canAutoRotate)"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HarborPreviewArtwork(item: meta, maxPixelSize: 2200, hero: true)
            LinearGradient(stops: [
                .init(color: HarborTVDesign.canvas, location: 0),
                .init(color: HarborTVDesign.canvas.opacity(0.90), location: 0.30),
                .init(color: .black.opacity(0.18), location: 0.68),
                .init(color: .clear, location: 1)
            ], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, HarborTVDesign.canvas], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 18) {
                Label("TOP 10  ·  #\(currentIndex + 1)", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .bold)).tracking(1.5)
                    .foregroundStyle(.white.opacity(0.8))
                if let logo {
                    Image(uiImage: logo).resizable().scaledToFit()
                        .frame(maxWidth: 460, maxHeight: 100, alignment: .leading)
                        .accessibilityLabel(meta.name)
                } else {
                    Text(meta.name).font(.system(size: 54, weight: .bold))
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .frame(maxWidth: 670, alignment: .leading)
                }
                Text(meta.description ?? item.description ?? "Explore this title and available watch options.")
                    .font(.system(size: 21)).foregroundStyle(.white.opacity(0.72))
                    .lineLimit(3).lineSpacing(4)
                    .frame(maxWidth: 650, alignment: .leading)
                HStack(spacing: 16) {
                    if let year = meta.releaseInfo { Text(year) }
                    Text(meta.type == "movie" ? "Movie" : "Series")
                    if let rating = meta.imdbRating { ImdbBadge(rating: rating) }
                }
                .font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                NavigationLink(value: meta) { Label("Watch options", systemImage: "play.fill") }
                    .buttonStyle(HarborActionButtonStyle(tone: .primary))
                    .focused($focused, equals: .details)
                    .accessibilityIdentifier("spotlight.details")
                    .accessibilityValue(item.contentKey)
            }
            .padding(.leading, 60).padding(.bottom, 102).padding(.top, 32)

            HStack(spacing: 14) {
                Text("Harbor Spotlight").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Button { move(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(HarborNavigationTabStyle(compact: true))
                    .focused($focused, equals: .previous)
                    .accessibilityLabel("Previous spotlight")
                    .accessibilityIdentifier("spotlight.previous")
                HStack(spacing: 4) {
                    ForEach(items.indices, id: \.self) { page in
                        Button { choose(page) } label: {
                            Capsule().fill(.white.opacity(page == currentIndex ? 1 : 0.35))
                                .frame(width: page == currentIndex ? 26 : 10, height: 5)
                                .frame(width: 30, height: 38)
                        }
                        .buttonStyle(SpotlightIndicatorStyle())
                        .focused($focused, equals: .page(page))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(focused == .page(page) ? 0.9 : 0), lineWidth: 2))
                        .accessibilityLabel("Spotlight \(page + 1): \(items[page].name)")
                        .accessibilityIdentifier("spotlight.page.\(page)")
                    }
                }
                Button { move(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(HarborNavigationTabStyle(compact: true))
                    .focused($focused, equals: .next)
                    .accessibilityLabel("Next spotlight")
                    .accessibilityIdentifier("spotlight.next")
                Spacer()
                Text("\(currentIndex + 1) / \(items.count)")
                    .font(.system(size: 17, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .accessibilityIdentifier("spotlight.position")
            }
            .padding(.horizontal, 60).padding(.bottom, 18)
            .focusSection()
        }
        .frame(height: 540)
        .clipped()
        .focusSection()
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onChange(of: focused) { _, value in
            if case let .page(page) = value { choose(page) }
        }
        .onChange(of: items.map(\.contentKey)) { _, _ in
            index = 0; enriched = [:]; logo = nil
        }
        .task(id: timerKey) {
            // Environment values are captured when a task starts. Restart it on
            // activation/focus changes instead of retaining an inactive scene.
            guard canAutoRotate else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                index = SpotlightPresentation.advance(index: currentIndex, by: 1, count: items.count)
            }
        }
        .task(id: item.contentKey) {
            let selected = item
            logo = nil
            if enriched[selected.contentKey] == nil,
               let full = await AddonService.meta(addons: auth.addons, type: selected.type, id: selected.id),
               !Task.isCancelled {
                enriched[selected.contentKey] = MetaItem(
                    id: selected.id, type: selected.type, name: full.name,
                    poster: full.poster ?? selected.poster, background: full.background ?? selected.background,
                    description: full.description ?? selected.description,
                    releaseInfo: full.releaseInfo ?? selected.releaseInfo,
                    imdbRating: full.imdbRating ?? selected.imdbRating, genres: full.genres ?? selected.genres,
                    runtime: full.runtime ?? selected.runtime, videos: full.videos ?? selected.videos,
                    logo: full.logo ?? selected.logo)
            }
            guard !Task.isCancelled else { return }
            let loaded = await HarborArtworkCache.shared.image(
                for: enriched[selected.contentKey]?.logo ?? selected.logo, maxPixelSize: 900)
            guard !Task.isCancelled else { return }
            logo = loaded
        }
    }

    private func move(_ offset: Int) {
        choose(SpotlightPresentation.advance(index: currentIndex, by: offset, count: items.count))
    }

    private func choose(_ page: Int) {
        guard items.indices.contains(page) else { return }
        manualRevision += 1
        index = page
    }
}

/// tvOS's plain style adds padding that overlaps neighboring small indicators.
private struct SpotlightIndicatorStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
    }
}
