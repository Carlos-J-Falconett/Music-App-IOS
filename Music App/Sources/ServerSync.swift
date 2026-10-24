import Foundation
import Observation
import SwiftData
import UIKit

/// Downloads new music from the home media server into the library (Settings → Media
/// Server). The server says what exists and what changed; the phone keeps its own copy.
///
/// For each music library on the server (the guide's section 3 algorithm):
/// 1. read the change feed from the saved cursor, 500 items a page;
/// 2. download each song that's missing or a different size, into
///    `Documents/Music/<rel_path>` (the High-Res library into `Documents/Music/Hi-Res/`),
///    through a `.part` file that resumes if interrupted;
/// 3. add the page's new files to the library (tags, cover, format read from the files,
///    like importing; the server's cover if the file has none);
/// 4. save the cursor, only once the page's files are on disk and in the library, so a
///    crash just repeats that page.
/// Songs removed on the server are never deleted from the phone.
@Observable
final class ServerSyncStore {
    struct Progress: Equatable {
        var library = ""
        /// Songs checked in the change feed so far, and how many the server has.
        var checked = 0
        var total = 0
        var downloaded = 0
        /// The song downloading now, and how far along it is (0…1).
        var current: String?
        var currentFraction = 0.0
    }

    struct Summary: Equatable {
        var date = Date.now
        var checked = 0
        var downloaded = 0
        var added = 0
        var updated = 0
        var cancelled = false
        /// Libraries skipped because their drive isn't connected to the PC.
        var unavailable: [String] = []
    }

    static let addressKey = "mediaServerAddress"
    static let syncOnLaunchKey = "mediaServerSyncOnLaunch"
    static func cursorKey(_ library: String) -> String { "serverCursor.\(library)" }
    static func enabledKey(_ library: String) -> String { "serverLibraryEnabled.\(library)" }

    private(set) var progress: Progress?
    private(set) var lastSummary: Summary?
    private(set) var lastError: String?
    var isSyncing: Bool { progress != nil }

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The local folder (inside `Documents/Music`) for a server library: music at the top,
    /// High-Res in "Hi-Res/" so its copies never overwrite the regular ones (the duplicate
    /// setting then picks which copy shows), any other music library in its own folder.
    static func localPrefix(for library: String) -> String {
        switch library {
        case "music": ""
        case "hires": "Hi-Res/"
        default: "\(library)/"
        }
    }

    func isEnabled(_ library: String) -> Bool { defaults.object(forKey: Self.enabledKey(library)) as? Bool ?? true }
    func setEnabled(_ library: String, _ enabled: Bool) { defaults.set(enabled, forKey: Self.enabledKey(library)) }

    // MARK: Sync

    /// Starts a sync in the background (ignored while one is running).
    func start(client: MediaServerClient?, context: ModelContext) {
        guard task == nil else { return }
        guard let client else {
            lastError = MediaServerError.notSetUp.errorDescription
            return
        }
        lastError = nil
        progress = Progress()
        // A little extra time if the app is left mid-sync (iOS pauses it after that; the
        // next sync resumes from the cursor and any part-downloaded file).
        let background = UIApplication.shared.beginBackgroundTask(withName: "Media server sync")
        task = Task { [weak self] in
            await self?.run(client: client, context: context)
            if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
        }
    }

    /// Stops after the current file's bytes so far are saved (it resumes next time).
    func cancel() { task?.cancel() }

    /// Runs a whole sync (also used directly by tests).
    func run(client: MediaServerClient, context: ModelContext) async {
        var summary = Summary()
        do {
            let libraries = try await client.libraries().filter { $0.isMusic && isEnabled($0.name) }
            summary.added += await LibraryActions.addMissingFiles(into: context)
            var existing = Set(((try? context.fetch(FetchDescriptor<Track>())) ?? []).map(\.relativePath))
            for library in libraries {
                guard library.available else {
                    summary.unavailable.append(library.name)
                    continue
                }
                progress = Progress(library: library.name, total: library.count ?? 0, downloaded: summary.downloaded)
                try await sync(library.name, client: client, context: context, existing: &existing, summary: &summary)
            }
        } catch is CancellationError {
            summary.cancelled = true
        } catch {
            lastError = (error as? MediaServerError)?.errorDescription ?? error.localizedDescription
        }
        summary.date = .now
        lastSummary = summary
        progress = nil
        task = nil
    }

    /// Songs are added to the library a few at a time while downloading (not only at the
    /// end of a 500-item page), so a sync that's stopped or interrupted keeps the songs it
    /// finished.
    static let addBatchSize = 10
    static let addInterval: TimeInterval = 20

    private func sync(_ library: String, client: MediaServerClient, context: ModelContext,
                      existing: inout Set<String>, summary: inout Summary) async throws {
        let prefix = Self.localPrefix(for: library)
        var cursor = defaults.integer(forKey: Self.cursorKey(library))
        var newFiles: [String: ServerItem] = [:]
        var changedFiles: [String: ServerItem] = [:]
        var lastAdded = Date.now

        /// Adds the waiting new songs to the library, and refreshes songs whose file changed.
        func addWaiting() async {
            if !newFiles.isEmpty {
                let imported = await LibraryImporter.indexInPlace(relativePaths: Array(newFiles.keys).sorted(), existing: existing)
                LibraryActions.insert(imported, into: context)
                existing.formUnion(imported.map(\.relativePath))
                summary.added += imported.count
            }
            if !changedFiles.isEmpty {
                let reread = await LibraryImporter.indexInPlace(relativePaths: Array(changedFiles.keys).sorted(), existing: [])
                summary.updated += LibraryActions.refresh(reread, in: context)
            }
            await attachServerInfo(newFiles.merging(changedFiles) { first, _ in first }, client: client, context: context)
            newFiles = [:]
            changedFiles = [:]
            lastAdded = .now
        }

        while true {
            try Task.checkCancellation()
            let page = try await client.items(library: library, since: cursor)
            do {
                for item in page.items where !item.deleted && item.kind == "audio" {
                    try Task.checkCancellation()
                    let relativePath = prefix + item.relPath
                    let local = LibraryLocations.musicDirectory.appending(path: relativePath)
                    if MediaServerClient.fileSize(local) != item.size {
                        progress?.current = [item.meta.artist, item.meta.title].compactMap { $0 }.joined(separator: " – ")
                        progress?.currentFraction = 0
                        let reporter = FractionReporter { [weak self] fraction in self?.progress?.currentFraction = fraction }
                        try await client.download(item, to: local) { reporter.report($0) }
                        summary.downloaded += 1
                        progress?.downloaded = summary.downloaded
                        if existing.contains(relativePath) { changedFiles[relativePath] = item } else { newFiles[relativePath] = item }
                    } else if !existing.contains(relativePath) {
                        // Already on the phone but not in the library (e.g. the app closed
                        // mid-sync after downloading it): add it now.
                        newFiles[relativePath] = item
                    }
                    summary.checked += 1
                    progress?.checked += 1
                    if newFiles.count + changedFiles.count >= Self.addBatchSize || Date.now.timeIntervalSince(lastAdded) >= Self.addInterval {
                        await addWaiting()
                    }
                }
            } catch {
                // Stopped or failed mid-page: keep the songs that did finish.
                await addWaiting()
                throw error
            }
            progress?.current = nil
            await addWaiting()

            // Only now, with the page's songs on the phone and in the library.
            cursor = page.nextSince
            defaults.set(cursor, forKey: Self.cursorKey(library))
            if !page.more { break }
        }
    }

    /// Remembers each song's server id and key, and uses the server's cover for songs
    /// whose file had none.
    private func attachServerInfo(_ items: [String: ServerItem], client: MediaServerClient, context: ModelContext) async {
        guard !items.isEmpty else { return }
        let paths = Array(items.keys)
        let tracks = (try? context.fetch(FetchDescriptor<Track>(predicate: #Predicate { paths.contains($0.relativePath) }))) ?? []
        for track in tracks {
            guard let item = items[track.relativePath] else { continue }
            track.serverID = item.id
            track.serverKey = item.key
            if track.coverKey == nil, let data = try? await client.cover(for: item) {
                track.coverKey = await ArtCache.storeInBackground(data)
            }
        }
        try? context.save()
    }
}

/// Passes a download's progress to the main actor at most every 2%, instead of once per
/// network chunk (hundreds of times a second).
nonisolated final class FractionReporter: @unchecked Sendable {
    private let update: @MainActor (Double) -> Void
    private let lock = NSLock()
    private var last = -1.0

    init(_ update: @escaping @MainActor (Double) -> Void) { self.update = update }

    func report(_ fraction: Double) {
        lock.lock()
        let changed = fraction - last >= 0.02 || fraction >= 1
        if changed { last = fraction }
        lock.unlock()
        guard changed else { return }
        Task { @MainActor in update(fraction) }
    }
}

extension LibraryActions {
    /// Adds audio files that are in `Documents/Music` but not in the library: songs a sync
    /// downloaded before it was interrupted. Unfinished `.part` files are left for the next
    /// sync to resume. Runs at launch and before each sync. Returns how many were added.
    @discardableResult
    static func addMissingFiles(into context: ModelContext) async -> Int {
        let existing = Set(((try? context.fetch(FetchDescriptor<Track>())) ?? []).map(\.relativePath))
        let missing = await LibraryImporter.audioFilesInLibraryFolder().filter { !existing.contains($0) }
        guard !missing.isEmpty else { return 0 }
        let imported = await LibraryImporter.indexInPlace(relativePaths: missing, existing: existing)
        insert(imported, into: context)
        return imported.count
    }

    /// Updates songs already in the library from re-read files (a newer version was
    /// downloaded). Returns how many were updated.
    static func refresh(_ reread: [ImportedTrack], in context: ModelContext) -> Int {
        let byPath = Dictionary(reread.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        let paths = Array(byPath.keys)
        let tracks = (try? context.fetch(FetchDescriptor<Track>(predicate: #Predicate { paths.contains($0.relativePath) }))) ?? []
        for track in tracks {
            guard let item = byPath[track.relativePath] else { continue }
            let meta = item.metadata
            track.title = meta.title
            track.artist = meta.artist
            track.album = meta.album
            track.genre = meta.genre
            track.year = meta.year
            track.trackNumber = meta.trackNumber
            track.duration = meta.duration
            track.albumArtist = meta.albumArtist ?? ""
            if let coverKey = item.coverKey { track.coverKey = coverKey }
            track.audioFormat = item.format ?? AudioFormat(codec: .other, sampleRate: 0)
        }
        try? context.save()
        return tracks.count
    }
}
