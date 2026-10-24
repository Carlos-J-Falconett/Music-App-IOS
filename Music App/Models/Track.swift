import Foundation
import SwiftData

/// One imported song. The audio file lives in `Documents/Music/<relativePath>`;
/// the app never modifies it (matching the desktop app's read-only rule).
@Model
final class Track {
    @Attribute(.unique) var id: UUID
    /// Path relative to `LibraryLocations.musicDirectory`.
    var relativePath: String
    var title: String
    var artist: String
    var album: String
    var genre: String
    var year: Int?
    var trackNumber: Int?
    /// Length in seconds (0 when unknown).
    var duration: Double
    /// Key into `ArtCache` for the album cover, if one was found.
    var coverKey: String?
    var isFavorite: Bool
    var addedAt: Date
    /// Saved per-song equalizer gains (10 bands, dB). `nil` means "use the global EQ".
    var eqGains: [Float]?
    /// The Album Artist tag (e.g. "TWICE" on a member's solo song). `nil` means the
    /// file hasn't been checked yet; "" means it has no Album Artist.
    var albumArtist: String?
    // The file's audio format (see `AudioFormat`). `codec == nil` means it hasn't been
    // read yet (songs imported before it was saved get it once at launch).
    var codec: String?
    var sampleRate: Double?
    /// Bits per sample, for lossless files.
    var bitDepth: Int?
    /// Average bitrate in kbps (file size ÷ length).
    var bitRate: Int?
    /// For songs downloaded from the media server: the server's item id, and its key
    /// ("library:rel_path"), the song's identity across devices (for syncing stats later).
    var serverID: String?
    var serverKey: String?

    init(
        relativePath: String,
        title: String,
        artist: String,
        album: String,
        genre: String,
        year: Int?,
        trackNumber: Int?,
        duration: Double,
        coverKey: String?,
        albumArtist: String? = nil
    ) {
        self.id = UUID()
        self.relativePath = relativePath
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.year = year
        self.trackNumber = trackNumber
        self.duration = duration
        self.coverKey = coverKey
        self.isFavorite = false
        self.addedAt = .now
        self.eqGains = nil
        self.albumArtist = albumArtist
    }

    /// The song's audio format, or `nil` if it hasn't been read yet.
    var audioFormat: AudioFormat? {
        get {
            codec.flatMap(AudioFormat.Codec.init(rawValue:)).map {
                AudioFormat(codec: $0, sampleRate: sampleRate ?? 0, bitDepth: bitDepth, bitRate: bitRate)
            }
        }
        set {
            codec = newValue?.codec.rawValue
            sampleRate = newValue?.sampleRate
            bitDepth = newValue?.bitDepth
            bitRate = newValue?.bitRate
        }
    }

    /// True for FLAC, ALAC, WAV/AIFF/CAF (uncompressed) files. Before the format has been
    /// read, guessed from the file extension (".m4a" can be either, so it counts as lossy).
    var isLossless: Bool {
        audioFormat?.isLossless ?? AudioFormat.losslessExtensions.contains(fileURL.pathExtension.lowercased())
    }

    /// Case-insensitive key used to group songs by artist and look up artist images.
    var artistKey: String { Track.key(for: artist) }

    /// Absolute file URL of the audio file inside the app's container.
    var fileURL: URL { LibraryLocations.musicDirectory.appending(path: relativePath) }

    /// "Album · Year" line shown under the artist on Now Playing.
    var albumLine: String {
        if let year { return "\(album) · \(year)" }
        return album
    }

    nonisolated static func key(for artist: String) -> String {
        artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
