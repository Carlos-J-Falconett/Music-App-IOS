import SwiftUI

/// Sort orders for the Songs section: library order or listening history.
enum SongSort: String, CaseIterable, Identifiable {
    case title, artist, album, recentlyAdded
    case mostListened, mostPlayed, recentlyPlayed, leastPlayed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .recentlyAdded: "Recently Added"
        case .mostListened: "Most Listened"
        case .mostPlayed: "Most Played"
        case .recentlyPlayed: "Recently Played"
        case .leastPlayed: "Least Played"
        }
    }

    var systemImage: String {
        switch self {
        case .title: "textformat"
        case .artist: "music.mic"
        case .album: "square.stack"
        case .recentlyAdded: "calendar.badge.plus"
        default: listeningOrder?.systemImage ?? "arrow.up.arrow.down"
        }
    }

    /// Set for the orders that come from listening history.
    var listeningOrder: ListeningOrder? {
        switch self {
        case .mostListened: .mostListened
        case .mostPlayed: .mostPlayed
        case .recentlyPlayed: .recentlyPlayed
        case .leastPlayed: .leastPlayed
        case .title, .artist, .album, .recentlyAdded: nil
        }
    }

    func sorted(_ tracks: [Track], totals: ListeningTotals) -> [Track] {
        if let order = listeningOrder {
            return tracks.sorted { a, b in
                order.ordered(totals.track(a.id), totals.track(b.id))
                    ?? (a.title.localizedStandardCompare(b.title) == .orderedAscending)
            }
        }
        switch self {
        case .artist:
            return tracks.sorted { ($0.artist, $0.album, $0.trackNumber ?? 0) < ($1.artist, $1.album, $1.trackNumber ?? 0) }
        case .album:
            return tracks.sorted { ($0.album, $0.trackNumber ?? 0) < ($1.album, $1.trackNumber ?? 0) }
        case .recentlyAdded:
            return tracks.sorted { $0.addedAt > $1.addedAt }
        default:
            return tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }
}

/// Sort orders for Artists and Genres (each section remembers its own choice).
enum CollectionSort: String, CaseIterable, Identifiable {
    case name, mostSongs
    case mostListened, mostPlayed, recentlyPlayed, leastPlayed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name: "Name"
        case .mostSongs: "Most Songs"
        case .mostListened: "Most Listened"
        case .mostPlayed: "Most Played"
        case .recentlyPlayed: "Recently Played"
        case .leastPlayed: "Least Played"
        }
    }

    var systemImage: String {
        switch self {
        case .name: "textformat"
        case .mostSongs: "music.note.list"
        default: listeningOrder?.systemImage ?? "arrow.up.arrow.down"
        }
    }

    var listeningOrder: ListeningOrder? {
        switch self {
        case .mostListened: .mostListened
        case .mostPlayed: .mostPlayed
        case .recentlyPlayed: .recentlyPlayed
        case .leastPlayed: .leastPlayed
        case .name, .mostSongs: nil
        }
    }

    /// Sorts any list of artists or genres; ties fall back to name order.
    func sorted<Item>(_ items: [Item], name: (Item) -> String, songCount: (Item) -> Int, listening: (Item) -> ListeningTotals.Entry) -> [Item] {
        items.sorted { a, b in
            let byName = name(a).localizedStandardCompare(name(b)) == .orderedAscending
            if let order = listeningOrder {
                return order.ordered(listening(a), listening(b)) ?? byName
            }
            if self == .mostSongs, songCount(a) != songCount(b) {
                return songCount(a) > songCount(b)
            }
            return byName
        }
    }
}

extension ListeningOrder {
    var systemImage: String {
        switch self {
        case .mostListened: "clock"
        case .mostPlayed: "play.circle"
        case .recentlyPlayed: "clock.arrow.circlepath"
        case .leastPlayed: "sparkles"
        }
    }
}

/// The Sort menu's choices, split into library orders and listening-history orders.
struct SortPicker<Sort: CaseIterable & Identifiable & Hashable>: View where Sort.AllCases: RandomAccessCollection {
    @Binding var selection: Sort
    let label: (Sort) -> String
    let systemImage: (Sort) -> String
    let isListening: (Sort) -> Bool

    var body: some View {
        // Menu sections with toggles (a Picker inside a menu flattens its sections and
        // drops the "Listening" heading). A toggle shows the checkmark on the current order.
        Section("Sort By") {
            ForEach(Sort.allCases.filter { !isListening($0) }) { option(for: $0) }
        }
        Section("Listening") {
            ForEach(Sort.allCases.filter(isListening)) { option(for: $0) }
        }
    }

    private func option(for value: Sort) -> some View {
        Toggle(isOn: Binding(get: { selection == value }, set: { if $0 { selection = value } })) {
            Label(label(value), systemImage: systemImage(value))
        }
    }
}

/// Shared with the Songs list and the Library header's Play / Shuffle: when on, only
/// lossless songs (FLAC, ALAC, WAV, AIFF) are shown and played.
enum SongFilter {
    static let losslessOnlyKey = "songsLosslessOnly"

    static func apply(_ tracks: [Track], losslessOnly: Bool) -> [Track] {
        losslessOnly ? tracks.filter(\.isLossless) : tracks
    }
}

/// Sort orders for the Albums section.
enum AlbumSort: String, CaseIterable, Identifiable {
    case title, artist, year, recentlyAdded
    case mostListened, mostPlayed, recentlyPlayed, leastPlayed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .year: "Year"
        case .recentlyAdded: "Recently Added"
        case .mostListened: "Most Listened"
        case .mostPlayed: "Most Played"
        case .recentlyPlayed: "Recently Played"
        case .leastPlayed: "Least Played"
        }
    }

    var systemImage: String {
        switch self {
        case .title: "textformat"
        case .artist: "music.mic"
        case .year: "calendar"
        case .recentlyAdded: "calendar.badge.plus"
        default: listeningOrder?.systemImage ?? "arrow.up.arrow.down"
        }
    }

    var listeningOrder: ListeningOrder? {
        switch self {
        case .mostListened: .mostListened
        case .mostPlayed: .mostPlayed
        case .recentlyPlayed: .recentlyPlayed
        case .leastPlayed: .leastPlayed
        case .title, .artist, .year, .recentlyAdded: nil
        }
    }

    /// Ties fall back to album title.
    func sorted(_ albums: [AlbumSummary], totals: ListeningTotals) -> [AlbumSummary] {
        albums.sorted { a, b in
            let byTitle = a.name.localizedStandardCompare(b.name) == .orderedAscending
            if let order = listeningOrder {
                return order.ordered(totals.combined(a.trackIDs), totals.combined(b.trackIDs)) ?? byTitle
            }
            switch self {
            case .artist:
                let byArtist = a.ownerName.localizedStandardCompare(b.ownerName)
                return byArtist == .orderedSame ? byTitle : byArtist == .orderedAscending
            case .year:
                // Newest first; albums without a year go last.
                if a.year != b.year { return (a.year ?? Int.min) > (b.year ?? Int.min) }
                return byTitle
            case .recentlyAdded:
                return a.addedAt == b.addedAt ? byTitle : a.addedAt > b.addedAt
            default:
                return byTitle
            }
        }
    }
}
