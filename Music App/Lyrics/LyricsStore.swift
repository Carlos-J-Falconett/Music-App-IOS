import Foundation
import Observation
import UIKit

/// Finds and remembers lyrics, like the desktop app's `LyricsService`.
///
/// Lookup order: memory → the disk cache (`Application Support/Lyrics/<song id>.json`)
/// → the providers in `MediaSources` (the song file's tags, then LRCLIB).
/// - "No lyrics" answers are kept for a week, then looked up again.
/// - Network trouble is never remembered (it shows Retry), and neither is a "not found"
///   given while LRCLIB was too busy to fully check.
///
/// It also keeps the songs with no lyrics (`missing`, saved across launches) for the
/// Missing Lyrics list and the marks on songs, and can look up the whole library at
/// once (`downloadAll`), one song at a time so LRCLIB isn't flooded.
@Observable
final class LyricsStore {
    /// What the Lyrics page shows for a song.
    enum Result: Equatable, Sendable {
        case found(Lyrics)
        case instrumental
        case none
        /// Couldn't check (offline, server trouble): offer Retry.
        case unavailable
    }

    struct Progress: Equatable { var done: Int; var total: Int }
    struct Summary: Equatable { var found = 0; var missing = 0; var errors = 0; var cancelled = false }

    /// Songs whose lookup found no lyrics (instrumentals and network errors don't count).
    private(set) var missing: Set<UUID>
    /// The running whole-library download, if any.
    private(set) var progress: Progress?
    /// How the last whole-library download went.
    private(set) var lastSummary: Summary?
    var isDownloading: Bool { progress != nil }

    @ObservationIgnored var sources: MediaSources
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var memory: [UUID: Result] = [:]
    @ObservationIgnored private var bulkTask: Task<Void, Never>?
    /// The missing list as it's being updated; published to `missing` in batches, since
    /// every song row reads it (marks) and would redraw on each change.
    @ObservationIgnored private var workingMissing: Set<UUID>

    static let noneRetryInterval: TimeInterval = 7 * 24 * 3600

    init(sources: MediaSources = .standard, directory: URL = LibraryLocations.lyricsDirectory) {
        self.sources = sources
        self.directory = directory
        let saved = Self.loadMissing(from: directory)
        missing = saved
        workingMissing = saved
    }

    func isMissing(_ trackID: UUID) -> Bool { missing.contains(trackID) }

    static func query(for track: Track) -> LyricsQuery {
        LyricsQuery(trackID: track.id, title: track.title, artist: track.artist, album: track.album,
                    duration: track.duration, fileURL: track.fileURL)
    }

    // MARK: One song

    /// The song's lyrics, from memory, the disk cache or the providers.
    func lyrics(for track: Track) async -> Result {
        let query = Self.query(for: track)
        if let cached = memory[query.trackID] { return cached }
        let outcome = await Self.resolve(query, sources: sources, directory: directory)
        apply(outcome, to: query.trackID)
        publishMissing()
        return outcome.result
    }

    /// Forgets a song's remembered result (Retry), so it's looked up again.
    func forget(_ trackID: UUID) {
        memory[trackID] = nil
        try? FileManager.default.removeItem(at: Self.cacheFile(for: trackID, in: directory))
    }

    // MARK: Whole library

    /// Looks up lyrics for `tracks` in the background, one song at a time.
    /// - Parameter searchAgainMissing: only the songs marked missing, forgetting their
    ///   remembered "no lyrics" first (to search online again).
    func downloadAll(_ tracks: [Track], searchAgainMissing: Bool = false) {
        guard bulkTask == nil else { return }
        let chosen = searchAgainMissing ? tracks.filter { missing.contains($0.id) } : tracks
        let queries = chosen.map(Self.query(for:))
        if searchAgainMissing { queries.forEach { forget($0.trackID) } }
        guard !queries.isEmpty else {
            lastSummary = Summary()
            return
        }
        progress = Progress(done: 0, total: queries.count)
        lastSummary = nil
        // A little extra time if the app is left mid-download (iOS pauses it after that).
        let background = UIApplication.shared.beginBackgroundTask(withName: "Download lyrics")
        bulkTask = Task { [weak self] in
            await self?.runDownload(queries)
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }
    }

    /// Stops a running download after the song it's on.
    func cancelDownload() { bulkTask?.cancel() }

    private func runDownload(_ queries: [LyricsQuery]) async {
        var summary = Summary()
        var lastProgress = Date.distantPast
        var lastMissing = Date.now
        for (index, query) in queries.enumerated() {
            if Task.isCancelled {
                summary.cancelled = true
                break
            }
            let result: Result
            if let cached = memory[query.trackID] {
                result = cached
            } else {
                let outcome = await Self.resolve(query, sources: sources, directory: directory)
                // Kept on disk only: holding a whole library's lyrics in memory could take
                // tens of MB. Opening a song reads its file from the cache (fast).
                apply(outcome, to: query.trackID, remember: false)
                result = outcome.result
            }
            switch result {
            case .found, .instrumental: summary.found += 1
            case .none: summary.missing += 1
            case .unavailable: summary.errors += 1
            }
            // Progress a few times a second and the missing list once a second, so the
            // views aren't redrawn for every song.
            if Date.now.timeIntervalSince(lastProgress) >= 0.3 || index == queries.count - 1 {
                lastProgress = .now
                progress = Progress(done: index + 1, total: queries.count)
            }
            if Date.now.timeIntervalSince(lastMissing) >= 1 {
                lastMissing = .now
                publishMissing()
            }
        }
        publishMissing()
        lastSummary = summary
        progress = nil
        bulkTask = nil
    }

    // MARK: Lookup (off the main actor)

    /// A lookup's result and whether to keep it on disk.
    struct Outcome: Sendable {
        var result: Result
        /// False for "not found while the server was busy".
        var certain = true
    }

    /// Disk cache, then each provider in order.
    @concurrent
    static func resolve(_ query: LyricsQuery, sources: MediaSources, directory: URL) async -> Outcome {
        let file = cacheFile(for: query.trackID, in: directory)
        if let entry = readCache(file), !entry.isExpired {
            return Outcome(result: entry.result)
        }
        var uncertain = false
        var failed = false
        for provider in sources.lyrics {
            do {
                switch try await provider.lyrics(for: query) {
                case .found(let lyrics):
                    writeCache(CacheEntry(result: .found(lyrics)), to: file)
                    return Outcome(result: .found(lyrics))
                case .instrumental:
                    writeCache(CacheEntry(result: .instrumental), to: file)
                    return Outcome(result: .instrumental)
                case .notFound(let certain):
                    if !certain { uncertain = true }
                }
            } catch {
                failed = true
            }
        }
        // Nothing found: couldn't check (an error) or really none.
        if failed { return Outcome(result: .unavailable) }
        if !uncertain { writeCache(CacheEntry(result: .none), to: file) }
        return Outcome(result: .none, certain: !uncertain)
    }

    /// Remembers a result and updates the missing list: "none" marks the song, lyrics or
    /// an instrumental clear it, and an error leaves it as it was.
    private func apply(_ outcome: Outcome, to trackID: UUID, remember: Bool = true) {
        if remember, outcome.result != .unavailable { memory[trackID] = outcome.result }
        switch outcome.result {
        case .none: workingMissing.insert(trackID)
        case .found, .instrumental: workingMissing.remove(trackID)
        case .unavailable: break
        }
    }

    // MARK: Storage

    /// One song's remembered result on disk.
    struct CacheEntry: Codable {
        var kind: String          // "lyrics" | "instrumental" | "none"
        var lyrics: Lyrics?
        var saved: Date

        init(result: Result, saved: Date = .now) {
            self.saved = saved
            switch result {
            case .found(let lyrics): kind = "lyrics"; self.lyrics = lyrics
            case .instrumental: kind = "instrumental"
            case .none, .unavailable: kind = "none"
            }
        }

        var result: Result {
            switch kind {
            case "lyrics": lyrics.map(Result.found) ?? .none
            case "instrumental": .instrumental
            default: .none
            }
        }

        /// "No lyrics" is looked up again after a week (LRCLIB keeps growing).
        var isExpired: Bool {
            kind == "none" && Date.now.timeIntervalSince(saved) > LyricsStore.noneRetryInterval
        }
    }

    nonisolated static func cacheFile(for trackID: UUID, in directory: URL) -> URL {
        directory.appending(path: "\(trackID.uuidString).json")
    }

    nonisolated static func readCache(_ file: URL) -> CacheEntry? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(CacheEntry.self, from: data)
    }

    nonisolated static func writeCache(_ entry: CacheEntry, to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entry) { try? data.write(to: file, options: .atomic) }
    }

    private static func missingFile(in directory: URL) -> URL {
        directory.deletingLastPathComponent().appending(path: "lyrics-missing.json")
    }

    private static func loadMissing(from directory: URL) -> Set<UUID> {
        guard let data = try? Data(contentsOf: missingFile(in: directory)),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return [] }
        return Set(ids)
    }

    /// Publishes the working missing list (if it changed) and saves it.
    private func publishMissing() {
        guard workingMissing != missing else { return }
        missing = workingMissing
        let file = Self.missingFile(in: directory)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(workingMissing.sorted { $0.uuidString < $1.uuidString }) {
            try? data.write(to: file, options: .atomic)
        }
    }
}
