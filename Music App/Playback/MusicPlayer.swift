import Foundation
import Observation
import SwiftData

/// The app-wide player that views talk to. It ties together the audio engine,
/// the queue, listening stats, the equalizer settings and the lock screen.
@Observable
final class MusicPlayer {
    let engine = PlayerEngine()
    let queue = QueueManager()
    private(set) var currentTrack: Track?
    /// Shown briefly when a file can't be played.
    var errorMessage: String?
    /// Songs that couldn't be played and why (Settings → Playback Problems).
    @ObservationIgnored let issues = PlaybackIssueLog()

    /// EQ used for songs without their own saved settings.
    private(set) var globalEQ: [Float]

    @ObservationIgnored let stats: StatsRecorder
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let nowPlaying = NowPlayingBridge()
    private static let globalEQKey = "globalEQGains"

    init(context: ModelContext) {
        self.context = context
        stats = StatsRecorder(context: context)
        globalEQ = (UserDefaults.standard.array(forKey: Self.globalEQKey) as? [Float]) ?? [Float](repeating: 0, count: 10)
        engine.setGains(globalEQ)

        engine.onFinished = { [weak self] in self?.trackFinished() }
        engine.onSystemPlaybackChange = { [weak self] playing in
            self?.stats.setPlaying(playing)
            self?.publishNowPlaying()
        }
        engine.onPlaybackFailure = { [weak self] error in self?.playFailed(error) }
        nowPlaying.configure(.init(
            play: { [weak self] in self?.resume() },
            pause: { [weak self] in self?.pause() },
            togglePlayPause: { [weak self] in self?.togglePlayPause() },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() },
            seek: { [weak self] time in self?.seek(to: time) }
        ))
    }

    var isPlaying: Bool { engine.isPlaying }

    // MARK: Starting playback

    /// Replaces the queue with `tracks` and starts at `index`.
    func play(_ tracks: [Track], startAt index: Int = 0, shuffle: Bool = false) {
        guard !tracks.isEmpty else { return }
        queue.setQueue(tracks.map(\.id), startAt: index, shuffle: shuffle)
        start(queue.current, autoplay: true)
    }

    func shuffleAll(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        play(tracks, startAt: Int.random(in: tracks.indices), shuffle: true)
    }

    func playNext(_ track: Track) {
        let wasEmpty = queue.isEmpty
        queue.playNext(track.id)
        if wasEmpty { start(queue.current, autoplay: true) }
    }

    func addToQueue(_ tracks: [Track]) {
        let wasEmpty = queue.isEmpty
        queue.append(tracks.map(\.id))
        if wasEmpty { start(queue.current, autoplay: true) }
    }

    func jump(to entry: QueueEntry) {
        start(queue.jump(to: entry.id), autoplay: true)
    }

    // MARK: Transport

    func togglePlayPause() {
        if engine.isPlaying { pause() } else { resume() }
    }

    func resume() {
        guard currentTrack != nil else { return }
        // A finished song restarts from the top when play is pressed again.
        if engine.currentTime >= engine.duration - 0.25 { engine.seek(to: 0) }
        engine.play()
        // If starting failed and the retry did too, the engine stays paused.
        stats.setPlaying(engine.isPlaying)
        publishNowPlaying()
    }

    func pause() {
        engine.pause()
        stats.setPlaying(false)
        publishNowPlaying()
    }

    func next() {
        start(queue.advance(automatic: false), autoplay: true, stopIfMissing: false)
    }

    /// Restarts the song if more than 3 s in, otherwise goes to the previous one.
    func previous() {
        if engine.currentTime > 3 || queue.index == 0 && queue.repeatMode != .all {
            seek(to: 0)
        } else {
            start(queue.goBack(), autoplay: true)
        }
    }

    func seek(to time: Double) {
        engine.seek(to: time)
        publishNowPlaying()
    }

    func toggleShuffle() { queue.toggleShuffle() }

    func cycleRepeat() { queue.repeatMode = queue.repeatMode.next }

    func toggleFavorite(_ track: Track) {
        track.isFavorite.toggle()
        try? context.save()
    }

    /// Call when the app moves to the background so stats are written.
    func saveState() { stats.flush() }

    /// Removes a deleted song from the queue and stops it if it was playing.
    func forget(_ track: Track) {
        if currentTrack?.id == track.id {
            stats.finish()
            engine.stop()
            currentTrack = nil
        }
        queue.remove(trackID: track.id)
        publishNowPlaying()
    }

    // MARK: Equalizer

    /// True when the current song has its own saved EQ.
    var currentSongHasEQ: Bool { currentTrack?.eqGains != nil }

    func setEQGain(_ gain: Float, band: Int) {
        engine.setGain(gain, band: band)
        storeEQ(engine.eqGains)
    }

    func applyEQPreset(_ gains: [Float]) {
        engine.setGains(gains)
        storeEQ(engine.eqGains)
    }

    /// Turns per-song EQ on (copying the current curve) or off (back to the global EQ).
    func setSongEQ(enabled: Bool) {
        guard let currentTrack else { return }
        if enabled {
            currentTrack.eqGains = engine.eqGains
        } else {
            currentTrack.eqGains = nil
            engine.setGains(globalEQ)
        }
        try? context.save()
    }

    private func storeEQ(_ gains: [Float]) {
        if let currentTrack, currentTrack.eqGains != nil {
            currentTrack.eqGains = gains
            try? context.save()
        } else {
            globalEQ = gains
            UserDefaults.standard.set(gains, forKey: Self.globalEQKey)
        }
    }

    // MARK: Internals

    private func trackFinished() {
        stats.finish()
        if let entry = queue.advance(automatic: true) {
            start(entry, autoplay: true)
        } else {
            // End of the queue: stay on the last song, paused at its end.
            publishNowPlaying()
        }
    }

    /// Loads `entry`'s song. Songs that were deleted or fail to open are skipped.
    ///
    /// This is a bounded loop (not recursion) so a queue full of unplayable files
    /// can't overflow the stack or cycle forever with Repeat on, and the user sees
    /// one summary message instead of an alert per file.
    private func start(_ entry: QueueEntry?, autoplay: Bool, stopIfMissing: Bool = true) {
        var next = entry
        var skipped: [String] = []
        var tried: Set<QueueEntry.ID> = []
        defer { reportSkipped(skipped) }

        for _ in 0...queue.order.count {
            guard let entry = next else {
                if stopIfMissing, queue.isEmpty {
                    stopPlayback()
                }
                return
            }
            guard let track = track(for: entry.trackID) else {
                queue.remove(trackID: entry.trackID)
                next = queue.current
                continue
            }

            stats.finish()
            do {
                try loadWithRetry(track, autoplay: autoplay)
            } catch {
                skipped.append(track.title)
                tried.insert(entry.id)
                // With Repeat on, advancing eventually wraps back to a song already tried.
                guard let following = queue.advance(automatic: false), !tried.contains(following.id) else {
                    // Nothing playable is left: don't keep showing a song that isn't loaded.
                    if currentTrack?.id == track.id || skipped.count > 1 { stopPlayback() }
                    return
                }
                next = following
                continue
            }
            engine.setGains(track.eqGains ?? globalEQ)
            currentTrack = track
            stats.begin(track, playing: autoplay)
            publishNowPlaying()
            return
        }
        // Every entry was tried once and none could be played.
        stopPlayback()
    }

    private func stopPlayback() {
        stats.finish()
        engine.stop()
        currentTrack = nil
        publishNowPlaying()
    }

    /// Loads a song; if that fails, resets the audio engine and tries once more before
    /// giving up. Most failures on a healthy file come from the audio session being taken
    /// away (a call, Siri, another app, Bluetooth switching), which the reset fixes.
    /// Every failure is written to the Playback Problems log, including ones the retry fixed.
    private func loadWithRetry(_ track: Track, autoplay: Bool) throws {
        do {
            try engine.load(track.fileURL, autoplay: autoplay)
        } catch let firstError {
            engine.recover()
            do {
                try engine.load(track.fileURL, autoplay: autoplay)
                logIssue(track, error: firstError, recovered: true)
            } catch {
                logIssue(track, error: error, recovered: false)
                throw error
            }
        }
    }

    private func logIssue(_ track: Track, error: any Error, recovered: Bool) {
        issues.record(PlaybackIssue(
            date: .now, title: track.title, artist: track.artist, path: track.relativePath,
            reason: (error as? PlayerEngineError)?.description ?? PlayerEngineError.detail(error),
            inBackground: PlaybackIssueLog.appIsInBackground, recovered: recovered
        ))
    }

    /// Pressing play (or the system resuming) couldn't start audio: reset and try once more.
    private func playFailed(_ error: any Error) {
        guard let currentTrack else { return }
        let resumeAt = engine.currentTime
        engine.recover()
        do {
            try engine.load(currentTrack.fileURL, autoplay: true)
            if resumeAt > 1 { engine.seek(to: resumeAt) }
            engine.setGains(currentTrack.eqGains ?? globalEQ)
            stats.setPlaying(true)
            logIssue(currentTrack, error: error, recovered: true)
        } catch {
            logIssue(currentTrack, error: error, recovered: false)
            errorMessage = "Couldn't start “\(currentTrack.title)”: \((error as? PlayerEngineError)?.description ?? "audio error"). Details are in Settings → Playback Problems."
        }
        publishNowPlaying()
    }

    private func reportSkipped(_ titles: [String]) {
        guard let first = titles.first else { return }
        let reason = issues.issues.first.map { " (\($0.reason))" } ?? ""
        errorMessage = titles.count == 1
            ? "Couldn't play “\(first)”\(reason), so it was skipped. Details are in Settings → Playback Problems."
            : "Skipped \(titles.count) songs that couldn't be played: \(titles.prefix(3).joined(separator: ", "))\(titles.count > 3 ? "…" : ""). Details are in Settings → Playback Problems."
    }

    private func track(for id: UUID) -> Track? {
        var descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func publishNowPlaying() {
        nowPlaying.update(
            track: currentTrack, elapsed: engine.currentTime,
            duration: engine.duration, isPlaying: engine.isPlaying
        )
    }
}
