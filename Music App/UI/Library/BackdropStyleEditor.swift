import SwiftUI

/// Artist page → … → Adjust Background…: changes how this artist's background looks,
/// with a full-screen live preview of either the player's backdrop or the top of
/// their page.
/// - Drag the picture to move it, pinch to zoom.
/// - Whole Picture (its own shape, never cropped) or Fill Screen (edges cropped).
/// The position, zoom and fit are separate for the player and the artist page: the
/// preview chip picks which one is being edited. The rest of the look is shared.
/// - Brightness (the picture), Dim and Blur (the area around it), Edge Fade, and Glow
///   (transparent cut-outs only).
/// Saving the standard look removes the artist's settings (members then use their group's).
struct BackdropStyleEditor: View {
    enum Preview: String, CaseIterable, Identifiable {
        case player = "Player"
        case page = "Artist Page"
        var id: String { rawValue }
    }

    enum Fit: String, CaseIterable, Identifiable {
        case whole = "Whole Picture"
        case fill = "Fill Screen"
        var id: String { rawValue }
    }

    let artistName: String
    let image: ArtistHeroImage
    /// The look to start from: the artist's current settings.
    @State var style: BackdropStyle
    /// The look without any settings, for Reset.
    let standard: BackdropStyle
    /// The new look, or `nil` to go back to the standard one.
    let onSave: (BackdropStyle?) -> Void

    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var preview: Preview = .player
    @State private var showsControls = true
    @State private var steadyZoom: Double?
    @State private var steadyOffset: CGSize?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let screen = geometry.size
                let heroHeight = ArtistArtwork.heroHeight(imageAspect: image.aspect, screen: screen, fillsScreen: style.page.fillsScreen)
                ZStack(alignment: .topLeading) {
                    StyledBackdrop(
                        blurred: image.blurred, sharp: image.sharp, isTransparent: image.isTransparent,
                        style: style, placement: placement,
                        glowPrimary: glowPrimary, glowSecondary: glowSecondary
                    )
                    if preview == .page {
                        // Where the name sits on the real page, so the picture can be framed around it.
                        Text(artistName)
                            .font(.largeTitle.weight(.heavy))
                            .foregroundStyle(theme.color(.pageTitle))
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                            .shadow(color: .black.opacity(0.45), radius: 12)
                            .padding(.leading, 16)
                            .padding(.top, max(heroHeight - 56, 0))
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(.rect)
                .gesture(moveAndZoom(in: screen))
                .accessibilityElement()
                .accessibilityLabel("Background preview")
                .accessibilityHint("Drag to move the picture, pinch to zoom.")
            }
            .ignoresSafeArea()
            .safeAreaInset(edge: .bottom) {
                if showsControls {
                    controls
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Background")
            .navigationSubtitle(artistName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(style == standard ? nil : style)
                        dismiss()
                    }
                    .tint(theme.ambientAccentLight)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(showsControls ? "Hide Controls" : "Show Controls",
                           systemImage: showsControls ? "chevron.down" : "slider.horizontal.3") {
                        withAnimation(Motion.standard) { showsControls.toggle() }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// The place whose position, zoom and fit are being edited.
    private var placement: StyledBackdrop.Placement { preview == .page ? .artistPage : .screen }

    /// The framing being edited (the player's or the artist page's).
    private var framing: BackdropFraming {
        get { style.framing(for: placement) }
        nonmutating set { style.setFraming(newValue, for: placement) }
    }

    /// The other place's framing, for "Copy Position from …".
    private var otherPlacement: StyledBackdrop.Placement { placement == .screen ? .artistPage : .screen }

    /// The picture's own colors with Match Artwork on (they're what glows while this
    /// artist plays), else the theme's.
    private var glowPrimary: Color {
        theme.palette.matchArtwork ? (image.colors?.primary.color ?? theme.glowPrimary) : theme.glowPrimary
    }
    private var glowSecondary: Color {
        theme.palette.matchArtwork ? (image.colors?.secondary.color ?? theme.glowSecondary) : theme.glowSecondary
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Compact chips, grouped at the leading edge (not spread across the panel).
            ChipPicker(options: Preview.allCases, selection: $preview) { $0.rawValue }
                .fixedSize(horizontal: true, vertical: false)
            ChipPicker(options: Fit.allCases, selection: fit) { $0.rawValue }
                .fixedSize(horizontal: true, vertical: false)
            Text(preview == .page
                 ? "Position, zoom and fit apply to the artist page."
                 : "Position, zoom and fit apply behind the player.")
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)

            StyleSlider(title: "Brightness", value: $style.brightness, range: BackdropStyle.brightnessRange, percentOf: 1, signed: true)
            StyleSlider(title: "Dim", value: $style.dim, range: BackdropStyle.dimRange, percentOf: 1)
            StyleSlider(title: "Blur", value: $style.blur, range: BackdropStyle.blurRange, percentOf: BackdropStyle.blurRange.upperBound)
            StyleSlider(title: "Edge Fade", value: $style.edgeFade, range: BackdropStyle.edgeFadeRange, percentOf: 1)
            if image.isTransparent {
                StyleSlider(title: "Glow", value: $style.glow, range: BackdropStyle.glowRange, percentOf: 1)
            }

            HStack {
                Text("Drag to move · pinch to zoom")
                    .font(.footnote)
                    .foregroundStyle(theme.secondaryText)
                Spacer(minLength: 8)
                Menu("Reset", systemImage: "arrow.counterclockwise") {
                    Button("Reset Position & Zoom") {
                        withAnimation(Motion.standard) {
                            framing.zoom = 1; framing.offsetX = 0; framing.offsetY = 0
                        }
                    }
                    Button(preview == .page ? "Copy from Player" : "Copy from Artist Page") {
                        withAnimation(Motion.standard) { framing = style.framing(for: otherPlacement) }
                    }
                    Button("Reset Everything", role: .destructive) {
                        withAnimation(Motion.standard) { style = standard }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .tint(theme.ambientAccentLight)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: Layout.cardCornerRadius, emphasis: 1.3)
    }

    private var fit: Binding<Fit> {
        Binding(
            get: { framing.fillsScreen ? .fill : .whole },
            set: { new in withAnimation(Motion.standard) { framing.fillsScreen = new == .fill } }
        )
    }

    /// Drag moves the picture (as a fraction of the screen), pinch zooms it.
    private func moveAndZoom(in screen: CGSize) -> some Gesture {
        SimultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard screen.width > 0, screen.height > 0 else { return }
                    let start = steadyOffset ?? CGSize(width: framing.offsetX, height: framing.offsetY)
                    steadyOffset = start
                    framing.offsetX = (start.width + value.translation.width / screen.width).clamped(to: BackdropStyle.offsetRange)
                    framing.offsetY = (start.height + value.translation.height / screen.height).clamped(to: BackdropStyle.offsetRange)
                }
                .onEnded { _ in steadyOffset = nil },
            MagnifyGesture()
                .onChanged { value in
                    let start = steadyZoom ?? framing.zoom
                    steadyZoom = start
                    framing.zoom = (start * value.magnification).clamped(to: BackdropStyle.zoomRange)
                }
                .onEnded { _ in steadyZoom = nil }
        )
    }
}

/// A labelled slider with its value as a percentage.
private struct StyleSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// The value shown as 100%.
    let percentOf: Double
    /// Shows "+" for values above zero (Brightness).
    var signed = false

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.text)
                .frame(width: 94, alignment: .leading)
            Slider(value: $value, in: range)
                .tint(theme.ambientAccent)
                .accessibilityLabel(title)
                .accessibilityValue(percentText)
            Text(percentText)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var percentText: String {
        let percent = Int((value / percentOf * 100).rounded())
        return "\(signed && percent > 0 ? "+" : "")\(percent)%"
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
