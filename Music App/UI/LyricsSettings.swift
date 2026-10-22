import SwiftUI
import SwiftData

/// Settings → Lyrics, like the desktop's Get Lyrics button and Missing Lyrics dialog:
/// - **Download All Lyrics** looks up every song (hidden artists too, so the list of
///   missing songs is complete), with progress and Stop;
/// - **Search Again for Missing** looks up only the songs without lyrics again, online;
/// - **Missing Lyrics** lists the songs that have none.
struct LyricsSettingsSection: View {
    @Environment(LyricsStore.self) private var lyrics
    @Environment(ThemeStore.self) private var theme
    @Environment(LibraryIndexStore.self) private var library
    @Query private var allTracks: [Track]

    var body: some View {
        // Hidden duplicate copies are skipped: the copy shown has the same lyrics.
        let tracks = HiddenArtistRules.withoutHiddenCopies(allTracks, index: library.index)
        let missingCount = tracks.count(where: { lyrics.isMissing($0.id) })
        Section {
            // The same rows while downloading and after (only their contents change), so the
            // list doesn't jump back to the top when a download finishes.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        lyrics.downloadAll(tracks)
                    } label: {
                        SettingsRowLabel(
                            title: lyrics.isDownloading ? "Downloading Lyrics" : "Download All Lyrics",
                            systemImage: "arrow.down.circle.fill", tile: theme.accent,
                            value: lyrics.progress.map { "\($0.done) / \($0.total)" } ?? countLabel(tracks.count, "song")
                        )
                    }
                    .disabled(tracks.isEmpty || lyrics.isDownloading)
                    if lyrics.isDownloading {
                        Button("Stop", role: .cancel) { lyrics.cancelDownload() }
                            .buttonStyle(.glass)
                            .tint(theme.ambientAccent)
                    }
                }
                if let progress = lyrics.progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .tint(theme.ambientAccent)
                        .accessibilityLabel("Lyrics download")
                        .accessibilityValue("\(progress.done) of \(progress.total) songs")
                }
            }
            .settingsRow()

            Button {
                lyrics.downloadAll(tracks, searchAgainMissing: true)
            } label: {
                SettingsRowLabel(title: "Search Again for Missing", systemImage: "arrow.clockwise.circle.fill",
                                 tile: theme.waveBottom.color)
            }
            .disabled(missingCount == 0 || lyrics.isDownloading)
            .settingsRow()

            if let summary = lyrics.lastSummary {
                Text(summaryText(summary))
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .settingsRow()
            }

            NavigationLink {
                MissingLyricsView()
            } label: {
                SettingsRowLabel(title: "Missing Lyrics", systemImage: "text.badge.xmark", tile: theme.favorite,
                                 value: missingCount == 0 ? "None" : "\(missingCount)")
            }
            .settingsRow()
        } header: {
            Text("Lyrics")
        } footer: {
            // Always the same text: swapping it for the result made the list jump to the top.
            Text(Self.footer)
                .settingsFooter()
        }
    }

    private func summaryText(_ summary: LyricsStore.Summary) -> String {
        var parts = ["Found \(summary.found)", "\(summary.missing) without lyrics"]
        if summary.errors > 0 { parts.append("\(summary.errors) couldn't be checked (try again later)") }
        return (summary.cancelled ? "Stopped. " : "Done. ") + parts.joined(separator: " · ") + "."
    }

    private static let footer = "Looks up lyrics for every song: first in the song file, then on lrclib.net. Lyrics are saved on the phone, so they show offline afterwards. Keep the app open while it runs: iOS pauses it shortly after you leave."
}

/// The songs whose lookup found no lyrics, by artist. Tap one to play it.
struct MissingLyricsView: View {
    @Environment(LyricsStore.self) private var lyrics
    @Environment(ThemeStore.self) private var theme
    @Query private var tracks: [Track]

    var body: some View {
        let missing = tracks
            .filter { lyrics.isMissing($0.id) }
            .sorted { ($0.artist.localizedLowercase, $0.title.localizedLowercase) < ($1.artist.localizedLowercase, $1.title.localizedLowercase) }
        List {
            if missing.isEmpty {
                ContentUnavailableView(
                    "No Missing Lyrics", systemImage: "checkmark.circle",
                    description: Text("Every song that's been checked has lyrics (or is instrumental). Use Download All Lyrics to check the whole library.")
                )
                .foregroundStyle(theme.text)
                .plainListRow()
            } else {
                SectionHeader(title: countLabel(missing.count, "song"), detail: "No lyrics found in the file or on lrclib.net")
                    .plainListRow()
                SongListSection(tracks: missing)
            }
        }
        .libraryListStyle()
        .navigationTitle("Missing Lyrics")
        .navigationBarTitleDisplayMode(.inline)
        .backdropScreen()
    }
}
