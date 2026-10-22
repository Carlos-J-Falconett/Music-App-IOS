import SwiftUI

/// A simple RGBA color used for theme math (mixing, hex round-trips).
nonisolated struct RGBA: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    /// Parses `#RRGGBB` or `#RRGGBBAA` (the leading `#` is optional).
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6 || string.count == 8, let value = UInt64(string, radix: 16) else { return nil }
        if string.count == 8 {
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        } else {
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
        }
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Linear mix toward `other`; `amount` 0 keeps self, 1 returns `other`.
    func mixed(with other: RGBA, amount: Double) -> RGBA {
        let t = min(max(amount, 0), 1)
        return RGBA(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            alpha: alpha + (other.alpha - alpha) * t
        )
    }

    var hex: String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }

    static let white = RGBA(red: 1, green: 1, blue: 1)
    static let black = RGBA(red: 0, green: 0, blue: 0)
}


nonisolated extension RGBA {
    /// Relative luminance (WCAG), used to pick readable text on a color.
    var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// White when it reaches WCAG's 3:1 contrast for large icons and bold labels
    /// (luminance ≤ 0.30), otherwise black. So blue and magenta keep white icons,
    /// while lighter colors like orange, teal or yellow get black ones.
    var contrastingText: RGBA { luminance > 0.30 ? .black : .white }
}

/// The five colors a theme is made of. Every element in the app derives its
/// color from one of these, so themes always look uniform.
nonisolated enum ThemeRole: String, CaseIterable, Identifiable, Sendable {
    case primary, secondary, highlight, background, text

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .primary: "Primary"
        case .secondary: "Secondary"
        case .highlight: "Highlight"
        case .background: "Background"
        case .text: "Text"
        }
    }

    var usage: String {
        switch self {
        case .primary: "Buttons, tab bar, sliders, stats"
        case .secondary: "Wave bottom edge"
        case .highlight: "Favorites, wave top edge"
        case .background: "Window and glass panels"
        case .text: "Titles and labels"
        }
    }
}

/// Interface elements that read a color from the theme. Each one follows a role.
nonisolated enum ThemeElement: String, CaseIterable, Sendable {
    case tabBar, pageTitle, songTitle, heading
    case slider, playButton, playIcon, transportIcons, toggleOn
    case heatmap, statBars, eqSliders, panelTint, backdropDim
}

/// A complete color theme. Users pick the five role colors (`ThemeRole`); the
/// rest is derived so themes stay consistent. Stored as hex strings so it encodes
/// to compact JSON, using the desktop app's key names.
nonisolated struct ThemePalette: Codable, Equatable, Sendable {
    /// Primary role.
    var accent = "#0A84FF"
    /// Derived: black or white, whichever reads best on `accent`.
    var accentText = "#FFFFFF"
    var text = "#FFFFFF"
    /// Background role.
    var window = "#08080B"
    /// Derived from the background: slightly lifted, used to tint glass.
    var panels = "#0D0D11"
    /// Highlight role (shared with `waveTop`).
    var favorite = "#FF2E63"
    var waveTop = "#FF2E63"
    /// Secondary role.
    var waveBottom = "#3D8BFF"
    /// How opaque Liquid Glass panels are (0 = fully see-through, 1 = solid panel tint).
    /// Higher values make text on glass easier to read over bright artist images.
    var glassOpacity: Double = ThemePalette.defaultGlassOpacity
    /// When on, glows and accents follow the playing song's artwork instead of the
    /// theme's Primary and Highlight (Settings → Theme → Match Artwork).
    var matchArtwork = true

    static let defaultGlassOpacity = 0.5
    static let glassOpacityRange: ClosedRange<Double> = 0.1...0.9
    static let `default` = ThemePreset.sun.palette

    init() {}

    /// Builds a palette from the five role colors.
    init(primary: String, secondary: String, highlight: String, background: String, text: String) {
        self.init()
        set(.primary, to: primary)
        set(.secondary, to: secondary)
        set(.highlight, to: highlight)
        set(.background, to: background)
        set(.text, to: text)
    }

    // MARK: Roles

    func hex(for role: ThemeRole) -> String {
        switch role {
        case .primary: accent
        case .secondary: waveBottom
        case .highlight: waveTop
        case .background: window
        case .text: text
        }
    }

    /// Sets a role color and keeps the colors derived from it in sync.
    mutating func set(_ role: ThemeRole, to hex: String) {
        switch role {
        case .primary:
            accent = hex
            accentText = rgba(hex).contrastingText.hex
        case .secondary:
            waveBottom = hex
        case .highlight:
            waveTop = hex
            favorite = hex
        case .background:
            window = hex
            panels = rgba(hex, fallback: .black).mixed(with: .white, amount: 0.03).hex
        case .text:
            text = hex
        }
    }

    /// True when both palettes use the same colors (Glass Opacity is ignored).
    func hasSameColors(as other: ThemePalette) -> Bool {
        ThemeRole.allCases.allSatisfy { RGBA(hex: hex(for: $0)) == RGBA(hex: other.hex(for: $0)) }
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case accent, accentText, text, window, panels, favorite, waveTop, waveBottom, glassOpacity, matchArtwork
    }

    /// Every key is optional so themes saved by older versions (before a key
    /// existed) still load instead of silently falling back to the default theme.
    /// Per-element colors from older versions (`overrides`) are ignored.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ThemePalette()
        accent = try container.decodeIfPresent(String.self, forKey: .accent) ?? fallback.accent
        // Always derived, so themes saved before the contrast rule get readable icons too.
        accentText = (RGBA(hex: accent) ?? .white).contrastingText.hex
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? fallback.text
        window = try container.decodeIfPresent(String.self, forKey: .window) ?? fallback.window
        panels = try container.decodeIfPresent(String.self, forKey: .panels) ?? fallback.panels
        favorite = try container.decodeIfPresent(String.self, forKey: .favorite) ?? fallback.favorite
        waveTop = try container.decodeIfPresent(String.self, forKey: .waveTop) ?? fallback.waveTop
        waveBottom = try container.decodeIfPresent(String.self, forKey: .waveBottom) ?? fallback.waveBottom
        let opacity = try container.decodeIfPresent(Double.self, forKey: .glassOpacity) ?? fallback.glassOpacity
        glassOpacity = min(max(opacity, Self.glassOpacityRange.lowerBound), Self.glassOpacityRange.upperBound)
        matchArtwork = try container.decodeIfPresent(Bool.self, forKey: .matchArtwork) ?? fallback.matchArtwork
    }

    // MARK: Derived colors (desktop: accent_light = accent mixed 20% toward white)

    func rgba(_ hex: String, fallback: RGBA = .white) -> RGBA { RGBA(hex: hex) ?? fallback }

    var accentLight: RGBA { rgba(accent).mixed(with: .white, amount: 0.2) }

    /// The bright end of each wave edge (base color mixed 45% toward white).
    var waveTopBright: RGBA { rgba(waveTop).mixed(with: .white, amount: 0.45) }
    var waveBottomBright: RGBA { rgba(waveBottom).mixed(with: .white, amount: 0.45) }

    /// The color an element uses, always derived from the role colors.
    func resolved(_ element: ThemeElement) -> RGBA {
        switch element {
        case .tabBar, .playButton, .heatmap, .statBars, .eqSliders: rgba(accent)
        case .pageTitle, .songTitle, .transportIcons, .slider: rgba(text)
        // Dimmed text, but bright enough to read over light backdrops.
        case .heading: rgba(text).mixed(with: rgba(panels, fallback: .black), amount: 0.3)
        case .playIcon: rgba(accentText)
        case .toggleOn: accentLight
        case .panelTint: rgba(panels, fallback: .black)
        case .backdropDim: .black
        }
    }
}

/// Built-in themes based on common color combinations.
nonisolated struct ThemePreset: Identifiable, Sendable {
    let name: String
    let palette: ThemePalette
    var id: String { name }

    private init(_ name: String, primary: String, secondary: String, highlight: String, background: String, text: String = "#FFFFFF") {
        self.name = name
        self.palette = ThemePalette(primary: primary, secondary: secondary, highlight: highlight, background: background, text: text)
    }

    /// The original desktop colors: blue with a red/blue wave.
    static let sun = ThemePreset("Sun", primary: "#0A84FF", secondary: "#3D8BFF", highlight: "#FF2E63", background: "#08080B")

    static let all: [ThemePreset] = [
        sun,
        // Orange, blue and red: warm accent with a cool counterpoint.
        ThemePreset("Sunset", primary: "#FF8A1F", secondary: "#2F6BFF", highlight: "#FF3B30", background: "#0A0D1C", text: "#FFF4E8"),
        // Teal and sky blue with a coral highlight.
        ThemePreset("Ocean", primary: "#14B8A6", secondary: "#0EA5E9", highlight: "#FF6B6B", background: "#03121B"),
        // Greens with a warm amber highlight.
        ThemePreset("Forest", primary: "#34C759", secondary: "#A3E635", highlight: "#F59E0B", background: "#08120A", text: "#F2FFF4"),
        // Purple and gold, a classic complementary pair.
        ThemePreset("Royal", primary: "#8B5CF6", secondary: "#F5C542", highlight: "#F43F5E", background: "#0B0816"),
        // Magenta and cyan with an electric yellow.
        ThemePreset("Neon", primary: "#FF2FD1", secondary: "#00E5FF", highlight: "#FAFF00", background: "#07020F"),
        // Soft pinks and peach.
        ThemePreset("Rosé", primary: "#F472B6", secondary: "#FDBA74", highlight: "#FB7185", background: "#140A0F", text: "#FFF1F5"),
        // Red and gold on near-black.
        ThemePreset("Ember", primary: "#EF4444", secondary: "#F59E0B", highlight: "#FB923C", background: "#120706", text: "#FFF5EE"),
        // Greys only.
        ThemePreset("Mono", primary: "#E5E5EA", secondary: "#8E8E93", highlight: "#FFFFFF", background: "#000000"),
    ]
}
