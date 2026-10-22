import SwiftUI
import SwiftData

/// Search across artists, albums, songs and genres (desktop search covers all four).
/// Hidden artists' songs and albums are left out; the artist themself still
/// shows up (dimmed) so their page can be opened on purpose.
struct SearchView: View {
    @Query private var tracks: [Track]
    @Query private var hiddenArtists: [HiddenArtist]
    @Environment(ThemeStore.self) private var theme
    @Environment(LibraryIndexStore.self) private var library
    @State private var query = ""

    var body: some View {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        List {
            if text.isEmpty {
                ContentUnavailableView(
                    "Search Your Library", systemImage: "magnifyingglass",
                    description: Text("Find artists, albums, songs and genres.")
                )
                .legibleOnGlass()
                .plainListRow()
            } else {
                results(for: text)
            }
        }
        .libraryListStyle()
        .navigationTitle("Search")
        // Always shown under the title, so the field is there as soon as the tab opens.
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Artists, albums, songs, genres")
        .backdropScreen()
    }

    @ViewBuilder
    private func results(for text: String) -> some View {
        let hidden = hiddenArtists.keys
        let index = library.index
        let visibleTracks = HiddenArtistRules.visible(tracks, hidden: hidden, index: index)
        let matches = { (value: String) in value.localizedStandardContains(text) }
        // Individual artists (after splitting credits), so "chuwi" finds Chuwi.
        let artists = library.artists.filter { matches($0.name) }
        let albums = Dictionary(grouping: visibleTracks.filter { matches($0.album) }) { "\(index.albumOwnerKey(of: $0))|\($0.album)" }
            .compactMap { $0.value.first }
            .sorted { $0.album.localizedStandardCompare($1.album) == .orderedAscending }
        let songs = visibleTracks.filter { matches($0.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let genres = Set(visibleTracks.map(\.genre)).filter(matches).sorted()

        if artists.isEmpty && albums.isEmpty && songs.isEmpty && genres.isEmpty {
            ContentUnavailableView.search(text: text)
                .legibleOnGlass()
                .plainListRow()
        }
        if !artists.isEmpty {
            Section {
                ForEach(artists.prefix(8)) { artist in
                    NavigationLink(value: LibraryRoute.artist(artist.id)) {
                        ArtistRow(artist: artist, isHidden: hidden.contains(artist.id))
                    }
                    .hideArtistMenu(artistKey: artist.id, isHidden: hidden.contains(artist.id))
                    .glassRow()
                }
            } header: {
                SectionHeader(title: "Artists")
            }
        }
        if !albums.isEmpty {
            Section {
                ForEach(albums.prefix(8)) { track in
                    NavigationLink(value: LibraryRoute.album(artistKey: index.albumOwnerKey(of: track), album: track.album)) {
                        HStack(spacing: 12) {
                            ArtworkView(artKey: track.coverKey, cornerRadius: 10)
                                .frame(width: Layout.rowArtwork, height: Layout.rowArtwork)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.album)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(theme.color(.songTitle))
                                    .lineLimit(1)
                                Text(index.name(for: index.albumOwnerKey(of: track)))
                                    .font(.subheadline)
                                    .foregroundStyle(theme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .glassRow()
                }
            } header: {
                SectionHeader(title: "Albums")
            }
        }
        if !songs.isEmpty {
            Section {
                SongListSection(tracks: Array(songs.prefix(50)))
            } header: {
                SectionHeader(title: "Songs", detail: songs.count > 50 ? "Top 50 of \(songs.count)" : nil)
            }
        }
        if !genres.isEmpty {
            Section {
                ForEach(genres, id: \.self) { genre in
                    NavigationLink(value: LibraryRoute.genre(genre)) {
                        Label {
                            Text(genre)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(theme.color(.songTitle))
                        } icon: {
                            Image(systemName: "guitars")
                                .foregroundStyle(theme.accentLight)
                        }
                    }
                    .glassRow()
                }
            } header: {
                SectionHeader(title: "Genres")
            }
        }
    }
}
