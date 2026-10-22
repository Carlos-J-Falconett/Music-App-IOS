import SwiftUI
import SwiftData

/// One album across the whole library, for the Albums grid and Home.
struct AlbumSummary: Identifiable {
    var id: String { "\(ownerKey)|\(name)" }
    let name: String
    /// The album's owner: its Album Artist, else its primary artist. Opens `LibraryRoute.album`.
    let ownerKey: String
    let ownerName: String
    let year: Int?
    let artKey: String?
    let trackIDs: [UUID]
    /// When its newest song was imported.
    let addedAt: Date
}

extension LibraryGrouping {
    /// Every album in `tracks`, grouped by name and owner (so two artists' albums
    /// called "Greatest Hits" stay apart).
    static func allAlbums(_ tracks: [Track], index: ArtistIndex) -> [AlbumSummary] {
        Dictionary(grouping: tracks) { AlbumKey(owner: index.albumOwnerKey(of: $0), name: $0.album) }
            .map { key, songs in
                AlbumSummary(
                    name: key.name,
                    ownerKey: key.owner,
                    ownerName: index.name(for: key.owner),
                    year: songs.compactMap(\.year).min(),
                    artKey: songs.first { $0.coverKey != nil }?.coverKey,
                    trackIDs: sortedByTrackNumber(songs).map(\.id),
                    addedAt: songs.map(\.addedAt).max() ?? .distantPast
                )
            }
    }

    private struct AlbumKey: Hashable {
        let owner: String
        let name: String
    }
}

/// Albums section of the Library: a grid of covers. Hidden artists' albums are left out,
/// like All Songs. Sorted with the Sort button in the Library header.
struct AlbumsView: View {
    @Query private var tracks: [Track]
    @Query private var hiddenArtists: [HiddenArtist]
    @Environment(LibraryIndexStore.self) private var library
    @Environment(ListeningTotalsStore.self) private var listening
    @AppStorage("albumSort") private var sort: AlbumSort = .title

    var body: some View {
        // Only a listening sort reads the totals, so name sorts aren't redone every time
        // a session is saved during playback (every 30 s).
        let totals = sort.listeningOrder != nil ? listening.totals : .empty
        let visible = HiddenArtistRules.visible(tracks, hidden: hiddenArtists.keys, index: library.index)
        let albums = sort.sorted(LibraryGrouping.allAlbums(visible, index: library.index), totals: totals)
        ScrollView {
            if tracks.isEmpty {
                EmptyLibraryView()
            } else {
                VStack(alignment: .leading, spacing: Layout.spacingSmall) {
                    SectionHeader(title: "All Albums", detail: "\(countLabel(albums.count, "album")) · \(sort.label)")
                        .padding(.horizontal, Layout.screenPadding)
                    GlassEffectContainer(spacing: 12) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                            ForEach(albums) { album in
                                NavigationLink(value: LibraryRoute.album(artistKey: album.ownerKey, album: album.name)) {
                                    CoverCard(artKey: album.artKey, title: album.name, detail: detail(for: album, totals: totals))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Layout.screenPadding)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Albums")
        .backdropScreen()
    }

    /// "Artist · 2015", or the number it's sorted by with a listening sort.
    private func detail(for album: AlbumSummary, totals: ListeningTotals) -> String {
        if let order = sort.listeningOrder {
            return "\(album.ownerName) · \(order.detail(totals.combined(album.trackIDs)))"
        }
        return [album.ownerName, album.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
    }
}
