import SwiftUI

struct DetailView: View {
    let item: MetaItem
    @State private var full: MetaItem?
    @State private var player: PlayerTarget?

    private var meta: MetaItem { full ?? item }

    var body: some View {
        ZStack {
            AsyncImage(url: URL(string: meta.background ?? meta.poster ?? "")) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { Color.black }
            .ignoresSafeArea()
            .overlay(LinearGradient(
                colors: [.black.opacity(0.2), .black.opacity(0.95)],
                startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer().frame(height: 420)
                    Text(meta.name).font(.system(size: 60, weight: .bold))
                    HStack(spacing: 18) {
                        if let y = meta.releaseInfo { Text(y) }
                        if let r = meta.imdbRating, !r.isEmpty { Text("★ \(r)") }
                        if let rt = meta.runtime { Text(rt) }
                    }
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)

                    HStack(spacing: 24) {
                        Button {
                            player = PlayerTarget(title: meta.name, url: DemoStream.url)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .padding(.horizontal, 20)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 8)

                    if let desc = meta.description {
                        Text(desc)
                            .font(.system(size: 26))
                            .frame(maxWidth: 1100, alignment: .leading)
                            .padding(.top, 12)
                    }

                    if let videos = meta.videos, !videos.isEmpty {
                        EpisodeList(meta: meta, videos: videos) { v in
                            player = PlayerTarget(title: v.title ?? meta.name, url: DemoStream.url)
                        }
                        .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 80)
            }
        }
        .fullScreenCover(item: $player) { target in
            PlayerView(target: target)
        }
        .task {
            if full == nil {
                full = await CatalogService.meta(type: item.type, id: item.id)
            }
        }
    }
}

struct EpisodeList: View {
    let meta: MetaItem
    let videos: [MetaItem.Video]
    let onPlay: (MetaItem.Video) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Episodes").font(.system(size: 32, weight: .semibold))
            ForEach(Array(videos.prefix(40).enumerated()), id: \.offset) { _, v in
                Button { onPlay(v) } label: {
                    HStack(spacing: 20) {
                        Image(systemName: "play.circle.fill").font(.system(size: 30))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episodeTitle(v)).font(.system(size: 24, weight: .medium))
                            if let ov = v.overview {
                                Text(ov).font(.system(size: 18)).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 1200, alignment: .leading)
    }

    private func episodeTitle(_ v: MetaItem.Video) -> String {
        if let s = v.season, let e = v.episode {
            return "S\(s)·E\(e)  \(v.title ?? "")"
        }
        return v.title ?? "Episode"
    }
}
