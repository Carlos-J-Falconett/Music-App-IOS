import SwiftUI

/// The glowing slider used for the timeline: a capsule track with a
/// two-color fill (the glow colors) that thickens and glows while dragging, with a
/// white knob that only shows then.
struct ThinSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    var onChanged: (Double) -> Void = { _ in }
    let onCommit: (Double) -> Void

    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = CGFloat(fraction(of: dragValue ?? value))
            let dragging = dragValue != nil
            let fill = LinearGradient(colors: [theme.glowPrimary, theme.glowSecondary], startPoint: .leading, endPoint: .trailing)
            ZStack(alignment: .leading) {
                Capsule().fill(theme.text.opacity(0.14))
                Capsule()
                    .fill(fill)
                    .frame(width: max(width * fraction, 0))
                    .shadow(color: reduceTransparency ? .clear : theme.glowPrimary.opacity(dragging ? 0.8 : 0.45), radius: dragging ? 10 : 5)
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(x: width * fraction - 9)
                    .opacity(dragging ? 1 : 0)
            }
            .frame(height: dragging ? 12 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = value(at: gesture.location.x, width: width)
                        dragValue = newValue
                        onChanged(newValue)
                    }
                    .onEnded { _ in
                        if let dragValue { onCommit(dragValue) }
                        dragValue = nil
                    }
            )
        }
        .frame(height: 28)
        .animation(.smooth(duration: 0.25), value: dragValue != nil)
        .accessibilityRepresentation {
            Slider(value: Binding(get: { value }, set: { onCommit($0) }), in: range)
        }
    }

    private func fraction(of value: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func value(at x: CGFloat, width: CGFloat) -> Double {
        let fraction = width > 0 ? min(max(Double(x / width), 0), 1) : 0
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
}

/// Playback position slider with elapsed and remaining time.
struct ScrubberView: View {
    @Environment(MusicPlayer.self) private var player
    @Environment(ThemeStore.self) private var theme
    @State private var dragTime: Double?

    var body: some View {
        // Position isn't observable, so redraw a few times a second (not while paused).
        TimelineView(.animation(minimumInterval: 0.25, paused: !player.isPlaying && dragTime == nil)) { _ in
            // Also redraws after a seek while paused (e.g. tapping a lyric line).
            let _ = player.engine.positionChanges
            let duration = player.engine.duration
            let time = dragTime ?? player.engine.currentTime
            VStack(spacing: 2) {
                ThinSlider(
                    value: time, range: 0...max(duration, 0.1),
                    onChanged: { dragTime = $0 },
                    onCommit: { newTime in
                        player.seek(to: newTime)
                        dragTime = nil
                    }
                )
                HStack {
                    Text(formatTime(time))
                    Spacer()
                    Text("-" + formatTime(max(duration - time, 0)))
                }
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(theme.secondaryText)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback position")
    }
}

/// Shuffle · Previous · Play/Pause · Next · Repeat. Play is a large glowing glass
/// circle tinted with the ambient accent; shuffle and repeat are small glass circles
/// that take the accent when on.
struct TransportControls: View {
    @Environment(MusicPlayer.self) private var player
    @Environment(ThemeStore.self) private var theme
    @ScaledMetric(relativeTo: .title) private var playSize: CGFloat = 78

    var body: some View {
        HStack {
            toggle("Shuffle", systemImage: "shuffle", isOn: player.queue.isShuffled, action: player.toggleShuffle)
            Spacer()
            skipButton("Previous", systemImage: "backward.fill", action: player.previous)
            Spacer()
            Button(action: player.togglePlayPause) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: playSize - 24, height: playSize - 24)
            }
            .buttonStyle(.glass(.regular.tint(theme.ambientAccent)))
            .buttonBorderShape(.circle)
            .foregroundStyle(theme.ambientAccentText)
            .frame(width: playSize, height: playSize)
            // Glows brighter while playing.
            .ambientGlow(radius: 18, strength: player.isPlaying ? 0.6 : 0.3)
            .animation(Motion.standard, value: player.isPlaying)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            skipButton("Next", systemImage: "forward.fill", action: player.next)
            Spacer()
            toggle(repeatLabel, systemImage: player.queue.repeatMode.symbolName,
                   isOn: player.queue.repeatMode != .off, action: player.cycleRepeat)
        }
        .foregroundStyle(theme.color(.transportIcons))
        .legibleOnGlass()
    }

    private var repeatLabel: String {
        switch player.queue.repeatMode {
        case .off: "Repeat Off"
        case .all: "Repeat Queue"
        case .one: "Repeat Song"
        }
    }

    /// Previous / Next: large icons with a 56 pt tap area.
    private func skipButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .frame(width: 56, height: 56)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    /// Shuffle / repeat: a small glass circle, tinted with the accent when on.
    private func toggle(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.glass(isOn ? .regular.tint(theme.ambientAccent) : .regular.tint(theme.glassTint)))
        .buttonBorderShape(.circle)
        .foregroundStyle(isOn ? theme.ambientAccentText : theme.secondaryText)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A round glass button with an icon (Now Playing's top bar and song actions).
struct GlassCircleButton: View {
    let title: String
    let systemImage: String
    var foreground: Color?
    let action: () -> Void

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.glass(.regular.tint(theme.glassTint)))
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .foregroundStyle(foreground ?? theme.text)
        .accessibilityLabel(title)
    }
}

/// The pages of Now Playing's swipeable area.
enum NowPlayingPage: Int, CaseIterable, Identifiable, Hashable {
    case cover, lyrics, queue, equalizer

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .cover: "Cover"
        case .lyrics: "Lyrics"
        case .queue: "Queue"
        case .equalizer: "Equalizer"
        }
    }

    var systemImage: String {
        switch self {
        case .cover: "photo"
        case .lyrics: "quote.bubble"
        case .queue: "list.bullet"
        case .equalizer: "slider.vertical.3"
        }
    }
}

extension View {
    /// Background for the queue and equalizer pages: Liquid Glass with the theme's
    /// panel tint, a little stronger than list rows so text reads over any backdrop.
    func nowPlayingPanel() -> some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
        return self
            .glassCard(cornerRadius: Layout.cardCornerRadius, emphasis: 1.4, glow: false)
            .clipShape(shape)
    }
}
