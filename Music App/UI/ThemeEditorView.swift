import SwiftUI
import SwiftData

/// Theme settings: built-in themes, the five role colors, glass opacity and the
/// user's saved themes. Every element derives its color from the five roles, so
/// any combination stays uniform. Changes apply live, so the whole app is the preview.
struct ThemeEditorView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedTheme.name) private var savedThemes: [SavedTheme]
    @State private var showSave = false
    @State private var themeName = ""
    /// Holds rapid edits (color-picker drags, the opacity slider) and applies them in batches.
    @State private var edits = ThemeEditBuffer()

    var body: some View {
        Form {
            Section {
                ThemePreview()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                Toggle("Match Artwork", isOn: Binding(
                    get: { theme.palette.matchArtwork },
                    set: { newValue in
                        edits.commit(theme)
                        withAnimation(Motion.ambient) { theme.palette.matchArtwork = newValue }
                    }
                ))
                .tint(theme.ambientAccent)
                .settingsRow()
            } footer: {
                Text("Glows and accents take their colors from the picture behind the player: the artist's picture if you've set one, otherwise the song's cover. Turn off to use your theme's Primary and Highlight colors everywhere. Text, background and glass always follow the theme.")
                    .settingsFooter()
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(ThemePreset.all) { preset in
                        PresetCard(preset: preset, isSelected: theme.palette.hasSameColors(as: preset.palette)) {
                            apply(preset.palette)
                        }
                    }
                }
                .padding(.vertical, 6)
                .settingsRow()
            } header: {
                Text("Themes")
            }

            Section {
                ForEach(ThemeRole.allCases) { role in
                    ColorPicker(selection: Binding(
                        get: { edits.current(theme).rgba(edits.current(theme).hex(for: role)).color },
                        set: { color in
                            let hex = color.hexString
                            edits.edit(theme) { $0.set(role, to: hex) }
                        }
                    ), supportsOpacity: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(role.displayName)
                            Text(role.usage)
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                    .settingsRow()
                }
            } header: {
                Text("Colors")
            } footer: {
                Text("Everything else, like the play button, toggles and glass tint, is worked out from these five so themes stay consistent.")
                    .settingsFooter()
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Glass Opacity")
                        Spacer()
                        Text("\(Int((edits.current(theme).glassOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(theme.secondaryText)
                    }
                    Slider(
                        value: Binding(get: { edits.current(theme).glassOpacity }, set: { value in edits.edit(theme) { $0.glassOpacity = value } }),
                        in: ThemePalette.glassOpacityRange
                    ) {
                        Text("Glass Opacity")
                    } minimumValueLabel: {
                        Image(systemName: "circle.dotted")
                    } maximumValueLabel: {
                        Image(systemName: "circle.fill")
                    }
                    .tint(theme.accent)
                }
                .settingsRow()
            } header: {
                Text("Glass Panels")
            } footer: {
                Text("Applies to list rows, cards, the tab bar and the mini player. Raise it if text is hard to read over bright pictures.")
                    .settingsFooter()
            }

            Section("My Themes") {
                ForEach(savedThemes) { saved in
                    Button {
                        apply(saved.palette)
                    } label: {
                        HStack {
                            Swatches(palette: saved.palette)
                            Text(saved.name)
                            Spacer()
                            if saved.palette.hasSameColors(as: theme.palette) {
                                Image(systemName: "checkmark").foregroundStyle(theme.accent)
                            }
                        }
                    }
                    .foregroundStyle(theme.text)
                    .settingsRow()
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(savedThemes[index]) }
                    try? context.save()
                }
                Button("Save Current Theme…", systemImage: "square.and.arrow.down") {
                    themeName = ""
                    showSave = true
                }
                .settingsRow()
                Button("Reset to Default", systemImage: "arrow.counterclockwise", role: .destructive) {
                    edits.cancel()
                    theme.palette = .default
                }
                .settingsRow()
            }
        }
        .onDisappear { edits.commit(theme) }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .backdropScreen()
        .alert("Save Theme", isPresented: $showSave) {
            TextField("Theme Name", text: $themeName)
            Button("Save") {
                let name = themeName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                edits.commit(theme)
                context.insert(SavedTheme(name: name, palette: theme.palette))
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Applies a theme's colors but keeps the user's Glass Opacity and Match Artwork setting.
    private func apply(_ palette: ThemePalette) {
        edits.cancel()
        var next = palette
        next.glassOpacity = theme.palette.glassOpacity
        next.matchArtwork = theme.palette.matchArtwork
        withAnimation(.easeInOut(duration: 0.3)) { theme.palette = next }
    }
}

/// Collects rapid theme edits and applies them about 12 times a second.
///
/// Each palette change redraws every screen that uses theme colors (every tab stays
/// loaded), with their glass and glows. A color-picker drag sends dozens of changes a
/// second, and redrawing the whole app that often kept the CPU so busy that music
/// stuttered. The picker and slider still follow the finger instantly: they show the
/// newest edit (`current`), while the app catches up in batches.
@Observable
final class ThemeEditBuffer {
    private(set) var draft: ThemePalette?
    @ObservationIgnored private var task: Task<Void, Never>?

    static let interval: Duration = .milliseconds(80)

    /// The palette as the controls should show it: the newest edit, else the theme's.
    func current(_ theme: ThemeStore) -> ThemePalette { draft ?? theme.palette }

    func edit(_ theme: ThemeStore, _ change: (inout ThemePalette) -> Void) {
        var next = current(theme)
        change(&next)
        guard next != current(theme) else { return }
        draft = next
        guard task == nil else { return }
        task = Task { [weak self, weak theme] in
            try? await Task.sleep(for: Self.interval)
            guard !Task.isCancelled, let self, let theme else { return }
            self.task = nil
            self.commit(theme)
        }
    }

    /// Applies any waiting edit now.
    func commit(_ theme: ThemeStore) {
        task?.cancel()
        task = nil
        if let draft, draft != theme.palette { theme.palette = draft }
        draft = nil
    }

    /// Drops any waiting edit (before applying a whole theme).
    func cancel() {
        task?.cancel()
        task = nil
        draft = nil
    }
}

/// One built-in theme: its colors as a small sample card.
private struct PresetCard: View {
    let preset: ThemePreset
    let isSelected: Bool
    let action: () -> Void

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        let palette = preset.palette
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    ForEach([ThemeRole.primary, .secondary, .highlight], id: \.self) { role in
                        Capsule()
                            .fill(palette.rgba(palette.hex(for: role)).color)
                            .frame(height: 22)
                    }
                }
                Text(preset.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.rgba(palette.text).color)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.rgba(palette.window, fallback: .black).color, in: .rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? theme.accent : .white.opacity(0.15), lineWidth: isSelected ? 2.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The three accent colors of a palette as overlapping dots.
private struct Swatches: View {
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: -4) {
            ForEach([ThemeRole.primary, .secondary, .highlight, .background], id: \.self) { role in
                Circle()
                    .fill(palette.rgba(palette.hex(for: role)).color)
                    .frame(width: 18, height: 18)
                    .overlay { Circle().strokeBorder(.white.opacity(0.3)) }
            }
        }
    }
}

/// A live sample of the current look, built from the same pieces as Now Playing:
/// the glass card with its glow rim, the playing song's cover and title (or a
/// placeholder), the glowing timeline bar, the theme's wave colors and the glowing
/// play button. With Match Artwork on, the glows show the backdrop picture's colors.
private struct ThemePreview: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(MusicPlayer.self) private var player
    @Environment(BackdropModel.self) private var backdrop

    var body: some View {
        let track = player.currentTrack
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Group {
                    if let track {
                        ArtworkView(artKey: track.coverKey, cornerRadius: Layout.rowArtworkCornerRadius)
                    } else {
                        RoundedRectangle(cornerRadius: Layout.rowArtworkCornerRadius, style: .continuous)
                            .fill(LinearGradient(colors: [theme.glowPrimary, theme.glowSecondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay { Image(systemName: "music.note").font(.title2.weight(.bold)).foregroundStyle(.white.opacity(0.85)) }
                    }
                }
                .frame(width: 64, height: 64)
                .ambientGlow(radius: 10, strength: 0.45)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Now Playing")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.color(.heading))
                    Text(track?.title ?? "Song Title")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(theme.color(.songTitle))
                        .lineLimit(1)
                    Text(track?.artist ?? "Artist")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }
            // The timeline bar, in the glow colors.
            ZStack(alignment: .leading) {
                Capsule().fill(theme.text.opacity(0.14))
                GeometryReader { geometry in
                    Capsule()
                        .fill(LinearGradient(colors: [theme.glowPrimary, theme.glowSecondary], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * 0.6)
                        .shadow(color: theme.glowPrimary.opacity(0.5), radius: 5)
                }
            }
            .frame(height: 6)
            // The wave's two edge colors (Secondary and Highlight).
            LinearGradient(colors: [theme.waveTop.color, theme.waveBottom.color], startPoint: .leading, endPoint: .trailing)
                .frame(height: 3)
                .clipShape(.capsule)
                .opacity(0.9)
            HStack {
                Image(systemName: "shuffle").foregroundStyle(theme.ambientAccentLight)
                Spacer()
                Image(systemName: "backward.fill").foregroundStyle(theme.color(.transportIcons))
                Spacer()
                Image(systemName: "play.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.ambientAccentText)
                    .frame(width: 52, height: 52)
                    .background { Circle().fill(theme.ambientAccent) }
                    .ambientGlow(radius: 12, strength: 0.55)
                Spacer()
                Image(systemName: "forward.fill").foregroundStyle(theme.color(.transportIcons))
                Spacer()
                Image(systemName: "heart.fill").foregroundStyle(theme.favorite)
            }
            .font(.body.weight(.semibold))
            Label(source, systemImage: theme.palette.matchArtwork && theme.artworkColors != nil ? "photo" : "paintpalette")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(18)
        .legibleOnGlass()
        .glassCard()
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Theme preview. \(source)")
    }

    /// Where the glow colors come from right now.
    private var source: String {
        guard theme.palette.matchArtwork else { return "Glows use your theme's Primary and Highlight colors." }
        guard let track = player.currentTrack else { return "Play a song to see its colors here." }
        // The colors come from the backdrop: the artist's picture, else the cover.
        let isArtistPicture = backdrop.shown?.isArtistImage ?? false
        if theme.artworkColors == nil {
            return isArtistPicture
                ? "The artist's picture has no strong colors, so glows use your theme."
                : "This cover has no strong colors, so glows use your theme."
        }
        return isArtistPicture
            ? "Glows match the picture of \(track.artist)."
            : "Glows match the cover of “\(track.title)”."
    }
}

extension View {
    /// Glass-tinted background for rows in Settings and Theme forms, over the backdrop.
    func settingsRow() -> some View {
        modifier(SettingsRow())
    }

    /// Section footers sit straight on the backdrop, so they use bright text with a shadow.
    func settingsFooter() -> some View {
        modifier(SettingsFooter())
    }
}

private struct SettingsFooter: ViewModifier {
    @Environment(ThemeStore.self) private var theme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(theme.text.opacity(0.85))
            .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
            .shadow(color: .black.opacity(0.35), radius: 8)
    }
}

private struct SettingsRow: ViewModifier {
    @Environment(ThemeStore.self) private var theme

    func body(content: Content) -> some View {
        content.listRowBackground(theme.color(.panelTint).opacity(min(theme.glassOpacity + 0.2, 1)))
    }
}

extension Color {
    /// `#RRGGBB` for theme storage (sRGB).
    var hexString: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return RGBA(red: Double(red), green: Double(green), blue: Double(blue)).hex
    }
}
