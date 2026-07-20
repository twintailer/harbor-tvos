import SwiftUI

// Focus-aware poster. The tvOS focus engine scales/highlights the whole card
// via .buttonStyle(.card) at the call site; here we just render art + title.
struct PosterCard: View {
    let item: MetaItem
    var width: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AsyncImage(url: URL(string: item.poster ?? "")) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                case .empty:
                    ZStack { Color.gray.opacity(0.2); ProgressView() }
                default:
                    ZStack {
                        Color.gray.opacity(0.2)
                        Text(item.name)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(8)
                    }
                }
            }
            .frame(width: width, height: width * 3 / 2)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Text(item.name)
                .font(.system(size: 22, weight: .medium))
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
            if let rating = item.imdbRating, !rating.isEmpty {
                Text("★ \(rating)")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
