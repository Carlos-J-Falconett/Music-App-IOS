import Foundation
import SwiftData

/// A user playlist. Track order is stored as an array of track ids so a song
/// can appear more than once and reordering is a simple array move.
@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var trackIDs: [UUID]
    var createdAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.trackIDs = []
        self.createdAt = .now
    }
}

/// One listening session, recorded by `StatsRecorder` using the desktop app's rules
/// (see `ListeningRules`). Song details are copied in so stats survive deleting a song.
@Model
final class ListenSession {
    var start: Date
    var listenedSeconds: Double
    /// True once the session qualifies as a "play".
    var counted: Bool
    var trackID: UUID
    var title: String
    var artist: String
    var album: String
    var genre: String

    init(start: Date, trackID: UUID, title: String, artist: String, album: String, genre: String) {
        self.start = start
        self.listenedSeconds = 0
        self.counted = false
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
    }
}

/// A picture the user picked for an artist. `artKey` points into `ArtCache`,
/// which also stores the pre-blurred version used by the backdrop.
@Model
final class ArtistImage {
    @Attribute(.unique) var artistKey: String
    var artKey: String

    init(artistKey: String, artKey: String) {
        self.artistKey = artistKey
        self.artKey = artKey
    }
}

/// How an artist's background looks, set in artist page → … → Adjust Background…
/// It applies to whichever picture is shown for them (their image, their group's, or
/// an album cover), behind the player and at the top of their page. Group members
/// without their own settings use their group's. Without any, `BackdropStyle.standard`.
@Model
final class ArtistBackdropStyle {
    @Attribute(.unique) var artistKey: String
    // Framing behind the player (these four predate the separate artist-page framing).
    var fillsScreen: Bool = false
    var zoom: Double = 1
    var offsetX: Double = 0
    var offsetY: Double = 0
    // Framing at the top of the artist page. `nil` = the same as behind the player, so
    // artists adjusted before the two were separate look exactly as they did.
    var pageFillsScreen: Bool?
    var pageZoom: Double?
    var pageOffsetX: Double?
    var pageOffsetY: Double?
    var dim: Double = 0.35
    var blur: Double = 12
    var edgeFade: Double = 0.04
    var glow: Double = 1
    var brightness: Double = 0

    init(artistKey: String, style: BackdropStyle) {
        self.artistKey = artistKey
        self.style = style
    }

    var style: BackdropStyle {
        get {
            let player = BackdropFraming(fillsScreen: fillsScreen, zoom: zoom, offsetX: offsetX, offsetY: offsetY)
            let page = BackdropFraming(
                fillsScreen: pageFillsScreen ?? player.fillsScreen, zoom: pageZoom ?? player.zoom,
                offsetX: pageOffsetX ?? player.offsetX, offsetY: pageOffsetY ?? player.offsetY
            )
            return BackdropStyle(player: player, page: page, dim: dim, blur: blur, edgeFade: edgeFade,
                                 glow: glow, brightness: brightness)
        }
        set {
            fillsScreen = newValue.player.fillsScreen
            zoom = newValue.player.zoom
            offsetX = newValue.player.offsetX
            offsetY = newValue.player.offsetY
            pageFillsScreen = newValue.page.fillsScreen
            pageZoom = newValue.page.zoom
            pageOffsetX = newValue.page.offsetX
            pageOffsetY = newValue.page.offsetY
            dim = newValue.dim
            blur = newValue.blur
            edgeFade = newValue.edgeFade
            glow = newValue.glow
            brightness = newValue.brightness
        }
    }
}

/// Where a backdrop picture sits and how big it is. Behind the player and at the top of
/// the artist page each have their own.
struct BackdropFraming: Equatable {
    /// Fill the screen (cropping the edges) instead of showing the whole picture.
    var fillsScreen = false
    /// 1 = the picture's normal size. Pinch in the editor.
    var zoom = 1.0
    /// Moves the picture, as a fraction of the screen's width and height. Drag in the editor.
    var offsetX = 0.0
    var offsetY = 0.0
}

/// The adjustable look of a backdrop picture.
struct BackdropStyle: Equatable {
    /// Framing behind the player (and every page while the artist plays).
    var player = BackdropFraming()
    /// Framing at the top of the artist's page.
    var page = BackdropFraming()
    /// The dark veil over the blurred area around the picture (0 = none), in Backdrop
    /// Dim's color. The picture itself is darkened or lightened with `brightness`.
    var dim = 0.35
    /// Blur radius of the copy filling the area around the picture.
    var blur = 12.0
    /// How much of the picture's top and bottom fades into the blur (0…0.35).
    var edgeFade = 0.04
    /// Strength of the outline glow around transparent cut-outs (0 = off, 1 = normal).
    var glow = 1.0
    /// Darkens (below 0) or lightens (above 0) the picture itself.
    var brightness = 0.0

    static let zoomRange = 0.5...5.0
    static let offsetRange = -1.0...1.0
    static let dimRange = 0.0...0.85
    static let blurRange = 0.0...40.0
    static let edgeFadeRange = 0.0...0.35
    static let glowRange = 0.0...2.0
    static let brightnessRange = -0.6...0.3

    /// The look before any adjusting: album covers fade more (14%) than artist pictures
    /// (4%), so their square edges disappear; transparent cut-outs don't fade at all.
    static func standard(isArtistImage: Bool, isTransparent: Bool) -> BackdropStyle {
        BackdropStyle(edgeFade: isTransparent ? 0 : (isArtistImage ? 0.04 : 0.14))
    }
}

/// No longer used: a build briefly gave artists a background separate from their
/// `ArtistImage`. Kept in the schema only so those rows can be read and merged back
/// into `ArtistImage` at launch (`ArtistArtwork.mergeLegacyBackgrounds`).
@Model
final class ArtistBackground {
    @Attribute(.unique) var artistKey: String
    var artKey: String

    init(artistKey: String, artKey: String) {
        self.artistKey = artistKey
        self.artKey = artKey
    }
}

/// An artist the user hid. Their songs stay out of All Songs, Search and every
/// Play / Shuffle queue, but still play from their own artist page, from
/// playlists, and when one of their songs is tapped directly.
@Model
final class HiddenArtist {
    @Attribute(.unique) var artistKey: String
    var hiddenAt: Date

    init(artistKey: String) {
        self.artistKey = artistKey
        self.hiddenAt = .now
    }
}

/// "Member of…" set by hand on an artist's page, for groups whose files have no
/// Album Artist tag. Songs tagged with an Album Artist are linked automatically.
@Model
final class ArtistGroupLink {
    @Attribute(.unique) var memberKey: String
    var groupKey: String

    init(memberKey: String, groupKey: String) {
        self.memberKey = memberKey
        self.groupKey = groupKey
    }
}

/// A saved custom color theme. The palette is stored as JSON so new theme
/// keys can be added later without a schema migration.
@Model
final class SavedTheme {
    @Attribute(.unique) var id: UUID
    var name: String
    var paletteData: Data

    init(name: String, palette: ThemePalette) {
        self.id = UUID()
        self.name = name
        self.paletteData = (try? JSONEncoder().encode(palette)) ?? Data()
    }

    var palette: ThemePalette {
        (try? JSONDecoder().decode(ThemePalette.self, from: paletteData)) ?? .default
    }
}

/// Where the app keeps its files.
nonisolated enum LibraryLocations {
    /// Imported audio files (and any cover images copied alongside them).
    static var musicDirectory: URL {
        URL.documentsDirectory.appending(path: "Music", directoryHint: .isDirectory)
    }

    /// Remembered lyrics lookups, one JSON file per song (`LyricsStore`).
    static var lyricsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Lyrics", directoryHint: .isDirectory)
    }

    /// Covers, artist pictures and their pre-blurred backdrop versions.
    static var artDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Art", directoryHint: .isDirectory)
    }
}
