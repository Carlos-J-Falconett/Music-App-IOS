import Foundation
import SwiftData
import SwiftUI

/// Per-song, per-artist and per-genre listening totals, used by the stat-based
/// sorts in the Library (Most Listened, Most Played, Recently Played, Least Played).
nonisolated struct ListeningTotals: Sendable {
    struct Entry: Sendable, Equatable {
        var seconds: Double = 0
        var plays = 0
        var lastPlayed: Date?
    }

    /// One saved session, copied out of SwiftData so it can be summed off the main actor.
    struct Session: Sendable {
        var trackID: UUID
        var start: Date
        var seconds: Double
        var counted: Bool
        /// Artist keys credited for the session (see `ListeningTotalsStore`).
        var artistKeys: [String]
        var genre: String
    }

    private(set) var byTrack: [UUID: Entry] = [:]
    private(set) var byArtist: [String: Entry] = [:]
    private(set) var byGenre: [String: Entry] = [:]
    /// Artists listened to in the 7 days before the totals were computed (Home's Top Artists).
    private(set) var byArtistThisWeek: [String: Entry] = [:]

    static let empty = ListeningTotals()

    init() {}

    init(sessions: [Session], now: Date = .now) {
        let weekStart = now.addingTimeInterval(-7 * 86_400)
        for session in sessions {
            Self.add(session, to: &byTrack[session.trackID, default: Entry()])
            for key in Set(session.artistKeys) {
                Self.add(session, to: &byArtist[key, default: Entry()])
                if session.start >= weekStart {
                    Self.add(session, to: &byArtistThisWeek[key, default: Entry()])
                }
            }
            Self.add(session, to: &byGenre[session.genre, default: Entry()])
        }
    }

    /// Songs by when they were last played, newest first.
    var recentlyPlayedTrackIDs: [UUID] {
        byTrack.compactMap { id, entry in entry.lastPlayed.map { (id, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// This week's artists by listening time, most first.
    var topArtistKeysThisWeek: [String] {
        byArtistThisWeek.filter { $0.value.seconds > 0 }
            .sorted { $0.value.seconds == $1.value.seconds ? $0.key < $1.key : $0.value.seconds > $1.value.seconds }
            .map(\.key)
    }

    /// Several songs added together (an album or a playlist).
    func combined(_ ids: some Sequence<UUID>) -> Entry {
        ids.reduce(into: Entry()) { total, id in
            let entry = track(id)
            total.seconds += entry.seconds
            total.plays += entry.plays
            if let last = entry.lastPlayed, total.lastPlayed.map({ last > $0 }) ?? true { total.lastPlayed = last }
        }
    }

    private static func add(_ session: Session, to entry: inout Entry) {
        entry.seconds += session.seconds
        if session.counted { entry.plays += 1 }
        if entry.lastPlayed.map({ session.start > $0 }) ?? true { entry.lastPlayed = session.start }
    }

    func track(_ id: UUID) -> Entry { byTrack[id] ?? Entry() }
    func artist(_ key: String) -> Entry { byArtist[key] ?? Entry() }
    func genre(_ name: String) -> Entry { byGenre[name] ?? Entry() }
}

/// The listening-based ways to order a list. Shared by songs, artists and genres.
nonisolated enum ListeningOrder: Sendable {
    case mostListened, mostPlayed, recentlyPlayed, leastPlayed

    /// `true` if `a` goes before `b`, `false` if after, `nil` when they tie
    /// (callers then fall back to name order).
    func ordered(_ a: ListeningTotals.Entry, _ b: ListeningTotals.Entry) -> Bool? {
        switch self {
        case .mostListened:
            return a.seconds == b.seconds ? nil : a.seconds > b.seconds
        case .mostPlayed:
            if a.plays != b.plays { return a.plays > b.plays }
            return a.seconds == b.seconds ? nil : a.seconds > b.seconds
        case .recentlyPlayed:
            switch (a.lastPlayed, b.lastPlayed) {
            case let (x?, y?): return x == y ? nil : x > y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return nil
            }
        case .leastPlayed:
            // Never-played first, then the fewest plays, then the least time.
            if a.plays != b.plays { return a.plays < b.plays }
            return a.seconds == b.seconds ? nil : a.seconds < b.seconds
        }
    }

    /// Short text shown in a row while this order is active, e.g. "12 plays" or "3h 12m".
    func detail(_ entry: ListeningTotals.Entry) -> String {
        switch self {
        case .mostListened:
            return entry.seconds > 0 ? formatListeningTime(entry.seconds) : "Not played yet"
        case .mostPlayed, .leastPlayed:
            return entry.plays > 0 ? countLabel(entry.plays, "play") : (entry.seconds > 0 ? "Played briefly" : "Not played yet")
        case .recentlyPlayed:
            guard let date = entry.lastPlayed else { return "Not played yet" }
            return "Played " + date.formatted(.relative(presentation: .named))
        }
    }
}

/// Holds the current `ListeningTotals` for every screen (like `LibraryIndexStore`).
@Observable
final class ListeningTotalsStore {
    private(set) var totals: ListeningTotals = .empty

    fileprivate func update(_ totals: ListeningTotals) { self.totals = totals }
}

extension View {
    /// Keeps `ListeningTotalsStore` in sync with listening history. Apply once, at the root.
    func listeningTotalsLoader() -> some View {
        modifier(ListeningTotalsLoader())
    }
}

private struct ListeningTotalsLoader: ViewModifier {
    /// Changes when sessions are added or grow, or once the library index is ready.
    private struct RefreshKey: Equatable {
        let count: Int
        let lastSeconds: Double
        let artistCount: Int
        let trackCount: Int
    }

    @Environment(ListeningTotalsStore.self) private var store
    @Environment(LibraryIndexStore.self) private var library
    @Query(sort: \ListenSession.start) private var sessions: [ListenSession]
    @Query private var tracks: [Track]

    func body(content: Content) -> some View {
        let index = library.index
        content.task(id: RefreshKey(count: sessions.count, lastSeconds: sessions.last?.listenedSeconds ?? 0,
                                    artistCount: index.artistKeys.count, trackCount: tracks.count)) {
            // Only copying the saved sessions has to happen on the main actor (SwiftData
            // models); crediting artists and adding up runs in the background, so it
            // doesn't block the interface every time a session is saved during playback.
            let genreByTrack = Dictionary(tracks.map { ($0.id, $0.genre) }, uniquingKeysWith: { first, _ in first })
            let raw = sessions.map { session in
                RawSession(trackID: session.trackID, start: session.start, seconds: session.listenedSeconds,
                           counted: session.counted, artist: session.artist,
                           genre: genreByTrack[session.trackID] ?? session.genre)
            }
            let totals = await Self.compute(raw, index: index)
            guard !Task.isCancelled else { return }
            store.update(totals)
        }
    }

    /// A saved session's fields, copied out of SwiftData.
    private struct RawSession: Sendable {
        let trackID: UUID
        let start: Date
        let seconds: Double
        let counted: Bool
        let artist: String
        let genre: String
    }

    /// Credits each session to the artists whose pages list that song (main, featured,
    /// and groups), so an artist's total matches their page, then adds everything up.
    /// Songs no longer in the library fall back to the saved artist text, like Stats.
    @concurrent
    private static func compute(_ sessions: [RawSession], index: ArtistIndex) async -> ListeningTotals {
        var keysByTrack: [UUID: [String]] = [:]
        for key in index.artistKeys {
            for id in index.songIDs(for: key) { keysByTrack[id, default: []].append(key) }
        }
        let known = index.knownKeys
        var parsed: [String: [String]] = [:]
        let copies = sessions.map { session in
            let keys = keysByTrack[session.trackID] ?? parsed[session.artist] ?? {
                let names = ArtistCredits.parse(session.artist, known: known).all.map(Track.key(for:))
                parsed[session.artist] = names
                return names
            }()
            return ListeningTotals.Session(
                trackID: session.trackID, start: session.start, seconds: session.seconds,
                counted: session.counted, artistKeys: keys, genre: session.genre
            )
        }
        return ListeningTotals(sessions: copies)
    }
}
