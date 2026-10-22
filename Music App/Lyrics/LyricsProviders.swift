import AVFoundation
import Foundation

/// Lyrics stored in the song file's tags (ID3 USLT, iTunes ©lyr, or the asset's lyrics).
/// Needs no network, so it's asked first.
nonisolated struct EmbeddedLyricsProvider: LyricsProvider {
    let id = "embedded"

    func lyrics(for query: LyricsQuery) async throws -> LyricsLookup {
        guard let url = query.fileURL else { return .notFound(certain: true) }
        let asset = AVURLAsset(url: url)
        guard let (common, all) = try? await asset.load(.commonMetadata, .metadata) else {
            return .notFound(certain: true)
        }
        let items = common + all
        for identifier in [AVMetadataIdentifier.id3MetadataUnsynchronizedLyric, .iTunesMetadataLyrics] {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let text = try? await item.load(.stringValue), let found = Lyrics.from(text: text, source: id) {
                    return .found(found)
                }
            }
        }
        if let text = try? await asset.load(.lyrics), let found = Lyrics.from(text: text, source: id) {
            return .found(found)
        }
        return .notFound(certain: true)
    }
}

/// lrclib.net, a free lyrics database, used the same way as the desktop app:
/// 1. `get-cached` (instant, LRCLIB's own database);
/// 2. `get` (may also consult other sources; answers 5xx when busy, then the search
///    still gets its chance, but a "not found" isn't certain);
/// 3. `search`, picking the closest duration within ±5 s, synced lyrics preferred.
/// Network trouble is retried once, then thrown (so nothing is remembered).
/// Pointing `baseURL` at a self-hosted LRCLIB works the same way.
nonisolated struct LRCLIBProvider: LyricsProvider {
    let id = "lrclib"
    var baseURL = URL(string: "https://lrclib.net/api")!
    var session: URLSession = .shared

    static let durationTolerance = 5.0
    static let timeout: TimeInterval = 8

    /// One LRCLIB record (only the fields used).
    struct Record: Decodable, Sendable, Equatable {
        var duration: Double?
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    enum Failure: Error {
        case busy
        case badResponse(Int)
    }

    func lyrics(for query: LyricsQuery) async throws -> LyricsLookup {
        let title = Lyrics.cleanName(query.title)
        let artist = Lyrics.cleanName(query.artist)
        let params: [String: String] = [
            "track_name": title, "artist_name": artist, "album_name": query.album,
            "duration": String(Int(query.duration.rounded())),
        ]
        var lastError: (any Error)?
        for _ in 0..<2 {   // LRCLIB is occasionally slow: retry once
            do {
                var busy = false
                var record = try await fetch("get-cached", params)
                if record == nil {
                    do {
                        record = try await fetch("get", params)
                    } catch Failure.busy {
                        busy = true
                    }
                }
                if record == nil {
                    record = try await search(title: title, artist: artist, duration: query.duration)
                }
                return Self.lookup(from: record, busy: busy, source: id)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? Failure.busy
    }

    /// Turns a record (or none) into an answer.
    static func lookup(from record: Record?, busy: Bool, source: String) -> LyricsLookup {
        guard let record else { return .notFound(certain: !busy) }
        if record.instrumental == true { return .instrumental }
        if let found = Lyrics.from(text: record.syncedLyrics ?? "", source: source)
            ?? Lyrics.from(text: record.plainLyrics ?? "", source: source) {
            return .found(found)
        }
        return .notFound(certain: !busy)
    }

    /// The best search result: within ±5 s of the song's length, synced lyrics first,
    /// then the closest length.
    static func bestMatch(_ results: [Record], duration: Double) -> Record? {
        results
            .filter { abs(($0.duration ?? 0) - duration) <= durationTolerance }
            .min { a, b in
                let aSynced = !(a.syncedLyrics ?? "").isEmpty, bSynced = !(b.syncedLyrics ?? "").isEmpty
                if aSynced != bSynced { return aSynced }
                return abs((a.duration ?? 0) - duration) < abs((b.duration ?? 0) - duration)
            }
    }

    private func search(title: String, artist: String, duration: Double) async throws -> Record? {
        let data = try await request("search", ["track_name": title, "artist_name": artist])
        guard let data else { return nil }
        let results = try JSONDecoder().decode([Record].self, from: data)
        return Self.bestMatch(results, duration: duration)
    }

    private func fetch(_ endpoint: String, _ params: [String: String]) async throws -> Record? {
        guard let data = try await request(endpoint, params) else { return nil }
        return try JSONDecoder().decode(Record.self, from: data)
    }

    /// GET an endpoint: the body, `nil` for 404 ("not found"); 5xx throws `.busy`.
    private func request(_ endpoint: String, _ params: [String: String]) async throws -> Data? {
        var components = URLComponents(url: baseURL.appending(path: endpoint), resolvingAgainstBaseURL: false)
        components?.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        switch status {
        case 200..<300: return data
        case 404: return nil
        case 500...: throw Failure.busy
        default: throw Failure.badResponse(status)
        }
    }

    /// LRCLIB asks clients to identify themselves.
    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Sun-iOS/\(version) (personal music player; https://github.com/Carlos-J-Falconett/Personal-Music-app)"
    }
}

#if DEBUG
/// Generated synced lyrics for the demo library's songs (`SUN_DEMO_LIBRARY=1`), so the
/// Lyrics page can be tried in the simulator: the demo titles don't exist on LRCLIB.
/// Every fifth song has none, and songs titled "Interlude" are instrumental.
nonisolated struct DemoLyricsProvider: LyricsProvider {
    let id = "demo"

    func lyrics(for query: LyricsQuery) async throws -> LyricsLookup {
        if query.title.localizedCaseInsensitiveContains("interlude") { return .instrumental }
        // A stable choice (hashValue changes every launch).
        let code = query.title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        if code % 5 == 0 && !query.title.hasPrefix("Opening") { return .notFound(certain: true) }
        let words = ["Lights", "on", "the", "water", "we", "keep", "running", "through", "the", "night",
                     "glass", "rooms", "and", "satellites", "calling", "your", "name"]
        let count = max(Int(query.duration / 3), 6)
        let lines = (0..<count).map { index in
            let start = index * 3 % words.count
            let text = (0..<4).map { words[(start + $0) % words.count] }.joined(separator: " ").capitalized
            return Lyrics.Line(time: 1 + Double(index) * 3, text: "\(text) (\(query.title))")
        }
        return .found(Lyrics(kind: .synced, lines: lines, source: id))
    }
}
#endif
