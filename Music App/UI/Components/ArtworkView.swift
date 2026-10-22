import SwiftUI

/// Shows a cached cover or artist image, loading it off the main thread.
/// Falls back to a music-note placeholder tinted with the theme's panel color.
struct ArtworkView: View {
    let artKey: String?
    var variant: ArtCache.Variant = .thumb
    var cornerRadius: CGFloat = 8
    var isCircle = false

    @Environment(ThemeStore.self) private var theme
    @State private var image: UIImage?

    var body: some View {
        // Already in memory (e.g. scrolling back up a grid): shown on the first frame,
        // with no placeholder flash while the task runs.
        let shown = image ?? artKey.flatMap { ArtCache.cachedImage(for: $0, variant) }
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let shown {
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFill()
                        // Transparent artist pictures sit on the panel color instead of
                        // showing whatever is behind the circle or card.
                        .background(theme.panels)
                } else {
                    ZStack {
                        theme.panels.opacity(0.8)
                        Image(systemName: "music.note")
                            .font(.title2)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .clipShape(clipShape)
            .task(id: artKey) {
                guard let artKey else {
                    image = nil
                    return
                }
                if let cached = ArtCache.cachedImage(for: artKey, variant) {
                    image = cached
                } else {
                    image = nil   // don't keep showing the previous key's picture
                    image = await ArtCache.load(artKey, variant)
                }
            }
            .accessibilityHidden(true)
    }

    private var clipShape: AnyShape {
        isCircle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
