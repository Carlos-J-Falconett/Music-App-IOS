import Foundation

// The home media server's API (see README → Media Server). The server runs on the PC
// and is reached over HTTPS through Tailscale, so no App Transport Security exceptions
// are needed. Every request except /api/health carries the device token as a Bearer
// header; the token comes from the Keychain (`ServerTokenStore`), never from the source.

/// One file on the server.
nonisolated struct ServerItem: Codable, Identifiable, Sendable, Equatable {
    let id: String
    /// "library:rel_path", the song's identity across devices.
    let key: String
    let library: String
    /// Always "/"-separated, mirroring the folders on the PC ("Artist/Album/01 Song.flac").
    let relPath: String
    let kind: String
    let size: Int64
    let mtime: Double
    let deleted: Bool
    let seq: Int
    let meta: ItemMeta
}

nonisolated struct ItemMeta: Codable, Sendable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var trackNo: Int?
    var discNo: Int?
    var year: Int?
    var genre: String?
    var duration: Double?
    var codec: String?
    var sampleRate: Double?
    var bitDepth: Int?
    var bitrate: Int?
    // books
    var author: String?
    var format: String?
}

/// One page of the change feed.
nonisolated struct ItemsPage: Codable, Sendable {
    let items: [ServerItem]
    let nextSince: Int
    let more: Bool
}

/// One library on the server (music, hires, books…).
nonisolated struct ServerLibrary: Decodable, Sendable, Identifiable, Equatable {
    let name: String
    let kind: String
    let count: Int?
    /// False when the drive holding it isn't connected to the PC.
    let available: Bool
    var id: String { name }

    /// Libraries with songs (not books or other files).
    var isMusic: Bool {
        let kind = kind.lowercased()
        return kind == "audio" || kind == "music" || name == "music" || name == "hires"
    }

    private enum CodingKeys: String, CodingKey { case name, kind, count, items, itemCount, available }

    init(name: String, kind: String, count: Int?, available: Bool) {
        self.name = name
        self.kind = kind
        self.count = count
        self.available = available
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        count = (try? container.decodeIfPresent(Int.self, forKey: .count))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .itemCount))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .items))
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? true
    }
}

/// What went wrong talking to the server, in words for Settings.
nonisolated enum MediaServerError: Error, Equatable, LocalizedError {
    /// No address or token saved yet.
    case notSetUp
    /// 401: the token is wrong or was changed on the server.
    case unauthorized
    /// 502: Tailscale is fine but the server isn't running on the PC.
    case serverClosed
    /// The server couldn't be reached at all (Tailscale off, PC asleep, no internet).
    case unreachable(String)
    case badResponse(Int)
    /// The file ended before its full size (the download can resume next time).
    case incomplete(String)

    var errorDescription: String? {
        switch self {
        case .notSetUp: "Add the server address and the device token first."
        case .unauthorized: "The server rejected the token. Paste it again (it may have been changed on the server)."
        case .serverClosed: "The server isn't running on the PC. Open Media Server from the tray on the PC."
        case .unreachable(let detail): "Can't reach the server. Check that Tailscale is connected on this iPhone and on the PC. (\(detail))"
        case .badResponse(let status): "The server answered with an error (\(status))."
        case .incomplete(let path): "The download of \(path) stopped early. Sync again to resume it."
        }
    }

    static func from(status: Int) -> MediaServerError? {
        switch status {
        case 200..<300: nil
        case 401, 403: .unauthorized
        case 502, 503, 504: .serverClosed
        default: .badResponse(status)
        }
    }
}

nonisolated struct MediaServerClient: Sendable {
    let baseURL: URL
    let token: String
    /// Swappable for tests (a stubbed URLProtocol); downloads use its configuration too.
    var session: URLSession = .shared

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// The saved address and Keychain token, or `nil` if either is missing.
    static func configured(address: String) -> MediaServerClient? {
        guard let url = normalizedURL(address), let token = ServerTokenStore.token, !token.isEmpty else { return nil }
        return MediaServerClient(baseURL: url, token: token)
    }

    /// "name.ts.net" or "https://name.ts.net/" → "https://name.ts.net".
    static func normalizedURL(_ address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host() != nil else { return nil }
        return url
    }

    func request(_ path: String, query: [URLQueryItem] = [], authorized: Bool = true) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        if authorized { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// GET returning the body, mapping HTTP errors and connection failures to `MediaServerError`.
    private func data(for request: URLRequest, allowNotFound: Bool = false) async throws -> Data? {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw MediaServerError.unreachable(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if allowNotFound && status == 404 { return nil }
        if let error = MediaServerError.from(status: status) { throw error }
        return data
    }

    /// True when the server answers (no token needed).
    func health() async throws -> Bool {
        try await data(for: request("api/health", authorized: false)) != nil
    }

    func libraries() async throws -> [ServerLibrary] {
        guard let data = try await data(for: request("api/libraries")) else { return [] }
        // Either a plain list or {"libraries": [...]}.
        if let list = try? Self.decoder.decode([ServerLibrary].self, from: data) { return list }
        struct Wrapped: Decodable { let libraries: [ServerLibrary] }
        return try Self.decoder.decode(Wrapped.self, from: data).libraries
    }

    func items(library: String, since: Int, limit: Int = 500) async throws -> ItemsPage {
        let data = try await data(for: request("api/items", query: [
            .init(name: "library", value: library),
            .init(name: "since", value: String(since)),
            .init(name: "limit", value: String(limit)),
        ]))
        return try Self.decoder.decode(ItemsPage.self, from: data ?? Data())
    }

    /// The item's embedded artwork or folder image, or `nil` if it has none (404).
    func cover(for item: ServerItem) async throws -> Data? {
        try await data(for: request("api/items/\(item.id)/cover"), allowNotFound: true)
    }

    /// Downloads the item to `destination`, through `destination.part` so an interrupted
    /// download resumes where it stopped (`Range: bytes=N-`; a 206 reply appends, a 200
    /// reply starts over). Replaces an older copy and keeps the server's modification date.
    func download(_ item: ServerItem, to destination: URL,
                  progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let part = destination.deletingLastPathComponent().appending(path: destination.lastPathComponent + ".part")
        var have = Self.fileSize(part) ?? 0
        if have > item.size {
            try? fileManager.removeItem(at: part)
            have = 0
        }
        if have < item.size {
            var request = request("api/items/\(item.id)/file")
            request.timeoutInterval = 60
            if have > 0 { request.setValue("bytes=\(have)-", forHTTPHeaderField: "Range") }
            try await PartFileDownload(part: part, expected: item.size, progress: progress).run(request, configuration: session.configuration)
        }
        guard Self.fileSize(part) == item.size else { throw MediaServerError.incomplete(item.relPath) }
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: part, to: destination)
        try? fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: item.mtime)], ofItemAtPath: destination.path)
    }

    static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
}

/// Streams a file download into a `.part` file as it arrives (so nothing is lost if it's
/// interrupted): appends after a 206 Partial Content reply, starts over after a 200.
nonisolated final class PartFileDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let part: URL
    private let expected: Int64
    private let progress: @Sendable (Double) -> Void
    // Only touched on the session's serial delegate queue.
    private var handle: FileHandle?
    private var written: Int64 = 0
    private var failure: (any Error)?
    private var continuation: CheckedContinuation<Void, any Error>?

    init(part: URL, expected: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.part = part
        self.expected = expected
        self.progress = progress
    }

    func run(_ request: URLRequest, configuration: URLSessionConfiguration) async throws {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                queue.addOperation {
                    self.continuation = continuation
                    task.resume()
                }
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let fileManager = FileManager.default
        do {
            switch status {
            case 206:
                if !fileManager.fileExists(atPath: part.path) { fileManager.createFile(atPath: part.path, contents: nil) }
                handle = try FileHandle(forWritingTo: part)
                written = Int64(try handle?.seekToEnd() ?? 0)
            case 200:
                // The server sent the whole file: start the part file over.
                fileManager.createFile(atPath: part.path, contents: nil)
                handle = try FileHandle(forWritingTo: part)
                written = 0
            default:
                failure = MediaServerError.from(status: status) ?? MediaServerError.badResponse(status)
                completionHandler(.cancel)
                return
            }
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try handle?.write(contentsOf: data)
            written += Int64(data.count)
            if expected > 0 { progress(min(Double(written) / Double(expected), 1)) }
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        try? handle?.close()
        handle = nil
        if let failure {
            continuation?.resume(throwing: failure)
        } else if let urlError = error as? URLError {
            // Cancelled by Stop (the part file stays, so the next sync resumes it).
            continuation?.resume(throwing: urlError.code == .cancelled
                                 ? CancellationError() : MediaServerError.unreachable(urlError.localizedDescription))
        } else if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}

/// The server as a song source, so songs not downloaded yet can be listed (and later
/// streamed). Groundwork: the player plays files on the phone, so nothing uses it yet.
/// Streaming would need the token as a header on the asset, e.g.
/// `AVURLAsset(url:options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer …"]])`.
nonisolated struct LocalServerSongSource: SongSource {
    let client: MediaServerClient
    var libraries = ["music", "hires"]
    let id = "media-server"

    func songs() async throws -> [RemoteSong] {
        var all: [RemoteSong] = []
        for library in libraries {
            var since = 0
            while true {
                let page = try await client.items(library: library, since: since)
                all += page.items.filter { !$0.deleted && $0.kind == "audio" }.map {
                    RemoteSong(id: $0.id, title: $0.meta.title ?? "", artist: $0.meta.artist ?? "",
                               album: $0.meta.album ?? "", duration: $0.meta.duration ?? 0)
                }
                since = page.nextSince
                if !page.more { break }
            }
        }
        return all
    }

    func audioURL(for song: RemoteSong) async throws -> URL {
        client.baseURL.appending(path: "api/items/\(song.id)/file")
    }
}
