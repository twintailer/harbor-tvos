import SwiftUI

struct DetailView: View {
    let item: MetaItem
    @EnvironmentObject private var auth: AuthStore
    @State private var full: MetaItem?
    @State private var player: PlayerTarget?
    @State private var pickerStreams: [StreamOption]?
    @State private var resolving = false
    @State private var libItem: StremioService.LibraryItem?
    @State private var selectedSeason: Int?

    private var meta: MetaItem { full ?? item }

    // Resolve streams for a movie or a specific episode via the user's addons,
    // then auto-play the first direct one — or show a picker.
    private func play(streamId: String, title: String) {
        guard !auth.addons.isEmpty else { pickerStreams = []; return }
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
                            play(streamId: resumeStreamId ?? meta.id, title: meta.name)
                        } label: {
                            Label(playLabelText, systemImage: "play.fill")
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
                        SeriesEpisodes(
                            meta: meta, videos: videos,
                            selectedSeason: selectedSeasonBinding(videos),
                            watched: watchedState) { v in
                                let sid = (v.season != nil && v.episode != nil)
                                    ? "\(meta.id):\(v.season!):\(v.episode!)"
                                    : (v.id ?? meta.id)
                                play(streamId: sid, title: episodeFullTitle(v))
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
            if item.type == "series", auth.isSignedIn, let key = auth.authKey {
                libItem = await AddonService.libraryItem(authKey: key, id: item.id)
            }
        }
    }

    // MARK: - Play button label / resume

    private var playLabelText: String {
        if resolving { return "Finding streams…" }
        if item.type == "series", let s = libItem?.state, let se = s.season, let ep = s.episode {
            return "Resume S\(se)·E\(ep)"
        }
        if (libItem?.state?.timeOffset ?? 0) > 0 { return "Resume" }
        return "Play"
    }

    /// For a series, resume the current episode from the library state; otherwise the movie id.
    private var resumeStreamId: String? {
        guard item.type == "series", let s = libItem?.state else { return nil }
        if let vid = s.video_id, !vid.isEmpty { return vid }
        if let se = s.season, let ep = s.episode { return "\(meta.id):\(se):\(ep)" }
        return nil
    }

    private func episodeFullTitle(_ v: MetaItem.Video) -> String {
        if let s = v.season, let e = v.episode {
            return "\(meta.name) · S\(s)E\(e) · \(v.title ?? "")"
        }
        return v.title ?? meta.name
    }

    // MARK: - Season selection + per-episode watched state

    private func selectedSeasonBinding(_ videos: [MetaItem.Video]) -> Binding<Int> {
        let seasons = Array(Set(videos.compactMap { $0.season })).sorted()
        let current = selectedSeason
            ?? libItem?.state?.season
            ?? seasons.first(where: { $0 > 0 })
            ?? seasons.first ?? 1
        return Binding(get: { current }, set: { selectedSeason = $0 })
    }

    /// Approximate per-episode watched/progress from the single library state: episodes before the
    /// current one are watched; the current one shows its progress ratio.
    private func watchedState(_ v: MetaItem.Video) -> EpisodeProgress {
        guard let s = libItem?.state, let curSeason = s.season, let curEp = s.episode,
              let vs = v.season, let ve = v.episode else {
            return .init(watched: false, ratio: 0, current: false)
        }
        if vs < curSeason || (vs == curSeason && ve < curEp) {
            return .init(watched: true, ratio: 0, current: false)
        }
        if vs == curSeason && ve == curEp {
            let ratio = (libItem?.progressRatio ?? 0)
            return .init(watched: ratio >= 0.9, ratio: ratio, current: true)
        }
        return .init(watched: false, ratio: 0, current: false)
    }
}

struct EpisodeProgress { let watched: Bool; let ratio: Double; let current: Bool }

// MARK: - Windows-style episode overview

struct SeriesEpisodes: View {
    let meta: MetaItem
    let videos: [MetaItem.Video]
    @Binding var selectedSeason: Int
    let watched: (MetaItem.Video) -> EpisodeProgress
    let onPlay: (MetaItem.Video) -> Void

    @AppStorage(SubtitleStyle.Key.episodeSort) private var episodeSort = "oldest"

    private var seasons: [Int] { Array(Set(videos.compactMap { $0.season })).sorted() }
    private var episodesInSeason: [MetaItem.Video] {
        let sorted = videos.filter { ($0.season ?? 1) == selectedSeason }
            .sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
        return episodeSort == "newest" ? Array(sorted.reversed()) : sorted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Episodes").font(.system(size: 34, weight: .bold))
                Spacer()
                if seasons.count > 1 {
                    Menu {
                        ForEach(seasons, id: \.self) { s in
                            Button("Season \(s)") { selectedSeason = s }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Season \(selectedSeason)")
                            Image(systemName: "chevron.down")
                        }
                        .font(.system(size: 24, weight: .semibold))
                    }
                }
            }

            ForEach(Array(episodesInSeason.enumerated()), id: \.offset) { _, v in
                EpisodeRowTV(meta: meta, video: v, progress: watched(v)) { onPlay(v) }
            }
        }
        .frame(maxWidth: 1400, alignment: .leading)
    }
}

struct EpisodeRowTV: View {
    let meta: MetaItem
    let video: MetaItem.Video
    let progress: EpisodeProgress
    let onPlay: () -> Void

    @AppStorage(SubtitleStyle.Key.showEpisodeDesc) private var showEpisodeDesc = true

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 28) {
                ZStack(alignment: .topLeading) {
                    AsyncImage(url: URL(string: video.thumbnail ?? "")) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        ZStack { Color.white.opacity(0.06); Image(systemName: "play.circle").font(.system(size: 30)).foregroundStyle(.white.opacity(0.5)) }
                    }
                    .frame(width: 300, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // Episode-number badge.
                    if let e = video.episode {
                        Text("\(e)")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(.black)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(.white.opacity(0.95)))
                            .padding(8)
                    }
                    // Watched check.
                    if progress.watched {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .heavy)).foregroundStyle(.green)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(.green.opacity(0.22)))
                            .overlay(Circle().stroke(.green.opacity(0.5), lineWidth: 1))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(8)
                    }
                    // Progress bar.
                    if progress.ratio > 0.01 {
                        VStack {
                            Spacer()
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(.black.opacity(0.55)).frame(height: 4)
                                    Rectangle().fill(.green).frame(width: geo.size.width * progress.ratio, height: 4)
                                }
                            }
                            .frame(height: 4)
                        }
                        .frame(width: 300, height: 168)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(video.title ?? "Episode \(video.episode ?? 0)")
                        .font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1)
                    Text(metaLine)
                        .font(.system(size: 19)).foregroundStyle(.white.opacity(0.6))
                    if showEpisodeDesc, let ov = video.overview, !ov.isEmpty {
                        Text(ov)
                            .font(.system(size: 20)).foregroundStyle(.white.opacity(0.75))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.card)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let s = video.season, let e = video.episode { parts.append("S\(s) E\(e)") }
        if let d = formattedDate { parts.append(d) }
        var line = parts.joined(separator: "  ·  ")
        if progress.watched { line += "   ·  Watched" }
        else if progress.ratio > 0.01 { line += "   ·  \(Int(progress.ratio * 100))% watched" }
        return line
    }

    private var formattedDate: String? {
        guard let released = video.released else { return nil }
        let iso = ISO8601DateFormatter()
        let date = iso.date(from: released) ?? {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: String(released.prefix(10)))
        }()
        guard let date else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "de_DE")
        out.dateFormat = "d. MMMM yyyy"
        return out.string(from: date)
    }
}
