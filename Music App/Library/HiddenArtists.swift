import SwiftUI
import SwiftData

/// Rules for hidden artists, kept in one place so every screen applies them the same way.
///
/// - All Songs and Search leave hidden artists' songs out entirely.
/// - Genre lists still show their songs, but Play / Shuffle skip them, and tapping
///   one of them plays just that song plus the rest of the list without hidden songs.
/// - Their own artist page (and its albums), playlists and Favorites play everything,
///   because opening those is an intentional choice.
/// - A song counts as hidden only when its **primary** (first) artist is hidden.
///   Hiding Chuwi doesn't hide "Bad Bunny & Chuwi"; hiding Bad Bunny does.
enum HiddenArtistRules {
    /// Songs whose primary artist isn't hidden, without hidden duplicate copies.
    static func visible(_ tracks: [Track], hidden: Set<String>, index: ArtistIndex) -> [Track] {
        let copies = index.hiddenCopies
        guard !hidden.isEmpty || !copies.isEmpty else { return tracks }
        return tracks.filter { !copies.contains($0.id) && !hidden.contains(index.primaryKey(of: $0)) }
    }

    /// Songs without hidden duplicate copies (lists that keep hidden artists, e.g. genres).
    static func withoutHiddenCopies(_ tracks: [Track], index: ArtistIndex) -> [Track] {
        let copies = index.hiddenCopies
        return copies.isEmpty ? tracks : tracks.filter { !copies.contains($0.id) }
    }

    static func isHidden(_ track: Track, hidden: Set<String>, index: ArtistIndex) -> Bool {
        !hidden.isEmpty && hidden.contains(index.primaryKey(of: track))
    }

    /// The queue for tapping `tapped` in a list that may contain hidden songs:
    /// the tapped song always plays, the rest of the queue skips hidden artists.
    static func queue(tapping tapped: Track, in tracks: [Track], hidden: Set<String>, index: ArtistIndex) -> (tracks: [Track], start: Int) {
        // Hidden duplicate copies are skipped too (they only appear in playlists).
        let copies = index.hiddenCopies
        let queue = tracks.filter { $0.id == tapped.id || (!copies.contains($0.id) && !isHidden($0, hidden: hidden, index: index)) }
        return (queue, queue.firstIndex { $0.id == tapped.id } ?? 0)
    }
}

extension Array where Element == HiddenArtist {
    var keys: Set<String> { Set(map(\.artistKey)) }
}

/// Hides or unhides artists. Hiding also drops their songs from what's coming up
/// in the current queue, so they disappear from "Up Next" right away.
enum HiddenArtistActions {
    static func setHidden(_ hide: Bool, artistKey: String, context: ModelContext, player: MusicPlayer, index: ArtistIndex) {
        let existing = (try? context.fetch(FetchDescriptor<HiddenArtist>(
            predicate: #Predicate { $0.artistKey == artistKey }
        ))) ?? []
        if hide {
            guard existing.isEmpty else { return }
            context.insert(HiddenArtist(artistKey: artistKey))
            let tracks = (try? context.fetch(FetchDescriptor<Track>())) ?? []
            // Only songs where they're the primary artist (features stay).
            let ids = Set(tracks.filter { index.primaryKey(of: $0) == artistKey }.map(\.id))
            player.queue.removeUpcoming(trackIDs: ids)
        } else {
            existing.forEach(context.delete)
        }
        try? context.save()
    }
}
