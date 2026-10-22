import SwiftUI
import SwiftData

/// The Library tab: Songs, Albums, Artists, Genres and Playlists in one place.
///
/// A compact `PageHeader` replaces the navigation bar on this page: the section's
/// name as the title, icon buttons on the same line (play all, shuffle, and sort or
/// new playlist), and the section chips underneath. Pages opened from here (artist,
/// album, playlist) still get the normal navigation bar with a back button.
struct LibraryView: View {
    enum Section: String, CaseIterable, Identifiable {
        case songs = "Songs"
        case albums = "Albums"
        case artists = "Artists"
        case genres = "Genres"
        case playlists = "Playlists"
        var id: String { rawValue }
    }

    @AppStorage("librarySection") private var section: Section = .songs
    /// Shared with each section's view, so Play plays Songs in the order it's shown
    /// and every section remembers its own order.
    @AppStorage("songSort") private var sort: SongSort = .title
    @AppStorage(SongFilter.losslessOnlyKey) private var losslessOnly = false
    @AppStorage("albumSort") private var albumSort: AlbumSort = .title
    @AppStorage("artistSort") private var artistSort: CollectionSort = .name
    @AppStorage("genreSort") private var genreSort: CollectionSort = .name
    @State private var showNewPlaylist = false

    @Query private var tracks: [Track]
    @Query private var hiddenArtists: [HiddenArtist]
    @Environment(LibraryIndexStore.self) private var library
    @Environment(ListeningTotalsStore.self) private var listening
    @Environment(MusicPlayer.self) private var player

    var body: some View {
        Group {
            switch section {
            case .songs: SongsView()
            case .albums: AlbumsView()
            case .artists: ArtistsView()
            case .genres: GenresView()
            case .playlists: PlaylistsView(showNewPlaylist: $showNewPlaylist)
            }
        }
        // Fixed at the top; the list scrolls below it, never underneath.
        .pinnedHeader {
            PageHeader(title: section.rawValue) {
                actions
            } below: {
                ChipPicker(options: Section.allCases, selection: $section) { $0.rawValue }
            }
            .animation(Motion.standard, value: section)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Play all · Shuffle all · Sort (Songs, Albums, Artists, Genres) or New Playlist (Playlists).
    @ViewBuilder
    private var actions: some View {
        HeaderIconButton(title: "Play All Songs", systemImage: "play.fill", prominent: true) {
            player.play(playableSongs())
        }
        .disabled(tracks.isEmpty)
        HeaderIconButton(title: "Shuffle All Songs", systemImage: "shuffle") {
            player.shuffleAll(playableSongs())
        }
        .disabled(tracks.isEmpty)
        switch section {
        case .songs:
            HeaderIconMenu(title: "Sort", systemImage: losslessOnly ? "line.3.horizontal.decrease" : "arrow.up.arrow.down") {
                SortPicker(selection: $sort, label: \.label, systemImage: \.systemImage) { $0.listeningOrder != nil }
                // SwiftUI's Section: `Section` alone is this view's own enum of library sections.
                SwiftUI.Section("Show") {
                    Toggle(isOn: $losslessOnly) {
                        Label("Lossless Only", systemImage: "waveform.badge.magnifyingglass")
                    }
                }
            }
        case .albums:
            HeaderIconMenu(title: "Sort", systemImage: "arrow.up.arrow.down") {
                SortPicker(selection: $albumSort, label: \.label, systemImage: \.systemImage) { $0.listeningOrder != nil }
            }
        case .artists:
            HeaderIconMenu(title: "Sort", systemImage: "arrow.up.arrow.down") {
                SortPicker(selection: $artistSort, label: \.label, systemImage: \.systemImage) { $0.listeningOrder != nil }
            }
        case .genres:
            HeaderIconMenu(title: "Sort", systemImage: "arrow.up.arrow.down") {
                SortPicker(selection: $genreSort, label: \.label, systemImage: \.systemImage) { $0.listeningOrder != nil }
            }
        case .playlists:
            HeaderIconButton(title: "New Playlist", systemImage: "text.badge.plus") {
                showNewPlaylist = true
            }
        }
    }

    /// Every song outside hidden artists, in the Songs sort order. Worked out on tap,
    /// not on every redraw, since it sorts the whole library.
    private func playableSongs() -> [Track] {
        sort.sorted(SongFilter.apply(HiddenArtistRules.visible(tracks, hidden: hiddenArtists.keys, index: library.index), losslessOnly: losslessOnly),
                    totals: listening.totals)
    }
}
