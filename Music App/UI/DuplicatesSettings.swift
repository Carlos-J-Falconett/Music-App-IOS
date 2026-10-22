import SwiftUI
import SwiftData

/// Settings → Duplicates: which copy stays when a song is in the library more than once
/// (the same title and main artist, lengths within 3 s), and the copies being hidden.
/// Hidden copies stay on the phone; changing the choice updates the library at once.
struct DuplicatesSettingsSection: View {
    @AppStorage(DuplicatePreference.storageKey) private var preference: DuplicatePreference = .lossless
    @Environment(LibraryIndexStore.self) private var library
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        let hiddenCount = library.keptCopy.count
        Section {
            Picker(selection: $preference) {
                ForEach(DuplicatePreference.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowLabel(title: "Copy to Keep", systemImage: "square.on.square", tile: theme.waveBottom.color)
            }
            .tint(theme.ambientAccentLight)
            .settingsRow()

            NavigationLink {
                HiddenCopiesView()
            } label: {
                SettingsRowLabel(title: "Hidden Copies", systemImage: "eye.slash.fill", tile: theme.accent,
                                 value: hiddenCount == 0 ? "None" : "\(hiddenCount)")
            }
            .settingsRow()
        } header: {
            Text("Duplicates")
        } footer: {
            Text("Songs in your library more than once (same title and artist, lengths within 3 seconds) show only one copy. \(preference.detail) The other copies stay on your phone and still play from playlists.")
                .settingsFooter()
        }
    }
}

/// The hidden duplicate copies, each with the copy kept in its place and both formats.
struct HiddenCopiesView: View {
    @Environment(LibraryIndexStore.self) private var library
    @Environment(ThemeStore.self) private var theme
    @Query private var tracks: [Track]

    private struct Pair: Identifiable {
        let hidden: Track
        let kept: Track
        var id: UUID { hidden.id }
    }

    var body: some View {
        let lookup = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pairs = library.keptCopy.compactMap { hidden, kept -> Pair? in
            guard let hiddenTrack = lookup[hidden], let keptTrack = lookup[kept] else { return nil }
            return Pair(hidden: hiddenTrack, kept: keptTrack)
        }
        .sorted { ($0.kept.artist.localizedLowercase, $0.kept.title.localizedLowercase) < ($1.kept.artist.localizedLowercase, $1.kept.title.localizedLowercase) }

        List {
            if pairs.isEmpty {
                ContentUnavailableView("No Duplicates", systemImage: "checkmark.circle",
                                       description: Text("Every song in your library is there once."))
                    .foregroundStyle(theme.text)
                    .plainListRow()
            } else {
                SectionHeader(title: countLabel(pairs.count, "hidden copy", plural: "hidden copies"), detail: "The copy shown in your library is listed first")
                    .plainListRow()
                ForEach(pairs) { pair in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pair.kept.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(theme.color(.songTitle))
                        Text(pair.kept.artist)
                            .font(.subheadline)
                            .foregroundStyle(theme.secondaryText)
                        copyLine("Shown", pair.kept, systemImage: "checkmark.circle.fill", color: theme.ambientAccentLight)
                        copyLine("Hidden", pair.hidden, systemImage: "eye.slash", color: theme.secondaryText)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .glassRow()
                }
            }
        }
        .libraryListStyle()
        .navigationTitle("Hidden Copies")
        .navigationBarTitleDisplayMode(.inline)
        .backdropScreen()
    }

    private func copyLine(_ title: String, _ track: Track, systemImage: String, color: Color) -> some View {
        Label {
            Text("\(title): \(track.audioFormat?.label ?? (track.isLossless ? "Lossless" : "Unknown format")) · \(track.album)")
                .font(.footnote)
                .lineLimit(2)
        } icon: {
            // Same width for both icons, so the Shown and Hidden lines line up.
            Image(systemName: systemImage)
                .frame(width: 22)
        }
        .foregroundStyle(color)
    }
}
