#if DEBUG
import AVFoundation
import SwiftData

/// Debug-only, read-only report of how songs are credited: artists with feature
/// markers, titles with "(feat. …)", and Album Artist tags read straight from the
/// files. Prints lines prefixed `[Tags]`; changes nothing and plays nothing.
///
/// Turned on with the environment variable `SUN_TAG_CHECK=1`.
enum TagCheck {
    static var runOnLaunch: Bool { ProcessInfo.processInfo.environment["SUN_TAG_CHECK"] == "1" || forceOn }
    /// Set to `true` temporarily to run it from Xcode's Run button (which can't pass env vars).
    private static let forceOn = false
    /// Only report file protection this run.
    private static let onlyProtection = false
    /// Only report inferred groups this run.
    private static let onlyGroups = true

    private static let markers = [" & ", ", ", " x ", " X ", "feat", "Feat", "FEAT", " ft.", " Ft.", "f/", " with ", " With ", " and "]

    static func run(context: ModelContext) async {
        let tracks = (try? context.fetch(FetchDescriptor<Track>())) ?? []
        print("[Tags] \(tracks.count) tracks")

        // File protection: "complete" files can't be read while the phone is locked.
        var protection: [String: Int] = [:]
        var completeExamples: [String] = []
        for track in tracks {
            let attributes = try? FileManager.default.attributesOfItem(atPath: track.fileURL.path)
            let value = (attributes?[.protectionKey] as? FileProtectionType)?.rawValue ?? "none/unknown"
            protection[value, default: 0] += 1
            if value == FileProtectionType.complete.rawValue, completeExamples.count < 15 {
                completeExamples.append("\(track.artist) – \(track.title)")
            }
        }
        print("[Tags] Protection: \(protection.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))")
        for example in completeExamples { print("[Tags] P | \(example)") }
        if onlyProtection { print("[Tags] Done"); return }

        if onlyGroups {
            // Every member → group link the index infers, with the song that caused it.
            let index = ArtistIndex(sources: tracks.map(\.creditSource))
            print("[Tags] --- Inferred groups: \(index.groupOf.count)")
            for (member, group) in index.groupOf.sorted(by: { $0.key < $1.key }) {
                let example = tracks.first { track in
                    index.credits(for: track.id)?.main.contains { Track.key(for: $0) == member } == true
                        && index.credits(for: track.id)?.albumArtists.contains { Track.key(for: $0) == group } == true
                }
                print("[Tags] G | \(index.name(for: member)) → \(index.name(for: group)) | via: \(example.map { "\($0.artist) – \($0.title) [\($0.album)] AA='\($0.albumArtist ?? "nil")'" } ?? "?")")
            }
            for track in tracks where track.artist.localizedCaseInsensitiveContains("mar") && track.artist.localizedCaseInsensitiveContains("as") {
                print("[Tags] M | \(track.artist) | \(track.title) | \(track.album) | AA='\(track.albumArtist ?? "nil")'")
            }
            print("[Tags] Done")
            return
        }

        let featured = tracks.filter { track in markers.contains { track.artist.contains($0) } }
        let titled = tracks.filter { track in
            let lower = track.title.lowercased()
            return ["(feat", "[feat", "(ft", "[ft", "(with", "[with", "feat.", " ft. "].contains { lower.contains($0) }
        }
        let tenAlbums = tracks.filter { $0.album.localizedCaseInsensitiveContains("TEN") || $0.album.localizedCaseInsensitiveContains("Story Goes On") }

        print("[Tags] --- Artist fields with feature markers: \(featured.count)")
        for track in featured.sorted(by: { $0.artist < $1.artist }).prefix(120) {
            print("[Tags] A | \(track.artist) | \(track.title) | \(track.album)")
        }
        print("[Tags] --- Titles with feature markers: \(titled.count)")
        for track in titled.sorted(by: { $0.title < $1.title }).prefix(80) {
            print("[Tags] T | \(track.artist) | \(track.title) | \(track.album)")
        }

        // Album Artist tags: every song on TEN-like albums, plus a sample of featured songs.
        let sample = Array(tenAlbums) + Array(featured.prefix(25))
        let files = sample.map { (title: $0.title, artist: $0.artist, album: $0.album, url: $0.fileURL) }
        print("[Tags] --- Album Artist tags (\(files.count) files)")
        for line in await albumArtists(files) { print("[Tags] AA | \(line)") }

        // Distinct artist names, to see which group/member names exist.
        let artists = Dictionary(grouping: tracks, by: \.artistKey).map { ($0.value.first?.artist ?? $0.key, $0.value.count) }
        print("[Tags] --- \(artists.count) distinct artist fields; those containing TWICE or a member-like name:")
        let twiceMembers = ["twice", "nayeon", "jeongyeon", "momo", "sana", "jihyo", "mina", "dahyun", "chaeyoung", "tzuyu"]
        for (name, count) in artists.sorted(by: { $0.0 < $1.0 }) where twiceMembers.contains(where: { name.lowercased().contains($0) }) {
            print("[Tags] N | \(name) | \(count) songs")
        }
        print("[Tags] Done")
    }

    @concurrent
    private static func albumArtists(_ files: [(title: String, artist: String, album: String, url: URL)]) async -> [String] {
        var lines: [String] = []
        for file in files {
            let asset = AVURLAsset(url: file.url)
            let items = ((try? await asset.load(.metadata)) ?? []) + ((try? await asset.load(.commonMetadata)) ?? [])
            var found: [String] = []
            for item in items {
                let id = item.identifier?.rawValue ?? ""
                let lower = id.lowercased()
                guard lower.contains("albumartist") || lower.contains("aart") || lower.contains("tpe2") || lower.contains("album artist") || lower.contains("band") else { continue }
                if let value = try? await item.load(.stringValue) { found.append("\(id)=\(value)") }
            }
            lines.append("\(file.artist) | \(file.title) | \(file.album) | \(found.isEmpty ? "no album artist tag" : found.joined(separator: "; ")) | .\(file.url.pathExtension)")
        }
        return lines
    }
}
#endif
