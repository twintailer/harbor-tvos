import SwiftUI

// Poster card in the Windows-app style: artwork only inside the focusable card
// (so the .card focus platter is JUST the poster, no grey text footer), with the
// IMDb rating as a yellow badge overlaid bottom-left ON the poster and the title
// as plain small text below the card.
struct PosterCard: View {
    let item: MetaItem
    var width: CGFloat = 240

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: item) {
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: URL(string: item.poster ?? "")) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        case .empty:
                            ZStack { Color.white.opacity(0.06); ProgressView() }
                        default:
                            ZStack {
                                Color.white.opacity(0.06)
                                Text(item.name)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .multilineTextAlignment(.center)
                                    .padding(8)
                            }
                        }
                    }
                    .frame(width: width, height: width * 3 / 2)

                    if let rating = item.imdbRating, !rating.isEmpty {
                        ImdbBadge(rating: rating)
                            .padding(10)
                    }
                }
                .frame(width: width, height: width * 3 / 2)
            }
            .buttonStyle(.card)

            Text(item.name)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }
}

/// The Windows-app IMDb chip: yellow "IMDb" tag + rating on a dark pill.
struct ImdbBadge: View {
    let rating: String

    var body: some View {
        HStack(spacing: 6) {
            Text("IMDb")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.black)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.96, green: 0.78, blue: 0.09)))
            Text(rating)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.72)))
    }
}

/// Continue-Watching card in the Windows style: landscape art, a "▶ S1E5" pill +
/// episode info on a bottom gradient, and a thin progress bar along the bottom edge.
struct ContinueCard: View {
    let entry: CwItem
    var width: CGFloat = 400

    private var height: CGFloat { width * 9 / 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: entry.meta) {
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: URL(string: entry.meta.background ?? entry.meta.poster ?? "")) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Color.white.opacity(0.06)
                        }
                    }
                    .frame(width: width, height: height)

                    LinearGradient(colors: [.clear, .black.opacity(0.75)],
                                   startPoint: .center, endPoint: .bottom)

                    // "▶ S1E5" pill like the Windows CW rail.
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                            if let s = entry.season, let e = entry.episode {
                                Text("S\(s)E\(e)").font(.system(size: 15, weight: .bold))
                            } else {
                                Text("Resume").font(.system(size: 15, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(.black.opacity(0.6)))
                    }
                    .padding(12)
                    .padding(.bottom, 6)

                    // Progress along the very bottom.
                    if entry.progress > 0.01 {
                        VStack(spacing: 0) {
                            Spacer()
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(.white.opacity(0.25))
                                    Rectangle().fill(.green)
                                        .frame(width: geo.size.width * entry.progress)
                                }
                            }
                            .frame(height: 5)
                        }
                        .frame(width: width, height: height)
                    }
                }
                .frame(width: width, height: height)
            }
            .buttonStyle(.card)

            Text(entry.meta.name)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
    }
}
