import SwiftUI

/// The compact header at the top of Home, Library and Stats: a big title with round
/// icon buttons on the same line, and optional content (like section chips) underneath.
/// At accessibility text sizes the buttons move under the title.
///
/// Use it with `pinnedHeader(_:)`, which keeps it fixed at the top with the page's
/// content scrolling below it (never underneath it).
struct PageHeader<Actions: View, Below: View>: View {
    let title: String
    var subtitle: String?
    /// Small text after the title on the same line (Home's version number).
    var titleDetail: String?
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let below: () -> Below

    @Environment(ThemeStore.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Layout.spacingSmall))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Layout.spacingSmall))
        VStack(alignment: .leading, spacing: Layout.spacingSmall) {
            layout {
                VStack(alignment: .leading, spacing: 0) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.text.opacity(0.8))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.largeTitle.weight(.heavy))
                            .foregroundStyle(theme.color(.pageTitle))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .contentTransition(.opacity)
                            .accessibilityAddTraits(.isHeader)
                        if let titleDetail {
                            Text(titleDetail)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                // Sits straight on the backdrop, so it gets the stronger shadow.
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                .shadow(color: .black.opacity(0.35), radius: 10)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Layout.spacingSmall) }
                GlassEffectContainer(spacing: Layout.spacingSmall) {
                    HStack(spacing: Layout.spacingSmall) { actions() }
                }
            }
            .padding(.horizontal, Layout.screenPadding)
            below()
        }
        // Full width and left-aligned even when nothing sits below the title (Home),
        // otherwise a short header would be centered on the page.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Layout.spacingSmall)
        .padding(.bottom, 6)
    }
}

extension PageHeader where Below == EmptyView {
    init(title: String, subtitle: String? = nil, titleDetail: String? = nil, @ViewBuilder actions: @escaping () -> Actions) {
        self.init(title: title, subtitle: subtitle, titleDetail: titleDetail, actions: actions, below: { EmptyView() })
    }
}

extension View {
    /// Puts `header` in a fixed area at the top of the page with this view (the page's
    /// scrolling content) below it. The content's scroll view starts under the header,
    /// so rows and cards never slide underneath the title and buttons. The artist
    /// backdrop still shows behind both.
    func pinnedHeader<Header: View>(@ViewBuilder _ header: () -> Header) -> some View {
        VStack(spacing: 0) {
            header()
            self.frame(maxHeight: .infinity)
        }
    }
}

/// The app's name and version, for Home's header.
enum AppInfo {
    static let name = "Sun"

    /// "v1.0", plus the build number when it isn't 1 ("v1.0 (12)"). Read from the app's
    /// Info.plist, so it follows the version set in Xcode.
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { $0 == "1" ? "v\(short)" : "v\(short) (\($0))" } ?? "v\(short)"
    }
}

/// Round glass icon-only button for page headers. The prominent one takes the
/// ambient accent and glows (Play). The title is the VoiceOver label.
struct HeaderIconButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        Button(action: action) { HeaderIconLabel(title: title, systemImage: systemImage) }
            .headerIconStyle(
                tint: prominent ? theme.ambientAccent : theme.glassTint,
                foreground: prominent ? theme.ambientAccentText : theme.text
            )
            .ambientGlow(radius: prominent ? 10 : 0, strength: prominent ? 0.4 : 0)
    }
}

/// A header icon button that opens a menu (Sort).
struct HeaderIconMenu<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        Menu(content: content) { HeaderIconLabel(title: title, systemImage: systemImage) }
            .headerIconStyle(tint: theme.glassTint, foreground: theme.text)
    }
}

/// The icon in a fixed square, so every button gets the same circle whatever the
/// symbol's width (play.fill is narrower than shuffle). Grows with the text size.
private struct HeaderIconLabel: View {
    let title: String
    let systemImage: String
    @ScaledMetric(relativeTo: .body) private var box: CGFloat = 24

    var body: some View {
        Label(title, systemImage: systemImage)
            .frame(width: box, height: box)
    }
}

private extension View {
    func headerIconStyle(tint: Color, foreground: Color) -> some View {
        self
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .buttonStyle(.glass(.regular.tint(tint)))
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .foregroundStyle(foreground)
    }
}

/// A cover with a title and a detail line on a glass card (albums, playlists,
/// genres). With `glows`, the cover gets a soft halo in the glow colors.
struct CoverCard: View {
    let artKey: String?
    let title: String
    var detail: String?
    /// Shown instead of a cover (e.g. the heart on Favorites).
    var symbol: String?
    var symbolColor: Color?
    /// Shelves use 1 so every card in a row has the same height.
    var detailLineLimit = 2

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(symbolColor ?? theme.ambientAccent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .glassCard(cornerRadius: Layout.rowArtworkCornerRadius, emphasis: 1.3, glow: false)
                } else {
                    ArtworkView(artKey: artKey, cornerRadius: Layout.rowArtworkCornerRadius)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.color(.songTitle))
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(detailLineLimit)
                }
            }
            .padding(.horizontal, 4)
            .legibleOnGlass()
        }
        .padding(10)
        .glassCard(interactive: true, glow: false)
        .accessibilityElement(children: .combine)
    }
}

/// A round artist picture with the name underneath (Artists grid, Home's Top Artists).
struct ArtistCircle: View {
    let name: String
    let artKey: String?
    var detail: String?
    var isHidden = false

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        VStack(spacing: 8) {
            ArtworkView(artKey: artKey, isCircle: true)
                .overlay {
                    Circle().strokeBorder(GlowRim.gradient(theme), lineWidth: 1.2)
                }
                .saturation(isHidden ? 0 : 1)
            VStack(spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(theme.color(.songTitle))
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .legibleOnGlass()
        }
        .opacity(isHidden ? 0.75 : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isHidden ? "Hidden" : "")
    }
}

/// A titled block on Home (and other scrolling pages): heading, optional count, content.
struct ShelfSection<Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let content: () -> Content

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacingSmall + 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(theme.color(.pageTitle))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.text.opacity(0.75))
                }
            }
            .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
            .padding(.horizontal, Layout.screenPadding)
            content()
        }
    }
}
