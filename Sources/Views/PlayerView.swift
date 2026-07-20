import SwiftUI

struct PlayerTarget: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

struct PlayerView: View {
    let target: PlayerTarget
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PlayerModel()
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>?
    @FocusState private var focused: Control?

    private enum Control { case back10, playPause, fwd10 }

    var body: some View {
        ZStack(alignment: .bottom) {
            MPVPlayerView(url: target.url, model: model)
                .ignoresSafeArea()

            if showControls {
                controls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onPlayPauseCommand { model.togglePause(); flash() }
        .onExitCommand { dismiss() }
        .onMoveCommand { _ in flash() }
        .onAppear { flash() }
    }

    private var controls: some View {
        VStack(spacing: 18) {
            Spacer()
            // Progress
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25)).frame(height: 6)
                        Capsule().fill(Color.green)
                            .frame(width: geo.size.width * model.progress, height: 6)
                    }
                }
                .frame(height: 6)
                HStack {
                    Text(model.timeText)
                    Spacer()
                    Text(model.remainingText)
                }
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            }

            Text(target.title)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 40) {
                iconButton("gobackward.10") { model.seekRelative(-10); flash() }
                    .focused($focused, equals: .back10)
                iconButton(model.paused ? "play.fill" : "pause.fill") { model.togglePause(); flash() }
                    .focused($focused, equals: .playPause)
                iconButton("goforward.10") { model.seekRelative(10); flash() }
                    .focused($focused, equals: .fwd10)
            }
        }
        .padding(.horizontal, 100)
        .padding(.bottom, 70)
        .padding(.top, 120)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
        )
        .onAppear { focused = .playPause }
    }

    private func iconButton(_ system: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 34, weight: .semibold))
                .frame(width: 90, height: 90)
        }
        .buttonStyle(.card)
    }

    private func flash() {
        showControls = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { withAnimation { showControls = false } }
        }
    }
}
