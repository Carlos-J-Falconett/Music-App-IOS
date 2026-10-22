import SwiftUI
import SwiftData

/// Genres tab: a grid of genre cards with a cover and song count (desktop Genres tab).
struct GenresView: View {
    @Query private var tracks: [Track]
    @Environment(LibraryIndexStore.self) private var library
    @Environment(ThemeStore.self) private var theme
    @Environment(ListeningTotalsStore.self) private var listening
    /// Chosen with the Sort button in the Library header.
    @AppStorage("genreSort") private var sort: CollectionSort = .name

    private struct GenreCard: Identifiable {
        var id: String { name }
        let name: String
        let count: Int
        let artKey: String?
    }

    private var genres: [GenreCard] {
        // Only a listening sort reads the totals, so name sorts aren't redone every time
        // a session is saved during playback (every 30 s).
        let totals = sort.listeningOrder != nil ? listening.totals : .empty
        let cards = Dictionary(grouping: HiddenArtistRules.withoutHiddenCopies(tracks, index: library.index), by: \.genre)
            .map { name, songs in
                GenreCard(name: name, count: songs.count, artKey: songs.first { $0.coverKey != nil }?.coverKey)
            }
        return sort.sorted(cards, name: \.name, songCount: \.count, listening: { totals.genre($0.name) })
    }

    /// "6 songs", plus the number the list is sorted by with a listening sort.
    private func detail(for genre: GenreCard) -> String {
        let songs = countLabel(genre.count, "song")
        guard let order = sort.listeningOrder else { return songs }
        return "\(songs) · \(order.detail(listening.totals.genre(genre.name)))"
    }

    var body: some View {
        ScrollView {
            if tracks.isEmpty {
                EmptyLibraryView()
            }
            GlassEffectContainer(spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(genres) { genre in
                        NavigationLink(value: LibraryRoute.genre(genre.name)) {
                            CoverCard(artKey: genre.artKey, title: genre.name, detail: detail(for: genre))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Layout.screenPadding)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Genres")
        .backdropScreen()
    }
}

/// All songs tagged with one genre. Hidden artists' songs are listed (dimmed)
/// but left out of Play / Shuffle.
struct GenreDetailView: View {
    let genre: String
    @Query private var tracks: [Track]
    @Query private var hiddenArtists: [HiddenArtist]
    @Environment(LibraryIndexStore.self) private var library

    var body: some View {
        let songs = HiddenArtistRules.withoutHiddenCopies(tracks, index: library.index)
            .filter { $0.genre == genre }
            .sorted { ($0.artist, $0.album, $0.trackNumber ?? 0) < ($1.artist, $1.album, $1.trackNumber ?? 0) }
        TrackListScreen(title: genre, tracks: songs, hiddenArtists: hiddenArtists.keys)
    }
}

/// A titled song list with Play / Shuffle — used for genres and favorites.
struct TrackListScreen: View {
    let title: String
    let tracks: [Track]
    var symbol: String?
    /// Artists whose songs Play / Shuffle skip (empty for Favorites, which plays everything).
    var hiddenArtists: Set<String> = []

    @Environment(ThemeStore.self) private var theme
    @Environment(LibraryIndexStore.self) private var library

    var body: some View {
        let playable = HiddenArtistRules.visible(tracks, hidden: hiddenArtists, index: library.index)
        List {
            DetailHeader(
                artKey: tracks.first { $0.coverKey != nil }?.coverKey,
                symbol: symbol,
                title: title,
                detail: countLabel(tracks.count, "song"),
                playTracks: playable
            )
            .plainListRow()
            if tracks.isEmpty {
                Text("No songs here yet.")
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .plainListRow()
            }
            SongListSection(tracks: tracks, hiddenArtists: hiddenArtists)
        }
        .libraryListStyle()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .backdropScreen()
    }
}
