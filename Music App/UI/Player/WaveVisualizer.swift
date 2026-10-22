import SwiftUI

/// The desktop app's audio "ribbon": one ribbon with two edges, drawn from the
/// live spectrum (`SpectrumAnalyzer`), bass on the left.
///
/// Shape (from `visualizer.py`):
/// - n lobes = width / 11, clamped to 24…64, alternating up and down, with amplitude
///   scaled by sin(πu)^0.6 so they ease into flat tails on the outer 12% of each side.
/// - The bottom edge is shifted 0.35 of a lobe to the right at 0.85× amplitude and
///   drops a little with loudness, so the ribbon twists and crosses.
/// - Catmull-Rom curves; 18 thin inner lines blend top → bottom color.
/// - Each edge has a soft 4 pt glow and a 1.4 pt core that brightens with loudness.
/// When nothing plays the levels ease to zero and it settles into two flat lines.
struct WaveVisualizer: View {
    @Environment(MusicPlayer.self) private var player
    @Environment(ThemeStore.self) private var theme
    /// True once playback has been paused long enough for the lines to settle flat.
    @State private var isIdle = false

    var body: some View {
        let analyzer = player.engine.analyzer
        let colors = theme.colors
        // Capped at 60 fps (the smoothing is designed in 1/60 s steps; ProMotion would
        // otherwise redraw at 120) and stopped entirely while idle to save battery.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: isIdle)) { timeline in
            let frame = analyzer.frame(at: timeline.date.timeIntervalSinceReferenceDate)
            Canvas { context, size in
                Self.draw(frame: frame, colors: colors, in: &context, size: size)
            }
        }
        .task(id: player.isPlaying) {
            guard !player.isPlaying else {
                isIdle = false
                return
            }
            // Let the levels decay to flat lines (0.88^90 ≈ 0) before stopping the redraws.
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { isIdle = true }
        }
        .accessibilityHidden(true)
    }

    // MARK: Drawing

    private static func draw(frame: SpectrumAnalyzer.Frame, colors: ResolvedColors, in context: inout GraphicsContext, size: CGSize) {
        let width = size.width, height = size.height
        guard width > 0, height > 0 else { return }

        let lobeCount = min(max(Int(width / 11), 24), 64)
        let tail = width * 0.12
        let usable = width - tail * 2
        let mid = height / 2
        let gap = max(height * 0.06, 4)
        let maxAmplitude = max(height / 2 - gap / 2 - 3, 0)
        let loud = CGFloat(frame.loudness)

        /// Level for a lobe, averaged from the 64 spectrum bins it covers.
        func level(atLobe position: Double) -> CGFloat {
            let bins = frame.levels
            guard !bins.isEmpty else { return 0 }
            let index = min(max(Int(position / Double(lobeCount) * Double(bins.count)), 0), bins.count - 1)
            return CGFloat(bins[index])
        }

        func edge(shift: Double, scale: CGFloat, baseline: CGFloat) -> [CGPoint] {
            var points = [CGPoint(x: 0, y: baseline), CGPoint(x: tail, y: baseline)]
            for lobe in 0..<lobeCount {
                let position = Double(lobe) + 0.5 + shift
                let u = position / Double(lobeCount)
                guard u > 0, u < 1 else { continue }
                let envelope = CGFloat(pow(sin(Double.pi * u), 0.6))
                let direction: CGFloat = lobe.isMultiple(of: 2) ? -1 : 1
                let amplitude = maxAmplitude * level(atLobe: position) * envelope * scale
                points.append(CGPoint(x: tail + CGFloat(u) * usable, y: baseline + direction * amplitude))
            }
            points.append(CGPoint(x: width - tail, y: baseline))
            points.append(CGPoint(x: width, y: baseline))
            return points
        }

        let top = edge(shift: 0, scale: 1, baseline: mid - gap / 2)
        let bottom = edge(shift: 0.35, scale: 0.85, baseline: mid + gap / 2 + height * 0.3 * loud * 0.25)

        let topColor = colors.waveTop
        let bottomColor = colors.waveBottom

        // Inner ribbon lines, blended between the two edges.
        if top.count == bottom.count, loud > 0.01 {
            let lineCount = 18
            for line in 1...lineCount {
                let t = CGFloat(line) / CGFloat(lineCount + 1)
                let points = zip(top, bottom).map { a, b in
                    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                }
                let color = topColor.mixed(with: bottomColor, amount: Double(t)).color
                context.stroke(smoothPath(points), with: .color(color.opacity(0.8 * loud)), lineWidth: 0.7)
            }
        }

        // Edges: glow then core, brightening toward the light edge color as it gets louder.
        for (points, base, bright) in [(top, topColor, colors.waveTopBright), (bottom, bottomColor, colors.waveBottomBright)] {
            let path = smoothPath(points)
            let core = base.mixed(with: bright, amount: Double(loud)).color
            context.stroke(path, with: .color(core.opacity(0.25 * loud)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            context.stroke(path, with: .color(core.opacity(0.95)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }

    /// Catmull-Rom spline through `points`, converted to cubic Béziers.
    private static func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}
