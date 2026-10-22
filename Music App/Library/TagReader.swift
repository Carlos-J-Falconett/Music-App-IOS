import AVFoundation

/// Song details read from a file's tags (or guessed from its folder path).
nonisolated struct TrackMetadata: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String
    var genre: String
    var year: Int?
    var trackNumber: Int?
    var duration: Double
    var artwork: Data?
    /// The Album Artist tag, or nil when the file has none.
    var albumArtist: String? = nil

    static let unknownArtist = "Unknown Artist"
    static let unknownAlbum = "Unknown Album"
    static let unknownGenre = "Unknown Genre"
}

/// Reads tags with AVFoundation. Like the desktop `tags.py`, files with missing
/// tags fall back to their folder structure: `Artist/Album/Song.ext`.
nonisolated enum TagReader {
    static func read(url: URL, relativePath: String) async -> TrackMetadata {
        var meta = fallback(for: relativePath)
        let asset = AVURLAsset(url: url)
        guard let (duration, common, all) = try? await asset.load(.duration, .commonMetadata, .metadata) else {
            return meta
        }
        let seconds = duration.seconds
        if seconds.isFinite, seconds > 0 { meta.duration = seconds }

        let items = common + all
        if let title = await string(in: items, [.commonIdentifierTitle, .id3MetadataTitleDescription]) {
            meta.title = title
        }
        if let artist = await string(in: items, [.commonIdentifierArtist, .id3MetadataLeadPerformer, .iTunesMetadataAlbumArtist]) {
            meta.artist = artist
        }
        if let album = await string(in: items, [.commonIdentifierAlbumName, .id3MetadataAlbumTitle]) {
            meta.album = album
        }
        meta.albumArtist = await albumArtist(in: items)
        if let genre = await string(in: items, [.iTunesMetadataUserGenre, .id3MetadataContentType, .quickTimeMetadataGenre]) {
            let cleaned = cleanGenre(genre)
            if !cleaned.isEmpty { meta.genre = cleaned }
        }
        if let yearText = await string(in: items, [.commonIdentifierCreationDate, .id3MetadataYear, .id3MetadataRecordingTime, .iTunesMetadataReleaseDate, .quickTimeMetadataYear]) {
            meta.year = parseYear(yearText)
        }
        if let number = await trackNumber(in: items) { meta.trackNumber = number }

        for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork) {
            if let data = try? await item.load(.dataValue), !data.isEmpty {
                meta.artwork = data
                break
            }
        }
        return meta
    }

    /// Reads only the Album Artist tag (used to fill it in for songs imported before it was saved).
    static func readAlbumArtist(url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        guard let (common, all) = try? await asset.load(.commonMetadata, .metadata) else { return nil }
        return await albumArtist(in: common + all)
    }

    /// Album Artist: ID3 `TPE2`, iTunes `aART`, or any format's "album artist" key (FLAC/Vorbis, QuickTime).
    private static func albumArtist(in items: [AVMetadataItem]) async -> String? {
        if let value = await string(in: items, [.id3MetadataBand, .iTunesMetadataAlbumArtist]) { return value }
        for item in items {
            let id = item.identifier?.rawValue.lowercased() ?? ""
            guard id.contains("albumartist") || id.contains("album artist") || id.contains("album_artist") else { continue }
            if let value = try? await item.load(.stringValue) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    /// Guesses title / album / artist from `Artist/Album/Song.ext`.
    static func fallback(for relativePath: String) -> TrackMetadata {
        let parts = relativePath.split(separator: "/").map(String.init)
        let fileName = parts.last ?? relativePath
        let folders = Array(parts.dropLast())
        var album = TrackMetadata.unknownAlbum
        var artist = TrackMetadata.unknownArtist
        if folders.count >= 2 {
            album = folders[folders.count - 1]
            artist = folders[folders.count - 2]
        } else if let only = folders.first, only != LibraryImporter.looseFilesFolder {
            album = only
        }
        return TrackMetadata(
            title: cleanTitle(fileName),
            artist: artist,
            album: album,
            genre: TrackMetadata.unknownGenre,
            year: nil,
            trackNumber: leadingNumber(in: fileName),
            duration: 0,
            artwork: nil
        )
    }

    // MARK: Helpers

    private static func string(in items: [AVMetadataItem], _ identifiers: [AVMetadataIdentifier]) async -> String? {
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let value = try? await item.load(.stringValue) {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        return nil
    }

    /// Track numbers are "3/12" strings in ID3 but packed bytes in iTunes atoms.
    private static func trackNumber(in items: [AVMetadataItem]) async -> Int? {
        for identifier in [AVMetadataIdentifier.id3MetadataTrackNumber, .iTunesMetadataTrackNumber] {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let text = try? await item.load(.stringValue),
                   let number = Int(text.split(separator: "/").first ?? "") {
                    return number
                }
                if let number = try? await item.load(.numberValue) { return number.intValue }
                if let data = try? await item.load(.dataValue), data.count >= 4 {
                    let bytes = [UInt8](data)
                    let number = Int(bytes[2]) << 8 | Int(bytes[3])
                    if number > 0 { return number }
                }
            }
        }
        return nil
    }

    /// Strips ID3v1 genre codes such as "(17)" that some taggers leave behind.
    static func cleanGenre(_ genre: String) -> String {
        genre.replacing(/\(\d+\)/, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseYear(_ text: String) -> Int? {
        guard let match = text.firstMatch(of: /(\d{4})/) else { return nil }
        return Int(match.1)
    }

    /// "01 - Song Name.mp3" → "Song Name".
    static func cleanTitle(_ fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        let stripped = base.replacing(/^\d{1,3}\s*[-._ ]\s*/, with: "")
        return stripped.isEmpty ? base : stripped
    }

    private static func leadingNumber(in fileName: String) -> Int? {
        guard let match = fileName.firstMatch(of: /^(\d{1,3})\s*[-._ ]/) else { return nil }
        return Int(match.1)
    }
}
