import SwiftUI
import SwiftData

/// One song in a list: cover thumbnail (or track number), title, details,
/// a favorite heart, a "now playing" speaker and the length.
struct SongRow: View {
    let track: Track
    var showsArtwork = true
    var subtitle: String?
    /// True for songs by a hidden artist in lists that still show them (genres).
    var isHiddenArtist = false

    @Environment(MusicPlayer.self) private var player
    @Environment(ThemeStore.self) private var theme
    @Environment(LyricsStore.self) private var lyrics

    private var isCurrent: Bool { player.currentTrack?.id == track.id }

    var body: some View {
        HStack(spacing: 12) {
            if showsArtwork {
                ArtworkView(artKey: track.coverKey, cornerRadius: Layout.rowArtworkCornerRadius)
                    .frame(width: Layout.rowArtwork, height: Layout.rowArtwork)
            } else {
                Text(track.trackNumber.map(String.init) ?? "–")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isCurrent ? theme.ambientAccentLight : theme.color(.songTitle))
                    .lineLimit(1)
                // An empty subtitle hides the line (e.g. a solo song on its own artist's page).
                let detail = subtitle ?? "\(track.artist) · \(track.album)"
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if isHiddenArtist {
                Image(systemName: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityLabel("Hidden artist")
            }
            if lyrics.isMissing(track.id) {
                // A lookup found no lyrics (Settings → Missing Lyrics).
                Image(systemName: "text.badge.xmark")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityLabel("No lyrics")
            }
            if track.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(theme.favorite)
                    .accessibilityLabel("Favorite")
            }
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(theme.ambientAccentLight)
                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                    .accessibilityLabel("Now playing")
            }
            Text(formatTime(track.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
        }
        .opacity(isHiddenArtist ? 0.75 : 1)
        .contentShape(.rect)
    }
}

/// A full song list section: tapping a row plays the list from that song.
struct SongListSection: View {
    let tracks: [Track]
    var showsArtwork = true
    var subtitle: ((Track) -> String)?
    /// Hidden artist keys. Their songs stay in the list but are left out of the
    /// queue unless they're the one tapped (see `HiddenArtistRules`).
    var hiddenArtists: Set<String> = []

    @Environment(MusicPlayer.self) private var player
    @Environment(LibraryIndexStore.self) private var library

    var body: some View {
        let index = library.index
        ForEach(tracks) { track in
            Button {
                let queue = HiddenArtistRules.queue(tapping: track, in: tracks, hidden: hiddenArtists, index: index)
                player.play(queue.tracks, startAt: queue.start)
            } label: {
                SongRow(
                    track: track, showsArtwork: showsArtwork, subtitle: subtitle?(track),
                    isHiddenArtist: HiddenArtistRules.isHidden(track, hidden: hiddenArtists, index: index)
                )
            }
            .buttonStyle(.plain)
            .trackActions(track)
            .glassRow()
        }
    }
}

extension View {
    /// Context menu and swipe actions shared by every song row.
    func trackActions(_ track: Track) -> some View {
        modifier(TrackActions(track: track))
    }
}

private struct TrackActions: ViewModifier {
    let track: Track

    @Environment(MusicPlayer.self) private var player
    @Environment(AppState.self) private var appState
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    player.playNext(track)
                }
                Button("Add to Queue", systemImage: "text.append") {
                    player.addToQueue([track])
                }
                Button(
                    track.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: track.isFavorite ? "heart.slash" : "heart"
                ) {
                    player.toggleFavorite(track)
                }
                Button("Add to Playlist…", systemImage: "music.note.list") {
                    appState.playlistPickerTracks = [track]
                }
                Divider()
                Button("Remove from Library", systemImage: "trash", role: .destructive) {
                    player.forget(track)
                    LibraryActions.delete(track, from: context)
                }
            }
            .swipeActions(edge: .leading) {
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    player.playNext(track)
                }
                .tint(theme.accent)
            }
            .swipeActions(edge: .trailing) {
                Button("Add to Queue", systemImage: "text.append") {
                    player.addToQueue([track])
                }
                .tint(theme.panels)
                Button(track.isFavorite ? "Unfavorite" : "Favorite", systemImage: track.isFavorite ? "heart.slash" : "heart") {
                    player.toggleFavorite(track)
                }
                .tint(theme.favorite)
            }
    }
}
