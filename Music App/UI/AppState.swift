import SwiftUI

/// App-wide UI state: things any screen can trigger but the root view presents
/// (importer, Now Playing, the playlist picker).
@Observable
final class AppState {
    var showImporter = false
    var showNowPlaying = false
    var isImporting = false
    /// Message shown after an import finishes.
    var importMessage: String?
    /// Songs waiting to be added to a playlist; non-nil shows the picker sheet.
    var playlistPickerTracks: [Track]?
    /// A page to open from outside a tab's navigation (e.g. the artist from Now Playing).
    /// The root pushes it onto the current tab and clears it.
    var pendingRoute: LibraryRoute?
}

/// `UserDefaults` keys shared by more than one screen.
enum PreferenceKeys {
    /// Whether Now Playing shows the album cover over the backdrop (off by default).
    static let nowPlayingShowsCover = "nowPlayingShowsCover"
}

/// Places a library screen can navigate to.
enum LibraryRoute: Hashable {
    case artist(String)
    case album(artistKey: String, album: String)
    case genre(String)
    case playlist(UUID)
    case favorites
}

extension View {
    /// Registers every library destination on a navigation stack root.
    func libraryDestinations() -> some View {
        navigationDestination(for: LibraryRoute.self) { route in
            switch route {
            case .artist(let key): ArtistDetailView(artistKey: key)
            case .album(let artistKey, let album): AlbumDetailView(artistKey: artistKey, album: album)
            case .genre(let genre): GenreDetailView(genre: genre)
            case .playlist(let id): PlaylistDetailView(playlistID: id)
            case .favorites: FavoritesView()
            }
        }
    }
}
