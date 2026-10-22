import SwiftUI
import SwiftData

/// Settings tab: a Library card (song count, Add Music), then grouped rows with
/// colored icon tiles for the theme, Now Playing options, lyrics, duplicates and Playback Problems.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeStore.self) private var theme
    @Query private var tracks: [Track]
    @Query private var hiddenArtists: [HiddenArtist]
    @AppStorage(PreferenceKeys.nowPlayingShowsCover) private var showsCover = false
    @Environment(LibraryIndexStore.self) private var library
    @Environment(MusicPlayer.self) private var player

    var body: some View {
        Form {
            Section {
                libraryCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("Pick songs or whole folders in the Files app. The app keeps its own copy, so your originals are never changed.")
                    .settingsFooter()
            }

            Section("Appearance") {
                NavigationLink {
                    ThemeEditorView()
                } label: {
                    SettingsRowLabel(title: "Theme", systemImage: "paintpalette.fill", tile: theme.accent, value: currentThemeName)
                }
                .settingsRow()
            }

            Section {
                Toggle(isOn: $showsCover) {
                    SettingsRowLabel(title: "Show Album Cover", systemImage: "photo.fill", tile: theme.palette.rgba(theme.palette.waveBottom).color)
                }
                .tint(theme.ambientAccent)
                .settingsRow()
            } header: {
                Text("Now Playing")
            } footer: {
                Text("When off, Now Playing shows just the artist backdrop. You can also switch it with the cover button on Now Playing.")
                    .settingsFooter()
            }

            LyricsSettingsSection()

            DuplicatesSettingsSection()

            Section {
                NavigationLink {
                    PlaybackProblemsView()
                } label: {
                    SettingsRowLabel(
                        title: "Playback Problems", systemImage: "exclamationmark.triangle.fill", tile: theme.favorite,
                        value: player.issues.issues.isEmpty ? "None" : "\(player.issues.issues.count)"
                    )
                }
                .settingsRow()
            } footer: {
                Text("Songs that couldn't be played, with the reason. Useful if a song keeps getting skipped.")
                    .settingsFooter()
            }
        }
        .foregroundStyle(theme.text)
        .navigationTitle("Settings")
        .backdropScreen()
    }

    /// Song count (and hidden artists) with a glowing Add Music button.
    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.color(.heading))
                    Text(countLabel(tracks.count, "song"))
                        .font(.largeTitle.weight(.heavy).monospacedDigit())
                        .foregroundStyle(theme.text)
                        .contentTransition(.numericText())
                    if !hiddenArtists.isEmpty {
                        // Explains why All Songs shows fewer songs than the library holds.
                        let hiddenKeys = hiddenArtists.keys
                        // Duplicate copies are counted on their own line, so the two never overlap.
                        let copies = library.index.hiddenCopies
                        let hiddenSongs = tracks.filter { !copies.contains($0.id) && HiddenArtistRules.isHidden($0, hidden: hiddenKeys, index: library.index) }.count
                        Text("\(countLabel(hiddenArtists.count, "hidden artist")) · \(countLabel(hiddenSongs, "song")) hidden")
                            .font(.subheadline)
                            .foregroundStyle(theme.secondaryText)
                    }
                    if !library.keptCopy.isEmpty {
                        // Also why All Songs shows fewer songs (Settings → Duplicates).
                        Text("\(countLabel(library.keptCopy.count, "duplicate copy", plural: "duplicate copies")) hidden")
                            .font(.subheadline)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                Spacer()
            }
            GlowCapsuleButton(title: "Add Music", systemImage: "plus", prominent: true) {
                appState.showImporter = true
            }
        }
        .padding(18)
        .legibleOnGlass()
        .glassCard()
        .accessibilityElement(children: .contain)
    }

    /// The matching built-in theme's name, or "Custom".
    private var currentThemeName: String {
        ThemePreset.all.first { $0.palette.hasSameColors(as: theme.palette) }?.name ?? "Custom"
    }
}

/// A Settings row: a colored rounded tile with a white symbol, the title, and an
/// optional value on the right (like the system Settings app).
struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    let tile: Color
    var value: String?

    @Environment(ThemeStore.self) private var theme
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 30

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(RGBA(hex: tile.hexString)?.contrastingText.color ?? .white)
                .frame(width: tileSize, height: tileSize)
                .background(tile.gradient, in: .rect(cornerRadius: tileSize * 0.28, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }
}

/// The Playback Problems log: newest first, with what failed and whether a retry fixed it.
struct PlaybackProblemsView: View {
    @Environment(MusicPlayer.self) private var player
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        let issues = player.issues.issues
        List {
            if issues.isEmpty {
                ContentUnavailableView("No Problems", systemImage: "checkmark.circle",
                                       description: Text("Every song played without errors."))
                    .settingsRow()
            }
            ForEach(issues) { issue in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(issue.title)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Text(issue.recovered ? "Fixed by retry" : "Skipped")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(issue.recovered ? theme.ambientAccentLight : theme.favorite)
                    }
                    Text(issue.artist)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                    Text(issue.reason.prefix(1).uppercased() + issue.reason.dropFirst())
                        .font(.footnote)
                    Text("\(issue.date.formatted(date: .abbreviated, time: .standard))\(issue.inBackground ? " · app in background" : "")")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                    Text(issue.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }
                .padding(.vertical, 2)
                .settingsRow()
            }
        }
        .foregroundStyle(theme.text)
        .navigationTitle("Playback Problems")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !issues.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) { player.issues.clear() }
                }
            }
        }
        .backdropScreen()
    }
}
