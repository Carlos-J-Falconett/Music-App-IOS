import SwiftUI
import os

/// The two glow colors taken from the backdrop picture: the artist's picture, or the
/// album cover when there isn't one (Settings → Theme → Match Artwork).
///
/// The cover's thumbnail is averaged down to an 8×8 grid. The most vivid cell
/// becomes the main color, and the most vivid cell with a clearly different hue
/// becomes the second one (or a hue-shifted copy of the main color when the cover
/// is mostly one color). Both are lifted so they glow on dark glass. Nearly
/// colorless covers (black-and-white photos) give no colors, so the theme's own
/// colors are used for them.
nonisolated enum ArtworkPalette {
    struct Colors: Equatable, Sendable {
        var primary: RGBA
        var secondary: RGBA
    }

    /// Covers below this saturation count as colorless.
    static let minimumSaturation = 0.18
    /// Hue distance (0…0.5 around the color wheel) for a second color to count as different.
    static let minimumHueDistance = 0.12

    private static let cache = OSAllocatedUnfairLock(initialState: [String: Colors?]())

    /// Colors for a cover in `ArtCache`, computed off the main actor and remembered per key.
    @concurrent
    static func colors(for key: String) async -> Colors? {
        if let cached = cache.withLock({ $0[key] }) { return cached }
        let colors = ArtCache.image(for: key, .thumb)?.cgImage.flatMap(colors(from:))
        cache.withLock { $0[key] = colors }
        return colors
    }

    /// Picks the glow colors from an image (pure, so it can be unit tested).
    static func colors(from image: CGImage) -> Colors? {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        let cells = stride(from: 0, to: pixels.count, by: 4).map { i in
            HSB(RGBA(red: Double(pixels[i]) / 255, green: Double(pixels[i + 1]) / 255, blue: Double(pixels[i + 2]) / 255))
        }
        guard let main = cells.max(by: { $0.vividness < $1.vividness }), main.saturation >= minimumSaturation else {
            return nil
        }
        let second = cells
            .filter { $0.saturation >= minimumSaturation && main.hueDistance(to: $0) >= minimumHueDistance }
            .max { $0.vividness < $1.vividness }
            ?? HSB(hue: (main.hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: main.saturation, brightness: main.brightness)
        return Colors(primary: main.glowing.rgba, secondary: second.glowing.rgba)
    }

    /// Hue, saturation and brightness, each 0…1.
    struct HSB {
        var hue: Double
        var saturation: Double
        var brightness: Double

        init(hue: Double, saturation: Double, brightness: Double) {
            self.hue = hue
            self.saturation = saturation
            self.brightness = brightness
        }

        init(_ color: RGBA) {
            let maxC = max(color.red, color.green, color.blue)
            let minC = min(color.red, color.green, color.blue)
            let delta = maxC - minC
            brightness = maxC
            saturation = maxC > 0 ? delta / maxC : 0
            guard delta > 0 else { hue = 0; return }
            var h: Double
            if maxC == color.red {
                h = (color.green - color.blue) / delta
            } else if maxC == color.green {
                h = (color.blue - color.red) / delta + 2
            } else {
                h = (color.red - color.green) / delta + 4
            }
            h /= 6
            hue = h < 0 ? h + 1 : h
        }

        /// How much a color stands out: saturated and bright beats dull or dark.
        var vividness: Double { saturation * (0.35 + 0.65 * brightness) }

        func hueDistance(to other: HSB) -> Double {
            let distance = abs(hue - other.hue)
            return min(distance, 1 - distance)
        }

        /// Lifted so it reads as light on dark glass, without turning pastel.
        var glowing: HSB {
            HSB(hue: hue, saturation: min(max(saturation, 0.55), 0.9), brightness: max(brightness, 0.82))
        }

        var rgba: RGBA {
            let h = hue * 6
            let sector = Int(h) % 6
            let f = h - Double(Int(h))
            let p = brightness * (1 - saturation)
            let q = brightness * (1 - saturation * f)
            let t = brightness * (1 - saturation * (1 - f))
            let (r, g, b): (Double, Double, Double) = switch sector {
            case 0: (brightness, t, p)
            case 1: (q, brightness, p)
            case 2: (p, brightness, t)
            case 3: (p, q, brightness)
            case 4: (t, p, brightness)
            default: (brightness, p, q)
            }
            return RGBA(red: r, green: g, blue: b)
        }
    }
}

extension View {
    /// Keeps `ThemeStore.artworkColors` in sync with the picture behind the interface.
    /// Apply once, at the root.
    func artworkPaletteLoader() -> some View {
        modifier(ArtworkPaletteLoader())
    }
}

private struct ArtworkPaletteLoader: ViewModifier {
    @Environment(MusicPlayer.self) private var player
    @Environment(ThemeStore.self) private var theme
    @Environment(BackdropModel.self) private var backdrop

    /// The image the colors come from: whatever the backdrop shows (the artist's
    /// picture, else their group's, else the album cover), so glows always match the
    /// background. Before the backdrop has loaded, the playing song's cover.
    private var sourceKey: String? {
        guard player.currentTrack != nil else { return nil }
        return backdrop.shown?.key ?? player.currentTrack?.coverKey
    }

    func body(content: Content) -> some View {
        content.task(id: sourceKey) {
            let colors: ArtworkPalette.Colors?
            if let key = sourceKey {
                colors = await ArtworkPalette.colors(for: key)
            } else {
                colors = nil
            }
            guard !Task.isCancelled, colors != theme.artworkColors else { return }
            // Slow crossfade between songs, like the backdrop.
            withAnimation(Motion.ambient) { theme.artworkColors = colors }
        }
    }
}
