import Foundation

// Where lyrics, songs and artist images come from.
//
// Today lyrics come from the song file and LRCLIB, songs from the files imported into
// the app, and artist images from Photos. These protocols are the groundwork for also
// taking them from a local server later: a server type conforms to the protocol and is
// put first in `MediaSources`, so it's asked before the built-in sources. Nothing calls
// a server yet.
//
// A self-hosted LRCLIB (it's open source) needs no new code at all: it speaks the same
// API, so it's an `LRCLIBProvider` with a different `baseURL`.

/// What a lyrics provider needs to know about a song. Copied from a `Track` on the
/// main actor, so lookups can run anywhere.
nonisolated struct LyricsQuery: Sendable, Hashable {
    let trackID: UUID
    let title: String
    let artist: String
    let album: String
    /// Seconds (0 when unknown).
    let duration: Double
    /// The song file, for lyrics embedded in its tags (`nil` for songs not on the phone).
    let fileURL: URL?
}

/// A provider's answer.
nonisolated enum LyricsLookup: Sendable, Equatable {
    case found(Lyrics)
    /// The song is known to have no words.
    case instrumental
    /// No lyrics for this song. `certain: false` when the provider couldn't fully check
    /// (e.g. LRCLIB's full lookup was too busy), so the answer isn't kept for a week.
    case notFound(certain: Bool)
}

/// A place lyrics can come from (the song file, LRCLIB, later a local server).
/// Throwing means "couldn't check right now" (offline, server down): the lookup moves
/// on, and nothing is remembered, so it's tried again next time.
nonisolated protocol LyricsProvider: Sendable {
    /// Short identifier, also stored as the lyrics' source.
    var id: String { get }
    func lyrics(for query: LyricsQuery) async throws -> LyricsLookup
}

/// A song offered by a source other than the phone's own library (for a future local
/// server: listed there, then streamed or downloaded into the library).
nonisolated struct RemoteSong: Sendable, Hashable, Identifiable {
    /// The source's own identifier for the song.
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
}

/// A place songs can come from besides the files imported into the app.
nonisolated protocol SongSource: Sendable {
    var id: String { get }
    /// Every song the source offers.
    func songs() async throws -> [RemoteSong]
    /// Where the song's audio can be streamed or downloaded from.
    func audioURL(for song: RemoteSong) async throws -> URL
}

/// A place artist images can come from besides Photos.
nonisolated protocol ArtistImageSource: Sendable {
    var id: String { get }
    /// Image data (JPEG/PNG/HEIC) for an artist, or `nil` if the source has none.
    func imageData(forArtist name: String) async throws -> Data?
}

/// The sources in use, in the order they're asked.
nonisolated struct MediaSources: Sendable {
    var lyrics: [any LyricsProvider]
    /// Extra song sources (none yet: songs come from imported files).
    var songs: [any SongSource] = []
    /// Extra artist image sources (none yet: images are picked in Photos).
    var artistImages: [any ArtistImageSource] = []

    /// Lyrics stored in the song file first (no network needed), then LRCLIB.
    static let standard = MediaSources(lyrics: [EmbeddedLyricsProvider(), LRCLIBProvider()])
}
