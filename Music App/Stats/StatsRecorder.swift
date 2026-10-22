import Foundation
import SwiftData

/// The desktop app's session rules (`stats.py`), kept separate so they can be tested.
nonisolated enum ListeningRules {
    /// Sessions shorter than this are never saved (quick skips).
    static let minimumSessionSeconds = 5.0
    /// A song counts as a play after half its length or 4 minutes, whichever comes first.
    static let playCap = 240.0
    static let saveInterval: Duration = .seconds(30)

    static func shouldSave(listened: Double) -> Bool { listened >= minimumSessionSeconds }

    static func isPlay(listened: Double, duration: Double) -> Bool {
        let threshold = duration > 0 ? min(duration / 2, playCap) : playCap
        return listened >= threshold
    }
}

/// Records listening sessions:
/// - a session starts whenever a song loads (and on each Repeat One restart);
/// - only time spent actually playing counts — pauses and seeks add nothing;
/// - the in-progress session is saved every 30 s, on song change and when the app backgrounds.
final class StatsRecorder {
    private struct Pending {
        let start: Date
        let trackID: UUID
        let title: String
        let artist: String
        let album: String
        let genre: String
        let duration: Double
    }

    private let context: ModelContext
    private var pending: Pending?
    private var saved: ListenSession?
    private var listened: Double = 0
    private var resumedAt: Date?
    private var saveLoop: Task<Void, Never>?

    init(context: ModelContext) {
        self.context = context
        saveLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: ListeningRules.saveInterval)
                guard let self else { return }
                flush()
            }
        }
    }

    /// Starts a new session for `track`, closing any previous one.
    func begin(_ track: Track, playing: Bool) {
        finish()
        pending = Pending(
            start: .now, trackID: track.id, title: track.title, artist: track.artist,
            album: track.album, genre: track.genre, duration: track.duration
        )
        listened = 0
        resumedAt = playing ? .now : nil
    }

    func setPlaying(_ playing: Bool) {
        if playing {
            if resumedAt == nil { resumedAt = .now }
        } else {
            accumulate()
            resumedAt = nil
        }
    }

    /// Saves progress without ending the session.
    func flush() {
        accumulate()
        save()
    }

    /// Saves and closes the current session.
    func finish() {
        flush()
        pending = nil
        saved = nil
        listened = 0
        resumedAt = nil
    }

    private func accumulate() {
        guard let resumedAt else { return }
        let now = Date.now
        listened += max(now.timeIntervalSince(resumedAt), 0)
        self.resumedAt = now
    }

    private func save() {
        guard let pending, ListeningRules.shouldSave(listened: listened) else { return }
        let session: ListenSession
        if let saved {
            session = saved
        } else {
            session = ListenSession(
                start: pending.start, trackID: pending.trackID, title: pending.title,
                artist: pending.artist, album: pending.album, genre: pending.genre
            )
            context.insert(session)
            saved = session
        }
        session.listenedSeconds = (listened * 10).rounded() / 10
        session.counted = ListeningRules.isPlay(listened: listened, duration: pending.duration)
        try? context.save()
    }
}
