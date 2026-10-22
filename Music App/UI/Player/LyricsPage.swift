import SwiftUI

/// Now Playing's Lyrics page (Cover · Lyrics · Queue · EQ), like the desktop's lyrics
/// card: synced lyrics highlight the line being sung and keep it in the middle; tapping
/// a line jumps there. After scrolling by hand, following pauses for a few seconds.
/// Messages for instrumentals, songs without lyrics, and network trouble (with Retry).
struct LyricsPage: View {
    let track: Track

    @Environment(LyricsStore.self) private var store
    @Environment(ThemeStore.self) private var theme
    /// `nil` while looking up.
    @State private var result: LyricsStore.Result?
    /// Bumped by Retry to look the song up again.
    @State private var attempt = 0

    private struct LoadKey: Hashable { let track: UUID; let attempt: Int }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .nowPlayingPanel()
            .task(id: LoadKey(track: track.id, attempt: attempt)) {
                result = nil
                result = await store.lyrics(for: track)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let result {
            loaded(result)
        } else {
            ProgressView()
                .tint(theme.text)
                .accessibilityLabel("Looking for lyrics")
        }
    }

    @ViewBuilder
    private func loaded(_ result: LyricsStore.Result) -> some View {
        switch result {
        case .found(let lyrics):
            VStack(spacing: 0) {
                if lyrics.isSynced {
                    SyncedLyricsView(lyrics: lyrics)
                } else {
                    PlainLyricsView(lyrics: lyrics)
                }
                if lyrics.source == "lrclib" {
                    Text("Lyrics from LRCLIB")
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryText)
                        .padding(.bottom, 8)
                }
            }
        case .instrumental:
            message("Instrumental", systemImage: "music.note")
        case .none:
            message("No lyrics found for this song", systemImage: "questionmark.bubble")
        case .unavailable:
            message("Couldn't reach lrclib.net", systemImage: "wifi.exclamationmark", retry: true)
        }
    }

    private func message(_ text: String, systemImage: String, retry: Bool = false) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text(text)
                .font(.headline)
                .multilineTextAlignment(.center)
            if retry {
                Button("Retry", systemImage: "arrow.clockwise") {
                    store.forget(track.id)
                    attempt += 1
                }
                .buttonStyle(.glass)
                .tint(theme.ambientAccent)
            }
        }
        .foregroundStyle(theme.secondaryText)
        .padding(24)
        .legibleOnGlass()
    }
}

/// Synced lyrics: follows the playback position about ten times a second, but the
/// lines only redraw when the current line changes.
private struct SyncedLyricsView: View {
    let lyrics: Lyrics

    @Environment(MusicPlayer.self) private var player

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !player.isPlaying)) { _ in
            // A seek while paused (tapping a line, the scrubber) still moves the highlight.
            let _ = player.engine.positionChanges
            LyricLines(lyrics: lyrics, current: lyrics.currentLineIndex(at: player.engine.currentTime)) { time in
                player.seek(to: time)
            }
            // Only redraw the lines when the current line changes (not on every tick).
            .equatable()
        }
    }
}

private struct LyricLines: View, Equatable {
    let lyrics: Lyrics
    let current: Int?
    let seek: (Double) -> Void

    nonisolated static func == (lhs: LyricLines, rhs: LyricLines) -> Bool {
        lhs.current == rhs.current && lhs.lyrics == rhs.lyrics
    }

    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrolledLine: Int?
    @State private var userScrolledAt = Date.distantPast

    /// After scrolling by hand, the lines stop following the song for this long.
    private static let followPause: TimeInterval = 4

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                    Button {
                        if let time = line.time { seek(time) }
                    } label: {
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(color(for: index))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .scaleEffect(index == current ? 1.04 : 1)
                            .animation(reduceMotion ? nil : Motion.standard, value: current)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(line.text.isEmpty ? "Instrumental break" : line.text)
                    .accessibilityHint(line.time.map { "Plays from \(formatTime($0))" } ?? "")
                    .accessibilityAddTraits(index == current ? .isSelected : [])
                    .id(index)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
            // Room above and below so the first and last lines can sit in the middle.
            .padding(.vertical, 150)
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $scrolledLine, anchor: .center)
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { userScrolledAt = .now }
        }
        .onAppear { scrolledLine = current ?? 0 }
        .onChange(of: current) { _, line in
            guard let line, Date.now.timeIntervalSince(userScrolledAt) > Self.followPause else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { scrolledLine = line }
        }
        .legibleOnGlass()
    }

    /// The current line in the accent, past lines dimmer than upcoming ones.
    private func color(for index: Int) -> Color {
        guard let current else { return theme.secondaryText }
        if index == current { return theme.ambientAccentLight }
        return index < current ? theme.text.opacity(0.45) : theme.secondaryText
    }
}

/// Plain (unsynced) lyrics: just the text, scrollable.
private struct PlainLyricsView: View {
    let lyrics: Lyrics
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        ScrollView {
            Text(lyrics.lines.map(\.text).joined(separator: "\n"))
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.text.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .frame(maxWidth: .infinity)
                .padding(20)
        }
        .scrollIndicators(.hidden)
        .legibleOnGlass()
    }
}
