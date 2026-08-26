import SwiftUI

// Stream picker shown when Play can't auto-start a single direct stream.
struct StreamsView: View {
    let title: String
    let streams: [StreamOption]
    let onPick: (StreamOption) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SubtitleStyle.Key.fullStreamDescription) private var fullDescription = true
    @AppStorage(SubtitleStyle.Key.pickerShowFilename) private var showFilename = false

    var body: some View {
        NavigationStack {
            List {
                if streams.isEmpty {
                    Text("No streams found. Sign in and install stream addons (e.g. Torrentio + a debrid service) in the Stremio app.")
                        .foregroundStyle(.secondary)
                }
                ForEach(streams) { s in
                    Button {
                        onPick(s)
                    } label: {
                        HStack {
                            Image(systemName: s.isPlayable ? "play.circle.fill" : (s.isResolvable ? "network" : "arrow.down.circle"))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.displayName.isEmpty ? "Stream" : s.displayName)
                                    .font(.system(size: 26, weight: .medium))
                                    .lineLimit(fullDescription ? 3 : 1)
                                if fullDescription, !s.detailText.isEmpty,
                                   s.detailText != s.displayName {
                                    Text(s.detailText)
                                        .font(.system(size: 19))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                                if showFilename, let filename = s.filename, !filename.isEmpty {
                                    Text(filename)
                                        .font(.system(size: 17, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                if !s.isPlayable {
                                    Text(s.isResolvable ? "Torrent · plays through TorrServer" : "Torrent · configure TorrServer or debrid")
                                        .font(.system(size: 18)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .disabled(!s.isResolvable)
                }
            }
            .navigationTitle("Streams — \(title)")
        }
    }
}
