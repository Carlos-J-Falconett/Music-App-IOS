import AVFoundation
import Foundation
import SwiftData
import Testing
import UIKit
@testable import Music_App

@MainActor
struct QueueTests {
    private func makeQueue(_ count: Int) -> (QueueManager, [UUID]) {
        let queue = QueueManager()
        queue.shuffler = { $0.reversed() }   // predictable "shuffle"
        let ids = (0..<count).map { _ in UUID() }
        return (queue, ids)
    }

    @Test func startsAtRequestedSong() {
        let (queue, ids) = makeQueue(4)
        queue.setQueue(ids, startAt: 2, shuffle: false)
        #expect(queue.current?.trackID == ids[2])
        #expect(queue.upcoming.map(\.trackID) == [ids[3]])
    }

    @Test func shuffleKeepsCurrentFirstAndRestoresOrder() {
        let (queue, ids) = makeQueue(4)
        queue.setQueue(ids, startAt: 1, shuffle: false)
        queue.toggleShuffle()
        #expect(queue.current?.trackID == ids[1])
        #expect(queue.upcoming.map(\.trackID) == [ids[3], ids[2], ids[0]])
        queue.toggleShuffle()
        #expect(queue.current?.trackID == ids[1])
        #expect(queue.upcoming.map(\.trackID) == [ids[2], ids[3]])
    }

    @Test func repeatModes() {
        let (queue, ids) = makeQueue(2)
        queue.setQueue(ids, startAt: 1, shuffle: false)

        queue.repeatMode = .off
        #expect(queue.advance(automatic: true) == nil)

        queue.repeatMode = .one
        #expect(queue.advance(automatic: true)?.trackID == ids[1])   // replays itself
        #expect(queue.advance(automatic: false) == nil)              // manual Next doesn't wrap

        queue.repeatMode = .all
        #expect(queue.advance(automatic: true)?.trackID == ids[0])   // wraps around
    }

    @Test func playNextAndReorder() {
        let (queue, ids) = makeQueue(3)
        queue.setQueue(ids, startAt: 0, shuffle: false)
        let extra = UUID()
        queue.playNext(extra)
        #expect(queue.upcoming.map(\.trackID) == [extra, ids[1], ids[2]])

        queue.moveUpcoming(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(queue.upcoming.map(\.trackID) == [ids[1], ids[2], extra])

        queue.removeUpcoming(atOffsets: IndexSet(integer: 1))
        #expect(queue.upcoming.map(\.trackID) == [ids[1], extra])

        queue.clearUpcoming()
        #expect(queue.upcoming.isEmpty)
        #expect(queue.current?.trackID == ids[0])
    }
}

struct ListeningRuleTests {
    @Test func shortSessionsAreNotSaved() {
        #expect(!ListeningRules.shouldSave(listened: 4.9))
        #expect(ListeningRules.shouldSave(listened: 5))
    }

    @Test func playNeedsHalfTheSongOrFourMinutes() {
        #expect(ListeningRules.isPlay(listened: 60, duration: 120))
        #expect(!ListeningRules.isPlay(listened: 59, duration: 120))
        #expect(ListeningRules.isPlay(listened: 240, duration: 900))   // long track: 4 min cap
        #expect(!ListeningRules.isPlay(listened: 239, duration: 0))    // unknown length
    }
}

struct StatsTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func day(_ offset: Int, from today: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))!
    }

    @Test func streaks() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        // Played yesterday and the two days before, then a gap, then a 4-day run.
        let days: Set<Date> = [-1, -2, -3, -6, -7, -8, -9].reduce(into: []) { $0.insert(day($1, from: today)) }
        let result = StatsCalendar.streaks(days: days, today: today, calendar: calendar)
        #expect(result.current == 3)   // ends yesterday because nothing played today yet
        #expect(result.longest == 4)
    }

    @Test func summaryTotalsAndTopLists() {
        let now = Date()
        let song = UUID()
        func record(_ seconds: Double, artist: String, counted: Bool, daysAgo: Double = 0, id: UUID = UUID()) -> SessionRecord {
            SessionRecord(start: now.addingTimeInterval(-daysAgo * 86_400), seconds: seconds, counted: counted,
                          trackID: id, title: "T", artist: artist, album: "A", genre: "G")
        }
        let records = [
            record(300, artist: "Alpha", counted: true, id: song),
            record(100, artist: "alpha", counted: false, id: song),
            record(100, artist: "Beta", counted: true),
            record(999, artist: "Old", counted: true, daysAgo: 40),
        ]
        let month = StatsSummary(records: records, period: .month, now: now)
        #expect(month.totalSeconds == 500)
        #expect(month.plays == 2)
        #expect(month.songCount == 2)
        #expect(month.artistCount == 2)                 // artist names compare case-insensitively
        #expect(month.topArtists.first?.title == "Alpha")
        #expect(month.topArtists.first?.fraction == 0.8)

        let allTime = StatsSummary(records: records, period: .allTime, now: now)
        #expect(allTime.plays == 3)
    }
}

struct ThemeTests {
    @Test func accentLightMixesTwentyPercentTowardWhite() {
        var palette = ThemePalette()
        palette.accent = "#000000"
        #expect(palette.accentLight.hex == "#333333")
    }

    @Test func elementsFollowTheirRole() {
        var palette = ThemePalette()
        palette.set(.primary, to: "#FF0000")
        #expect(palette.resolved(.playButton).hex == "#FF0000")
        #expect(palette.resolved(.tabBar).hex == "#FF0000")
        palette.set(.highlight, to: "#00FF00")
        #expect(palette.favorite == "#00FF00" && palette.waveTop == "#00FF00")
    }

    @Test func derivedColorsStayReadable() {
        var palette = ThemePalette()
        palette.set(.primary, to: "#FFE066")     // light yellow → dark icon on the play button
        #expect(palette.accentText == "#000000")
        palette.set(.primary, to: "#1D3A8A")     // dark blue → white icon
        #expect(palette.accentText == "#FFFFFF")
        palette.set(.primary, to: "#FF8A1F")     // Sunset orange → dark icon (white would be ~2.4:1)
        #expect(palette.accentText == "#000000")
        #expect(ThemePreset.sun.palette.accentText == "#FFFFFF")   // default blue keeps its white icon
        palette.set(.background, to: "#000000")
        #expect(palette.panels != palette.window)  // panels are lifted slightly from the background
    }

    @Test func presetsIncludeOrangeBlueRedAndAreDistinct() throws {
        let sunset = try #require(ThemePreset.all.first { $0.name == "Sunset" })
        let primary = try #require(RGBA(hex: sunset.palette.hex(for: .primary)))
        let secondary = try #require(RGBA(hex: sunset.palette.hex(for: .secondary)))
        let highlight = try #require(RGBA(hex: sunset.palette.hex(for: .highlight)))
        #expect(primary.red > 0.9 && primary.green > 0.4 && primary.blue < 0.3)   // orange
        #expect(secondary.blue > 0.9 && secondary.red < 0.3)                      // blue
        #expect(highlight.red > 0.9 && highlight.green < 0.3)                     // red
        #expect(Set(ThemePreset.all.map(\.name)).count == ThemePreset.all.count)
        #expect(ThemePalette.default.hasSameColors(as: ThemePreset.sun.palette))
    }

    @Test func olderThemesWithPerElementColorsStillLoad() throws {
        let old = ##"{"accent":"#FF8800","overrides":{"playButton":"#00FF00"}}"##
        let palette = try JSONDecoder().decode(ThemePalette.self, from: Data(old.utf8))
        #expect(palette.accent == "#FF8800")
        #expect(palette.resolved(.playButton).hex == "#FF8800")   // old per-element colors are ignored
    }

    @Test func hexParsing() {
        #expect(RGBA(hex: "#0A84FF")?.hex == "#0A84FF")
        #expect(RGBA(hex: "nope") == nil)
    }
}

struct LibraryTests {
    @Test func folderFallbackForUntaggedFiles() {
        let meta = TagReader.fallback(for: "Music/Some Artist/Great Album/03 - Song Name.flac")
        #expect(meta.artist == "Some Artist")
        #expect(meta.album == "Great Album")
        #expect(meta.title == "Song Name")
        #expect(meta.trackNumber == 3)
    }

    @Test func looseFilesHaveUnknownArtist() {
        let meta = TagReader.fallback(for: "Imported/track.mp3")
        #expect(meta.artist == TrackMetadata.unknownArtist)
        #expect(meta.album == TrackMetadata.unknownAlbum)
        #expect(meta.title == "track")
    }

    @Test func genreAndYearCleanup() {
        #expect(TagReader.cleanGenre("(17) Rock") == "Rock")
        #expect(TagReader.parseYear("2019-05-01") == 2019)
    }
}

struct SpectrumTests {
    @Test func silenceMapsToZeroAndLoudSineLightsItsBin() {
        let fftSize = 2048
        let sampleRate = 44_100.0
        let silent = SpectrumAnalyzer.levels(fromMagnitudes: [Float](repeating: 0, count: fftSize / 2), sampleRate: sampleRate, fftSize: fftSize)
        #expect(silent.count == SpectrumAnalyzer.binCount)
        #expect(silent.allSatisfy { $0 == 0 })

        // A full-scale 1 kHz tone: its bin should be near the top, distant bins stay dark.
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        let bin = Int(1000 / (sampleRate / Double(fftSize)))
        magnitudes[bin] = Float(fftSize) / 4
        let levels = SpectrumAnalyzer.levels(fromMagnitudes: magnitudes, sampleRate: sampleRate, fftSize: fftSize)
        #expect((levels.max() ?? 0) > 0.9)
        #expect(levels[0] == 0)
    }
}

// MARK: - Playback robustness (generated audio only)

/// Plays generated files through the real engine. Covers the bug where switching
/// between 44.1 kHz and 48 kHz songs broke the audio graph (error -10868) and made
/// every following skip freeze the app for ~5 seconds.
@MainActor
@Suite(.serialized)
struct PlaybackRobustnessTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "SunFixtures-\(UUID().uuidString)")

    @Test func mixedFormatsLoadBackToBackWithoutStalling() throws {
        let engine = PlayerEngine()
        defer { engine.stop() }
        let formats: [(rate: Double, channels: AVAudioChannelCount)] = [
            (44_100, 2), (48_000, 2), (48_000, 1), (96_000, 2), (22_050, 1), (8_000, 1), (44_100, 2),
        ]
        let clock = ContinuousClock()
        for (index, format) in formats.enumerated() {
            let url = try AudioFixtures.writeTone(
                to: folder.appending(path: "\(index).caf"), seconds: 0.5,
                sampleRate: format.rate, channels: format.channels
            )
            let elapsed = try clock.measure { try engine.load(url, autoplay: true) }
            #expect(abs(engine.duration - 0.5) < 0.01, "duration for \(format)")
            #expect(elapsed < .seconds(1), "loading \(format) took \(elapsed)")
        }
    }

    @Test func veryShortFilePlays() throws {
        let engine = PlayerEngine()
        defer { engine.stop() }
        let url = try AudioFixtures.writeTone(to: folder.appending(path: "short.caf"), seconds: 0.001)
        try engine.load(url, autoplay: true)
        #expect(engine.duration > 0)
    }

    @Test func emptyAndCorruptedFilesAreRejectedWithoutBreakingTheEngine() throws {
        let engine = PlayerEngine()
        defer { engine.stop() }
        let empty = try AudioFixtures.writeEmpty(to: folder.appending(path: "empty.caf"))
        let garbage = try AudioFixtures.writeGarbage(to: folder.appending(path: "garbage.m4a"))
        #expect(throws: (any Error).self) { try engine.load(empty, autoplay: true) }
        #expect(throws: (any Error).self) { try engine.load(garbage, autoplay: true) }

        // A good file still plays afterwards.
        let good = try AudioFixtures.writeTone(to: folder.appending(path: "good.caf"), seconds: 0.5, sampleRate: 48_000)
        try engine.load(good, autoplay: true)
        #expect(engine.isPlaying)
    }
}

/// Unplayable songs in a queue are skipped with one message, and a queue made only
/// of unplayable songs (even with Repeat on) stops instead of looping forever.
@MainActor
@Suite(.serialized)
struct SkippingTests {
    private let folderName = "TestFixtures-\(UUID().uuidString)"
    /// Held for the whole test: a context stops working once its container is released.
    private let container: ModelContainer

    init() throws {
        container = try ModelContainer(
            for: Track.self, Playlist.self, ListenSession.self, ArtistImage.self, ArtistBackground.self, ArtistBackdropStyle.self, SavedTheme.self, HiddenArtist.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makePlayer() -> (Music_App.MusicPlayer, ModelContext) {
        (Music_App.MusicPlayer(context: container.mainContext), container.mainContext)
    }

    private func track(_ name: String, good: Bool, in context: ModelContext) throws -> Track {
        let relativePath = "\(folderName)/\(name).caf"
        let url = LibraryLocations.musicDirectory.appending(path: relativePath)
        if good {
            try AudioFixtures.writeTone(to: url, seconds: 0.5)
        } else {
            try AudioFixtures.writeGarbage(to: url)
        }
        let track = Track(relativePath: relativePath, title: name, artist: "A", album: "B", genre: "G",
                          year: nil, trackNumber: nil, duration: 0.5, coverKey: nil)
        context.insert(track)
        return track
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: LibraryLocations.musicDirectory.appending(path: folderName))
    }

    @Test func unplayableSongsAreSkippedWithOneMessage() throws {
        defer { cleanUp() }
        let (player, context) = makePlayer()
        let tracks = [
            try track("bad1", good: false, in: context),
            try track("bad2", good: false, in: context),
            try track("good", good: true, in: context),
        ]
        player.play(tracks)
        #expect(player.currentTrack?.title == "good")
        #expect(player.errorMessage?.hasPrefix("Skipped 2 songs that couldn't be played: bad1, bad2") == true)
        // Both were retried once after resetting the engine, then logged with the reason.
        #expect(player.issues.issues.prefix(2).allSatisfy { !$0.recovered && $0.reason.contains("couldn't be opened") })
        player.pause()
    }

    @Test func queueOfOnlyUnplayableSongsStopsEvenWithRepeat() throws {
        defer { cleanUp() }
        let (player, context) = makePlayer()
        let tracks = try (0..<20).map { try track("bad\($0)", good: false, in: context) }
        player.queue.repeatMode = .all
        player.play(tracks)
        #expect(player.currentTrack == nil)
        #expect(player.errorMessage != nil)
    }
}

/// Tag reading and artwork caching with odd generated input.
struct OddFileTests {
    @Test func tagsFromCorruptedFileFallBackToFolderNames() async throws {
        let url = try AudioFixtures.writeGarbage(
            to: FileManager.default.temporaryDirectory.appending(path: "Odd/Some Artist/Some Album/01 - Broken.mp3")
        )
        let meta = await TagReader.read(url: url, relativePath: "Some Artist/Some Album/01 - Broken.mp3")
        #expect(meta.artist == "Some Artist")
        #expect(meta.title == "Broken")
        #expect(meta.artwork == nil)
    }

    @Test func hugeArtworkIsDownsampled() throws {
        let data = AudioFixtures.coverArt(side: 5000, hue: 0.6)
        let key = try #require(ArtCache.store(data))
        let thumb = try #require(ArtCache.image(for: key, .thumb))
        #expect(max(thumb.size.width, thumb.size.height) * thumb.scale <= 256)
        let full = try #require(ArtCache.image(for: key, .full))
        #expect(max(full.size.width, full.size.height) * full.scale <= 2048)
    }
}

// MARK: - Hidden artists

@MainActor
struct HiddenArtistTests {
    private func track(_ title: String, artist: String) -> Track {
        Track(relativePath: "\(title).mp3", title: title, artist: artist, album: "Album", genre: "Pop",
              year: nil, trackNumber: nil, duration: 60, coverKey: nil)
    }

    @Test func visibleLeavesHiddenArtistsOut() {
        let tracks = [track("a", artist: "Shown"), track("b", artist: "Hidden Band"), track("c", artist: " hidden band ")]
        let index = ArtistIndex(sources: tracks.map(\.creditSource))
        let visible = HiddenArtistRules.visible(tracks, hidden: [Track.key(for: "Hidden Band")], index: index)
        #expect(visible.map(\.title) == ["a"])   // artist keys ignore case and spaces
    }

    @Test func tappingAHiddenSongPlaysItButSkipsOtherHiddenSongs() {
        let tracks = [track("1", artist: "Shown"), track("2", artist: "Hidden"), track("3", artist: "Hidden"), track("4", artist: "Shown")]
        let hidden: Set<String> = [Track.key(for: "Hidden")]
        let queue = HiddenArtistRules.queue(tapping: tracks[2], in: tracks, hidden: hidden,
                                            index: ArtistIndex(sources: tracks.map(\.creditSource)))
        #expect(queue.tracks.map(\.title) == ["1", "3", "4"])
        #expect(queue.start == 1)
    }

    @Test func hidingRemovesTheirSongsFromUpNext() {
        let queue = QueueManager()
        let ids = (0..<4).map { _ in UUID() }
        queue.setQueue(ids, startAt: 0, shuffle: false)
        queue.removeUpcoming(trackIDs: [ids[0], ids[2]])
        #expect(queue.current?.trackID == ids[0])               // the playing song stays
        #expect(queue.upcoming.map(\.trackID) == [ids[1], ids[3]])
    }
}

@MainActor
struct QueueEditingByIDTests {
    @Test func reorderAndRemoveByEntryID() {
        let queue = QueueManager()
        let ids = (0..<4).map { _ in UUID() }
        queue.setQueue(ids, startAt: 0, shuffle: false)
        let upcoming = queue.upcoming.map(\.id)
        queue.reorderUpcoming([upcoming[2], upcoming[0], upcoming[1]])
        #expect(queue.upcoming.map(\.trackID) == [ids[3], ids[1], ids[2]])
        queue.removeUpcoming(ids: [upcoming[0]])
        #expect(queue.upcoming.map(\.trackID) == [ids[3], ids[2]])
    }
}

struct ThemeCompatibilityTests {
    @Test func themesSavedBeforeGlassOpacityStillLoad() throws {
        let old = ##"{"accent":"#FF0000","accentText":"#FFFFFF","text":"#FFFFFF","window":"#000000","panels":"#111111","favorite":"#FF4D5E","waveTop":"#FF2E63","waveBottom":"#3D8BFF","overrides":{}}"##
        let palette = try JSONDecoder().decode(ThemePalette.self, from: Data(old.utf8))
        #expect(palette.accent == "#FF0000")
        #expect(palette.glassOpacity == ThemePalette.defaultGlassOpacity)
    }

    @Test func glassOpacityRoundTrips() throws {
        var palette = ThemePalette()
        palette.glassOpacity = 0.8
        let decoded = try JSONDecoder().decode(ThemePalette.self, from: JSONEncoder().encode(palette))
        #expect(decoded == palette)
    }
}

/// Songs ending by themselves (not skipped) across mixed formats: the player must
/// move through the whole queue without blocking the main thread.
@MainActor
@Suite(.serialized)
struct AutoAdvanceTests {
    private let folderName = "AutoAdvance-\(UUID().uuidString)"
    private let container: ModelContainer

    init() throws {
        container = try ModelContainer(
            for: Track.self, Playlist.self, ListenSession.self, ArtistImage.self, ArtistBackground.self, ArtistBackdropStyle.self, SavedTheme.self, HiddenArtist.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test func naturalSongEndsAdvanceThroughMixedFormatsWithoutStalling() async throws {
        defer { try? FileManager.default.removeItem(at: LibraryLocations.musicDirectory.appending(path: folderName)) }
        let context = container.mainContext
        let formats: [(Double, AVAudioChannelCount)] = [(44_100, 2), (48_000, 2), (48_000, 1), (44_100, 1), (96_000, 2), (44_100, 2)]
        var tracks: [Track] = []
        for (index, format) in formats.enumerated() {
            let relativePath = "\(folderName)/\(index).caf"
            try AudioFixtures.writeTone(to: LibraryLocations.musicDirectory.appending(path: relativePath),
                                        seconds: 0.4, sampleRate: format.0, channels: format.1)
            let track = Track(relativePath: relativePath, title: "T\(index)", artist: "A", album: "B", genre: "G",
                              year: nil, trackNumber: index, duration: 0.4, coverKey: nil)
            context.insert(track)
            tracks.append(track)
        }

        let player = Music_App.MusicPlayer(context: context)
        player.play(tracks)

        // Poll the main actor every 20 ms; a stall shows up as a long gap between polls.
        let clock = ContinuousClock()
        var last = clock.now
        var worstGap = Duration.zero
        let deadline = clock.now + .seconds(8)
        while clock.now < deadline, player.currentTrack?.title != "T5" || player.isPlaying {
            try await Task.sleep(for: .milliseconds(20))
            let now = clock.now
            worstGap = max(worstGap, now - last)
            last = now
        }
        #expect(player.currentTrack?.title == "T5", "stopped at \(player.currentTrack?.title ?? "nil")")
        #expect(!player.isPlaying)                       // the queue ended after the last song
        #expect(worstGap < .milliseconds(500), "main thread stalled for \(worstGap)")
        #expect(player.errorMessage == nil)
    }
}


// MARK: - Artist credits (strings as they appear in a real library)

struct ArtistCreditTests {
    /// Artists that exist on their own in the test "library".
    private let known: Set<String> = ["bad bunny", "kendrick lamar", "calle 13", "taylor swift", "twice", "keiichi okabe", "becky g"]

    private func parse(_ field: String) -> ArtistCredits.Parsed { ArtistCredits.parse(field, known: known) }

    @Test func featureMarkersAlwaysSplit() {
        #expect(parse("Bad Bunny ft. Drake") == .init(main: ["Bad Bunny"], featured: ["Drake"]))
        #expect(parse("Kendrick Lamar f/ Kodak Black") == .init(main: ["Kendrick Lamar"], featured: ["Kodak Black"]))
        #expect(parse("TWICE feat. Megan Thee Stallion") == .init(main: ["TWICE"], featured: ["Megan Thee Stallion"]))
        #expect(parse("Unknown Band featuring Someone").featured == ["Someone"])
    }

    @Test func featuredPartSplitsOnCommasAmpersandsAndSlashes() {
        #expect(parse("Kendrick Lamar feat. Bilal, Anna Wise & Snoop Dogg").featured == ["Bilal", "Anna Wise", "Snoop Dogg"])
        #expect(parse("Calle 13 feat. Totó la Momposina / Susana Baca / Maria Rita").featured
                == ["Totó la Momposina", "Susana Baca", "Maria Rita"])
    }

    @Test func personOfBandStaysOneName() {
        #expect(parse("Kendrick Lamar f/ Beth Gibbons of Portishead").featured == ["Beth Gibbons of Portishead"])
    }

    @Test func smartSplitOnlyWhenAPieceIsKnown() {
        #expect(parse("Bad Bunny & Chuwi").main == ["Bad Bunny", "Chuwi"])
        #expect(parse("Almighty, Ozuna, Bad Bunny & Wisin").main == ["Almighty", "Ozuna", "Bad Bunny", "Wisin"])
        #expect(parse("Of Mice & Men").main == ["Of Mice & Men"])
        #expect(parse("Wolf & Bear").main == ["Wolf & Bear"])
        #expect(parse("Sleeping With Sirens").main == ["Sleeping With Sirens"])
        #expect(parse("Taylor Swift feat. Florence + the Machine").featured == ["Florence + the Machine"])
        #expect(ArtistCredits.smartSplit("Becky G + Paulo Londra", known: known) == ["Becky G", "Paulo Londra"])
    }

    @Test func slashesOutsideFeaturesAreNeverSplit() {
        #expect(parse("AC/DC").main == ["AC/DC"])
    }

    @Test func titleFeatures() {
        #expect(ArtistCredits.titleFeatures("Song (feat. A & B)") == ["A", "B"])
        #expect(ArtistCredits.titleFeatures("Song [ft. C]") == ["C"])
        #expect(ArtistCredits.titleFeatures("Song (with D)") == ["D"])
        #expect(ArtistCredits.titleFeatures("Plain Song").isEmpty)
    }
}

@MainActor
struct ArtistIndexTests {
    private func source(_ artist: String, _ title: String, album: String, albumArtist: String? = nil) -> CreditSource {
        CreditSource(id: UUID(), artist: artist, title: title, album: album, albumArtist: albumArtist)
    }

    @Test func featuredSongsAppearOnBothArtistsInTheRightAlbum() {
        let solo = source("Bad Bunny", "NUEVAYoL", album: "DeBÍ TiRAR MáS FOToS", albumArtist: "Bad Bunny")
        let feat = source("Bad Bunny & Chuwi", "WELTiTA", album: "DeBÍ TiRAR MáS FOToS", albumArtist: "Bad Bunny")
        let index = ArtistIndex(sources: [solo, feat])
        #expect(index.songIDs(for: "bad bunny") == [solo.id, feat.id])
        #expect(index.songIDs(for: "chuwi") == [feat.id])
        #expect(index.name(for: "chuwi") == "Chuwi")
        #expect(index.subtitle(for: feat.id, onPageOf: "chuwi") == "with Bad Bunny")
        #expect(index.subtitle(for: solo.id, onPageOf: "bad bunny") == nil)
        #expect(index.primaryKey(of: feat.id) == "bad bunny")
    }

    @Test func groupAlbumMembersAppearOnTheGroupPage() {
        let group = source("TWICE", "ME+YOU", album: "TEN: The Story Goes On", albumArtist: "TWICE")
        let sana = source("SANA", "DECAFFEINATED", album: "TEN: The Story Goes On", albumArtist: "TWICE")
        let mina = source("MINA", "STONE COLD", album: "TEN: The Story Goes On", albumArtist: "TWICE")
        let other = source("TWICE", "Strategy", album: "Strategy", albumArtist: "TWICE")
        let index = ArtistIndex(sources: [group, sana, mina, other])
        #expect(Set(index.songIDs(for: "twice")) == [group.id, sana.id, mina.id, other.id])
        #expect(index.songIDs(for: "sana") == [sana.id])
        #expect(index.groupOf["sana"] == "twice")
        #expect(index.groupOf["mina"] == "twice")
        #expect(index.groupOf["twice"] == nil)
        #expect(index.subtitle(for: sana.id, onPageOf: "twice") == "SANA")
        #expect(index.primaryKey(of: sana.id) == "sana")   // hiding TWICE doesn't hide SANA's own song
    }

    @Test func featuredGuestOnAGroupSongIsNotAMember() {
        let song = source("TWICE feat. Megan Thee Stallion", "Strategy", album: "Strategy", albumArtist: "TWICE")
        let index = ArtistIndex(sources: [song])
        #expect(index.groupOf["megan thee stallion"] == nil)
        #expect(index.songIDs(for: "megan thee stallion") == [song.id])
    }

    @Test func compilationsDontMakeGroups() {
        let song = source("Someone", "Track", album: "Hits", albumArtist: "Various Artists")
        let index = ArtistIndex(sources: [song])
        #expect(index.groupOf.isEmpty)
        #expect(index.songIDs(for: "various artists").isEmpty)
    }

    @Test func splittingUnlocksMoreSplits() {
        // "Chencho Corleone" is only known after "Bad Bunny & Chencho Corleone" splits,
        // which then lets "Rauw Alejandro & Chencho Corleone" split too.
        let a = source("Bad Bunny", "A", album: "X")
        let b = source("Bad Bunny & Chencho Corleone", "B", album: "X")
        let c = source("Rauw Alejandro & Chencho Corleone", "C", album: "Y")
        let index = ArtistIndex(sources: [a, b, c])
        #expect(index.songIDs(for: "chencho corleone") == [b.id, c.id])
        #expect(index.songIDs(for: "rauw alejandro") == [c.id])
    }

    @Test func manualGroupLinksMembersOnSharedAlbums() {
        let groupSong = source("BAND", "Intro", album: "Debut")
        let memberSolo = source("Singer", "Solo on Debut", album: "Debut")
        let memberElsewhere = source("Singer", "Own Album Song", album: "Solo Record")
        let index = ArtistIndex(sources: [groupSong, memberSolo, memberElsewhere], manualGroups: ["singer": "band"])
        #expect(index.groupOf["singer"] == "band")
        #expect(Set(index.songIDs(for: "band")) == [groupSong.id, memberSolo.id])   // only the group's album
    }

    @Test func hidingThePrimaryArtistHidesTheSongButHidingAFeatureDoesNot() {
        let solo = Track(relativePath: "a.mp3", title: "A", artist: "Bad Bunny", album: "X", genre: "G",
                         year: nil, trackNumber: nil, duration: 1, coverKey: nil)
        let feat = Track(relativePath: "b.mp3", title: "B", artist: "Bad Bunny & Chuwi", album: "X", genre: "G",
                         year: nil, trackNumber: nil, duration: 1, coverKey: nil)
        let index = ArtistIndex(sources: [solo, feat].map(\.creditSource))
        #expect(HiddenArtistRules.visible([solo, feat], hidden: ["chuwi"], index: index).count == 2)
        #expect(HiddenArtistRules.visible([solo, feat], hidden: ["bad bunny"], index: index).isEmpty)
    }
}

struct CropGeometryTests {
    @Test func photoAlwaysCoversTheSquare() {
        let frame = CGSize(width: 300, height: 300)
        let base = ArtistImageCropper.fillSize(for: CGSize(width: 4000, height: 3000), frame: frame)
        #expect(base.height == 300 && base.width == 400)
        // At 1×, it can move 50 pt sideways and not at all up or down.
        let clamped = ArtistImageCropper.clamped(CGSize(width: 999, height: -999), base: base, scale: 1, frame: frame)
        #expect(clamped == CGSize(width: 50, height: 0))
        // Zoomed 2×, there's more room to move.
        let zoomed = ArtistImageCropper.clamped(CGSize(width: 999, height: 999), base: base, scale: 2, frame: frame)
        #expect(zoomed == CGSize(width: 250, height: 150))
    }

    @Test func framesKeepTheirShape() {
        let available = CGSize(width: 400, height: 600)
        let landscape = CGSize(width: 4000, height: 3000)
        // Whole Picture uses the image's own shape (4:3), as large as fits.
        let whole = ArtistImageCropper.frameSize(for: .whole, image: landscape, in: available)
        #expect(whole == CGSize(width: 400, height: 300))
        // Square and Screen keep their shape whatever the image is.
        #expect(ArtistImageCropper.frameSize(for: .square, image: landscape, in: available) == CGSize(width: 400, height: 400))
        let screen = ArtistImageCropper.frameSize(for: .screen, image: landscape, in: available)
        #expect(abs(screen.width / screen.height - 430.0 / 932.0) < 0.001)
        #expect(screen.height <= 600)
    }
}

// MARK: - Album Artist edge cases (from a real library's tags)

@MainActor
struct AlbumArtistEdgeCaseTests {
    private func source(_ artist: String, _ title: String, album: String, albumArtist: String?) -> CreditSource {
        CreditSource(id: UUID(), artist: artist, title: title, album: album, albumArtist: albumArtist)
    }

    @Test func databaseIDsAreNotGroups() {
        let song = source("The Marías", "Hush (Still Woozy remix)", album: "Hush (Still Woozy remix)",
                          albumArtist: "7a3970c9-ecd8-4eee-a267-4d8c77d97ff3")
        let index = ArtistIndex(sources: [song, source("The Marías", "Hush", album: "CINEMA", albumArtist: "The Marías")])
        #expect(index.groupOf["the marías"] == nil)
        #expect(index.songIDs(for: "7a3970c9-ecd8-4eee-a267-4d8c77d97ff3").isEmpty)
        #expect(ArtistCredits.isIdentifier("7a3970c9-ecd8-4eee-a267-4d8c77d97ff3"))
        #expect(!ArtistCredits.isIdentifier("TWICE"))
        #expect(!ArtistCredits.isIdentifier("Bring Me the Horizon"))
    }

    @Test func albumArtistWrittenDifferentlyIsNotAGroup() {
        let songs = [
            source("Bad Bunny", "Callaíta", album: "Un verano sin ti", albumArtist: "Bad Bunny"),
            source("Bad Bunny ft. Drake", "MIA", album: "MIA", albumArtist: "Bad Bunny ft. Drake"),
            source("Becky G & Paulo Londra", "Cuando te besé", album: "Cuando te besé", albumArtist: "Becky G + Paulo Londra"),
            source("HYDE × MY FIRST STORY", "永久", album: "夢幻 / 永久", albumArtist: "MY FIRST STORY × HYDE"),
            source("Georg Philipp Telemann", "Fantasia no. 1", album: "Twelve Fantasias", albumArtist: "Georg Philipp Telemann; Barthold Kuijken"),
        ]
        let index = ArtistIndex(sources: songs)
        #expect(index.groupOf.isEmpty)
    }

    @Test func soundtrackCollaboratorsAreNotMembers() {
        let album = "NieR:Automata Original Soundtrack"
        let songs = [
            source("Keigo Hoashi", "The Sound of the End", album: album, albumArtist: "Keiichi Okabe"),
            source("Keigo Hoashi, Keiichi Okabe", "Dark Colossus / Kaiju", album: album, albumArtist: "Keiichi Okabe"),
            source("Keiichi Okabe", "City Ruins", album: album, albumArtist: "Keiichi Okabe"),
        ]
        let index = ArtistIndex(sources: songs)
        #expect(index.groupOf.isEmpty)
        // Still the composer's album: all three songs show on his page.
        #expect(Set(index.songIDs(for: "keiichi okabe")) == Set(songs.map(\.id)))
    }

    @Test func realGroupAlbumStillMakesMembers() {
        let songs = [
            source("TWICE", "ME+YOU", album: "TEN: The Story Goes On", albumArtist: "TWICE"),
            source("SANA", "DECAFFEINATED", album: "TEN: The Story Goes On", albumArtist: "TWICE"),
        ]
        let index = ArtistIndex(sources: songs)
        #expect(index.groupOf["sana"] == "twice")
    }

    @Test func semicolonsAndTimesSignSplit() {
        #expect(ArtistCredits.parse("Georg Philipp Telemann; Barthold Kuijken", known: []).main
                == ["Georg Philipp Telemann", "Barthold Kuijken"])
        #expect(ArtistCredits.parse("HYDE × MY FIRST STORY", known: ["hyde"]).main == ["HYDE", "MY FIRST STORY"])
    }
}

struct StatsCreditTests {
    @Test func everyCreditedArtistGetsTheTime() {
        let now = Date()
        func record(_ artist: String, _ artists: [String], _ seconds: Double) -> SessionRecord {
            SessionRecord(start: now, seconds: seconds, counted: true, trackID: UUID(), title: "T",
                          artist: artist, album: "A", genre: "G", artists: artists)
        }
        let summary = StatsSummary(records: [
            record("Bad Bunny & Chuwi", ["Bad Bunny", "Chuwi"], 100),
            record("Bad Bunny", [], 50),
        ], period: .allTime, now: now)
        #expect(summary.artistCount == 2)                       // not 3 ("Bad Bunny & Chuwi" isn't an artist)
        #expect(summary.topArtists.map(\.title) == ["Bad Bunny", "Chuwi"])
        #expect(summary.topArtists.first?.seconds == 150)
        #expect(!summary.topArtists.contains { $0.title == "Bad Bunny & Chuwi" })
    }
}

@MainActor
struct AlbumYearTests {
    @Test func albumYearIsTheSameOnEveryArtistsPage() {
        func track(_ artist: String, _ title: String, year: Int, albumArtist: String) -> Track {
            Track(relativePath: "\(title).mp3", title: title, artist: artist, album: "Northern Lights", genre: "G",
                  year: year, trackNumber: nil, duration: 1, coverKey: nil, albumArtist: albumArtist)
        }
        let library = [
            track("Aurora Vale", "Opening", year: 2015, albumArtist: "Aurora Vale"),
            track("Aurora Vale & Kenji Sato", "Duet Lights", year: 2025, albumArtist: "Aurora Vale"),
            track("Kenji Sato", "Night Train", year: 2017, albumArtist: "Kenji Sato"),
        ]
        let index = ArtistIndex(sources: library.map(\.creditSource))
        let lookup = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
        let auroraYear = LibraryGrouping.albums(from: index.songs(for: "aurora vale", in: lookup), library: library, index: index)
            .first { $0.name == "Northern Lights" }?.year
        let kenjiYear = LibraryGrouping.albums(from: index.songs(for: "kenji sato", in: lookup), library: library, index: index)
            .first { $0.name == "Northern Lights" }?.year
        #expect(auroraYear == 2015)
        #expect(kenjiYear == 2015)
    }
}

@MainActor
struct ArtworkPaletteTests {
    /// A generated image: left half one color, right half another.
    private func image(left: RGBA, right: RGBA, side: Int = 64) -> CGImage {
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(red: left.red, green: left.green, blue: left.blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side / 2, height: side))
        context.setFillColor(red: right.red, green: right.green, blue: right.blue, alpha: 1)
        context.fill(CGRect(x: side / 2, y: 0, width: side / 2, height: side))
        return context.makeImage()!
    }

    @Test func twoColorCoverGivesBothHues() throws {
        let red = RGBA(red: 0.9, green: 0.1, blue: 0.1)
        let blue = RGBA(red: 0.1, green: 0.2, blue: 0.9)
        let colors = try #require(ArtworkPalette.colors(from: image(left: red, right: blue)))
        let hues = [ArtworkPalette.HSB(colors.primary).hue, ArtworkPalette.HSB(colors.secondary).hue]
        #expect(hues.contains { $0 < 0.05 || $0 > 0.95 })          // red
        #expect(hues.contains { $0 > 0.55 && $0 < 0.72 })          // blue
    }

    @Test func colorsAreBrightEnoughToGlow() throws {
        let darkGreen = RGBA(red: 0.05, green: 0.3, blue: 0.08)
        let colors = try #require(ArtworkPalette.colors(from: image(left: darkGreen, right: darkGreen)))
        #expect(ArtworkPalette.HSB(colors.primary).brightness >= 0.8)
        // A one-color cover still gets a second color, close in hue.
        #expect(ArtworkPalette.HSB(colors.primary).hueDistance(to: ArtworkPalette.HSB(colors.secondary)) > 0)
    }

    @Test func colorlessCoverFallsBackToTheTheme() {
        let grey = RGBA(red: 0.5, green: 0.5, blue: 0.5)
        let black = RGBA(red: 0.02, green: 0.02, blue: 0.02)
        #expect(ArtworkPalette.colors(from: image(left: grey, right: black)) == nil)
    }

    @Test func themesSavedBeforeMatchArtworkTurnItOn() throws {
        let old = ##"{"accent":"#FF0000","glassOpacity":0.7}"##
        let palette = try JSONDecoder().decode(ThemePalette.self, from: Data(old.utf8))
        #expect(palette.matchArtwork)
        #expect(palette.glassOpacity == 0.7)
    }

    @Test func matchArtworkRoundTrips() throws {
        var palette = ThemePalette()
        palette.matchArtwork = false
        let decoded = try JSONDecoder().decode(ThemePalette.self, from: JSONEncoder().encode(palette))
        #expect(decoded.matchArtwork == false)
    }

    @Test func glowsUseTheThemeWhenMatchArtworkIsOff() {
        let theme = ThemeStore()
        let saved = theme.palette
        defer { theme.palette = saved }
        var palette = ThemePalette.default
        palette.set(.primary, to: "#00FF00")
        palette.set(.highlight, to: "#0000FF")
        theme.palette = palette
        let artwork = ArtworkPalette.Colors(primary: RGBA(red: 1, green: 0.5, blue: 0), secondary: RGBA(red: 1, green: 0, blue: 1))
        theme.artworkColors = artwork

        theme.palette.matchArtwork = true
        #expect(theme.glowPrimaryRGBA == artwork.primary)
        #expect(theme.glowSecondaryRGBA == artwork.secondary)

        theme.palette.matchArtwork = false
        #expect(theme.glowPrimaryRGBA.hex == "#00FF00")
        #expect(theme.glowSecondaryRGBA.hex == "#0000FF")

        // On, but the cover had no usable colors: the theme is used too.
        theme.palette.matchArtwork = true
        theme.artworkColors = nil
        #expect(theme.glowPrimaryRGBA.hex == "#00FF00")
    }
}

@MainActor
struct ListeningSortTests {
    private let day: TimeInterval = 86_400
    private let a = UUID(), b = UUID(), c = UUID()

    /// a: 2 plays, 10 min, played 3 days ago · b: 1 play, 30 min, played today · c: never played.
    private func totals() -> ListeningTotals {
        let now = Date.now
        func session(_ id: UUID, _ seconds: Double, counted: Bool, daysAgo: Double, artist: String, genre: String) -> ListeningTotals.Session {
            ListeningTotals.Session(trackID: id, start: now.addingTimeInterval(-daysAgo * day), seconds: seconds,
                                    counted: counted, artistKeys: [artist], genre: genre)
        }
        return ListeningTotals(sessions: [
            session(a, 300, counted: true, daysAgo: 4, artist: "x", genre: "Rock"),
            session(a, 300, counted: true, daysAgo: 3, artist: "x", genre: "Rock"),
            session(b, 1800, counted: true, daysAgo: 0, artist: "y", genre: "Jazz"),
        ])
    }

    @Test func entriesAddUpPerSongArtistAndGenre() {
        let totals = totals()
        #expect(totals.track(a).plays == 2)
        #expect(totals.track(a).seconds == 600)
        #expect(totals.artist("x").plays == 2)
        #expect(totals.genre("Jazz").seconds == 1800)
        #expect(totals.track(c) == ListeningTotals.Entry())          // never played
        #expect(totals.track(b).lastPlayed! > totals.track(a).lastPlayed!)
    }

    @Test func ordersFollowListeningHistory() {
        let totals = totals()
        func order(_ sort: ListeningOrder) -> [UUID] {
            [a, b, c].sorted { sort.ordered(totals.track($0), totals.track($1)) ?? ($0.uuidString < $1.uuidString) }
        }
        #expect(order(.mostListened) == [b, a, c])     // 30 min > 10 min > nothing
        #expect(order(.mostPlayed) == [a, b, c])       // 2 plays > 1 play > none
        #expect(order(.recentlyPlayed) == [b, a, c])   // today > 3 days ago > never
        #expect(order(.leastPlayed) == [c, b, a])      // never first, then fewest plays
    }

    @Test func collectionSortFallsBackToNameOnTies() {
        struct Item { let name: String; let songs: Int; let entry: ListeningTotals.Entry }
        let items = [
            Item(name: "Zeta", songs: 1, entry: .init(seconds: 50, plays: 1)),
            Item(name: "Alpha", songs: 5, entry: .init()),
            Item(name: "Beta", songs: 5, entry: .init()),
        ]
        func names(_ sort: CollectionSort) -> [String] {
            sort.sorted(items, name: \.name, songCount: \.songs, listening: \.entry).map(\.name)
        }
        #expect(names(.name) == ["Alpha", "Beta", "Zeta"])
        #expect(names(.mostSongs) == ["Alpha", "Beta", "Zeta"])
        #expect(names(.mostListened) == ["Zeta", "Alpha", "Beta"])  // unplayed ones tie, then by name
    }

    @Test func rowDetailsDescribeTheSortValue() {
        #expect(ListeningOrder.mostPlayed.detail(.init(seconds: 400, plays: 3)) == "3 plays")
        #expect(ListeningOrder.mostPlayed.detail(.init()) == "Not played yet")
        #expect(ListeningOrder.mostPlayed.detail(.init(seconds: 20, plays: 0)) == "Played briefly")
        #expect(ListeningOrder.mostListened.detail(.init(seconds: 3900, plays: 2)) == "1h 5m")
    }
}

@MainActor
struct HomeAndAlbumTests {
    private let day: TimeInterval = 86_400

    @Test func weekTotalsOnlyCountThePastSevenDays() {
        let now = Date.now
        let song = UUID()
        func session(daysAgo: Double, artist: String, seconds: Double) -> ListeningTotals.Session {
            .init(trackID: song, start: now.addingTimeInterval(-daysAgo * day), seconds: seconds,
                  counted: true, artistKeys: [artist], genre: "Pop")
        }
        let totals = ListeningTotals(sessions: [
            session(daysAgo: 1, artist: "recent", seconds: 100),
            session(daysAgo: 2, artist: "busy", seconds: 500),
            session(daysAgo: 30, artist: "old", seconds: 9_000),   // all-time only
        ], now: now)
        #expect(totals.topArtistKeysThisWeek == ["busy", "recent"])
        #expect(totals.artist("old").seconds == 9_000)
    }

    @Test func recentlyPlayedIsNewestFirst() {
        let now = Date.now
        let a = UUID(), b = UUID()
        let totals = ListeningTotals(sessions: [
            .init(trackID: a, start: now.addingTimeInterval(-3 * day), seconds: 60, counted: true, artistKeys: [], genre: ""),
            .init(trackID: b, start: now.addingTimeInterval(-1 * day), seconds: 60, counted: true, artistKeys: [], genre: ""),
            .init(trackID: a, start: now.addingTimeInterval(-2 * day), seconds: 60, counted: true, artistKeys: [], genre: ""),
        ], now: now)
        #expect(totals.recentlyPlayedTrackIDs == [b, a])
    }

    @Test func combinedAddsUpAnAlbum() {
        let now = Date.now
        let a = UUID(), b = UUID()
        let totals = ListeningTotals(sessions: [
            .init(trackID: a, start: now.addingTimeInterval(-day), seconds: 100, counted: true, artistKeys: [], genre: ""),
            .init(trackID: b, start: now, seconds: 50, counted: false, artistKeys: [], genre: ""),
        ], now: now)
        let album = totals.combined([a, b, UUID()])
        #expect(album.seconds == 150)
        #expect(album.plays == 1)
        #expect(album.lastPlayed == now)
    }

    @Test func albumSortOrders() {
        func album(_ name: String, owner: String, year: Int?, added: TimeInterval) -> AlbumSummary {
            AlbumSummary(name: name, ownerKey: owner.lowercased(), ownerName: owner, year: year, artKey: nil,
                         trackIDs: [], addedAt: Date(timeIntervalSince1970: added))
        }
        let albums = [
            album("Beta", owner: "Zed", year: 2020, added: 1),
            album("Alpha", owner: "Amy", year: nil, added: 3),
            album("Gamma", owner: "Amy", year: 2024, added: 2),
        ]
        func names(_ sort: AlbumSort) -> [String] { sort.sorted(albums, totals: .empty).map(\.name) }
        #expect(names(.title) == ["Alpha", "Beta", "Gamma"])
        #expect(names(.artist) == ["Alpha", "Gamma", "Beta"])        // Amy, Amy, Zed
        #expect(names(.year) == ["Gamma", "Beta", "Alpha"])          // newest first, no year last
        #expect(names(.recentlyAdded) == ["Alpha", "Gamma", "Beta"])
    }
}

@MainActor
struct StatsActivityTests {
    @Test func activeDaysCountOnlyThePeriod() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ ago: Int) -> Date { calendar.date(byAdding: .day, value: -ago, to: today)! }
        let daily: [Date: Double] = [day(0): 600, day(3): 120, day(10): 900, day(40): 300, day(5): 0]

        let week = StatsView.activity(daily: daily, period: .week, today: .now, calendar: calendar)
        #expect(week.active == 2)       // today and 3 days ago; a zero-second day doesn't count
        #expect(week.length == 7)

        let month = StatsView.activity(daily: daily, period: .month, today: .now, calendar: calendar)
        #expect(month.active == 3)
        #expect(month.length == 30)

        // All Time runs from the first day listened (40 days ago) through today.
        let all = StatsView.activity(daily: daily, period: .allTime, today: .now, calendar: calendar)
        #expect(all.active == 4)
        #expect(all.length == 41)
    }

    @Test func noHistoryGivesAnEmptyRing() {
        let result = StatsView.activity(daily: [:], period: .allTime)
        #expect(result.active == 0)
        #expect(result.length == 1)
    }
}

struct TransparentArtTests {
    /// A generated 200 × 300 picture: a colored figure, with or without a see-through background.
    private func picture(transparent: Bool) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !transparent
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 300), format: format).image { context in
            if !transparent {
                UIColor.darkGray.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
            }
            UIColor.systemPink.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 40, y: 40, width: 120, height: 220))
        }
        return image.pngData()!
    }

    @Test func transparentPicturesKeepTheirTransparency() throws {
        let key = try #require(ArtCache.store(picture(transparent: true)))
        #expect(ArtCache.hasTransparency(key))
        let full = try #require(ArtCache.image(for: key, .full))
        #expect(full.size.width < full.size.height)          // kept its own (portrait) shape
        #expect(ArtCache.isTransparent(try #require(full.cgImage)))
        #expect(ArtCache.image(for: key, .thumb) != nil)
        #expect(ArtCache.image(for: key, .blur) != nil)
    }

    @Test func opaquePicturesAreStoredAsBefore() throws {
        let key = try #require(ArtCache.store(picture(transparent: false)))
        #expect(!ArtCache.hasTransparency(key))
        #expect(ArtCache.image(for: key, .full) != nil)
    }
}

struct ArtistImageTests {
    @Test @MainActor func separateBackgroundsMergeIntoTheArtistImage() throws {
        let container = try ModelContainer(
            for: Track.self, Playlist.self, ListenSession.self, ArtistImage.self, ArtistBackground.self, ArtistBackdropStyle.self, SavedTheme.self, HiddenArtist.self,
            ArtistGroupLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        context.insert(ArtistImage(artistKey: "aurora", artKey: "pic-a"))
        context.insert(ArtistImage(artistKey: "kenji", artKey: "pic-k"))
        context.insert(ArtistBackground(artistKey: "aurora", artKey: "bg-a"))
        context.insert(ArtistBackground(artistKey: "mira", artKey: "bg-m"))
        try context.save()

        ArtistArtwork.mergeLegacyBackgrounds(in: context)

        let images = ArtistArtwork.imageMap(try context.fetch(FetchDescriptor<ArtistImage>()))
        // The background wins (it's what showed behind the player); others are kept or added.
        #expect(images == ["aurora": "bg-a", "kenji": "pic-k", "mira": "bg-m"])
        #expect(try context.fetch(FetchDescriptor<ArtistBackground>()).isEmpty)
    }

    @Test func artistPageGivesThePictureRoomButKeepsTheListOnScreen() {
        let screen = CGSize(width: 430, height: 932)
        // A square picture shows at its full-width height.
        #expect(ArtistArtwork.heroHeight(imageAspect: 1, screen: screen) == 430)
        // A very wide one still gets 42% of the screen.
        #expect(ArtistArtwork.heroHeight(imageAspect: 16.0 / 9.0, screen: screen) == 932 * 0.42)
        // A screen-shaped one is capped at 62%, so the name and discography stay visible.
        #expect(ArtistArtwork.heroHeight(imageAspect: 430.0 / 932.0, screen: screen) == 932 * 0.62)
        #expect(ArtistArtwork.heroHeight(imageAspect: 1, screen: .zero) == 0)
    }
}

struct ArtistCircleAndBackdropStyleTests {
    private func song(_ title: String, artist: String, album: String, year: Int?, cover: String?, albumArtist: String? = nil, added: TimeInterval = 0) -> Track {
        let track = Track(relativePath: "\(title).mp3", title: title, artist: artist, album: album, genre: "Pop",
                          year: year, trackNumber: 1, duration: 200, coverKey: cover, albumArtist: albumArtist)
        track.addedAt = Date(timeIntervalSince1970: 1_000_000 + added)
        return track
    }

    @Test func circleShowsTheLatestAlbumCover() {
        let old = song("A", artist: "Aurora", album: "Old", year: 2015, cover: "old")
        let new = song("B", artist: "Aurora", album: "New", year: 2023, cover: "new")
        let noCover = song("C", artist: "Aurora", album: "Newest, no art", year: 2025, cover: nil)
        // A guest spot on someone else's newer album doesn't count while they have their own.
        let guest = song("D", artist: "Kenji feat. Aurora", album: "Kenji's", year: 2024, cover: "guest")
        let tracks = [old, new, noCover, guest]
        let index = ArtistIndex(sources: tracks.map(\.creditSource))
        let summary = LibraryGrouping.artists(index: index, tracks: tracks).first { $0.name == "Aurora" }
        #expect(summary?.artKey == "new")
    }

    @Test func sameYearPicksTheMostRecentlyAdded() {
        let first = song("A", artist: "Mira", album: "First", year: 2020, cover: "first", added: 0)
        let second = song("B", artist: "Mira", album: "Second", year: 2020, cover: "second", added: 60)
        let tracks = [first, second]
        let index = ArtistIndex(sources: tracks.map(\.creditSource))
        #expect(LibraryGrouping.latestAlbumCover(of: tracks, artistKey: Track.key(for: "Mira"), index: index) == "second")
    }

    @Test func membersUseTheirGroupsBackgroundSettings() {
        let group = song("A", artist: "PRISM", album: "Ten", year: 2020, cover: "c", albumArtist: "PRISM")
        let member = song("B", artist: "LUMI", album: "Ten", year: 2020, cover: "c", albumArtist: "PRISM")
        let index = ArtistIndex(sources: [group, member].map(\.creditSource))
        let groupStyle = BackdropStyle(player: BackdropFraming(fillsScreen: true), dim: 0.6)
        let styles = [Track.key(for: "PRISM"): groupStyle]
        #expect(ArtistArtwork.style(for: Track.key(for: "LUMI"), styles: styles, index: index) == groupStyle)
        // Their own settings win.
        let own = BackdropStyle(blur: 30)
        #expect(ArtistArtwork.style(for: Track.key(for: "LUMI"), styles: styles.merging([Track.key(for: "LUMI"): own]) { $1 }, index: index) == own)
        #expect(ArtistArtwork.style(for: "nobody", styles: styles, index: index) == nil)
    }

    @Test @MainActor func settingsAreSavedPerArtist() throws {
        let container = try ModelContainer(for: ArtistBackdropStyle.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let style = BackdropStyle(player: BackdropFraming(fillsScreen: true, zoom: 1.5, offsetX: 0.1, offsetY: -0.2),
                                  page: BackdropFraming(fillsScreen: false, zoom: 2, offsetX: -0.3, offsetY: 0.25),
                                  dim: 0.5, blur: 20, edgeFade: 0.1, glow: 1.4, brightness: -0.3)
        container.mainContext.insert(ArtistBackdropStyle(artistKey: "aurora", style: style))
        try container.mainContext.save()
        let saved = try container.mainContext.fetch(FetchDescriptor<ArtistBackdropStyle>())
        #expect(ArtistArtwork.styleMap(saved) == ["aurora": style])
    }

    @Test func pictureFrameFollowsTheStyle() {
        let screen = CGSize(width: 400, height: 800)
        // Whole picture behind the player: fits the width, centered, never cropped.
        let whole = StyledBackdrop.pictureFrame(imageAspect: 2, in: screen, style: BackdropStyle(), placement: .screen)
        #expect(whole == CGRect(x: 0, y: 300, width: 400, height: 200))
        // Fill Screen covers the whole screen.
        let fill = StyledBackdrop.pictureFrame(imageAspect: 2, in: screen, style: BackdropStyle(player: BackdropFraming(fillsScreen: true)), placement: .screen)
        #expect(fill.height == 800 && fill.width == 1600 && fill.midX == 200)
        // Zoom grows it around its center; the move is a fraction of the screen.
        let moved = StyledBackdrop.pictureFrame(imageAspect: 2, in: screen, style: BackdropStyle(player: BackdropFraming(zoom: 2, offsetX: 0.25, offsetY: -0.1)), placement: .screen)
        #expect(moved.size == CGSize(width: 800, height: 400))
        #expect(moved.midX == 300 && moved.midY == 320)
        // Artist page: the picture stands on the bottom edge, full width, however tall it is.
        let page = StyledBackdrop.pictureFrame(imageAspect: 2, in: screen, style: BackdropStyle(), placement: .artistPage)
        #expect(page == CGRect(x: 0, y: 600, width: 400, height: 200))
        let tall = StyledBackdrop.pictureFrame(imageAspect: 0.25, in: screen, style: BackdropStyle(), placement: .artistPage)
        #expect(tall.maxY == 800 && tall.width == 400)
        // Zooming keeps it standing on the bottom edge.
        let zoomedPage = StyledBackdrop.pictureFrame(imageAspect: 2, in: screen, style: BackdropStyle(page: BackdropFraming(zoom: 1.5)), placement: .artistPage)
        #expect(zoomedPage.maxY == 800 && zoomedPage.width == 600 && zoomedPage.midX == 200)
        // Filling on the artist page also sits on the bottom edge.
        let filledPage = StyledBackdrop.pictureFrame(imageAspect: 0.25, in: screen, style: BackdropStyle(page: BackdropFraming(fillsScreen: true)), placement: .artistPage)
        #expect(filledPage.maxY == 800)
    }

    @Test func standardLookMatchesTheOldBackdrop() {
        #expect(BackdropStyle.standard(isArtistImage: true, isTransparent: false).edgeFade == 0.04)
        #expect(BackdropStyle.standard(isArtistImage: false, isTransparent: false).edgeFade == 0.14)
        #expect(BackdropStyle.standard(isArtistImage: true, isTransparent: true).edgeFade == 0)
        let standard = BackdropStyle.standard(isArtistImage: true, isTransparent: false)
        #expect(standard.dim == 0.35 && standard.blur == 12 && standard.player == BackdropFraming() && standard.page == BackdropFraming())
    }
}

struct ThemePerformanceTests {
    @Test func cachedColorsMatchThePalette() {
        for preset in ThemePreset.all {
            let palette = preset.palette
            let colors = ResolvedColors(palette)
            #expect(colors.accent == palette.rgba(palette.accent))
            #expect(colors.waveTopBright == palette.waveTopBright)
            for element in ThemeElement.allCases {
                #expect(colors.element(element) == palette.resolved(element))
            }
        }
    }

    @Test @MainActor func storeUpdatesItsCachedColorsWithThePalette() {
        let theme = ThemeStore()
        let original = theme.palette
        defer { theme.palette = original; theme.saveNow() }
        theme.palette.set(.primary, to: "#FF8800")
        #expect(theme.colors.accent == RGBA(hex: "#FF8800"))
        #expect(theme.colors == ResolvedColors(theme.palette))
    }

    @Test @MainActor func rapidEditsAreBatched() async throws {
        let theme = ThemeStore()
        let original = theme.palette
        defer { theme.palette = original; theme.saveNow() }
        let buffer = ThemeEditBuffer()
        // A color-picker drag: many changes in quick succession.
        for step in 0..<20 {
            let hex = RGBA(red: Double(step) / 20, green: 0.5, blue: 0.5).hex
            buffer.edit(theme) { $0.set(.secondary, to: hex) }
        }
        // The controls already show the newest color; the theme hasn't been redrawn 20 times.
        #expect(buffer.current(theme).waveBottom == RGBA(red: 19.0 / 20, green: 0.5, blue: 0.5).hex)
        #expect(theme.palette.waveBottom == original.waveBottom)
        // The batch lands about 80 ms later; wait up to 2 s (the main actor can be busy
        // while the other tests run in parallel).
        for _ in 0..<100 where buffer.draft != nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(theme.palette.waveBottom == RGBA(red: 19.0 / 20, green: 0.5, blue: 0.5).hex)
        #expect(buffer.draft == nil)
    }
}

struct SeparateFramingTests {
    @Test func playerAndPageFramingsAreIndependent() {
        let screen = CGSize(width: 400, height: 800)
        let style = BackdropStyle(player: BackdropFraming(fillsScreen: true), page: BackdropFraming(zoom: 1.5, offsetX: 0.1))
        let player = StyledBackdrop.pictureFrame(imageAspect: 2, in: screen, style: style, placement: .screen)
        let page = StyledBackdrop.pictureFrame(imageAspect: 2, in: screen, style: style, placement: .artistPage)
        // Behind the player it fills the screen; on the page it's the whole picture, zoomed and moved.
        #expect(player.height == 800)
        #expect(page.width == 600 && page.maxY == 800 && page.midX == 240)
    }

    @Test @MainActor func stylesSavedBeforeTheSplitUseThePlayersFramingOnThePage() throws {
        let container = try ModelContainer(for: ArtistBackdropStyle.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let saved = ArtistBackdropStyle(artistKey: "aurora", style: BackdropStyle())
        // As a row saved by the previous version: player framing only, no page fields.
        saved.fillsScreen = true
        saved.zoom = 1.4
        saved.offsetY = 0.2
        saved.pageFillsScreen = nil
        saved.pageZoom = nil
        saved.pageOffsetX = nil
        saved.pageOffsetY = nil
        container.mainContext.insert(saved)
        #expect(saved.style.page == BackdropFraming(fillsScreen: true, zoom: 1.4, offsetX: 0, offsetY: 0.2))
        #expect(saved.style.page == saved.style.player)
        // Framing the page separately keeps the player's as it was.
        var edited = saved.style
        edited.page.zoom = 3
        saved.style = edited
        #expect(saved.style.page.zoom == 3 && saved.style.player.zoom == 1.4)
    }
}

struct LyricsParsingTests {
    @Test func lrcHandlesSeveralTagsOffsetsAndMetadata() {
        let text = """
        [ti:Song]
        [ar:Someone]
        [offset:500]
        [00:01.00]First
        [00:05.50][00:20.25]Chorus
        [00:03:75]Second
        [01:02.123]Late
        """
        let lines = LRC.parse(text)
        #expect(lines.map(\.text) == ["First", "Second", "Chorus", "Chorus", "Late"])
        // The 500 ms offset is taken off every time; "ss:xx" works like "ss.xx".
        #expect(lines[0].time == 0.5)
        #expect(abs((lines[1].time ?? 0) - 3.25) < 0.001)
        #expect(abs((lines[4].time ?? 0) - 61.623) < 0.001)
    }

    @Test func threeTimedLinesMakeSyncedLyricsOtherwisePlain() throws {
        let synced = try #require(Lyrics.from(text: "[00:01.00]a\n[00:02.00]b\n[00:03.00]c", source: "test"))
        #expect(synced.kind == .synced && synced.lines.count == 3)
        let plain = try #require(Lyrics.from(text: "[00:01.00]a\nJust words\nMore words", source: "test"))
        #expect(plain.kind == .plain && plain.lines.allSatisfy { $0.time == nil })
        #expect(Lyrics.from(text: "   \n ", source: "test") == nil)
    }

    @Test func currentLineFollowsTheTimeWithALead() throws {
        let lyrics = try #require(Lyrics.from(text: "[00:05.00]a\n[00:10.00]b\n[00:15.00]c", source: "test"))
        #expect(lyrics.currentLineIndex(at: 1) == nil)          // before the first line
        #expect(lyrics.currentLineIndex(at: 4.9) == 0)          // 0.15 s early
        #expect(lyrics.currentLineIndex(at: 12) == 1)
        #expect(lyrics.currentLineIndex(at: 99) == 2)
        let plain = try #require(Lyrics.from(text: "one\ntwo", source: "test"))
        #expect(plain.currentLineIndex(at: 10) == nil)
    }

    @Test func featuredArtistsAreLeftOutOfLookups() {
        #expect(Lyrics.cleanName("Song (feat. Someone)") == "Song")
        #expect(Lyrics.cleanName("Bad Bunny ft. Chuwi") == "Bad Bunny")
        #expect(Lyrics.cleanName("Track [with Guest]") == "Track")
        #expect(Lyrics.cleanName("Withering") == "Withering")
    }
}

/// Answers LRCLIB requests from a table, so the provider is tested without the network.
final class LRCLIBStub: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (Int, String)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let endpoint = request.url?.lastPathComponent ?? ""
        let (status, body) = Self.responses[endpoint] ?? (404, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct LRCLIBProviderTests {
    private func provider() -> LRCLIBProvider {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LRCLIBStub.self]
        return LRCLIBProvider(session: URLSession(configuration: configuration))
    }

    private let query = LyricsQuery(trackID: UUID(), title: "Song (feat. X)", artist: "Artist", album: "Album", duration: 200, fileURL: nil)

    @Test func searchPicksSyncedLyricsWithinFiveSeconds() {
        let results = [
            LRCLIBProvider.Record(duration: 230, plainLyrics: "far", syncedLyrics: "[00:01.00]x\n[00:02.00]y\n[00:03.00]z"),
            LRCLIBProvider.Record(duration: 201, plainLyrics: "close plain"),
            LRCLIBProvider.Record(duration: 204, plainLyrics: "p", syncedLyrics: "[00:01.00]a\n[00:02.00]b\n[00:03.00]c"),
        ]
        #expect(LRCLIBProvider.bestMatch(results, duration: 200)?.duration == 204)
        #expect(LRCLIBProvider.bestMatch([results[0]], duration: 200) == nil)
    }

    @Test func cachedAnswerIsUsedFirst() async throws {
        LRCLIBStub.responses = ["get-cached": (200, #"{"duration":200,"syncedLyrics":"[00:01.00]a\n[00:02.00]b\n[00:03.00]c"}"#)]
        guard case .found(let lyrics) = try await provider().lyrics(for: query) else { Issue.record("expected lyrics"); return }
        #expect(lyrics.isSynced && lyrics.source == "lrclib")
    }

    @Test func busyFullLookupFallsBackToSearchAndIsntCertain() async throws {
        LRCLIBStub.responses = ["get-cached": (404, ""), "get": (503, ""), "search": (200, "[]")]
        #expect(try await provider().lyrics(for: query) == .notFound(certain: false))
        LRCLIBStub.responses = ["get-cached": (404, ""), "get": (404, ""), "search": (200, "[]")]
        #expect(try await provider().lyrics(for: query) == .notFound(certain: true))
        LRCLIBStub.responses = ["get-cached": (404, ""), "get": (200, #"{"duration":200,"instrumental":true}"#)]
        #expect(try await provider().lyrics(for: query) == .instrumental)
    }
}

/// A provider with fixed answers per title.
struct FakeLyricsProvider: LyricsProvider {
    let id = "fake"
    var answers: [String: LyricsLookup]
    var failing: Set<String> = []

    struct Offline: Error {}

    func lyrics(for query: LyricsQuery) async throws -> LyricsLookup {
        if failing.contains(query.title) { throw Offline() }
        return answers[query.title] ?? .notFound(certain: true)
    }
}

@MainActor
struct LyricsStoreTests {
    private func song(_ title: String) -> Track {
        Track(relativePath: "\(title).mp3", title: title, artist: "A", album: "B", genre: "G",
              year: nil, trackNumber: nil, duration: 200, coverKey: nil)
    }

    private func store(_ provider: FakeLyricsProvider) -> (LyricsStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "lyrics-tests-\(UUID().uuidString)/Lyrics")
        return (LyricsStore(sources: MediaSources(lyrics: [provider]), directory: directory), directory)
    }

    private let words = Lyrics(kind: .plain, lines: [.init(time: nil, text: "la")], source: "fake")

    @Test func missingListFollowsTheResults() async {
        let (lyricsStore, _) = store(FakeLyricsProvider(answers: ["Found": .found(words), "Inst": .instrumental], failing: ["Offline"]))
        let found = song("Found"), none = song("None"), inst = song("Inst"), offline = song("Offline")
        #expect(await lyricsStore.lyrics(for: found) == .found(words))
        #expect(await lyricsStore.lyrics(for: none) == .none)
        #expect(await lyricsStore.lyrics(for: inst) == .instrumental)
        #expect(await lyricsStore.lyrics(for: offline) == .unavailable)
        #expect(lyricsStore.missing == [none.id])
    }

    @Test func errorsAreNotRememberedButAnswersAre() async throws {
        let (lyricsStore, directory) = store(FakeLyricsProvider(answers: ["Found": .found(words)], failing: ["Offline"]))
        let found = song("Found"), offline = song("Offline")
        _ = await lyricsStore.lyrics(for: found)
        _ = await lyricsStore.lyrics(for: offline)
        #expect(FileManager.default.fileExists(atPath: LyricsStore.cacheFile(for: found.id, in: directory).path))
        #expect(!FileManager.default.fileExists(atPath: LyricsStore.cacheFile(for: offline.id, in: directory).path))
        // A fresh store (another launch) reads the saved answer and the missing list.
        let (other, _) = (LyricsStore(sources: MediaSources(lyrics: []), directory: directory), directory)
        #expect(await other.lyrics(for: found) == .found(words))
    }

    @Test func noLyricsIsCheckedAgainAfterAWeek() {
        #expect(!LyricsStore.CacheEntry(result: .none, saved: .now.addingTimeInterval(-6 * 86_400)).isExpired)
        #expect(LyricsStore.CacheEntry(result: .none, saved: .now.addingTimeInterval(-8 * 86_400)).isExpired)
        #expect(!LyricsStore.CacheEntry(result: .found(words), saved: .distantPast).isExpired)
    }

    @Test func downloadAllCountsAndSearchAgainOnlyChecksMissingSongs() async throws {
        let songs = (0..<6).map { song("Song \($0)") }
        var answers: [String: LyricsLookup] = [:]
        for index in 0..<4 { answers["Song \(index)"] = .found(words) }
        let (lyricsStore, _) = store(FakeLyricsProvider(answers: answers))
        lyricsStore.downloadAll(songs)
        while lyricsStore.isDownloading { try await Task.sleep(for: .milliseconds(20)) }
        #expect(lyricsStore.lastSummary == LyricsStore.Summary(found: 4, missing: 2, errors: 0, cancelled: false))
        #expect(lyricsStore.missing == Set(songs.suffix(2).map(\.id)))

        // Search again: only the two missing songs are looked up.
        lyricsStore.downloadAll(songs, searchAgainMissing: true)
        while lyricsStore.isDownloading { try await Task.sleep(for: .milliseconds(20)) }
        #expect(lyricsStore.lastSummary?.missing == 2 && lyricsStore.lastSummary?.found == 0)
    }
}

struct AudioFormatTests {
    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "format-tests-\(UUID().uuidString)/\(name)")
    }

    @Test func uncompressedFilesAreLosslessWithTheirSampleRate() throws {
        let url = try AudioFixtures.writeTone(to: temporaryURL("tone.caf"), seconds: 1, sampleRate: 48_000)
        let format = try #require(AudioFormat.read(url: url))
        #expect(format.codec == .pcm && format.isLossless)
        #expect(format.sampleRate == 48_000)
        #expect(format.bitDepth == 32)   // the fixture writes 32-bit float samples
    }

    @Test func aacFilesAreLossyWithABitrate() throws {
        let url = try AudioFixtures.writeAAC(to: temporaryURL("tone.m4a"), seconds: 2)
        let format = try #require(AudioFormat.read(url: url))
        #expect(format.codec == .aac && !format.isLossless)
        #expect((format.bitRate ?? 0) > 0)
        #expect(format.label.hasPrefix("AAC · "))
    }

    @Test func codecsAndBitDepthsFromCoreAudio() {
        #expect(AudioFormat.codec(for: kAudioFormatFLAC) == .flac)
        #expect(AudioFormat.codec(for: kAudioFormatAppleLossless) == .alac)
        #expect(AudioFormat.codec(for: kAudioFormatMPEGLayer3) == .mp3)
        #expect(AudioFormat.codec(for: kAudioFormatMPEG4AAC_HE) == .aac)
        var flac = AudioStreamBasicDescription()
        flac.mFormatFlags = kAppleLosslessFormatFlag_24BitSourceData
        #expect(AudioFormat.bitDepth(of: flac, codec: .flac) == 24)
        #expect(AudioFormat.bitDepth(of: flac, codec: .mp3) == nil)
        #expect(AudioFormat(codec: .flac, sampleRate: 96_000, bitDepth: 24).label == "FLAC · 24-bit/96 kHz")
        #expect(AudioFormat(codec: .mp3, sampleRate: 44_100, bitRate: 320).label == "MP3 · 320 kbps")
    }

    @Test func songsNotYetCheckedAreJudgedByExtension() {
        let flac = Track(relativePath: "a.flac", title: "A", artist: "B", album: "C", genre: "G", year: nil, trackNumber: nil, duration: 1, coverKey: nil)
        let m4a = Track(relativePath: "a.m4a", title: "A", artist: "B", album: "C", genre: "G", year: nil, trackNumber: nil, duration: 1, coverKey: nil)
        #expect(flac.isLossless && !m4a.isLossless)
        m4a.audioFormat = AudioFormat(codec: .alac, sampleRate: 44_100, bitDepth: 16)
        #expect(m4a.isLossless)   // an ALAC .m4a, once read
        #expect(SongFilter.apply([flac, m4a], losslessOnly: true).count == 2)
    }
}

struct DuplicateTests {
    private func copy(_ title: String, artist: String = "aurora", duration: Double = 200, format: AudioFormat?, added: TimeInterval = 0) -> DuplicateFinder.Candidate {
        DuplicateFinder.Candidate(id: UUID(), title: title, artistKey: artist, duration: duration,
                                  isLossless: format?.isLossless ?? false, format: format,
                                  addedAt: Date(timeIntervalSince1970: 1_000_000 + added))
    }

    private let mp3 = AudioFormat(codec: .mp3, sampleRate: 44_100, bitRate: 320)
    private let cdFlac = AudioFormat(codec: .flac, sampleRate: 44_100, bitDepth: 16, bitRate: 900)
    private let hiResFlac = AudioFormat(codec: .flac, sampleRate: 96_000, bitDepth: 24, bitRate: 3000)

    @Test func losslessCopyStaysByDefault() {
        let lossy = copy("Satellite", format: mp3, added: 0)
        let lossless = copy("satellite ", format: cdFlac, added: 60)   // case and spaces don't matter
        let hidden = DuplicateFinder.hiddenCopies([lossy, lossless], keeping: .lossless)
        #expect(hidden == [lossy.id: lossless.id])
    }

    @Test func lengthsMustBeWithinThreeSeconds() {
        let single = copy("Opening", duration: 200, format: mp3)
        let album = copy("Opening", duration: 202.5, format: cdFlac)
        let live = copy("Opening", duration: 260, format: cdFlac)
        let otherArtist = copy("Opening", artist: "kenji", duration: 200, format: cdFlac)
        let hidden = DuplicateFinder.hiddenCopies([single, album, live, otherArtist], keeping: .lossless)
        #expect(hidden == [single.id: album.id])
    }

    @Test func bestQualityPrefersHiResThenBitrate() {
        let cd = copy("Glass", format: cdFlac, added: 0)
        let hiRes = copy("Glass", format: hiResFlac, added: 60)
        // Lossless keeps the one added first; Best Quality keeps the hi-res copy.
        #expect(DuplicateFinder.hiddenCopies([cd, hiRes], keeping: .lossless) == [hiRes.id: cd.id])
        #expect(DuplicateFinder.hiddenCopies([cd, hiRes], keeping: .bestQuality) == [cd.id: hiRes.id])
        let low = copy("Glass", format: AudioFormat(codec: .aac, sampleRate: 44_100, bitRate: 128))
        let high = copy("Glass", format: AudioFormat(codec: .aac, sampleRate: 44_100, bitRate: 256), added: 60)
        #expect(DuplicateFinder.hiddenCopies([low, high], keeping: .bestQuality) == [low.id: high.id])
    }

    @Test func unknownLengthsAreNeverMatched() {
        let a = copy("Untitled", duration: 0, format: mp3)
        let b = copy("Untitled", duration: 0, format: cdFlac)
        #expect(DuplicateFinder.hiddenCopies([a, b], keeping: .lossless).isEmpty)
    }

    @Test @MainActor func hiddenCopiesLeaveListsButStillPlayWhenTapped() {
        let lossy = Track(relativePath: "A/Song.mp3", title: "Song", artist: "Aurora", album: "Single", genre: "Pop", year: nil, trackNumber: 1, duration: 200, coverKey: nil)
        lossy.audioFormat = mp3
        let lossless = Track(relativePath: "A/Song.flac", title: "Song", artist: "Aurora", album: "Album", genre: "Pop", year: nil, trackNumber: 1, duration: 201, coverKey: nil)
        lossless.audioFormat = cdFlac
        let other = Track(relativePath: "A/Other.flac", title: "Other", artist: "Aurora", album: "Album", genre: "Pop", year: nil, trackNumber: 2, duration: 150, coverKey: nil)
        let store = LibraryIndexStore()
        store.rebuild(tracks: [lossy, lossless, other], manualGroups: [:])
        #expect(store.keptCopy == [lossy.id: lossless.id])
        #expect(HiddenArtistRules.visible([lossy, lossless, other], hidden: [], index: store.index).map(\.id) == [lossless.id, other.id])
        // The artist page lists only the kept copy.
        #expect(Set(store.index.songIDs(for: Track.key(for: "Aurora"))) == [lossless.id, other.id])
        // In a playlist that holds the hidden copy, tapping it plays it, and the queue skips other copies.
        let queue = HiddenArtistRules.queue(tapping: lossy, in: [lossy, other], hidden: [], index: store.index)
        #expect(queue.tracks.map(\.id) == [lossy.id, other.id])
        // Keeping every copy isn't an option, but the choice changes which one stays.
        store.rebuild(tracks: [lossy, lossless, other], manualGroups: [:], duplicates: .bestQuality)
        #expect(store.keptCopy == [lossy.id: lossless.id])
    }
}
