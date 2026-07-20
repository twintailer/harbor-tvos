import SwiftUI

// Stream picker shown when Play can't auto-start a single direct stream.
struct StreamsView: View {
    let title: String
    let streams: [StreamOption]
    let onPick: (StreamOption) -> Void
    @Environment(\.dismiss) private var dismiss

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
                            Image(systemName: s.isPlayable ? "play.circle.fill" : "arrow.down.circle")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.displayName.isEmpty ? "Stream" : s.displayName)
                                    .font(.system(size: 26, weight: .medium))
                                if !s.isPlayable {
                                    Text("Torrent — not playable on Apple TV yet")
                                        .font(.system(size: 18)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .disabled(!s.isPlayable)
                }
            }
            .navigationTitle("Streams — \(title)")
        }
    }
}
