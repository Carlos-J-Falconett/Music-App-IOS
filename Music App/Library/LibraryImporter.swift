import Foundation
import SwiftData

/// One file that was copied into the library and is ready to become a `Track`.
nonisolated struct ImportedTrack: Sendable {
    var relativePath: String
    var metadata: TrackMetadata
    var coverKey: String?
    var format: AudioFormat?
}

/// Copies files or whole folders picked in the Files app into `Documents/Music`
/// and reads their tags. Folder structure is kept so the `Artist/Album/Song`
/// fallback and folder cover images keep working. Original files are never changed.
nonisolated enum LibraryImporter {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "flac", "wav", "aif", "aiff", "caf", "alac", "mp4"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic"]
    /// Desktop cover lookup order for folder images.
    static let coverNames = ["cover", "folder", "front", "album", "albumart"]
    /// Folder used for single files picked on their own.
    static let looseFilesFolder = "Imported"

    /// Imports the picked items. `existing` holds relative paths already in the library.
    @concurrent
    static func importItems(_ urls: [URL], existing: Set<String>) async -> [ImportedTrack] {
        let copied = urls.flatMap { copyIntoLibrary($0) }
        return await read(copied.filter { !existing.contains($0) })
    }

    /// Indexes files that are already inside `musicDirectory` (server downloads): the same
    /// per-file steps as importing, without copying anything.
    @concurrent
    static func indexInPlace(relativePaths: [String], existing: Set<String>) async -> [ImportedTrack] {
        await read(relativePaths.filter { !existing.contains($0) })
    }

    /// Relative paths of every audio file in `musicDirectory` (not `.part` downloads).
    @concurrent
    static func audioFilesInLibraryFolder() async -> [String] {
        let root = LibraryLocations.musicDirectory.resolvingSymlinksInPath()
        let rootComponents = root.pathComponents.count
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                              options: [.skipsHiddenFiles]) else { return [] }
        var paths: [String] = []
        while let file = enumerator.nextObject() as? URL {
            guard audioExtensions.contains(file.pathExtension.lowercased()) else { continue }
            paths.append(file.resolvingSymlinksInPath().pathComponents.dropFirst(rootComponents).joined(separator: "/"))
        }
        return paths.sorted()
    }

    /// Reads tags, cover art (embedded, else a folder image, checked once per folder) and
    /// the audio format of files in `musicDirectory`.
    private static func read(_ relativePaths: [String]) async -> [ImportedTrack] {
        var results: [ImportedTrack] = []
        var folderCovers: [String: String?] = [:]
        for relativePath in relativePaths {
            let fileURL = LibraryLocations.musicDirectory.appending(path: relativePath)
            var metadata = await TagReader.read(url: fileURL, relativePath: relativePath)
            var coverKey: String?
            if let artwork = metadata.artwork {
                coverKey = ArtCache.store(artwork)
            } else {
                // Fall back to a cover image in the same folder (checked once per folder).
                let folder = fileURL.deletingLastPathComponent()
                if let cached = folderCovers[folder.path] {
                    coverKey = cached
                } else {
                    let key = folderCoverImage(in: folder).flatMap { try? Data(contentsOf: $0) }.flatMap(ArtCache.store)
                    folderCovers[folder.path] = key
                    coverKey = key
                }
            }
            metadata.artwork = nil
            results.append(ImportedTrack(relativePath: relativePath, metadata: metadata, coverKey: coverKey,
                                         format: AudioFormat.read(url: fileURL)))
        }
        return results
    }

    /// Copies one picked file or folder and returns the relative paths of the audio files.
    private static func copyIntoLibrary(_ url: URL) -> [String] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        let root = LibraryLocations.musicDirectory
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }

        if !isDirectory.boolValue {
            guard audioExtensions.contains(url.pathExtension.lowercased()) else { return [] }
            let relativePath = "\(looseFilesFolder)/\(url.lastPathComponent)"
            return copy(url, to: root.appending(path: relativePath)) ? [relativePath] : []
        }

        // Keep the picked folder's own name as the top level, e.g. "Music/Artist/Album/Song.mp3".
        let baseComponents = url.resolvingSymlinksInPath().deletingLastPathComponent().pathComponents
        var audioPaths: [String] = []
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let file = enumerator?.nextObject() as? URL {
            let ext = file.pathExtension.lowercased()
            let isAudio = audioExtensions.contains(ext)
            guard isAudio || imageExtensions.contains(ext) else { continue }
            let components = file.resolvingSymlinksInPath().pathComponents
            let relativePath = components.dropFirst(baseComponents.count).joined(separator: "/")
            guard !relativePath.isEmpty, copy(file, to: root.appending(path: relativePath)) else { continue }
            if isAudio { audioPaths.append(relativePath) }
        }
        return audioPaths
    }

    /// Copies a file unless an identical path already exists in the library.
    private static func copy(_ source: URL, to destination: URL) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) { return true }
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
            return true
        } catch {
            return false
        }
    }

    /// Desktop order: cover, folder, front, album, albumart — then any image in the folder.
    static func folderCoverImage(in folder: URL) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return nil
        }
        let images = files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
        for name in coverNames {
            if let match = images.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == name }) {
                return match
            }
        }
        return images.sorted { $0.lastPathComponent < $1.lastPathComponent }.first
    }
}

/// Main-actor helpers that turn import results into SwiftData records.
enum LibraryActions {
    /// Imports picked files/folders and inserts the new tracks. Returns how many were added.
    @discardableResult
    static func importFiles(_ urls: [URL], into context: ModelContext) async -> Int {
        let existing = Set(((try? context.fetch(FetchDescriptor<Track>())) ?? []).map(\.relativePath))
        let imported = await LibraryImporter.importItems(urls, existing: existing)
        insert(imported, into: context)
        return imported.count
    }

    /// Adds imported (or downloaded) files to the library and saves.
    static func insert(_ imported: [ImportedTrack], into context: ModelContext) {
        for item in imported {
            let meta = item.metadata
            let track = Track(
                relativePath: item.relativePath,
                title: meta.title,
                artist: meta.artist,
                album: meta.album,
                genre: meta.genre,
                year: meta.year,
                trackNumber: meta.trackNumber,
                duration: meta.duration,
                coverKey: item.coverKey,
                albumArtist: meta.albumArtist ?? ""
            )
            track.audioFormat = item.format ?? AudioFormat(codec: .other, sampleRate: 0)
            context.insert(track)
        }
        try? context.save()
    }

    /// Fills in the Album Artist for songs imported before it was saved (`albumArtist == nil`).
    /// Runs once in the background at launch: the tags are read off the main thread,
    /// then saved together. "" marks a song as checked with no Album Artist.
    static func backfillAlbumArtists(in context: ModelContext) async {
        let pending = ((try? context.fetch(FetchDescriptor<Track>(predicate: #Predicate { $0.albumArtist == nil }))) ?? [])
        guard !pending.isEmpty else { return }
        let files = pending.map { (id: $0.id, url: $0.fileURL) }
        let found = await readAlbumArtists(files)
        for track in pending {
            track.albumArtist = found[track.id] ?? ""
        }
        try? context.save()
    }

    @concurrent
    private static func readAlbumArtists(_ files: [(id: UUID, url: URL)]) async -> [UUID: String] {
        var result: [UUID: String] = [:]
        for file in files {
            if let value = await TagReader.readAlbumArtist(url: file.url) { result[file.id] = value }
        }
        return result
    }

    /// Reads the audio format (codec, sample rate, bit depth, bitrate) of songs imported
    /// before it was saved (`codec == nil`). Runs once in the background at launch, from
    /// the file headers only, then saves everything together. Files that can't be read
    /// are marked "other" so they aren't tried again on every launch.
    static func backfillAudioFormats(in context: ModelContext) async {
        let pending = ((try? context.fetch(FetchDescriptor<Track>(predicate: #Predicate { $0.codec == nil }))) ?? [])
        guard !pending.isEmpty else { return }
        let files = pending.map { (id: $0.id, url: $0.fileURL) }
        let found = await readFormats(files)
        for track in pending {
            track.audioFormat = found[track.id] ?? AudioFormat(codec: .other, sampleRate: 0)
        }
        try? context.save()
    }

    @concurrent
    private static func readFormats(_ files: [(id: UUID, url: URL)]) async -> [UUID: AudioFormat] {
        var result: [UUID: AudioFormat] = [:]
        for file in files {
            if let format = AudioFormat.read(url: file.url) { result[file.id] = format }
        }
        return result
    }

    /// Removes a song from the library and deletes its copied file.
    static func delete(_ track: Track, from context: ModelContext) {
        try? FileManager.default.removeItem(at: track.fileURL)
        context.delete(track)
        try? context.save()
    }
}
