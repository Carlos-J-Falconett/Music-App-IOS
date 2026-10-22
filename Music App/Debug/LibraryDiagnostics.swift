#if DEBUG
import AVFoundation
import SwiftData
import UIKit
import os

/// Debug-only test that runs against the real library on the device.
/// 1. Opens every audio file off the main thread and reports formats and failures.
/// 2. Plays every song through the real player (muted), the same path as tapping a
///    song: checks that audio starts, seeks to the middle, then jumps to the last half
///    second and checks that the song plays to its end, which is where damaged files
///    usually fail. Player calls are timed on the main thread (a call that blocks for
///    seconds gets the app killed), and the app's memory use is logged after every
///    song so leaks show up as a steadily climbing number.
///
/// Before each song starts, its position is saved to a checkpoint file. If the app
/// crashes, launching it again marks that song as a crash suspect and continues
/// with the next one, so a single run gets through the whole library. Each song
/// plays for well under 5 s, so no listening sessions are saved.
/// Everything is printed with a `[Diag]` prefix so it is easy to grep.
///
/// Turned on by launching with the environment variable `SUN_DIAGNOSTICS=1`
/// (Product → Scheme → Edit Scheme → Run → Arguments).
enum LibraryDiagnostics {
    static var runOnLaunch: Bool { ProcessInfo.processInfo.environment["SUN_DIAGNOSTICS"] == "1" }

    /// A main-thread player call slower than this is reported (the watchdog kills at a few seconds).
    static let slowCallMs = 250.0

    /// Progress saved before each song so a crash can be traced back to it.
    nonisolated struct Checkpoint: Codable {
        var cursor = 0
        var suspects: [String] = []
        var problems: [String] = []
        var peakMemoryMB = 0
    }

    private static var checkpointURL: URL {
        URL.cachesDirectory.appending(path: "diag-sweep-v2.json")
    }

    static func run(player: MusicPlayer, context: ModelContext) async {
        // Same order on every launch so the checkpoint cursor points at the same song.
        let tracks = ((try? context.fetch(FetchDescriptor<Track>())) ?? []).sorted { $0.relativePath < $1.relativePath }
        print("[Diag] Library: \(tracks.count) tracks, memory \(Memory.report)")
        guard !tracks.isEmpty else { return }

        let previous = loadCheckpoint()
        if previous == nil {
            // 1. Fresh run: probe every file off the main thread first.
            let report = await probe(tracks.map { (title: $0.title, url: $0.fileURL) })
            print("[Diag] Formats: \(report.formats.sorted { $0.value > $1.value }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
            print("[Diag] Unopenable files: \(report.failures.count)")
            for failure in report.failures { print("[Diag]   ✗ \(failure)") }
            print("[Diag] Slowest opens: \(report.slowest.map { "\($0.title) \(Int($0.ms))ms" }.joined(separator: " | "))")
        }
        var state = previous ?? Checkpoint()
        if previous != nil {
            // The app died during this song: remember it and carry on after it.
            if tracks.indices.contains(state.cursor) {
                let track = tracks[state.cursor]
                print("[Diag] Previous run ended while playing \(state.cursor + 1) (peak memory \(state.peakMemoryMB) MB): \(track.title) — \(track.relativePath)")
                state.suspects.append("\(track.title) — \(track.relativePath)")
            }
            state.cursor += 1
        }

        // 2. Play every song.
        let savedVolume = player.engine.volume
        let savedRepeat = player.queue.repeatMode
        player.engine.volume = 0
        player.queue.repeatMode = .off
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            player.pause()
            player.engine.volume = savedVolume
            player.queue.repeatMode = savedRepeat
            UIApplication.shared.isIdleTimerDisabled = false
        }

        let clock = ContinuousClock()
        let sweepStart = clock.now
        while state.cursor < tracks.count {
            let index = state.cursor
            let track = tracks[index]
            state.peakMemoryMB = max(state.peakMemoryMB, Memory.footprintMB)
            saveCheckpoint(state)
            print("[Diag] ▶︎ \(index + 1)/\(tracks.count) [\(Memory.report)] \(track.title) — \(track.relativePath)")
            for problem in await check(track, player: player) {
                print("[Diag]   ✗ \(problem)")
                state.problems.append("\(track.title) — \(track.relativePath): \(problem)")
            }
            state.cursor += 1
        }
        try? FileManager.default.removeItem(at: checkpointURL)

        print("[Diag] Sweep took \(Int((clock.now - sweepStart).milliseconds / 1000))s, peak memory \(state.peakMemoryMB) MB, now \(Memory.report)")
        print("[Diag] Crash suspects (app ended while playing): \(state.suspects.count)")
        for suspect in state.suspects { print("[Diag]   ☠︎ \(suspect)") }
        print("[Diag] Songs with problems: \(state.problems.count)")
        for problem in state.problems { print("[Diag]   ✗ \(problem)") }
        print("[Diag] Done")
    }

    /// Plays one song's start, middle and end. Returns what went wrong (empty when it played fine).
    private static func check(_ track: Track, player: MusicPlayer) async -> [String] {
        var problems: [String] = []
        let clock = ContinuousClock()
        let lastIssue = player.issues.issues.first?.id

        let loadTime = clock.measure { player.play([track]) }
        if loadTime.milliseconds > slowCallMs { problems.append("slow start \(Int(loadTime.milliseconds))ms") }
        player.errorMessage = nil
        if let issue = player.issues.issues.first, issue.id != lastIssue {
            problems.append(issue.recovered ? "failed once, retry worked: \(issue.reason)" : "won't play: \(issue.reason)")
        }
        guard player.currentTrack?.id == track.id else {
            if problems.isEmpty { problems.append("didn't load") }
            return problems
        }

        try? await Task.sleep(for: .milliseconds(300))
        let engine = player.engine
        guard engine.isPlaying, engine.currentTime > 0.05 else {
            problems.append("no audio at the start (playing: \(engine.isPlaying), time: \(engine.currentTime))")
            return problems
        }
        if abs(engine.duration - track.duration) > 2 {
            problems.append("length mismatch: file \(Int(engine.duration))s, tags \(Int(track.duration))s")
        }

        let middle = engine.duration / 2
        let seekTime = clock.measure { player.seek(to: middle) }
        if seekTime.milliseconds > slowCallMs { problems.append("slow seek \(Int(seekTime.milliseconds))ms") }
        try? await Task.sleep(for: .milliseconds(200))
        if engine.isPlaying, engine.currentTime < middle {
            problems.append("audio stalled after seeking to the middle")
        }

        // Jump to the end and wait for the song to finish on its own.
        player.seek(to: max(engine.duration - 0.5, 0))
        var waited = 0
        while engine.isPlaying, waited < 30 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        if engine.isPlaying {
            problems.append("didn't reach the end (stuck at \(String(format: "%.1f", engine.currentTime)) of \(String(format: "%.1f", engine.duration))s)")
        }
        return problems
    }

    private static func loadCheckpoint() -> Checkpoint? {
        guard let data = try? Data(contentsOf: checkpointURL) else { return nil }
        return try? JSONDecoder().decode(Checkpoint.self, from: data)
    }

    private static func saveCheckpoint(_ checkpoint: Checkpoint) {
        // Written atomically so a crash right after can't leave half a file.
        try? JSONEncoder().encode(checkpoint).write(to: checkpointURL, options: .atomic)
    }

    nonisolated struct ProbeReport: Sendable {
        var formats: [String: Int] = [:]
        var failures: [String] = []
        var slowest: [(title: String, ms: Double)] = []
    }

    @concurrent
    private static func probe(_ files: [(title: String, url: URL)]) async -> ProbeReport {
        var report = ProbeReport()
        let clock = ContinuousClock()
        var timings: [(title: String, ms: Double)] = []
        for file in files {
            var opened: AVAudioFile?
            let time = clock.measure { opened = try? AVAudioFile(forReading: file.url) }
            guard let opened else {
                report.failures.append("\(file.title) — \(file.url.lastPathComponent)")
                continue
            }
            let format = opened.processingFormat
            let key = "\(Int(format.sampleRate))Hz/\(format.channelCount)ch"
            report.formats[key, default: 0] += 1
            if format.sampleRate <= 0 || opened.length <= 0 {
                report.failures.append("\(file.title) — empty or invalid format \(key), length \(opened.length)")
            }
            timings.append((file.title, time.milliseconds))
        }
        report.slowest = Array(timings.sorted { $0.ms > $1.ms }.prefix(5))
        return report
    }
}

/// The app's memory use as iOS counts it when deciding whether to kill the app.
nonisolated enum Memory {
    /// Physical footprint in MB (the number shown in Xcode's memory gauge).
    static var footprintMB: Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }

    /// How much more the app can use before iOS kills it, in MB.
    static var headroomMB: Int { Int(os_proc_available_memory() / 1_048_576) }

    static var report: String { "\(footprintMB) MB used, \(headroomMB) MB left" }
}

nonisolated private extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
#endif
