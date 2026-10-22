import Foundation
import Observation

/// Splits artist credits like "Kendrick Lamar feat. Bilal, Anna Wise & Snoop Dogg"
/// into individual artists. The rules:
///
/// - **Feature markers always split:** `feat`, `feat.`, `ft`, `ft.`, `featuring`
///   and `f/` separate the main artists from the featured ones.
/// - **Inside the featured part**, `,` `&` and ` / ` always split
///   (so "Totó la Momposina / Susana Baca" becomes two artists).
/// - **Everywhere else**, `,` `&` ` x ` ` + ` and ` with ` split **only** if at least one
///   of the pieces is already its own artist in the library. "Bad Bunny & Chuwi" splits
///   (Bad Bunny exists); "Of Mice & Men", "Wolf & Bear", "Sleeping With Sirens" and
///   "Florence + the Machine" stay whole.
/// - `;` always splits (tag editors use it between multiple artists), and ` × ` is
///   treated like ` x `.
/// - Names are never guessed: "Daryl Palumbo of Glassjaw" stays one name, and
///   slashes outside a featured part (like "AC/DC") are never touched.
/// - Song titles can add featured artists too: "(feat. X)", "[ft. X]", "(with X)".
nonisolated enum ArtistCredits {
    struct Parsed: Equatable, Sendable {
        var main: [String]
        var featured: [String]
        var all: [String] { main + featured }
    }

    /// Separates the main artists from the featured ones.
    private static let featureMarker = /(?i)\s+(?:feat\.?|ft\.?|featuring|f\/)\s+/
    /// Separators that only split when one piece is a known artist.
    private static let smartSeparators = /(?i)\s*,\s+|\s+(?:&|x|×|\+|with)\s+/
    /// Separators that always split inside a featured part.
    private static let featuredSeparators = /\s*,\s+|\s+&\s+|\s+\/\s+|\s*;\s*/
    /// Always splits anywhere (multi-value tags like "Telemann; Kuijken").
    private static let listSeparator = /\s*;\s*/
    /// Every separator at once, for comparing two credits loosely.
    private static let anySeparator = /(?i)\s*[,;]\s*|\s+(?:&|x|×|\+|\/|with|and|feat\.?|ft\.?|featuring|f\/)\s+/
    /// "(feat. X)", "[ft. X]", "(with X)" in a song title.
    private static let titleFeature = /(?i)[\(\[]\s*(?:feat\.?|ft\.?|featuring|with)\s+([^\)\]]+)[\)\]]/

    /// Parses an artist field. `known` holds the keys (`Track.key(for:)`) of artists
    /// that exist on their own, which decides the smart separators.
    static func parse(_ field: String, known: Set<String>) -> Parsed {
        let trimmed = field.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Parsed(main: [], featured: []) }

        var mainPart = Substring(trimmed)
        var featuredPart: Substring?
        if let match = trimmed.firstMatch(of: featureMarker) {
            mainPart = trimmed[..<match.range.lowerBound]
            featuredPart = trimmed[match.range.upperBound...]
        }

        let main = split(String(mainPart), on: listSeparator).flatMap { smartSplit($0, known: known) }
        let featured = featuredPart.map { part in
            split(String(part), on: featuredSeparators).flatMap { smartSplit($0, known: known) }
        } ?? []
        return deduplicated(Parsed(main: main, featured: featured))
    }

    /// Featured artists named in a song title, e.g. "Song (feat. A & B)".
    static func titleFeatures(_ title: String) -> [String] {
        title.matches(of: titleFeature).flatMap { match in
            split(String(match.1), on: featuredSeparators)
        }
    }

    /// Splits on the smart separators only when one of the pieces is a known artist.
    static func smartSplit(_ text: String, known: Set<String>) -> [String] {
        let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = split(whole, on: smartSeparators)
        guard pieces.count > 1, pieces.contains(where: { known.contains(Track.key(for: $0)) }) else {
            return whole.isEmpty ? [] : [whole]
        }
        return pieces
    }

    /// Every name in a credit split on every separator, as keys. Used to tell whether an
    /// Album Artist is just the song's own credit written differently
    /// ("Becky G + Paulo Londra" vs "Becky G & Paulo Londra", "A × B" vs "B × A").
    static func looseKeys(_ text: String) -> Set<String> {
        Set(split(text, on: anySeparator).map(Track.key(for:)))
    }

    /// Album Artist values that aren't names, like the database ID
    /// "7a3970c9-ecd8-4eee-a267-4d8c77d97ff3" some taggers store there.
    static func isIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.wholeMatch(of: /(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/) != nil { return true }
        // Long runs of hex digits or letter-digit soup with no spaces (e.g. 24+ character IDs).
        return trimmed.count >= 20 && !trimmed.contains(" ") && trimmed.contains(where: \.isNumber) && trimmed.contains(where: \.isLetter)
    }

    private static func split(_ text: String, on separator: some RegexComponent) -> [String] {
        text.split(separator: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Removes repeats (by key), and featured artists that are also main artists.
    private static func deduplicated(_ parsed: Parsed) -> Parsed {
        var seen = Set<String>()
        func unique(_ names: [String]) -> [String] {
            names.filter { seen.insert(Track.key(for: $0)).inserted }
        }
        let main = unique(parsed.main)
        return Parsed(main: main, featured: unique(parsed.featured))
    }
}

/// The plain song details the index needs, so it can be built and tested without SwiftData.
nonisolated struct CreditSource: Sendable {
    let id: UUID
    let artist: String
    let title: String
    let album: String
    /// The Album Artist tag ("" or nil when there isn't one).
    let albumArtist: String?
}

/// Who is on which song, built from the whole library at once (the smart split needs
/// to know every artist). Also works out groups: a song by "SANA" on an album whose
/// Album Artist is "TWICE" makes SANA a member of TWICE, so the song is listed on
/// TWICE's page too and SANA shows TWICE's picture until she gets her own.
nonisolated struct ArtistIndex: Sendable {
    struct Credits: Sendable, Equatable {
        /// Main artists; the first one is the song's primary artist.
        var main: [String]
        var featured: [String]
        /// Album Artist names (split with the same rules).
        var albumArtists: [String]
        var primary: String? { main.first }
        var all: [String] { main + featured }
    }

    /// Album Artist values that mean "a compilation", not a group.
    static let compilationNames: Set<String> = ["various artists", "various", "va", "soundtrack", "unknown artist"]

    private(set) var credits: [UUID: Credits] = [:]
    /// Display name for each artist key (the first spelling seen, preferring a standalone credit).
    private(set) var names: [String: String] = [:]
    /// Songs listed on each artist's page (credited, or on their group's albums).
    private(set) var songsByArtist: [String: [UUID]] = [:]
    /// Member key → group key.
    private(set) var groupOf: [String: String] = [:]
    /// Keys whose display name came from a song credited to that artist alone.
    private var standaloneKeys: Set<String> = []
    /// Artists that exist on their own (decides the smart split; reused for stats).
    private(set) var knownKeys: Set<String> = []
    /// Extra copies of songs the library has more than once (Settings → Duplicates). They
    /// aren't in the index, and lists, search and shuffle leave them out.
    var hiddenCopies: Set<UUID> = []

    static let empty = ArtistIndex()

    private init() {}

    /// - Parameter manualGroups: member key → group key set by the user ("Member of…").
    init(sources: [CreditSource], manualGroups: [String: String] = [:]) {
        // 1. Artists that exist on their own: whole artist fields and Album Artists.
        var known = Set<String>()
        for source in sources {
            known.insert(Track.key(for: source.artist))
            if let albumArtist = source.albumArtist, !albumArtist.isEmpty, !ArtistCredits.isIdentifier(albumArtist) {
                known.insert(Track.key(for: albumArtist))
            }
            if let match = source.artist.firstMatch(of: /(?i)\s+(?:feat\.?|ft\.?|featuring|f\/)\s+/) {
                known.insert(Track.key(for: String(source.artist[..<match.range.lowerBound])))
            }
        }
        defer { knownKeys = known }
        // 2. Splitting can reveal more standalone artists ("Chencho Corleone" from
        //    "Bad Bunny & Chencho Corleone"), which can unlock other credits. Repeat a few times.
        for _ in 0..<4 {
            var grew = false
            for source in sources {
                for name in ArtistCredits.parse(source.artist, known: known).all where known.insert(Track.key(for: name)).inserted {
                    grew = true
                }
            }
            if !grew { break }
        }

        // 3. Credits for every song.
        for source in sources {
            let parsed = ArtistCredits.parse(source.artist, known: known)
            var featured = parsed.featured
            for name in ArtistCredits.titleFeatures(source.title)
            where !(parsed.main + featured).contains(where: { Track.key(for: $0) == Track.key(for: name) }) {
                featured.append(name)
            }
            let entry = Credits(main: parsed.main.isEmpty ? [source.artist] : parsed.main,
                                featured: featured,
                                albumArtists: Self.albumArtistNames(for: source, known: known))
            credits[source.id] = entry
            for name in entry.all { add(source.id, to: name, standalone: entry.all.count == 1) }
        }

        // 4. Albums where the Album Artist is co-credited with other artists (like a
        //    soundtrack where the composer shares credits) are collaborations, not
        //    group albums, so nobody becomes a "member" from them.
        var collaborationAlbums = Set<String>()        // "groupKey|album"
        for source in sources {
            guard let entry = credits[source.id], entry.all.count > 1,
                  let raw = source.albumArtist, !raw.isEmpty, !ArtistCredits.isIdentifier(raw) else { continue }
            // Uses the raw tag: on these songs the cleaned-up Album Artist is empty,
            // because the owner is credited on the song itself.
            let ownerKey = Track.key(for: raw)
            if entry.all.contains(where: { Track.key(for: $0) == ownerKey }) {
                collaborationAlbums.insert(ownerKey + "|" + source.album)
            }
        }

        // 5. Album Artists that aren't credited on the song: it's their album, so the song
        //    goes on their page. On a real group album (like TWICE's TEN, where TWICE is
        //    never co-credited), the song's main artists also count as members.
        var groupAlbums: [String: Set<String>] = [:]   // artist key → album names they own or are on
        for source in sources {
            guard let entry = credits[source.id] else { continue }
            for name in entry.all { groupAlbums[Track.key(for: name), default: []].insert(source.album) }
            for groupName in entry.albumArtists {
                let groupKey = Track.key(for: groupName)
                groupAlbums[groupKey, default: []].insert(source.album)
                names[groupKey] = names[groupKey] ?? groupName
                add(source.id, to: groupName, standalone: false)
                let isGroupAlbum = entry.albumArtists.count == 1
                    && !collaborationAlbums.contains(groupKey + "|" + source.album)
                    && !Self.isSoundtrack(source.album)
                guard isGroupAlbum else { continue }
                for member in entry.main where Track.key(for: member) != groupKey {
                    groupOf[Track.key(for: member)] = groupKey
                }
            }
        }

        // 6. Groups set by hand: the member's songs on the group's albums join the group page.
        for (member, group) in manualGroups where member != group {
            groupOf[member] = group
            let albums = groupAlbums[group] ?? []
            for source in sources where albums.contains(source.album) {
                guard let entry = credits[source.id], entry.main.contains(where: { Track.key(for: $0) == member }) else { continue }
                if !(songsByArtist[group] ?? []).contains(source.id) { songsByArtist[group, default: []].append(source.id) }
            }
        }
    }

    /// The song's Album Artist names that are *someone else* (a group, the album's main
    /// artist). Empty when there's no tag, it's a compilation or an ID instead of a name,
    /// or it's just the song's own credit written another way.
    private static func albumArtistNames(for source: CreditSource, known: Set<String>) -> [String] {
        guard let raw = source.albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              !ArtistCredits.isIdentifier(raw), !compilationNames.contains(Track.key(for: raw)) else { return [] }
        // "Bad Bunny ft. Drake", "MY FIRST STORY × HYDE", "Telemann; Kuijken": the same
        // artists as the song (in any order or style), so not a separate album owner.
        if !ArtistCredits.looseKeys(raw).isDisjoint(with: ArtistCredits.looseKeys(source.artist)) { return [] }
        return ArtistCredits.parse(raw, known: known).all
    }

    /// Soundtracks credit a composer as Album Artist; their collaborators aren't members.
    private static func isSoundtrack(_ album: String) -> Bool {
        album.range(of: #"(?i)\b(soundtrack|o\.?s\.?t\.?|score)\b"#, options: .regularExpression) != nil
    }

    private mutating func add(_ id: UUID, to name: String, standalone: Bool) {
        let key = Track.key(for: name)
        // Prefer the spelling from a song credited to this artist alone ("Bad Bunny", not a piece of a credit).
        if names[key] == nil || (standalone && !standaloneKeys.contains(key)) {
            names[key] = name
            if standalone { standaloneKeys.insert(key) }
        }
        if songsByArtist[key]?.last != id { songsByArtist[key, default: []].append(id) }
    }

    // MARK: Lookups

    func credits(for id: UUID) -> Credits? { credits[id] }

    /// The song's primary artist key, or nil if the song isn't in the index.
    func primaryKey(of id: UUID) -> String? {
        credits[id]?.primary.map(Track.key(for:))
    }

    func name(for key: String) -> String { names[key] ?? key }

    /// Every artist key with at least one song.
    var artistKeys: [String] { Array(songsByArtist.keys) }

    func songIDs(for key: String) -> [UUID] { songsByArtist[key] ?? [] }

    /// Whether `key` is credited on the song (main or featured), as opposed to only owning its album.
    func isCredited(_ key: String, on id: UUID) -> Bool {
        credits[id]?.all.contains { Track.key(for: $0) == key } ?? false
    }

    /// The line under a song on an artist's page: the other artists on it.
    /// "with Bad Bunny" on Chuwi's page; "SANA" for a member's song on TWICE's page.
    func subtitle(for id: UUID, onPageOf key: String) -> String? {
        guard let entry = credits[id] else { return nil }
        if isCredited(key, on: id) {
            let others = entry.all.filter { Track.key(for: $0) != key }
            return others.isEmpty ? nil : "with " + others.formatted(.list(type: .and))
        }
        return entry.main.formatted(.list(type: .and))
    }
}

/// Holds the current `ArtistIndex` for every screen. A root modifier rebuilds it
/// only when the library's credits actually change, so screens never redo the work.
@Observable
final class LibraryIndexStore {
    private(set) var index: ArtistIndex = .empty
    /// Every artist with their counts and circle cover, sorted by name. Worked out once
    /// per library change instead of on every redraw of the Artists grid, Home, Search
    /// and Member of… (it walks the whole library).
    private(set) var artists: [ArtistSummary] = []
    @ObservationIgnored private var artistsByKey: [String: ArtistSummary] = [:]
    /// Each hidden duplicate copy, mapped to the copy kept in its place.
    private(set) var keptCopy: [UUID: UUID] = [:]

    /// The summaries for `keys`, in that order (unknown keys are skipped).
    func artists(for keys: [String]) -> [ArtistSummary] { keys.compactMap { artistsByKey[$0] } }

    /// Changes whenever anything the index depends on changes.
    static func fingerprint(tracks: [Track], manualGroups: [String: String], duplicates: DuplicatePreference = .lossless) -> Int {
        var hasher = Hasher()
        hasher.combine(tracks.count)
        hasher.combine(duplicates)
        for track in tracks {
            hasher.combine(track.id)
            hasher.combine(track.artist)
            hasher.combine(track.title)
            hasher.combine(track.album)
            hasher.combine(track.albumArtist)
            // The circles show the latest album's cover, which depends on these too.
            hasher.combine(track.coverKey)
            hasher.combine(track.year)
            // Which copy of a duplicated song stays depends on these.
            hasher.combine(track.duration)
            hasher.combine(track.codec)
            hasher.combine(track.sampleRate)
            hasher.combine(track.bitDepth)
            hasher.combine(track.bitRate)
        }
        for (member, group) in manualGroups.sorted(by: { $0.key < $1.key }) {
            hasher.combine(member)
            hasher.combine(group)
        }
        return hasher.finalize()
    }

    func rebuild(tracks: [Track], manualGroups: [String: String], duplicates: DuplicatePreference = .lossless) {
        let full = ArtistIndex(sources: tracks.map(\.creditSource), manualGroups: manualGroups)
        // Songs in the library more than once: one copy stays, the others are left out of
        // the index (so artist pages, counts and circles skip them) and of every list.
        let candidates = tracks.map { track in
            DuplicateFinder.Candidate(id: track.id, title: track.title, artistKey: full.primaryKey(of: track),
                                      duration: track.duration, isLossless: track.isLossless,
                                      format: track.audioFormat, addedAt: track.addedAt)
        }
        keptCopy = DuplicateFinder.hiddenCopies(candidates, keeping: duplicates)
        if keptCopy.isEmpty {
            index = full
        } else {
            index = ArtistIndex(sources: tracks.filter { keptCopy[$0.id] == nil }.map(\.creditSource), manualGroups: manualGroups)
            index.hiddenCopies = Set(keptCopy.keys)
        }
        artists = LibraryGrouping.artists(index: index, tracks: tracks)
        artistsByKey = Dictionary(artists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Lookups that take a SwiftData `Track` (main actor only).
extension ArtistIndex {
    /// The song's primary artist key (falls back to the whole artist field).
    func primaryKey(of track: Track) -> String {
        primaryKey(of: track.id) ?? track.artistKey
    }

    /// The key of the artist who owns the song's album: the Album Artist, else the primary artist.
    func albumOwnerKey(of track: Track) -> String {
        if let owner = credits(for: track.id)?.albumArtists.first, !Self.compilationNames.contains(Track.key(for: owner)) {
            return Track.key(for: owner)
        }
        return primaryKey(of: track)
    }

    /// The songs on an artist's page, in library order.
    func songs(for key: String, in lookup: [UUID: Track]) -> [Track] {
        songIDs(for: key).compactMap { lookup[$0] }
    }
}

extension Track {
    var creditSource: CreditSource {
        CreditSource(id: id, artist: artist, title: title, album: album, albumArtist: albumArtist)
    }
}

import SwiftUI
import SwiftData

extension View {
    /// Keeps `LibraryIndexStore` in sync with the library. Apply once, at the root.
    func libraryIndexing() -> some View {
        modifier(LibraryIndexing())
    }
}

private struct LibraryIndexing: ViewModifier {
    @Environment(LibraryIndexStore.self) private var store
    @Query private var tracks: [Track]
    @Query private var groupLinks: [ArtistGroupLink]
    @AppStorage(DuplicatePreference.storageKey) private var duplicates: DuplicatePreference = .lossless

    func body(content: Content) -> some View {
        let manual = Dictionary(groupLinks.map { ($0.memberKey, $0.groupKey) }, uniquingKeysWith: { first, _ in first })
        // Only rebuilt when credits, formats or the duplicate setting change (not on
        // favorites, EQ or play counts).
        content.onChange(of: LibraryIndexStore.fingerprint(tracks: tracks, manualGroups: manual, duplicates: duplicates), initial: true) {
            store.rebuild(tracks: tracks, manualGroups: manual, duplicates: duplicates)
        }
    }
}
