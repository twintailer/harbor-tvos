import SwiftUI

struct DetailView: View {
    let item: MetaItem
    @EnvironmentObject private var auth: AuthStore
    @State private var full: MetaItem?
    @State private var player: PlayerTarget?
    @State private var pickerStreams: [StreamOption]?
    @State private var resolving = false

    private var meta: MetaItem { full ?? item }

    // Resolve streams for a movie or a specific episode via the user's addons,
    // then auto-play the first direct one — or show a picker.
    private func play(streamId: String, title: String) {
        guard !auth.addons.isEmpty else {
            // Not signed in / no addons: nothing to resolve.
            pickerStreams = []
            return
        }
        resolving = true
        Task {
            let streams = await StreamResolver.streams(
                addons: auth.addons, type: meta.type, id: streamId)
            await MainActor.run {
                resolving = false
                if let first = streams.first(where: { $0.isPlayable }), let u = URL(string: first.url ?? "") {
                    player = PlayerTarget(title: title, url: u)
                } else {
                    pickerStreams = streams
                }
            }
        }
    }

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
                            play(streamId: meta.id, title: meta.name)
                        } label: {
                            Label(resolving ? "Finding streams…" : "Play", systemImage: "play.fill")
                                .padding(.horizontal, 20)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(resolving)
                    }
                    .padding(.top, 8)
                    if !auth.isSignedIn {
                        Text("Sign in (Account tab) to load streams from your addons.")
                            .font(.system(size: 20)).foregroundStyle(.secondary)
                    }

                    if let desc = meta.description {
                        Text(desc)
                            .font(.system(size: 26))
                            .frame(maxWidth: 1100, alignment: .leading)
                            .padding(.top, 12)
                    }

                    if let videos = meta.videos, !videos.isEmpty {
                        EpisodeList(meta: meta, videos: videos) { v in
                            // Stremio stream id for an episode: imdbId:season:episode
                            let sid = (v.season != nil && v.episode != nil)
                                ? "\(meta.id):\(v.season!):\(v.episode!)"
                                : (v.id ?? meta.id)
                            play(streamId: sid, title: v.title ?? meta.name)
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
        .sheet(isPresented: Binding(get: { pickerStreams != nil }, set: { if !$0 { pickerStreams = nil } })) {
            StreamsView(title: meta.name, streams: pickerStreams ?? []) { s in
                pickerStreams = nil
                if let u = URL(string: s.url ?? "") { player = PlayerTarget(title: meta.name, url: u) }
            }
        }
        .task {
            if full == nil {
                full = await AddonService.meta(addons: auth.addons, type: item.type, id: item.id)
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
