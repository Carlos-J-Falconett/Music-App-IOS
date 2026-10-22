import SwiftUI
import SwiftData

/// Home: the app's name and version with Shuffle All, then shelves of recently played
/// songs, this week's top artists and recently added albums. Hidden artists are left
/// out, like All Songs. Uses the same fixed header as Library instead of a navigation bar.
struct HomeView: View {
    @Query private var tracks: [Track]
    @Query private var hiddenArtists: [HiddenArtist]
    @Environment(LibraryIndexStore.self) private var library
    @Environment(ListeningTotalsStore.self) private var listening
    @Environment(MusicPlayer.self) private var player
    @Environment(ThemeStore.self) private var theme

    /// How many items each shelf shows.
    private static let shelfLimit = 15

    var body: some View {
        let index = library.index
        let totals = listening.totals
        let visible = HiddenArtistRules.visible(tracks, hidden: hiddenArtists.keys, index: index)
        ScrollView {
            if tracks.isEmpty {
                EmptyLibraryView()
            } else {
                VStack(alignment: .leading, spacing: Layout.spacingLarge) {
                    recentlyPlayed(visible, totals: totals)
                    topArtists(visible, totals: totals, index: index)
                    recentlyAdded(visible, index: index)
                }
                .padding(.top, Layout.spacingSmall)
                .padding(.bottom, 24)
            }
        }
        // Fixed at the top; the shelves scroll below it, never underneath.
        .pinnedHeader {
            PageHeader(title: AppInfo.name, titleDetail: AppInfo.version) {
                HeaderIconButton(title: "Shuffle All Songs", systemImage: "shuffle", prominent: true) {
                    player.shuffleAll(visible)
                }
                .disabled(visible.isEmpty)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // Shown as the back button title on pages opened from here.
        .navigationTitle("Home")
        .backdropScreen()
    }

    // MARK: Shelves

    @ViewBuilder
    private func recentlyPlayed(_ visible: [Track], totals: ListeningTotals) -> some View {
        let lookup = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recent = Array(totals.recentlyPlayedTrackIDs.lazy.compactMap { lookup[$0] }.prefix(Self.shelfLimit))
        ShelfSection(title: "Recently Played") {
            if recent.isEmpty {
                hint("Songs you play show up here.", systemImage: "clock.arrow.circlepath")
            } else {
                shelf {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { position, track in
                        Button {
                            // Plays the shelf from this song, so Next continues through it.
                            player.play(recent, startAt: position)
                        } label: {
                            CoverCard(artKey: track.coverKey, title: track.title, detail: track.artist, detailLineLimit: 1)
                                .frame(width: 156)
                        }
                        .buttonStyle(.plain)
                        .trackActions(track)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func topArtists(_ visible: [Track], totals: ListeningTotals, index: ArtistIndex) -> some View {
        let hidden = hiddenArtists.keys
        let keys = Array(totals.topArtistKeysThisWeek.lazy.filter { !hidden.contains($0) }.prefix(Self.shelfLimit))
        let artists = library.artists(for: keys)
        ShelfSection(title: "Top Artists This Week") {
            if artists.isEmpty {
                hint("Your most-played artists from the past 7 days show up here.", systemImage: "music.mic")
            } else {
                shelf {
                    ForEach(artists) { artist in
                        NavigationLink(value: LibraryRoute.artist(artist.id)) {
                            ArtistCircle(
                                name: artist.name, artKey: artist.artKey,
                                detail: formatListeningTime(totals.byArtistThisWeek[artist.id]?.seconds ?? 0)
                            )
                            .frame(width: 116)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func recentlyAdded(_ visible: [Track], index: ArtistIndex) -> some View {
        let albums = LibraryGrouping.allAlbums(visible, index: index)
            .sorted { $0.addedAt == $1.addedAt ? $0.name < $1.name : $0.addedAt > $1.addedAt }
            .prefix(Self.shelfLimit)
        ShelfSection(title: "Recently Added") {
            shelf {
                ForEach(Array(albums)) { album in
                    NavigationLink(value: LibraryRoute.album(artistKey: album.ownerKey, album: album.name)) {
                        CoverCard(artKey: album.artKey, title: album.name, detail: album.ownerName, detailLineLimit: 1)
                            .frame(width: 156)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Building blocks

    /// A horizontally scrolling row that lines up with the page margins.
    private func shelf<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 12) {
                LazyHStack(alignment: .top, spacing: 12) { content() }
                    .padding(.horizontal, Layout.screenPadding)
                    .padding(.vertical, 4)
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    /// Shown in a shelf that has nothing yet.
    private func hint(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassCard(cornerRadius: Layout.rowCornerRadius, glow: false)
            .padding(.horizontal, Layout.screenPadding)
    }
}
