#if DEBUG
import AVFoundation
import SwiftData
import UIKit

/// Generated audio and artwork for tests and the simulator demo library, so
/// testing never needs anyone's real music or pictures.
nonisolated enum AudioFixtures {
    /// Writes a sine tone as an uncompressed CAF file and returns its URL.
    @discardableResult
    static func writeTone(
        to url: URL, seconds: Double, sampleRate: Double = 44_100, channels: AVAudioChannelCount = 2,
        frequency: Double = 440
    ) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(max(seconds * sampleRate, 0))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return url }
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(frames) {
                samples[frame] = Float(0.2 * sin(2 * .pi * frequency * Double(frame) / sampleRate))
            }
        }
        try file.write(from: buffer)
        return url
    }

    /// Writes a sine tone as a compressed AAC file (.m4a), for lossy-vs-lossless checks.
    @discardableResult
    static func writeAAC(to url: URL, seconds: Double, sampleRate: Double = 44_100, bitRate: Int = 128_000) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let pcm = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: bitRate,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(max(seconds * sampleRate, 0))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: frames) else { return url }
        buffer.frameLength = frames
        for channel in 0..<2 {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(frames) { samples[frame] = Float(0.2 * sin(2 * .pi * 440 * Double(frame) / sampleRate)) }
        }
        try file.write(from: buffer)
        return url
    }

    /// Writes an audio file with no samples at all.
    @discardableResult
    static func writeEmpty(to url: URL) throws -> URL {
        try writeTone(to: url, seconds: 0)
    }

    /// Writes random bytes under an audio file name (a "corrupted" song).
    @discardableResult
    static func writeGarbage(to url: URL, byteCount: Int = 4096) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max) }
        try Data(bytes).write(to: url)
        return url
    }

    /// A generated gradient cover as JPEG data (`side` px square).
    static func coverArt(side: CGFloat, hue: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let image = renderer.image { context in
            let colors = [
                UIColor(hue: hue, saturation: 0.75, brightness: 0.95, alpha: 1).cgColor,
                UIColor(hue: (hue + 0.18).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.35, alpha: 1).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            }
            UIColor.white.withAlphaComponent(0.25).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: side * 0.25, y: side * 0.25, width: side * 0.5, height: side * 0.5))
        }
        return image.jpegData(compressionQuality: 0.85) ?? Data()
    }

    /// A generated "artist picture": a simple figure (head and shoulders).
    /// - `transparent`: the figure alone on a see-through background (PNG), like a cut-out.
    /// - otherwise: a wide 16:9 picture with a gradient behind the figure (JPEG), to check
    ///   that non-square pictures show whole.
    static func artistPicture(transparent: Bool, hue: CGFloat) -> Data {
        let size = transparent ? CGSize(width: 900, height: 1200) : CGSize(width: 1600, height: 900)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !transparent
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            if !transparent {
                let colors = [
                    UIColor(hue: hue, saturation: 0.6, brightness: 0.7, alpha: 1).cgColor,
                    UIColor(hue: (hue + 0.5).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.3, alpha: 1).cgColor,
                ] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                }
                // Marks at the far left and right edges, so any cropping is easy to spot.
                UIColor.white.setFill()
                cg.fill(CGRect(x: 0, y: 0, width: 24, height: size.height))
                cg.fill(CGRect(x: size.width - 24, y: 0, width: 24, height: size.height))
            }
            let figure = UIColor(hue: hue, saturation: 0.85, brightness: 0.95, alpha: 1)
            figure.setFill()
            let head = min(size.width, size.height) * 0.28
            let centerX = size.width / 2
            cg.fillEllipse(in: CGRect(x: centerX - head / 2, y: size.height * 0.18, width: head, height: head))
            let shoulders = UIBezierPath(roundedRect: CGRect(x: centerX - head * 1.1, y: size.height * 0.18 + head * 1.08,
                                                             width: head * 2.2, height: size.height), cornerRadius: head * 0.8)
            shoulders.fill()
        }
        return (transparent ? image.pngData() : image.jpegData(compressionQuality: 0.9)) ?? Data()
    }
}

/// Fills an empty library with generated songs so the UI can be tested in the
/// simulator. Turned on by launching with the environment variable `SUN_DEMO_LIBRARY=1`.
enum DemoLibrary {
    static var isRequested: Bool { ProcessInfo.processInfo.environment["SUN_DEMO_LIBRARY"] == "1" }

    private static let artists: [(name: String, albums: [String], genre: String)] = [
        ("Aurora Vale", ["Northern Lights", "Glass Rooms"], "Synthpop"),
        ("The Tidewaters", ["Low Tide"], "Indie Rock"),
        ("Kenji Sato", ["Night Train"], "Jazz"),
        ("Mira Santos", ["Calor", "Fiesta Lenta"], "Latin"),
        ("Bassline Theory", ["Subharmonics"], "Electronic"),
        ("Hollow Pines", ["Embers"], "Folk"),
    ]
    private static let songTitles = ["Opening", "Satellite", "Paper Planes", "Undertow", "Midnight Drive", "Slow Bloom"]

    static func seedIfEmpty(context: ModelContext) async {
        let existing = (try? context.fetchCount(FetchDescriptor<Track>())) ?? 0
        guard existing == 0 else { return }
        var made = 0
        for (artistIndex, artist) in artists.enumerated() {
            for (albumIndex, album) in artist.albums.enumerated() {
                let hue = CGFloat(artistIndex * 2 + albumIndex) / 12
                let coverKey = await ArtCache.storeInBackground(AudioFixtures.coverArt(side: 900, hue: hue))
                for (songIndex, title) in songTitles.prefix(albumIndex == 0 ? 6 : 4).enumerated() {
                    let relativePath = "Demo/\(artist.name)/\(album)/\(songIndex + 1) - \(title).caf"
                    let url = LibraryLocations.musicDirectory.appending(path: relativePath)
                    // Alternate sample rates and channel counts, like a real mixed library.
                    let rate = made.isMultiple(of: 3) ? 48_000.0 : 44_100.0
                    let channels: AVAudioChannelCount = made.isMultiple(of: 5) ? 1 : 2
                    let seconds = 20.0 + Double(songIndex * 7)
                    _ = try? AudioFixtures.writeTone(to: url, seconds: seconds, sampleRate: rate, channels: channels,
                                                 frequency: 220 + Double(made % 12) * 40)
                    context.insert(Track(
                        relativePath: relativePath, title: title, artist: artist.name, album: album,
                        genre: artist.genre, year: 2015 + artistIndex, trackNumber: songIndex + 1,
                        duration: seconds, coverKey: coverKey
                    ))
                    made += 1
                }
            }
        }
        try? context.save()
        print("[Demo] Seeded \(made) generated songs")
    }

    /// Extra generated songs for the artist-credit features: songs with featured
    /// artists, and a group album ("PRISM") where each member has a solo song,
    /// like TWICE's TEN: The Story Goes On. Added once, even to an existing demo library.
    /// Gives two demo artists generated pictures (if they have none): Aurora Vale a wide
    /// 16:9 one (checks pictures show whole, uncropped), and Kenji Sato a transparent cut-out (checks the outline glow).
    static func seedArtistPicturesIfMissing(context: ModelContext) async {
        let existing = Set(((try? context.fetch(FetchDescriptor<ArtistImage>())) ?? []).map(\.artistKey))
        for (name, transparent, hue) in [("Aurora Vale", false, 0.02), ("Kenji Sato", true, 0.33)] {
            let key = Track.key(for: name)
            guard !existing.contains(key),
                  let artKey = await ArtCache.storeInBackground(AudioFixtures.artistPicture(transparent: transparent, hue: hue))
            else { continue }
            context.insert(ArtistImage(artistKey: key, artKey: artKey))
        }
        try? context.save()
    }

    /// Compressed (AAC) demo songs for the Lossless Only filter and duplicates: a lossy copy
    /// of Aurora Vale's "Satellite" (same length as the lossless one, so the lossless copy
    /// stays and this one is hidden) and a song that only exists as AAC.
    static func seedFormatExamplesIfMissing(context: ModelContext) async {
        let marker = "Demo/Formats/"
        let existing = (try? context.fetch(FetchDescriptor<Track>())) ?? []
        guard !existing.isEmpty, !existing.contains(where: { $0.relativePath.hasPrefix(marker) }) else { return }
        let cover = existing.first { $0.artist == "Aurora Vale" && $0.album == "Northern Lights" }?.coverKey
        for (file, title, album, seconds) in [("Satellite.m4a", "Satellite", "Satellite (Single)", 27.0),
                                              ("Radio Edit.m4a", "Radio Edit", "Satellite (Single)", 18.0)] {
            let relativePath = marker + file
            let url = LibraryLocations.musicDirectory.appending(path: relativePath)
            guard (try? AudioFixtures.writeAAC(to: url, seconds: seconds)) != nil else { continue }
            let track = Track(relativePath: relativePath, title: title, artist: "Aurora Vale", album: album,
                              genre: "Synthpop", year: 2026, trackNumber: 1, duration: seconds, coverKey: cover)
            track.audioFormat = AudioFormat.read(url: url)
            context.insert(track)
        }
        try? context.save()
    }

    static func seedCreditExamplesIfMissing(context: ModelContext) async {
        let marker = "Demo/PRISM/"
        let existing = (try? context.fetch(FetchDescriptor<Track>())) ?? []
        guard !existing.isEmpty, !existing.contains(where: { $0.relativePath.hasPrefix(marker) }) else { return }

        let groupCover = await ArtCache.storeInBackground(AudioFixtures.coverArt(side: 900, hue: 0.83))
        let featCover = existing.first { $0.artist == "Aurora Vale" }?.coverKey
        let songs: [(artist: String, title: String, album: String, albumArtist: String, cover: String?)] = [
            ("PRISM", "Ten Colors", "PRISM TEN", "PRISM", groupCover),
            ("LUMI", "Glow Up", "PRISM TEN", "PRISM", groupCover),
            ("NOVA", "Starfall", "PRISM TEN", "PRISM", groupCover),
            ("SOLA", "Sun Kissed", "PRISM TEN", "PRISM", groupCover),
            ("PRISM feat. Kenji Sato", "Late Night Prism", "PRISM TEN", "PRISM", groupCover),
            ("Aurora Vale & Kenji Sato", "Duet Lights", "Northern Lights", "Aurora Vale", featCover),
            ("Mira Santos feat. Hollow Pines / Cielo Rojo", "Fuego Lento", "Calor", "Mira Santos",
             existing.first { $0.artist == "Mira Santos" }?.coverKey),
            ("Of Mice & Men", "Band Name Test", "Ampersand", "Of Mice & Men", groupCover),
        ]
        for (number, song) in songs.enumerated() {
            let relativePath = "\(song.albumArtist == "PRISM" ? marker : "Demo/Credits/")\(number + 1) - \(song.title).caf"
            let url = LibraryLocations.musicDirectory.appending(path: relativePath)
            _ = try? AudioFixtures.writeTone(to: url, seconds: 25, sampleRate: number.isMultiple(of: 2) ? 44_100 : 48_000,
                                             frequency: 300 + Double(number) * 35)
            context.insert(Track(
                relativePath: relativePath, title: song.title, artist: song.artist, album: song.album,
                genre: "K-Pop", year: 2025, trackNumber: number + 1, duration: 25, coverKey: song.cover,
                albumArtist: song.albumArtist
            ))
        }
        try? context.save()
        print("[Demo] Added \(songs.count) credit example songs")
    }
}
#endif
