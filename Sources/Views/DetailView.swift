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
    @State private var pendingStreamId = ""
    @State private var pendingTitle = ""
    @State private var pendingVideo: MetaItem.Video?
    @State private var changingBookmark = false
    @State private var streamError: String?
    @AppStorage(SubtitleStyle.Key.instantPlay) private var instantPlay = true
    @AppStorage(SubtitleStyle.Key.rememberStream) private var rememberStream = true
    @AppStorage(SubtitleStyle.Key.resume) private var resumePlayback = true

    private var meta: MetaItem { full ?? item }

    // Resolve streams for a movie or a specific episode via the user's addons,
    // then auto-play the first direct one — or show a picker.
    private func play(streamId: String, title: String, video: MetaItem.Video? = nil) {
        guard !auth.addons.isEmpty else { pickerStreams = []; return }
        pendingStreamId = streamId
        pendingTitle = title
        pendingVideo = video
        resolving = true
        Task {
            let streams = await StreamResolver.streams(
                addons: auth.addons, type: meta.type, id: streamId)
            await MainActor.run {
                resolving = false
                let remembered = rememberStream
                    ? UserDefaults.standard.string(forKey: lastStreamKey(streamId))
                        .flatMap { id in streams.first { $0.id == id && $0.isResolvable } }
                    : nil
                if instantPlay, let first = remembered ?? streams.first(where: { $0.isResolvable }) {
                    open(stream: first, streamId: streamId, title: title, video: video)
                } else {
                    pickerStreams = streams
                }
            }
        }
    }

    var body: some View {
        ZStack {
            HarborArtworkImage(url: meta.background ?? meta.poster,
                               maxPixelSize: 2200)
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
                            if let episode = playButtonEpisode {
                                play(streamId: streamID(for: episode),
                                     title: episodeFullTitle(episode), video: episode)
                            } else {
                                play(streamId: meta.id, title: meta.name)
                            }
                        } label: {
                            Label(playLabelText, systemImage: "play.fill")
                                .padding(.horizontal, 20)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(resolving)
                        if auth.isSignedIn {
                            Button {
                                toggleBookmark()
                            } label: {
                                Label(isBookmarked ? "In Library" : "Add to Library",
                                      systemImage: isBookmarked ? "checkmark" : "plus")
                            }
                            .buttonStyle(.bordered)
                            .disabled(changingBookmark)
                        }
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
                                play(streamId: streamID(for: v), title: episodeFullTitle(v), video: v)
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
                if rememberStream { UserDefaults.standard.set(s.id, forKey: lastStreamKey(pendingStreamId)) }
                open(stream: s, streamId: pendingStreamId,
                     title: pendingTitle.isEmpty ? meta.name : pendingTitle,
                     video: pendingVideo)
            }
        }
        .alert("Stream unavailable", isPresented: Binding(
            get: { streamError != nil }, set: { if !$0 { streamError = nil } })) {
                Button("OK", role: .cancel) { streamError = nil }
            } message: {
                Text(streamError ?? "The selected source could not be opened.")
            }
        .task {
            if full == nil {
                full = await AddonService.meta(addons: auth.addons, type: item.type, id: item.id)
            }
            // A user meta addon may serve rich text/art but no episode list. Series need
            // episodes to be playable, so backfill videos from Cinemeta when they're missing.
            if item.type == "series", (full?.videos ?? []).isEmpty,
               let cine = await CatalogService.meta(type: item.type, id: item.id),
               let vids = cine.videos, !vids.isEmpty {
                full = (full ?? cine).withVideos(vids)
            }
            if auth.isSignedIn, let key = auth.authKey {
                libItem = await StremioService.libraryItem(authKey: key, id: item.id)
            }
        }
    }

    // MARK: - Play button label / resume

    private var playLabelText: String {
        if resolving { return "Finding streams…" }
        if !resumePlayback { return "Play" }
        // Only claim a resumable episode when the state actually names one (S0·E0 = none).
        if item.type != "movie", let se = libItem?.seasonEpisode, se.episode > 0 {
            return "Resume S\(se.season)·E\(se.episode)"
        }
        if (libItem?.state?.timeOffset ?? 0) > 0 { return "Resume" }
        return "Play"
    }

    private var isBookmarked: Bool {
        guard let libItem else { return false }
        return !(libItem.removed ?? false) && !(libItem.temp ?? false)
    }

    private func toggleBookmark() {
        guard let key = auth.authKey else { return }
        changingBookmark = true
        Task {
            await StremioService.setBookmarked(authKey: key, meta: meta, existing: libItem,
                                               bookmarked: !isBookmarked)
            libItem = await StremioService.libraryItem(authKey: key, id: meta.id)
            await auth.loadLibrary()
            changingBookmark = false
        }
    }

    private func episodeFullTitle(_ v: MetaItem.Video) -> String {
        if let s = v.season, let e = v.episode {
            return "\(meta.name) · S\(s)E\(e) · \(v.title ?? "")"
        }
        return v.title ?? meta.name
    }

    private func streamID(for video: MetaItem.Video) -> String {
        if let season = video.season, let episode = video.episode {
            return "\(meta.id):\(season):\(episode)"
        }
        return video.id ?? meta.id
    }

    private var playButtonEpisode: MetaItem.Video? {
        guard meta.type != "movie", let videos = meta.videos, !videos.isEmpty else { return nil }
        if resumePlayback, let currentID = libItem?.state?.video_id,
           let current = videos.first(where: { streamID(for: $0) == currentID || $0.id == currentID }) {
            return current
        }
        if resumePlayback, let current = libItem?.seasonEpisode,
           let video = videos.first(where: { $0.season == current.season && $0.episode == current.episode }) {
            return video
        }
        return videos
            .filter { ($0.season ?? 0) > 0 && ($0.episode ?? 0) > 0 }
            .sorted {
                let leftSeason = $0.season ?? 0
                let rightSeason = $1.season ?? 0
                return leftSeason == rightSeason
                    ? ($0.episode ?? 0) < ($1.episode ?? 0)
                    : leftSeason < rightSeason
            }
            .first ?? videos.first
    }

    private var isAnime: Bool {
        meta.type == "anime" || meta.id.hasPrefix("kitsu:") || meta.id.hasPrefix("mal:") ||
            (meta.genres ?? []).contains {
                $0.localizedCaseInsensitiveContains("anime") || $0.localizedCaseInsensitiveContains("animation")
            }
    }

    private func lastStreamKey(_ streamId: String) -> String {
        "harbor.lastStream.\(meta.id).\(streamId)"
    }

    private func open(stream: StreamOption, streamId: String, title: String,
                      video: MetaItem.Video?) {
        if let raw = stream.url, let url = URL(string: raw) {
            player = makeTarget(stream: stream, resolvedURL: url, streamId: streamId,
                                title: title, video: video)
            return
        }
        guard let hash = stream.infoHash, TorrServerService.isConfigured else {
            streamError = "This is a torrent-only source. Configure TorrServer in Settings → P2P & servers, or use a debrid-enabled add-on."
            return
        }
        resolving = true
        Task {
            let result = await TorrServerService.resolve(infoHash: hash, season: video?.season,
                                                         episode: video?.episode)
            await MainActor.run {
                resolving = false
                switch result {
                case .success(let url):
                    player = makeTarget(stream: stream, resolvedURL: url, streamId: streamId,
                                        title: title, video: video)
                case .notConfigured:
                    streamError = "TorrServer is not configured."
                case .failed(let message):
                    streamError = message
                }
            }
        }
    }

    private func makeTarget(stream: StreamOption, resolvedURL url: URL, streamId: String,
                            title: String, video: MetaItem.Video?) -> PlayerTarget {
        if rememberStream { UserDefaults.standard.set(stream.id, forKey: lastStreamKey(streamId)) }
        let state = libItem?.state
        let sameVideo = meta.type == "movie" || state?.video_id == streamId ||
            (state?.season == video?.season && state?.episode == video?.episode)
        let start = resumePlayback && sameVideo ? (state?.timeOffset ?? 0) / 1000 : 0
        let next = video.flatMap { nextEpisode(after: $0) }
        let playNext: (() -> Void)?
        if let next {
            playNext = {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    let id: String
                    if let season = next.season, let episode = next.episode {
                        id = "\(meta.id):\(season):\(episode)"
                    } else {
                        id = next.id ?? meta.id
                    }
                    play(streamId: id, title: episodeFullTitle(next), video: next)
                }
            }
        } else {
            playNext = nil
        }
        return PlayerTarget(
            title: title,
            url: url,
            startAt: start,
            isAnime: isAnime,
            contentID: meta.id,
            season: video?.season,
            episode: video?.episode,
            requestHeaders: stream.requestHeaders,
            onProgress: { position, duration in
                guard let key = auth.authKey else { return }
                Task {
                    await StremioService.saveProgress(
                        authKey: key, meta: meta, videoId: streamId,
                        season: video?.season, episode: video?.episode,
                        position: position, duration: duration, existing: libItem)
                    await auth.loadLibrary()
                    await auth.loadContinueWatching()
                }
            },
            onEnded: playNext)
    }

    private func nextEpisode(after video: MetaItem.Video) -> MetaItem.Video? {
        guard let videos = meta.videos, let season = video.season, let episode = video.episode else { return nil }
        let ordered = videos
            .filter { ($0.season ?? 0) > 0 && ($0.episode ?? 0) > 0 }
            .sorted {
                let leftSeason = $0.season ?? 0
                let rightSeason = $1.season ?? 0
                if leftSeason != rightSeason { return leftSeason < rightSeason }
                return ($0.episode ?? 0) < ($1.episode ?? 0)
            }
        guard let index = ordered.firstIndex(where: { $0.season == season && $0.episode == episode }),
              ordered.indices.contains(index + 1) else { return nil }
        return ordered[index + 1]
    }

    // MARK: - Season selection + per-episode watched state

    private func selectedSeasonBinding(_ videos: [MetaItem.Video]) -> Binding<Int> {
        let seasons = Array(Set(videos.compactMap { $0.season })).sorted()
        // Never default to season 0 (specials — often empty, which made the episode list look
        // missing entirely). Library season only counts when it's a real (>0, existing) season.
        let fromLibrary = libItem?.seasonEpisode?.season
        let current = selectedSeason
            ?? fromLibrary.flatMap { $0 > 0 && seasons.contains($0) ? $0 : nil }
            ?? seasons.first(where: { $0 > 0 })
            ?? seasons.first ?? 1
        return Binding(get: { current }, set: { selectedSeason = $0 })
    }

    /// Approximate per-episode watched/progress from the single library state: episodes before the
    /// current one are watched; the current one shows its progress ratio.
    private func watchedState(_ v: MetaItem.Video) -> EpisodeProgress {
        guard let se = libItem?.seasonEpisode, se.episode > 0,
              let vs = v.season, let ve = v.episode else {
            return .init(watched: false, ratio: 0, current: false)
        }
        let curSeason = se.season, curEp = se.episode
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

    @AppStorage(SubtitleStyle.Key.episodeSort) private var episodeSort = "aired"
    @AppStorage(SubtitleStyle.Key.episodeLayout) private var episodeLayout = "list"
    @AppStorage(SubtitleStyle.Key.hideWatched) private var hideWatched = false
    @AppStorage(SubtitleStyle.Key.hideUnreleased) private var hideUnreleased = false

    private var seasons: [Int] { Array(Set(videos.compactMap { $0.season })).sorted() }
    private var episodesInSeason: [MetaItem.Video] {
        let candidates = videos.filter {
            if episodeSort != "absolute", ($0.season ?? 1) != selectedSeason { return false }
            if episodeSort == "absolute", ($0.season ?? 0) <= 0 { return false }
            if hideWatched && watched($0).watched { return false }
            if hideUnreleased, let date = releaseDate($0.released), date > Date() { return false }
            return true
        }
        let sorted = candidates.sorted(by: airedBefore)
        return episodeSort == "newest" ? Array(sorted.reversed()) : sorted
    }

    private var orderTitle: String {
        switch episodeSort {
        case "absolute": return "Absolute"
        case "newest": return "Newest"
        default: return "Aired"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Episodes").font(.system(size: 34, weight: .bold))
                Spacer()
                if seasons.count > 1, episodeSort != "absolute" {
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
                Menu {
                    Button("Aired order") { episodeSort = "aired" }
                    Button("Absolute order") { episodeSort = "absolute" }
                    Button("Newest first") { episodeSort = "newest" }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(orderTitle)
                    }
                    .font(.system(size: 22, weight: .semibold))
                }
            }

            // Plain VStack, NOT LazyVStack: the tvOS focus engine can only move to views
            // that exist, and lazy rows below the fold are never instantiated — which made
            // the episode list unreachable ("can't go down"). Capped for render cost.
            if episodeLayout == "strip" {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 28) {
                        ForEach(Array(episodesInSeason.prefix(200).enumerated()), id: \.offset) { _, video in
                            EpisodeStripCard(video: video, progress: watched(video)) { onPlay(video) }
                        }
                    }
                    .padding(.vertical, 14)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(episodesInSeason.prefix(200).enumerated()), id: \.offset) { _, v in
                        EpisodeRowTV(meta: meta, video: v, progress: watched(v)) { onPlay(v) }
                    }
                }
            }
            if episodesInSeason.isEmpty {
                Text(episodeSort == "absolute" ? "No episodes available in absolute order." : "No episodes listed for this season.")
                    .font(.system(size: 20)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: 1400, alignment: .leading)
    }

    private func releaseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let date = ISO8601DateFormatter().date(from: raw) { return date }
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.dateFormat = "yyyy-MM-dd"
        return parser.date(from: String(raw.prefix(10)))
    }

    private func airedBefore(_ lhs: MetaItem.Video, _ rhs: MetaItem.Video) -> Bool {
        if let l = releaseDate(lhs.released), let r = releaseDate(rhs.released), l != r { return l < r }
        let ls = lhs.season ?? 0, rs = rhs.season ?? 0
        if ls != rs { return ls < rs }
        return (lhs.episode ?? 0) < (rhs.episode ?? 0)
    }
}

private struct EpisodeStripCard: View {
    let video: MetaItem.Video
    let progress: EpisodeProgress
    let onPlay: () -> Void
    @AppStorage(SubtitleStyle.Key.hideSpoilers) private var hideSpoilers = false
    @AppStorage(SubtitleStyle.Key.spoilerThumbnails) private var hideThumbnail = true
    @AppStorage(SubtitleStyle.Key.accent) private var accentID = "green"
    private var accent: Color { HarborSettings.accentColor(accentID) }

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    HarborArtworkImage(url: video.thumbnail, maxPixelSize: 900)
                    .frame(width: 360, height: 203)
                    .blur(radius: hideSpoilers && hideThumbnail ? 24 : 0)
                    if progress.ratio > 0.01 {
                        GeometryReader { proxy in
                            VStack { Spacer(); Rectangle().fill(accent).frame(width: proxy.size.width * progress.ratio, height: 5) }
                        }
                    }
                }
                .frame(width: 360, height: 203)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                Text(hideSpoilers ? "Episode \(video.episode ?? 0)" : (video.title ?? "Episode \(video.episode ?? 0)"))
                    .font(.system(size: 22, weight: .semibold)).lineLimit(1)
                if progress.watched { Label("Watched", systemImage: "checkmark.circle.fill").foregroundStyle(accent) }
            }
            .frame(width: 360, alignment: .leading)
        }
        .buttonStyle(.card)
    }
}

struct EpisodeRowTV: View {
    let meta: MetaItem
    let video: MetaItem.Video
    let progress: EpisodeProgress
    let onPlay: () -> Void

    @AppStorage(SubtitleStyle.Key.showEpisodeDesc) private var showEpisodeDesc = true
    @AppStorage(SubtitleStyle.Key.hideSpoilers) private var hideSpoilers = false
    @AppStorage(SubtitleStyle.Key.spoilerThumbnails) private var hideThumbnail = true
    @AppStorage(SubtitleStyle.Key.accent) private var accentID = "green"
    private var accent: Color { HarborSettings.accentColor(accentID) }

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 28) {
                ZStack(alignment: .topLeading) {
                    HarborArtworkImage(url: video.thumbnail, maxPixelSize: 800)
                    .frame(width: 300, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .blur(radius: hideSpoilers && hideThumbnail ? 24 : 0)

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
                            .font(.system(size: 14, weight: .heavy)).foregroundStyle(accent)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(accent.opacity(0.22)))
                            .overlay(Circle().stroke(accent.opacity(0.5), lineWidth: 1))
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
                                    Rectangle().fill(accent).frame(width: geo.size.width * progress.ratio, height: 4)
                                }
                            }
                            .frame(height: 4)
                        }
                        .frame(width: 300, height: 168)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(hideSpoilers ? "Episode \(video.episode ?? 0)" : (video.title ?? "Episode \(video.episode ?? 0)"))
                        .font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1)
                    Text(metaLine)
                        .font(.system(size: 19)).foregroundStyle(.white.opacity(0.6))
                    if showEpisodeDesc, !hideSpoilers, let ov = video.overview, !ov.isEmpty {
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
