import SwiftUI
import UIKit

/// Shared layout values so every screen lines up the same way.
enum Layout {
    /// Side margin for page content (lists inset their glass rows by this much).
    static let screenPadding: CGFloat = 16
    /// Gap between glass rows in a list.
    static let rowSpacing: CGFloat = 8
    static let rowCornerRadius: CGFloat = 20
    static let cardCornerRadius: CGFloat = 28
    static let sheetCornerRadius: CGFloat = 32
    /// Cover size in song rows.
    static let rowArtwork: CGFloat = 48
    /// Picture size in artist and playlist rows.
    static let largeRowArtwork: CGFloat = 56
    /// Corner radius of covers in rows (rounder than the old 10 pt).
    static let rowArtworkCornerRadius: CGFloat = 14

    /// Spacing scale used between blocks of content.
    static let spacingSmall: CGFloat = 8
    static let spacingMedium: CGFloat = 16
    static let spacingLarge: CGFloat = 28
}

/// The app's motion: slow and fluid (the "ambient" look).
enum Motion {
    /// Taps, selections and panels appearing.
    static let standard = Animation.smooth(duration: 0.6)
    /// Color and backdrop changes between songs.
    static let ambient = Animation.easeInOut(duration: 1.2)
}

/// Rounded navigation bar titles to match the rest of the app (SF Pro Rounded).
/// Navigation bar titles are drawn by UIKit, so `.fontDesign(.rounded)` doesn't reach them.
enum Typography {
    static func configureNavigationBars() {
        func rounded(_ style: UIFont.TextStyle, size: CGFloat, weight: UIFont.Weight) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
            // Scaled so titles still follow Dynamic Type.
            return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
        }
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.font: rounded(.largeTitle, size: 34, weight: .heavy)]
        appearance.titleTextAttributes = [.font: rounded(.headline, size: 17, weight: .bold)]
    }
}

extension View {
    /// A Liquid Glass card over the artist backdrop.
    ///
    /// Clear glass alone lets bright images show straight through text, so a
    /// dimming layer in the theme's "Glass Panel Tint" sits between the glass and
    /// the content. Its strength is Themes → Glass Opacity; `emphasis` scales it
    /// for surfaces that need more contrast (the equalizer card uses 1.4).
    ///
    /// The edge has a thin rim in the two glow colors (`ThemeStore.glowPrimary` and
    /// `glowSecondary`, from the artwork or the theme), and `glow` adds a soft halo
    /// of the same colors around the card. List rows leave the halo off: a blurred
    /// shadow on every row would cost too much while scrolling.
    func glassCard(cornerRadius: CGFloat = Layout.cardCornerRadius, emphasis: Double = 1, interactive: Bool = false, glow: Bool = true) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, emphasis: emphasis, interactive: interactive, glow: glow))
    }

    /// A soft halo in the glow colors around any shape (covers, the play button).
    func ambientGlow(radius: CGFloat = 22, strength: Double = 0.45) -> some View {
        modifier(AmbientGlow(radius: radius, strength: strength))
    }

    /// A soft shadow under text and icons so they stay readable on glass over any image.
    func legibleOnGlass() -> some View {
        modifier(LegibleOnGlass())
    }

    /// Clears the system backgrounds of a library screen and puts the artist
    /// backdrop behind it, so every page shows the see-through look.
    func backdropScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .containerBackground(for: .navigation) { BackdropView() }
    }

    /// The list style every library screen uses: plain rows with even spacing.
    func libraryListStyle() -> some View {
        self
            .listStyle(.plain)
            .listRowSpacing(Layout.rowSpacing)
            .listSectionSpacing(18)
    }
}

private struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat
    let emphasis: Double
    let interactive: Bool
    let glow: Bool

    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let tint = theme.color(.panelTint)
        let opacity = min(theme.glassOpacity * emphasis, 1)
        content
            .background(shape.fill(tint.opacity(opacity * 0.7)))
            .glassEffect(.clear.tint(tint.opacity(opacity * 0.5)).interactive(interactive), in: shape)
            .overlay {
                if !reduceTransparency {
                    shape.strokeBorder(GlowRim.gradient(theme), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .background {
                if glow && !reduceTransparency {
                    shape.fill(theme.glowPrimary.opacity(0.18))
                        .blur(radius: 18)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// The thin two-color rim on glass edges: brightest at the top left, fading around.
enum GlowRim {
    static func gradient(_ theme: ThemeStore) -> AngularGradient {
        AngularGradient(
            colors: [
                theme.glowPrimary.opacity(0.65), theme.glowSecondary.opacity(0.35),
                theme.glowPrimary.opacity(0.08), theme.glowSecondary.opacity(0.35),
                theme.glowPrimary.opacity(0.65),
            ],
            center: .center, angle: .degrees(225)
        )
    }
}

private struct AmbientGlow: ViewModifier {
    let radius: CGFloat
    let strength: Double

    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
        } else {
            content
                .shadow(color: theme.glowPrimary.opacity(strength), radius: radius)
                .shadow(color: theme.glowSecondary.opacity(strength * 0.5), radius: radius * 1.6, x: radius * 0.3, y: radius * 0.4)
        }
    }
}

private struct LegibleOnGlass: ViewModifier {
    @Environment(ThemeStore.self) private var theme

    func body(content: Content) -> some View {
        // A stronger glass tint already darkens the panel, so the shadow can be lighter.
        content.shadow(color: .black.opacity(0.55 - theme.glassOpacity * 0.3), radius: 1.5, y: 0.5)
    }
}

/// Liquid Glass background for one list row, inset so rows float as separate cards.
struct GlassRowBackground: View {
    var body: some View {
        Color.clear
            .glassCard(cornerRadius: Layout.rowCornerRadius, glow: false)
            .padding(.horizontal, Layout.screenPadding - 4)
            .padding(.vertical, 1)
    }
}

extension View {
    /// Applies `GlassRowBackground`, hides separators (the cards separate rows)
    /// and adds the legibility shadow to the row's content.
    func glassRow() -> some View {
        self
            .legibleOnGlass()
            .listRowBackground(GlassRowBackground())
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: Layout.screenPadding + 8, bottom: 8, trailing: Layout.screenPadding + 8))
    }

    /// A list row with no card behind it (headers, buttons, empty states).
    func plainListRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: Layout.screenPadding, bottom: 6, trailing: Layout.screenPadding))
    }
}

/// Section title used in every list: bold, sentence case, with an optional count.
struct SectionHeader: View {
    let title: String
    var detail: String?

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.color(.heading))
            Spacer()
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(theme.text.opacity(0.75))
            }
        }
        .textCase(nil)
        .legibleOnGlass()
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // Plain lists pin section headers, so the header gets its own glass bar:
        // rows scrolling underneath stay hidden and it reads over bright pictures.
        .glassEffect(.regular.tint(theme.glassTint), in: .capsule)
        .padding(.horizontal, -4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Formats seconds as `m:ss` (or `h:mm:ss` for long tracks).
nonisolated func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
    if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
    return String(format: "%d:%02d", minutes, secs)
}

/// "1 song", "3 songs" — simple English plurals for counts.
nonisolated func countLabel(_ count: Int, _ noun: String, plural: String? = nil) -> String {
    count == 1 ? "1 \(noun)" : "\(count) \(plural ?? noun + "s")"
}

/// Formats listening time for stats, e.g. "3h 12m" or "45m".
nonisolated func formatListeningTime(_ seconds: Double) -> String {
    let minutes = Int(seconds / 60)
    if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
    if minutes == 0 { return "\(Int(seconds))s" }
    return "\(minutes)m"
}

/// Big rounded capsule used for "Play" and "Shuffle". The prominent one is tinted
/// with the ambient accent (artwork or theme) and glows softly.
struct GlowCapsuleButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.bold))
                // One line: at large text sizes the row stacks the buttons instead (PlayShuffleRow).
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.glass(prominent ? .regular.tint(theme.ambientAccent) : .regular.tint(theme.glassTint)))
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .foregroundStyle(prominent ? theme.ambientAccentText : theme.text)
        .ambientGlow(radius: prominent ? 16 : 0, strength: prominent ? 0.4 : 0)
    }
}

/// "Play" + "Shuffle" row shown above song lists.
struct PlayShuffleRow: View {
    /// The songs these buttons queue (already without hidden artists where that applies).
    let tracks: [Track]
    @Environment(MusicPlayer.self) private var player
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Side by side normally; stacked at accessibility text sizes so labels don't wrap.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        GlassEffectContainer(spacing: 12) {
            layout {
                GlowCapsuleButton(title: "Play", systemImage: "play.fill", prominent: true) {
                    player.play(tracks)
                }
                GlowCapsuleButton(title: "Shuffle", systemImage: "shuffle") {
                    player.shuffleAll(tracks)
                }
            }
        }
        .disabled(tracks.isEmpty)
    }
}

/// The top of a detail page (artist, album, genre, playlist): artwork, title,
/// a details line and the Play / Shuffle buttons, centered and evenly spaced.
struct DetailHeader: View {
    var artKey: String?
    var isCircle = false
    /// Shown instead of artwork when there's no picture to show (e.g. Favorites).
    var symbol: String?
    let title: String
    var subtitle: String?
    var detail: String?
    let playTracks: [Track]

    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Glow colors from this page's own artwork (not the playing song's).
    @State private var pageColors: ArtworkPalette.Colors?

    private static let artworkSide: CGFloat = 230

    var body: some View {
        // With Match Artwork off (or a colorless cover) the halo uses the theme's glow colors.
        let glowA = theme.palette.matchArtwork ? (pageColors?.primary.color ?? theme.glowPrimary) : theme.glowPrimary
        let glowB = theme.palette.matchArtwork ? (pageColors?.secondary.color ?? theme.glowSecondary) : theme.glowSecondary
        VStack(spacing: 16) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundStyle(theme.favorite)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .glassCard(cornerRadius: Layout.cardCornerRadius)
                } else {
                    ArtworkView(artKey: artKey, variant: .full, cornerRadius: Layout.cardCornerRadius, isCircle: isCircle)
                        .overlay {
                            let rim = AngularGradient(colors: [glowA.opacity(0.7), glowB.opacity(0.4), glowA.opacity(0.1), glowB.opacity(0.4), glowA.opacity(0.7)],
                                                      center: .center, angle: .degrees(225))
                            if isCircle {
                                Circle().strokeBorder(rim, lineWidth: 1.5)
                            } else {
                                RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous).strokeBorder(rim, lineWidth: 1.5)
                            }
                        }
                }
            }
            .frame(width: Self.artworkSide, height: Self.artworkSide)
            // The halo: two soft glows in the artwork's colors, plus a grounding shadow.
            .shadow(color: reduceTransparency ? .clear : glowA.opacity(0.45), radius: 30)
            .shadow(color: reduceTransparency ? .clear : glowB.opacity(0.3), radius: 48, x: 10, y: 16)
            .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
            .padding(.vertical, 6)
            .animation(Motion.ambient, value: pageColors)
            .task(id: artKey) {
                pageColors = if let artKey { await ArtworkPalette.colors(for: artKey) } else { nil }
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.title.weight(.heavy))
                    .foregroundStyle(theme.color(.pageTitle))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if let subtitle {
                    Text(subtitle)
                        .font(.headline)
                        .foregroundStyle(theme.text.opacity(0.9))
                        .lineLimit(1)
                }
                if let detail {
                    Text(detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.text.opacity(0.8))
                }
            }
            // This text sits straight on the backdrop (no glass), so it gets a stronger shadow.
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            .shadow(color: .black.opacity(0.35), radius: 10)

            PlayShuffleRow(tracks: playTracks)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// Glass chips used as a segmented control (Library sections, Stats periods).
/// The selected chip is tinted with the ambient accent and glows slightly.
struct ChipPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        // Every chip always fully on screen: one row spread across the width (compact
        // chips, so five fit on any iPhone at normal text sizes), otherwise wrapped onto
        // more lines (large text sizes).
        ViewThatFits(in: .horizontal) {
            fittedRow
            wrappedRows
        }
    }

    /// Fallback when the chips don't fit on one line: they wrap onto the next line.
    private var wrappedRows: some View {
        GlassEffectContainer(spacing: Layout.spacingSmall) {
            FlowLayout(spacing: Layout.spacingSmall) {
                ForEach(options, id: \.self) { option in
                    chip(option, horizontalPadding: 12, fills: false)
                }
            }
            .padding(.horizontal, Layout.screenPadding)
            .padding(.vertical, 6)
        }
    }

    /// All chips in one row at their natural widths (so no label is cut short), with the
    /// leftover space shared evenly between them so the row spans the screen.
    private var fittedRow: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element) { position, option in
                    if position > 0 { Spacer(minLength: 4) }
                    chip(option, horizontalPadding: 10, fills: false)
                        .fixedSize()
                }
            }
            .padding(.horizontal, Layout.screenPadding)
            .padding(.vertical, 6)
        }
    }


    private func chip(_ option: Value, horizontalPadding: CGFloat, fills: Bool) -> some View {
        let isSelected = option == selection
        return Button {
            withAnimation(Motion.standard) { selection = option }
        } label: {
            Text(title(option))
                // Footnote size keeps five chips (Songs … Playlists) on one row even on a
                // 390 pt-wide phone; subheadline pushed "Playlists" to a second row on 430 pt.
                .font(.footnote.weight(.bold))
                .lineLimit(1)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 8)
                .frame(maxWidth: fills ? .infinity : nil)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? theme.ambientAccentText : theme.text)
        .glassEffect(isSelected ? .regular.tint(theme.ambientAccent).interactive() : .regular.tint(theme.glassTint).interactive(), in: .capsule)
        .ambientGlow(radius: isSelected ? 10 : 0, strength: isSelected ? 0.35 : 0)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Lays views out left to right, starting a new line when the next one doesn't fit
/// (chips at large text sizes). Each view keeps its natural size.
// `SwiftUI.` because the app's own `Layout` enum (spacing values) shadows the protocol.
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: LayoutSubviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                let nextY = current.y + current.height + spacing
                rows.append(current)
                current = Row(y: nextY)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
