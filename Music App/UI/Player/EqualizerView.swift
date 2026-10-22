import SwiftUI

/// Built-in EQ curves (dB for the 10 bands, 31 Hz → 16 kHz).
struct EQPreset: Identifiable {
    var id: String { name }
    let name: String
    let gains: [Float]

    static let all: [EQPreset] = [
        EQPreset(name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Bass Boost", gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
        EQPreset(name: "Treble Boost", gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
        EQPreset(name: "Vocal", gains: [-2, -2, -1, 1, 3, 4, 3, 1, 0, -1]),
        EQPreset(name: "Rock", gains: [4, 3, 2, 0, -1, -1, 1, 2, 3, 4]),
        EQPreset(name: "Pop", gains: [-1, 1, 2, 3, 2, 0, -1, -1, 1, 2]),
        EQPreset(name: "Electronic", gains: [5, 4, 1, 0, -2, 1, 0, 2, 4, 5]),
        EQPreset(name: "Acoustic", gains: [3, 3, 2, 1, 1, 1, 2, 3, 2, 1]),
        EQPreset(name: "Classical", gains: [4, 3, 2, 1, -1, -1, 0, 2, 3, 4]),
    ]
}

/// 10-band equalizer with presets and an optional per-song curve.
struct EqualizerView: View {
    @Environment(MusicPlayer.self) private var player
    @Environment(ThemeStore.self) private var theme

    private static let labels = ["31", "62", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Equalizer")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.text)
                Spacer()
                Menu("Presets") {
                    ForEach(EQPreset.all) { preset in
                        Button(preset.name) { player.applyEQPreset(preset.gains) }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .tint(theme.ambientAccentLight)
            }

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<10, id: \.self) { band in
                    let gain = player.engine.eqGains[band]
                    VStack(spacing: 6) {
                        Text(gain == 0 ? "0" : String(format: "%+.0f", gain))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(theme.secondaryText)
                        VerticalGainSlider(gain: gain) { player.setEQGain($0, band: band) }
                            .accessibilityLabel("\(Self.labels[band]) hertz")
                        Text(Self.labels[band])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)

            Toggle("Save for this song", isOn: Binding(
                get: { player.currentSongHasEQ },
                set: { player.setSongEQ(enabled: $0) }
            ))
            .font(.subheadline)
            .foregroundStyle(theme.text)
            .tint(theme.ambientAccent)
            .disabled(player.currentTrack == nil)
        }
    }
}

/// A vertical gain slider for one EQ band. The fill grows from the 0 dB center line.
struct VerticalGainSlider: View {
    let gain: Float
    let onChange: (Float) -> Void

    @Environment(ThemeStore.self) private var theme
    private let range = PlayerEngine.gainRange

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let span = CGFloat(range.upperBound - range.lowerBound)
            let y = height * (1 - CGFloat(gain - range.lowerBound) / span)
            let centerY = height / 2
            ZStack(alignment: .top) {
                Capsule()
                    .fill(theme.text.opacity(0.18))
                    .frame(width: 4)
                Capsule()
                    .fill(theme.color(.eqSliders))
                    .frame(width: 4, height: abs(centerY - y))
                    .offset(y: min(y, centerY))
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .offset(y: y - 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let fraction = 1 - min(max(drag.location.y / max(height, 1), 0), 1)
                    let value = range.lowerBound + Float(fraction) * Float(span)
                    onChange((value * 2).rounded() / 2)   // 0.5 dB steps
                }
            )
        }
        .frame(minHeight: 110)
        .accessibilityRepresentation {
            Slider(value: Binding(get: { gain }, set: { onChange($0) }), in: range, step: 0.5)
        }
    }
}
