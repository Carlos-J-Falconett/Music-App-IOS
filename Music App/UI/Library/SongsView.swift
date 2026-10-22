import SwiftUI
import SwiftData

/// All Songs: every song in the library (except hidden artists and hidden duplicate
/// copies), or only lossless ones (Sort menu → Lossless Only). Play, Shuffle and Sort
/// (see `SongSort`) are icon buttons in the Library header.
struct SongsView: View {
    @Query private var tracks: [Track]
    @Query private var hiddenArtists: [HiddenArtist]
    @Environment(LibraryIndexStore.self) private var library
    @Environment(ListeningTotalsStore.self) private var listening
    @Environment(ThemeStore.self) private var theme
    @AppStorage("songSort") private var sort: SongSort = .title
    @AppStorage(SongFilter.losslessOnlyKey) private var losslessOnly = false

    var body: some View {
        // Only a listening sort reads the totals, so name sorts aren't redone every time
        // a session is saved during playback (every 30 s).
        let totals = sort.listeningOrder != nil ? listening.totals : .empty
        let visible = SongFilter.apply(HiddenArtistRules.visible(tracks, hidden: hiddenArtists.keys, index: library.index), losslessOnly: losslessOnly)
        let sorted = sort.sorted(visible, totals: totals)
        // With a listening sort, each row shows the number it's sorted by.
        let subtitle: ((Track) -> String)? = sort.listeningOrder.map { order in
            { track in "\(track.artist) · \(order.detail(totals.track(track.id)))" }
        }
        List {
            if tracks.isEmpty {
                EmptyLibraryView()
                    .plainListRow()
            } else {
                // A plain first row, not a sticky section header, so it scrolls away with
                // the list instead of staying put with songs sliding underneath it.
                SectionHeader(title: losslessOnly ? "Lossless Songs" : "All Songs",
                              detail: "\(countLabel(sorted.count, "song")) · \(sort.label)")
                    .plainListRow()
                if losslessOnly && sorted.isEmpty {
                    ContentUnavailableView("No Lossless Songs", systemImage: "waveform",
                                           description: Text("None of your songs are FLAC, ALAC, WAV or AIFF. Turn off Lossless Only in the Sort menu to see every song."))
                        .foregroundStyle(theme.text)
                        .plainListRow()
                }
                SongListSection(tracks: sorted, subtitle: subtitle)
            }
        }
        .libraryListStyle()
        // Shown as the back button title on pages opened from here.
        .navigationTitle("Songs")
        .backdropScreen()
    }
}

/// Shown when nothing has been imported yet.
struct EmptyLibraryView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        ContentUnavailableView {
            Label("No Music Yet", systemImage: "music.note.house")
        } description: {
            Text("Import songs or whole folders from the Files app. The app keeps its own copy, so your original files are never changed.")
        } actions: {
            Button("Import Music", systemImage: "plus") { appState.showImporter = true }
                .buttonStyle(.glassProminent)
                .tint(theme.accent)
        }
        .foregroundStyle(theme.text)
        .padding(.vertical, 40)
    }
}
