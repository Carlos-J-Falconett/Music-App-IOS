import AVFoundation
import Observation

enum PlayerEngineError: Error, CustomStringConvertible {
    /// The file opened but has no playable audio (zero length, sample rate or channels).
    case unsupportedFormat
    /// The file couldn't be opened.
    case openFailed(String)
    /// Wiring the player into the EQ/mixer for this file's format failed.
    case connectFailed(String)
    /// The audio engine or session wouldn't start.
    case startFailed(String)

    var description: String {
        switch self {
        case .unsupportedFormat: "the file has no playable audio"
        case .openFailed(let detail): "the file couldn't be opened (\(detail))"
        case .connectFailed(let detail): "audio setup for this format failed (\(detail))"
        case .startFailed(let detail): "the audio engine wouldn't start (\(detail))"
        }
    }

    /// "domain code" for an underlying error, e.g. "NSOSStatusErrorDomain 561015905".
    static func detail(_ error: any Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }
}

/// Low-level audio playback: AVAudioEngine → player node → 10-band EQ → mixer.
/// The spectrum tap sits on the EQ output, so the visualizer shows post-EQ audio
/// like the desktop app. Higher-level logic (queue, stats) lives in `MusicPlayer`.
@Observable
final class PlayerEngine {
    /// Center frequencies of the 10 EQ bands (same layout as the desktop equalizer).
    static let bandFrequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let gainRange: ClosedRange<Float> = -12...12

    private(set) var isPlaying = false
    private(set) var duration: Double = 0
    private(set) var eqGains = [Float](repeating: 0, count: 10)
    /// Bumped on every seek and song load. The position itself isn't observable (views
    /// poll it while playing), so views read this to refresh after a jump while paused.
    private(set) var positionChanges = 0
    var volume: Float = 1 {
        didSet { engine.mainMixerNode.outputVolume = volume }
    }

    /// Called on the main actor when the current file plays to its end.
    @ObservationIgnored var onFinished: (() -> Void)?
    /// Called when the system pauses or resumes playback (interruptions, unplugged headphones).
    @ObservationIgnored var onSystemPlaybackChange: ((Bool) -> Void)?
    /// Called when pressing play couldn't start audio.
    @ObservationIgnored var onPlaybackFailure: ((any Error) -> Void)?

    @ObservationIgnored let analyzer = SpectrumAnalyzer()
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let eq = AVAudioUnitEQ(numberOfBands: 10)
    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var connectedFormat: AVAudioFormat?
    /// First frame of the currently scheduled segment (changes on every seek).
    @ObservationIgnored private var segmentStartFrame: AVAudioFramePosition = 0
    /// Position reported while paused or stopped.
    @ObservationIgnored private var pausedTime: Double = 0
    /// Bumped whenever scheduled audio is thrown away, so stale completion callbacks are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var resumeAfterInterruption = false
    /// Whether this app has activated its audio session (reset when the system deactivates it).
    @ObservationIgnored private var sessionActive = false
    @ObservationIgnored private var observerTasks: [Task<Void, Never>] = []

    init() {
        engine.attach(player)
        engine.attach(eq)
        for (band, frequency) in zip(eq.bands, Self.bandFrequencies) {
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = 1
            band.gain = 0
            band.bypass = false
        }
        try? engine.connectNode(eq, to: engine.mainMixerNode, format: nil)
        analyzer.attach(to: eq)

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        observeSystemEvents()
    }

    // MARK: Playback

    /// Opens a file and schedules it from the beginning.
    func load(_ url: URL, autoplay: Bool) throws {
        let newFile: AVAudioFile
        do {
            newFile = try AVAudioFile(forReading: url)
        } catch {
            throw PlayerEngineError.openFailed(PlayerEngineError.detail(error))
        }
        let format = newFile.processingFormat
        // Files with no audio or a broken header would give a zero/NaN duration and crash scheduling.
        guard format.sampleRate > 0, format.channelCount > 0, newFile.length > 0 else {
            throw PlayerEngineError.unsupportedFormat
        }
        generation += 1
        player.stop()
        file = newFile

        if connectedFormat != format {
            try reconnect(for: format)
        }
        duration = Double(newFile.length) / format.sampleRate
        analyzer.silence()
        schedule(from: 0)
        positionChanges &+= 1
        if autoplay {
            try startPlayback()
        } else {
            isPlaying = false
        }
    }

    /// Puts the engine back in a clean state after a failure: stops it, forgets the
    /// wired format (so the next load rewires) and re-activates the audio session next
    /// time. The session can be taken away without us hearing about it (another app,
    /// Siri, a call, switching to or from Bluetooth), which makes the next start fail.
    func recover() {
        generation += 1
        player.stop()
        engine.stop()
        connectedFormat = nil
        sessionActive = false
        isPlaying = false
    }

    /// Rewires player → EQ → mixer for a new file format.
    ///
    /// The EQ can't convert formats, so its input and output both use the file's
    /// format and the main mixer does any sample-rate conversion to the hardware.
    /// Rewiring a running engine between 44.1 kHz and 48 kHz files fails with
    /// error -10868 and leaves the graph broken (every later `player.stop()` then
    /// blocks the main thread for ~5 s), so the engine is stopped while rewiring.
    private func reconnect(for format: AVAudioFormat) throws {
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        analyzer.detach(from: eq)
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(eq)
        defer { analyzer.attach(to: eq) }
        do {
            try engine.connectNode(player, to: eq, format: format)
            try engine.connectNode(eq, to: engine.mainMixerNode, format: format)
        } catch {
            connectedFormat = nil
            throw PlayerEngineError.connectFailed(PlayerEngineError.detail(error))
        }
        connectedFormat = format
        if wasRunning { try startEngine() }
    }

    /// Starts the engine (activating the session if needed). If that fails, the session
    /// was probably deactivated behind our back, so it's re-activated and tried once more.
    private func startEngine() throws {
        guard !engine.isRunning else { return }
        do {
            try activateSession()
            try engine.start()
        } catch {
            sessionActive = false
            do {
                try activateSession()
                try engine.start()
            } catch {
                throw PlayerEngineError.startFailed(PlayerEngineError.detail(error))
            }
        }
    }

    /// Activating the session can block for a moment, so it's only done when needed
    /// rather than on every song change.
    private func activateSession() throws {
        guard !sessionActive else { return }
        try AVAudioSession.sharedInstance().setActive(true)
        sessionActive = true
    }

    private func startPlayback() throws {
        guard file != nil else { return }
        try startEngine()
        do {
            try player.playAudio()
        } catch {
            throw PlayerEngineError.startFailed(PlayerEngineError.detail(error))
        }
        isPlaying = true
    }

    /// Resumes or starts playback (play button, lock screen). Failures are reported
    /// through `onPlaybackFailure` instead of silently leaving the player paused.
    func play() {
        do {
            try startPlayback()
        } catch {
            onPlaybackFailure?(error)
        }
    }

    func pause() {
        guard isPlaying else { return }
        pausedTime = currentTime
        player.pause()
        engine.pause()
        isPlaying = false
        analyzer.silence()
    }

    func stop() {
        generation += 1
        player.stop()
        file = nil
        isPlaying = false
        duration = 0
        pausedTime = 0
        analyzer.silence()
    }

    /// Jumps to `time` seconds, keeping the play/pause state.
    func seek(to time: Double) {
        guard file != nil else { return }
        let wasPlaying = isPlaying
        generation += 1
        player.stop()
        schedule(from: time)
        positionChanges &+= 1
        guard wasPlaying else { return }
        do {
            try player.playAudio()
        } catch {
            // Show paused instead of "playing" in silence; pressing play runs the recovery path.
            isPlaying = false
            onSystemPlaybackChange?(false)
        }
    }

    /// Current position in seconds. Not observed — views poll it with `TimelineView`.
    var currentTime: Double {
        guard isPlaying, let file,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return pausedTime }
        let start = Double(segmentStartFrame) / file.processingFormat.sampleRate
        let time = start + Double(playerTime.sampleTime) / playerTime.sampleRate
        return min(max(time, 0), duration)
    }

    private func schedule(from time: Double) {
        guard let file else { return }
        let sampleRate = file.processingFormat.sampleRate
        let clamped = min(max(time, 0), duration)
        let start = AVAudioFramePosition(clamped * sampleRate)
        segmentStartFrame = start
        pausedTime = clamped
        let remaining = file.length - start
        guard remaining > 0 else { return }

        let token = generation
        player.scheduleSegment(
            file, startingFrame: start, frameCount: AVAudioFrameCount(clamping: remaining), at: nil,
            completionCallbackType: .dataPlayedBack
        ) { @Sendable [weak self] _ in
            // Copy the weak reference into a constant before hopping to the main actor.
            let engine = self
            Task { @MainActor in engine?.segmentFinished(token) }
        }
    }

    private func segmentFinished(_ token: Int) {
        guard token == generation, isPlaying else { return }
        pausedTime = duration
        isPlaying = false
        onFinished?()
    }

    // MARK: Equalizer

    func setGain(_ gain: Float, band: Int) {
        guard eq.bands.indices.contains(band) else { return }
        let clamped = min(max(gain, Self.gainRange.lowerBound), Self.gainRange.upperBound)
        eq.bands[band].gain = clamped
        eqGains[band] = clamped
    }

    func setGains(_ gains: [Float]) {
        for (band, gain) in gains.prefix(eq.bands.count).enumerated() { setGain(gain, band: band) }
    }

    // MARK: System events

    private func observeSystemEvents() {
        let center = NotificationCenter.default

        // Interruptions (calls, alarms, other audio apps): the system deactivates the session…
        observerTasks.append(Task { [weak self] in
            for await note in center.notifications(named: AVAudioSession.didBecomeInactiveNotification) {
                guard let self,
                      let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext,
                      context.source == .system else { continue }
                sessionActive = false
                resumeAfterInterruption = isPlaying
                pause()
                onSystemPlaybackChange?(false)
            }
        })

        // …and later tells us whether it's appropriate to resume.
        observerTasks.append(Task { [weak self] in
            for await note in center.notifications(named: AVAudioSession.resumptionRecommendationNotification) {
                guard let self,
                      let context = note.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext else { continue }
                if resumeAfterInterruption, context.recommendation == .shouldResume {
                    play()
                    onSystemPlaybackChange?(true)
                }
                resumeAfterInterruption = false
            }
        })

        observerTasks.append(Task { [weak self] in
            for await note in center.notifications(named: AVAudioSession.routeChangeNotification) {
                guard let self,
                      let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { continue }
                // Headphones unplugged: pause like every other music app.
                pause()
                onSystemPlaybackChange?(false)
            }
        })

        observerTasks.append(Task { [weak self] in
            for await _ in center.notifications(named: .AVAudioEngineConfigurationChange) {
                guard let self, isPlaying else { continue }
                // The engine stops itself when the hardware changes (e.g. AirPods connect);
                // restart it. If that fails, pause visibly instead of "playing" in silence.
                do {
                    try startEngine()
                    try player.playAudio()
                } catch {
                    pausedTime = currentTime
                    isPlaying = false
                    onSystemPlaybackChange?(false)
                    onPlaybackFailure?(error)
                }
            }
        })
    }
}
