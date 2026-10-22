import Accelerate
import AVFoundation
import os

/// Turns post-EQ audio into the 64 spectrum levels that drive `WaveVisualizer`.
///
/// Follows the desktop `visualizer.py` recipe:
/// - 64 log-spaced bins from 50 Hz to 16 kHz, +3 dB/octave tilt around 1 kHz.
/// - dB range −70…−10 mapped to 0…1, then raised to the power 1.4.
/// - Smoothing per 1/60 s step: attack 0.5, decay 0.12.
/// - Auto-gain peak that releases ×0.995 per frame, never below 0.3.
///
/// Audio arrives on the render thread and frames are read on the main thread,
/// so all mutable state is guarded by a lock.
nonisolated final class SpectrumAnalyzer: @unchecked Sendable {
    static let binCount = 64
    static let lowFrequency = 50.0
    static let highFrequency = 16_000.0

    struct Frame: Sendable {
        var levels: [Float]
        /// 0…1 loudness used for line alpha and edge brightening (max level × 1.2).
        var loudness: Float
    }

    private let fftSize = 2048
    private let dft: vDSP.DiscreteFourierTransform<Float>?
    private let window: [Float]

    private struct State {
        var targets = [Float](repeating: 0, count: SpectrumAnalyzer.binCount)
        var current = [Float](repeating: 0, count: SpectrumAnalyzer.binCount)
        var peak: Float = 0.3
        var lastFrameTime: TimeInterval = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    init() {
        dft = try? vDSP.DiscreteFourierTransform(
            count: fftSize, direction: .forward, transformType: .complexComplex, ofType: Float.self
        )
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
    }

    /// Installs a tap on `node` so its output feeds the analyzer.
    ///
    /// The tap block must never call back into the engine or the node (for example
    /// `outputFormat(forBus:)`): those calls take the engine's lock, while `engine.stop()`
    /// and `playerNode.stop()` on the main thread hold that lock and wait for the tap to
    /// finish. That deadlock froze the app on song changes and seeks until the watchdog
    /// killed it. Everything needed, including the sample rate, comes with the buffer.
    func attach(to node: AVAudioNode) {
        try? node.installAudioTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: nil) { [weak self] buffer, _ in
            self?.process(buffer)
        }
    }

    /// Removes the tap (needed before the node is rewired to a new format).
    func detach(from node: AVAudioNode) {
        node.removeTap(onBus: 0)
    }

    /// Lets the levels fall back to flat lines (used on pause and song changes).
    func silence() {
        state.withLock { $0.targets = [Float](repeating: 0, count: Self.binCount) }
    }

    /// Advances smoothing to `time` and returns the levels to draw.
    func frame(at time: TimeInterval) -> Frame {
        state.withLock { state in
            let elapsed = state.lastFrameTime == 0 ? 1.0 / 60 : min(max(time - state.lastFrameTime, 0), 0.25)
            state.lastFrameTime = time
            let steps = Float(elapsed * 60)
            let attack = 1 - pow(1 - 0.5, steps)
            let decay = 1 - pow(1 - 0.12, steps)

            var maxLevel: Float = 0
            for i in 0..<Self.binCount {
                let target = state.targets[i]
                let value = state.current[i]
                state.current[i] = value + (target - value) * (target > value ? attack : decay)
                maxLevel = max(maxLevel, state.current[i])
            }
            state.peak = max(state.peak * pow(0.995, steps), maxLevel, 0.3)
            let peak = state.peak
            let levels = state.current.map { $0 / peak }
            return Frame(levels: levels, loudness: min((levels.max() ?? 0) * 1.2, 1))
        }
    }

    // MARK: Audio thread

    private func process(_ buffer: AVReadOnlyAudioPCMBuffer) {
        let sampleRate = buffer.format.sampleRate
        guard let dft, sampleRate > 0 else { return }

        // Mix the newest samples of each (deinterleaved float) channel down to mono.
        var samples = [Float](repeating: 0, count: fftSize)
        let fftSize = fftSize
        let channelCount = buffer.withUnsafeAudioBufferList { list -> Int in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
            var used = 0
            for audioBuffer in buffers {
                guard let data = audioBuffer.mData else { continue }
                let frames = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
                let count = min(frames, fftSize)
                let pointer = data.assumingMemoryBound(to: Float.self)
                for i in 0..<count { samples[i] += pointer[frames - count + i] }
                used += 1
            }
            return used
        }
        guard channelCount > 0 else { return }
        vDSP.multiply(1 / Float(channelCount), samples, result: &samples)
        vDSP.multiply(samples, window, result: &samples)

        let output = dft.transform(real: samples, imaginary: [Float](repeating: 0, count: fftSize))
        let half = fftSize / 2
        var magnitudes = [Float](repeating: 0, count: half)
        for i in 0..<half {
            magnitudes[i] = (output.real[i] * output.real[i] + output.imaginary[i] * output.imaginary[i]).squareRoot()
        }
        let levels = Self.levels(fromMagnitudes: magnitudes, sampleRate: sampleRate, fftSize: fftSize)
        state.withLock { $0.targets = levels }
    }

    /// Maps FFT magnitudes to the 64 display bins (pure, so it can be unit tested).
    static func levels(fromMagnitudes magnitudes: [Float], sampleRate: Double, fftSize: Int) -> [Float] {
        let half = magnitudes.count
        guard half > 1, sampleRate > 0 else { return [Float](repeating: 0, count: binCount) }
        let binWidth = sampleRate / Double(fftSize)
        // A full-scale sine through a Hann window peaks at about fftSize / 4.
        let reference = Float(fftSize) / 4
        let ratio = highFrequency / lowFrequency

        return (0..<binCount).map { bin in
            let f0 = lowFrequency * pow(ratio, Double(bin) / Double(binCount))
            let f1 = lowFrequency * pow(ratio, Double(bin + 1) / Double(binCount))
            let i0 = min(max(Int(f0 / binWidth), 0), half - 1)
            let i1 = min(max(Int((f1 / binWidth).rounded(.up)), i0 + 1), half)
            var peak: Float = 0
            for i in i0..<i1 { peak = max(peak, magnitudes[i]) }

            var db = 20 * log10(max(peak / reference, 1e-9))
            db += Float(3 * log2((f0 * f1).squareRoot() / 1000))
            let normalized = min(max((db + 70) / 60, 0), 1)
            return pow(normalized, 1.4)
        }
    }
}
