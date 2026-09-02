import SwiftUI

// Stream picker shown when Play can't auto-start a single direct stream.
struct StreamsView: View {
    let title: String
    let streams: [StreamOption]
    let onPick: (StreamOption) -> Void
    @AppStorage(SubtitleStyle.Key.fullStreamDescription) private var fullDescription = true
    @AppStorage(SubtitleStyle.Key.pickerShowFilename) private var showFilename = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HarborPageHeader(title: "Choose a stream", eyebrow: "Playback source",
                                     subtitle: title, count: streams.count)
                        .padding(.bottom, 12)
                    if streams.isEmpty {
                        HarborEmptyState(icon: "play.slash",
                                         title: "No streams found",
                                         message: "Sign in and install a stream add-on with debrid support, or configure TorrServer.")
                    }
                    ForEach(streams) { s in
                        Button {
                            onPick(s)
                        } label: {
                            HStack(spacing: 22) {
                                Image(systemName: s.isPlayable ? "play.fill" : (s.isResolvable ? "network" : "exclamationmark.triangle"))
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(s.isResolvable ? HarborTVDesign.cinemaRed : HarborTVDesign.tertiaryText)
                                    .frame(width: 54, height: 54)
                                    .background(Circle().fill(.white.opacity(0.08)))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(s.displayName.isEmpty ? "Stream" : s.displayName)
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(fullDescription ? 2 : 1)
                                    if fullDescription, !s.detailText.isEmpty,
                                       s.detailText != s.displayName {
                                        Text(s.detailText)
                                            .font(.system(size: 18))
                                            .foregroundStyle(HarborTVDesign.secondaryText)
                                            .lineLimit(2)
                                    }
                                    if showFilename, let filename = s.filename, !filename.isEmpty {
                                        Text(filename)
                                            .font(.system(size: 17, design: .monospaced))
                                            .foregroundStyle(HarborTVDesign.tertiaryText)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text(s.isPlayable ? "DIRECT" : (s.isResolvable ? "TORRSERVER" : "UNAVAILABLE"))
                                    .font(.system(size: 13, weight: .heavy))
                                    .tracking(1.2)
                                    .foregroundStyle(s.isResolvable ? .white : HarborTVDesign.tertiaryText)
                                    .padding(.horizontal, 11).padding(.vertical, 6)
                                    .background(Capsule().fill(s.isResolvable ? HarborTVDesign.cinemaRed.opacity(0.78) : .white.opacity(0.07)))
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(HarborRowFocusStyle())
                        .disabled(!s.isResolvable)
                        .opacity(s.isResolvable ? 1 : 0.55)
                    }
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 42)
            }
            .background(HarborStageBackground())
        }
    }
}
