import Foundation
import Observation
import SwiftUI  // Array.move(fromOffsets:toOffset:)

/// One slot in the queue. It has its own id so the same song can be queued twice.
nonisolated struct QueueEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let trackID: UUID

    init(trackID: UUID) {
        self.id = UUID()
        self.trackID = trackID
    }
}

nonisolated enum RepeatMode: String, CaseIterable, Sendable {
    case off, all, one

    /// Desktop cycle order: off → repeat queue → repeat current song.
    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    var symbolName: String { self == .one ? "repeat.1" : "repeat" }
}

/// "Up Next". Like the desktop app it keeps the original order and a separate
/// play order, so turning shuffle off returns to the original sequence.
@Observable
final class QueueManager {
    private(set) var original: [QueueEntry] = []
    private(set) var order: [QueueEntry] = []
    private(set) var index = 0
    private(set) var isShuffled = false
    var repeatMode: RepeatMode = .off

    /// Shuffle function; tests replace it to get a predictable order.
    @ObservationIgnored var shuffler: ([QueueEntry]) -> [QueueEntry] = { $0.shuffled() }

    var current: QueueEntry? { order.indices.contains(index) ? order[index] : nil }

    /// Songs after the current one, in play order.
    var upcoming: [QueueEntry] {
        guard index + 1 < order.count else { return [] }
        return Array(order[(index + 1)...])
    }

    var isEmpty: Bool { order.isEmpty }

    // MARK: Building the queue

    /// Replaces the queue with `trackIDs`, starting at `startIndex`.
    func setQueue(_ trackIDs: [UUID], startAt startIndex: Int, shuffle: Bool) {
        original = trackIDs.map(QueueEntry.init)
        isShuffled = shuffle
        guard !original.isEmpty else {
            order = []
            index = 0
            return
        }
        let start = min(max(startIndex, 0), original.count - 1)
        if shuffle {
            var rest = original
            let first = rest.remove(at: start)
            order = [first] + shuffler(rest)
            index = 0
        } else {
            order = original
            index = start
        }
    }

    func toggleShuffle() {
        isShuffled.toggle()
        guard let current else { return }
        if isShuffled {
            // Keep the current song playing and shuffle everything else after it.
            order = [current] + shuffler(original.filter { $0.id != current.id })
            index = 0
        } else {
            order = original
            index = original.firstIndex(of: current) ?? 0
        }
    }

    /// Inserts a song right after the current one.
    func playNext(_ trackID: UUID) {
        let entry = QueueEntry(trackID: trackID)
        guard let current else {
            original = [entry]
            order = [entry]
            index = 0
            return
        }
        order.insert(entry, at: index + 1)
        let originalIndex = original.firstIndex(of: current).map { $0 + 1 } ?? original.count
        original.insert(entry, at: originalIndex)
    }

    /// Adds songs to the end of the queue.
    func append(_ trackIDs: [UUID]) {
        let entries = trackIDs.map(QueueEntry.init)
        order += entries
        original += entries
    }

    // MARK: Moving through the queue

    /// Moves to the next entry. `automatic` is true when a song ended by itself,
    /// which is the only time Repeat One replays the same song.
    func advance(automatic: Bool) -> QueueEntry? {
        guard !order.isEmpty else { return nil }
        if automatic && repeatMode == .one { return current }
        if index + 1 < order.count {
            index += 1
            return current
        }
        if repeatMode == .all {
            index = 0
            return current
        }
        return nil
    }

    func goBack() -> QueueEntry? {
        guard !order.isEmpty else { return nil }
        if index > 0 {
            index -= 1
        } else if repeatMode == .all {
            index = order.count - 1
        }
        return current
    }

    /// Jumps straight to an entry (tapping a song in the queue).
    func jump(to entryID: QueueEntry.ID) -> QueueEntry? {
        guard let target = order.firstIndex(where: { $0.id == entryID }) else { return nil }
        index = target
        return current
    }

    // MARK: Editing "Up Next"

    /// Reorders the upcoming list (offsets are relative to `upcoming`).
    func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        var next = upcoming
        next.move(fromOffsets: source, toOffset: destination)
        order = Array(order.prefix(index + 1)) + next
        if !isShuffled { original = order }
    }

    /// Removes upcoming entries (offsets are relative to `upcoming`).
    func removeUpcoming(atOffsets offsets: IndexSet) {
        let removed = Set(offsets.compactMap { upcoming.indices.contains($0) ? upcoming[$0].id : nil })
        order.removeAll { removed.contains($0.id) }
        original.removeAll { removed.contains($0.id) }
    }

    /// Removes upcoming entries by their queue ids (the current song is never removed).
    func removeUpcoming(ids: Set<QueueEntry.ID>) {
        let upcomingIDs = Set(upcoming.map(\.id))
        let removed = ids.intersection(upcomingIDs)
        order.removeAll { removed.contains($0.id) }
        original.removeAll { removed.contains($0.id) }
    }

    /// Removes every upcoming entry for these songs (used when an artist is hidden).
    func removeUpcoming(trackIDs: Set<UUID>) {
        removeUpcoming(ids: Set(upcoming.filter { trackIDs.contains($0.trackID) }.map(\.id)))
    }

    /// Moves upcoming entries given as a reordered list of their ids. Entries not
    /// in `newOrder` keep their relative order after the moved ones.
    func reorderUpcoming(_ newOrder: [QueueEntry.ID]) {
        let byID = Dictionary(upcoming.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let listed = newOrder.compactMap { byID[$0] }
        let listedIDs = Set(listed.map(\.id))
        let rest = upcoming.filter { !listedIDs.contains($0.id) }
        order = Array(order.prefix(index + 1)) + listed + rest
        if !isShuffled { original = order }
    }

    /// Clears everything after the current song.
    func clearUpcoming() {
        guard let current else { return clear() }
        order = [current]
        original = [current]
        index = 0
    }

    func clear() {
        order = []
        original = []
        index = 0
    }

    /// Drops every entry for a song that was deleted from the library.
    func remove(trackID: UUID) {
        let currentID = current?.id
        order.removeAll { $0.trackID == trackID }
        original.removeAll { $0.trackID == trackID }
        index = currentID.flatMap { id in order.firstIndex { $0.id == id } } ?? min(index, max(order.count - 1, 0))
    }
}
