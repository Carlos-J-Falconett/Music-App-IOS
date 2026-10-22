import SwiftUI
import SwiftData

/// The artist images currently shown behind the interface. Shared by every
/// screen so navigating never reloads or flashes the backdrop.
@Observable
final class BackdropModel {
    struct Shown: Equatable {
        let key: String
        let blurred: UIImage?
        let sharp: UIImage?
        /// An artist (or group) picture rather than an album cover.
        var isArtistImage = false
        /// A picture with see-through areas (e.g. a cut-out artist).
        var isTransparent = false
        /// The playing song's primary artist, whose background settings apply.
        var artistKey: String?
    }

    var shown: Shown?
}

/// The see-through artist backdrop behind every screen, for the playing song. Drawn
/// by `StyledBackdrop` with the artist's background settings (Adjust Background…),
/// or the standard look when they have none.
struct BackdropView: View {
    @Environment(BackdropModel.self) private var model
    @Environment(ThemeStore.self) private var theme
    @Environment(LibraryIndexStore.self) private var library
    @Query private var styles: [ArtistBackdropStyle]

    var body: some View {
        ZStack {
            theme.window

            if let shown = model.shown {
                StyledBackdrop(
                    blurred: shown.blurred, sharp: shown.sharp, isTransparent: shown.isTransparent,
                    style: style(for: shown),
                    glowPrimary: theme.glowPrimary, glowSecondary: theme.glowSecondary
                )
                .id(shown.key)
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func style(for shown: BackdropModel.Shown) -> BackdropStyle {
        shown.artistKey.flatMap { ArtistArtwork.style(for: $0, styles: ArtistArtwork.styleMap(styles), index: library.index) }
            ?? .standard(isArtistImage: shown.isArtistImage, isTransparent: shown.isTransparent)
    }
}

/// An artist page's own picture, loaded by the page.
struct ArtistHeroImage: Equatable {
    let key: String
    let blurred: UIImage?
    let sharp: UIImage
    let isTransparent: Bool
    /// An artist (or group) picture rather than an album cover.
    var isArtistImage = true
    /// Glow colors taken from this picture (not the playing song's).
    var colors: ArtworkPalette.Colors?
    /// Width ÷ height.
    var aspect: CGFloat { sharp.size.width / sharp.size.height }
}

/// Behind an artist's page: their picture standing on the bottom edge of the screen,
/// fixed in place (wherever the discography starts) so the list scrolls up over it.
/// Uses the page's own glow colors (with Match Artwork on), not the playing song's.
struct ArtistPageBackdrop: View {
    let image: ArtistHeroImage
    let style: BackdropStyle

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        let match = theme.palette.matchArtwork
        StyledBackdrop(
            blurred: image.blurred, sharp: image.sharp, isTransparent: image.isTransparent,
            style: style, placement: .artistPage,
            glowPrimary: match ? (image.colors?.primary.color ?? theme.glowPrimary) : theme.glowPrimary,
            glowSecondary: match ? (image.colors?.secondary.color ?? theme.glowSecondary) : theme.glowSecondary
        )
    }
}

extension BackdropStyle {
    /// The framing for a place: behind the player, or at the top of the artist page.
    func framing(for placement: StyledBackdrop.Placement) -> BackdropFraming {
        switch placement {
        case .screen: player
        case .artistPage: page
        }
    }

    /// Sets the framing for a place.
    mutating func setFraming(_ framing: BackdropFraming, for placement: StyledBackdrop.Placement) {
        switch placement {
        case .screen: player = framing
        case .artistPage: page = framing
        }
    }
}

/// Draws a backdrop picture with a `BackdropStyle`, layered like the desktop
/// `backdrop.py` (bottom to top):
/// 1. window color
/// 2. the pre-blurred image filling the screen, at the style's blur (a soft wash of the
///    glow colors instead, for transparent pictures)
/// 3. a veil in Backdrop Dim at the style's strength (over the area around the picture)
/// 4. the sharp image, placed by `pictureFrame` (whole at its own shape, or filling the
///    screen), moved and zoomed by the style, at its brightness, its top and bottom
///    faded into the blur.
///    Transparent pictures get a glow in the glow colors traced around their outline.
struct StyledBackdrop: View {
    enum Placement: Equatable {
        /// Behind the player and every page: the whole screen.
        case screen
        /// An artist page: the picture stands on the screen's bottom edge.
        case artistPage
    }

    let blurred: UIImage?
    let sharp: UIImage?
    let isTransparent: Bool
    let style: BackdropStyle
    var placement: Placement = .screen
    let glowPrimary: Color
    let glowSecondary: Color

    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                theme.window
                if isTransparent {
                    // A transparent picture's blurred copy would just be a smudged cut-out,
                    // so a soft wash of the glow colors sits behind it instead.
                    RadialGradient(colors: [glowPrimary.opacity(0.45), glowSecondary.opacity(0.2), .clear],
                                   center: washCenter(in: size, aspect: sharp.map { $0.size.width / max($0.size.height, 1) }),
                                   startRadius: 0, endRadius: 520)
                } else if let blurred {
                    Color.clear
                        .overlay {
                            Image(uiImage: blurred)
                                .resizable()
                                .scaledToFill()
                                .blur(radius: style.blur)
                        }
                        .clipped()
                }
                theme.color(.backdropDim).opacity(style.dim)
                if let sharp, sharp.size.height > 0 {
                    let rect = Self.pictureFrame(imageAspect: sharp.size.width / sharp.size.height, in: size,
                                                 style: style, placement: placement)
                    picture(sharp, fades: fades(for: rect))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// The glow-color wash sits behind the picture's middle.
    private func washCenter(in size: CGSize, aspect: CGFloat?) -> UnitPoint {
        guard let aspect, size.width > 0, size.height > 0 else { return .center }
        let rect = Self.pictureFrame(imageAspect: aspect, in: size, style: style, placement: placement)
        return UnitPoint(x: rect.midX / size.width, y: rect.midY / size.height)
    }

    /// Where the sharp picture goes on a screen of `size`, after the style's zoom and move.
    /// - Behind the player: centered on the screen, as large as fits (Whole Picture,
    ///   never cropped) or covering it (Fill Screen, edges cropped). Zoom grows it
    ///   around its center.
    /// - Artist page: the same sizes, but standing on the screen's bottom edge, however
    ///   tall the picture is and wherever the discography starts. Whole Picture spans the
    ///   full width. Zoom grows it upward from the bottom edge, so it stays standing there.
    /// The style's move is added last, as a fraction of the screen.
    static func pictureFrame(imageAspect aspect: CGFloat, in size: CGSize, style: BackdropStyle, placement: Placement) -> CGRect {
        guard aspect > 0, size.width > 0, size.height > 0 else { return .zero }
        let framing = style.framing(for: placement)
        let width: CGFloat
        switch (framing.fillsScreen, placement) {
        case (true, _): width = max(size.width, size.height * aspect)
        case (false, .screen): width = min(size.width, size.height * aspect)
        case (false, .artistPage): width = size.width
        }
        let zoomed = CGSize(width: width * framing.zoom, height: width / aspect * framing.zoom)
        let x = (size.width - zoomed.width) / 2 + framing.offsetX * size.width
        let y: CGFloat = switch placement {
        case .screen: (size.height - zoomed.height) / 2
        case .artistPage: size.height - zoomed.height
        }
        return CGRect(x: x, y: y + framing.offsetY * size.height, width: zoomed.width, height: zoomed.height)
    }

    /// How much of the picture's top and bottom fades. Behind the player both use the
    /// style's Edge Fade. On an artist page the top always fades at least 12% into the
    /// blur above it (none for cut-outs, whose edges are already see-through).
    private func fades(for rect: CGRect) -> (top: Double, bottom: Double) {
        let fade = style.edgeFade
        guard placement == .artistPage, !isTransparent else { return (fade, fade) }
        return (max(fade, 0.12), fade)
    }

    @ViewBuilder
    private func picture(_ image: UIImage, fades: (top: Double, bottom: Double)) -> some View {
        let faded = Image(uiImage: image)
            .resizable()
            .brightness(style.brightness)
            .mask {
                LinearGradient(stops: [
                    .init(color: fades.top > 0 ? .clear : .black, location: 0),
                    .init(color: .black, location: fades.top),
                    .init(color: .black, location: 1 - fades.bottom),
                    .init(color: fades.bottom > 0 ? .clear : .black, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
        if isTransparent {
            // The glow follows the picture's own outline: shadows of an image with
            // transparency take the shape of its visible pixels.
            let glow = reduceTransparency ? 0 : style.glow
            faded
                .shadow(color: glowPrimary.opacity(min(0.85 * glow, 1)), radius: 6)
                .shadow(color: glowPrimary.opacity(min(0.55 * glow, 1)), radius: 18)
                .shadow(color: glowSecondary.opacity(min(0.45 * glow, 1)), radius: 36)
        } else {
            faded
        }
    }
}

extension View {
    /// Keeps `BackdropModel` in sync with the playing song. Apply once, at the root.
    func backdropLoader() -> some View {
        modifier(BackdropLoader())
    }
}

/// Picks the backdrop image: the song's primary artist's picture, else their group's
/// picture (TWICE members use TWICE's until they get their own), else the song's
/// album cover. It only changes when the picture changes, then crossfades over 800 ms
/// once both image versions are loaded.
private struct BackdropLoader: ViewModifier {
    @Environment(MusicPlayer.self) private var player
    @Environment(BackdropModel.self) private var model
    @Environment(LibraryIndexStore.self) private var library
    @Query private var artistImages: [ArtistImage]

    func body(content: Content) -> some View {
        content.task(id: identity) { await loadImages() }
    }

    private var identity: String {
        guard let track = player.currentTrack else { return "" }
        return library.index.primaryKey(of: track) + "|" + (imageKey(for: track) ?? "")
    }

    private func imageKey(for track: Track) -> String? {
        let index = library.index
        // The artist's image (or their group's), else the album cover.
        return ArtistArtwork.customKey(for: index.primaryKey(of: track), images: ArtistArtwork.imageMap(artistImages), index: index)
            ?? track.coverKey
    }

    private func loadImages() async {
        guard let track = player.currentTrack, let key = imageKey(for: track) else {
            withAnimation(.easeInOut(duration: 0.8)) { model.shown = nil }
            return
        }
        guard model.shown?.key != key else { return }
        async let blurred = ArtCache.load(key, .blur)
        async let sharp = ArtCache.load(key, .full)
        let images = await (blurred, sharp)
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.8)) {
            model.shown = BackdropModel.Shown(
                key: key, blurred: images.0, sharp: images.1,
                isArtistImage: key != track.coverKey,
                isTransparent: ArtCache.hasTransparency(key),
                artistKey: library.index.primaryKey(of: track)
            )
        }
    }
}
