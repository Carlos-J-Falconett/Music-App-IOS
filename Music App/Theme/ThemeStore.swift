import SwiftUI

/// The active color theme, shared through the environment. Every custom UI
/// element reads its colors from here so the theme editor can restyle it.
@Observable
final class ThemeStore {
    private static let defaultsKey = "activeThemePalette"

    /// The palette currently applied to the app. Saved shortly after the last change
    /// (not on every step of a color-picker drag), and when the app leaves the foreground.
    var palette: ThemePalette {
        didSet {
            guard palette != oldValue else { return }
            colors = ResolvedColors(palette)
            scheduleSave()
        }
    }

    /// Every color worked out from `palette` once, instead of parsing hex strings on
    /// every read (views read these thousands of times per redraw).
    private(set) var colors: ResolvedColors

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let initial: ThemePalette
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode(ThemePalette.self, from: data) {
            initial = stored
        } else {
            initial = .default
        }
        palette = initial
        colors = ResolvedColors(initial)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes the palette right away (also called when the app goes to the background).
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        if let data = try? JSONEncoder().encode(palette) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: Base colors

    var accent: Color { colors.accent.color }
    var accentLight: Color { colors.accentLight.color }
    var accentText: Color { colors.accentText.color }
    var text: Color { colors.text.color }
    /// Secondary text is the main text color at 70%. (The desktop `--fg-dim` is 58%,
    /// but over bright artist pictures that was too faint to read on a phone.)
    var secondaryText: Color { text.opacity(0.7) }
    var window: Color { colors.window.color }
    var panels: Color { colors.panels.color }
    var favorite: Color { colors.favorite.color }
    var waveTop: RGBA { colors.waveTop }
    var waveBottom: RGBA { colors.waveBottom }

    /// Opacity of the panel tint laid over Liquid Glass (Themes → Glass Opacity).
    var glassOpacity: Double { palette.glassOpacity }
    /// The tint every glass surface uses: the "Glass Panel Tint" element at the chosen opacity.
    var glassTint: Color { color(.panelTint).opacity(glassOpacity) }

    // MARK: Ambient colors (glows and accents)

    /// Colors taken from the picture behind the player: the artist's picture, else the
    /// song's cover (set by `artworkPaletteLoader()`).
    /// Not saved: they change with every song.
    var artworkColors: ArtworkPalette.Colors?

    /// The artwork colors when Match Artwork is on and the cover has usable colors.
    private var activeArtwork: ArtworkPalette.Colors? { palette.matchArtwork ? artworkColors : nil }

    /// Main glow color: the artwork's, or the theme's Primary.
    var glowPrimaryRGBA: RGBA { activeArtwork?.primary ?? colors.accent }
    /// Second glow color: the artwork's, or the theme's Highlight.
    var glowSecondaryRGBA: RGBA { activeArtwork?.secondary ?? colors.waveTop }
    var glowPrimary: Color { glowPrimaryRGBA.color }
    var glowSecondary: Color { glowSecondaryRGBA.color }

    /// Accent for selected controls and prominent buttons; follows the artwork like the glows.
    var ambientAccent: Color { glowPrimary }
    /// Readable text and icons on `ambientAccent` (white or black, same rule as the theme).
    var ambientAccentText: Color { glowPrimaryRGBA.contrastingText.color }
    /// The accent lifted 40% toward white, for accent-colored text on glass
    /// (e.g. the playing song's title), which a saturated color alone can't carry.
    var ambientAccentLight: Color { glowPrimaryRGBA.mixed(with: .white, amount: 0.4).color }

    // MARK: Derived tones (desktop hover = text@0.06, active = text@0.11, hairline = text@0.07)

    var hover: Color { text.opacity(0.06) }
    var active: Color { text.opacity(0.11) }
    var hairline: Color { text.opacity(0.07) }

    /// Color for an individually themeable element (override or "Auto").
    func color(_ element: ThemeElement) -> Color { colors.element(element).color }
}

/// A palette's colors, parsed and derived once.
nonisolated struct ResolvedColors: Equatable, Sendable {
    let accent, accentLight, accentText, text, window, panels, favorite, waveTop, waveBottom: RGBA
    let waveTopBright, waveBottomBright: RGBA
    private let elements: [RGBA]

    init(_ palette: ThemePalette) {
        accent = palette.rgba(palette.accent)
        accentLight = palette.accentLight
        accentText = palette.rgba(palette.accentText)
        text = palette.rgba(palette.text)
        window = palette.rgba(palette.window, fallback: .black)
        panels = palette.rgba(palette.panels, fallback: .black)
        favorite = palette.rgba(palette.favorite)
        waveTop = palette.rgba(palette.waveTop)
        waveBottom = palette.rgba(palette.waveBottom)
        waveTopBright = palette.waveTopBright
        waveBottomBright = palette.waveBottomBright
        elements = ThemeElement.allCases.map(palette.resolved)
    }

    func element(_ element: ThemeElement) -> RGBA {
        elements[ThemeElement.allCases.firstIndex(of: element) ?? 0]
    }
}
