import SwiftUI
import ImageIO

/// Sets how a picked photo becomes the artist's image: shown behind the player while
/// their songs play and across the top of their page. (Circles in lists show the
/// artist's latest album cover.) How it looks can be fine-tuned later with Adjust Background….
/// The framings:
/// - **Whole Picture**: the entire image at its own shape, uncropped.
/// - **Screen**: pinch and drag to choose a section shaped like the phone's screen,
///   so it fills the backdrop exactly.
/// - **Square**: pinch and drag to choose a square section.
/// Transparent areas are kept (saved as PNG), so a cut-out artist stays cut out.
struct ArtistImageCropper: View {
    enum Framing: String, CaseIterable, Identifiable {
        case whole = "Whole Picture"
        case screen = "Screen"
        case square = "Square"
        var id: String { rawValue }

        /// Width ÷ height of the saved picture (`nil`: the image's own shape).
        var aspect: CGFloat? {
            switch self {
            case .whole: nil
            // An iPhone screen in portrait (430 × 932 pt on a 15 Pro Max).
            case .screen: 430.0 / 932.0
            case .square: 1
            }
        }
    }

    let image: UIImage
    let artistName: String
    let onSave: (Data) -> Void

    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var framing: Framing = .whole
    @State private var scale: CGFloat = 1
    @State private var steadyScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero
    @State private var frameSize: CGSize = .zero

    private static let maxScale: CGFloat = 6
    /// Long side of the saved picture in pixels (the art cache keeps up to 2048 px).
    private static let outputLongSide: CGFloat = 2048

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                ChipPicker(options: Framing.allCases, selection: $framing) { $0.rawValue }

                GeometryReader { geometry in
                    let size = Self.frameSize(for: framing, image: image.size, in: geometry.size)
                    cropArea(size: size)
                        .frame(width: size.width, height: size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear { frameSize = size }
                        .onChange(of: size) { frameSize = size }
                }
                .padding(.horizontal, 16)

                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button("Reset", systemImage: "arrow.counterclockwise") { resetPosition(animated: true) }
                    .disabled(framing == .whole || (scale == 1 && offset == .zero))
            }
            .padding(.vertical, 16)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Artist Image")
            .navigationSubtitle(artistName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let data = render() { onSave(data) }
                        dismiss()
                    }
                    .tint(theme.ambientAccent)
                }
            }
            .onChange(of: framing) { resetPosition(animated: false) }
        }
        .preferredColorScheme(.dark)
    }

    private var hint: String {
        switch framing {
        case .whole: "The whole picture is used at its own shape, behind the player and at the top of the artist's page."
        case .screen: "Pinch to zoom, drag to move. The frame is the shape of your screen, so this part fills the background."
        case .square: "Pinch to zoom, drag to move. This square shows behind the player and at the top of the artist's page."
        }
    }

    private func resetPosition(animated: Bool) {
        withAnimation(animated ? .snappy : nil) {
            scale = 1; steadyScale = 1
            offset = .zero; steadyOffset = .zero
        }
    }

    @ViewBuilder
    private func cropArea(size: CGSize) -> some View {
        let base = Self.fillSize(for: image.size, frame: size)
        ZStack {
            // Shows see-through areas of transparent pictures.
            Checkerboard()
            Image(uiImage: image)
                .resizable()
                .frame(width: base.width, height: base.height)
                .scaleEffect(scale)
                .offset(offset)
            Rectangle()
                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(.rect)
        .gesture(framing == .whole ? nil : cropGesture(base: base, frame: size))
        .accessibilityLabel(framing == .whole ? "Whole picture" : "Photo crop area")
        .accessibilityHint(framing == .whole ? "" : "Pinch to zoom and drag to choose the part of the photo to use.")
    }

    private func cropGesture(base: CGSize, frame: CGSize) -> some Gesture {
        SimultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    scale = min(max(steadyScale * value.magnification, 1), Self.maxScale)
                    offset = Self.clamped(offset, base: base, scale: scale, frame: frame)
                }
                .onEnded { _ in
                    steadyScale = scale
                    steadyOffset = offset
                },
            DragGesture()
                .onChanged { value in
                    let proposed = CGSize(width: steadyOffset.width + value.translation.width,
                                          height: steadyOffset.height + value.translation.height)
                    offset = Self.clamped(proposed, base: base, scale: scale, frame: frame)
                }
                .onEnded { _ in steadyOffset = offset }
        )
    }

    // MARK: Geometry

    /// The crop frame: the framing's shape (or the image's, for Whole Picture), as
    /// large as fits in `available`.
    static func frameSize(for framing: Framing, image: CGSize, in available: CGSize) -> CGSize {
        let aspect = framing.aspect ?? (image.height > 0 ? image.width / image.height : 1)
        guard available.width > 0, available.height > 0, aspect > 0 else { return .zero }
        let width = min(available.width, available.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    /// The image's size when it just fills `frame` (like `scaledToFill`).
    static func fillSize(for size: CGSize, frame: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return frame }
        let ratio = max(frame.width / size.width, frame.height / size.height)
        return CGSize(width: size.width * ratio, height: size.height * ratio)
    }

    /// Keeps the photo covering the whole frame (no empty edges).
    static func clamped(_ offset: CGSize, base: CGSize, scale: CGFloat, frame: CGSize) -> CGSize {
        let maxX = max((base.width * scale - frame.width) / 2, 0)
        let maxY = max((base.height * scale - frame.height) / 2, 0)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }

    /// Draws exactly what's inside the frame, at up to 2048 px on its long side. PNG
    /// when the picture has see-through areas (keeps them), JPEG otherwise.
    private func render() -> Data? {
        let frame = frameSize
        guard frame.width > 0, frame.height > 0 else { return nil }
        let pixelLong = framing == .whole
            ? min(Self.outputLongSide, max(image.size.width * image.scale, image.size.height * image.scale))
            : Self.outputLongSide
        let factor = pixelLong / max(frame.width, frame.height)
        let output = CGSize(width: (frame.width * factor).rounded(), height: (frame.height * factor).rounded())
        let base = Self.fillSize(for: image.size, frame: frame)
        let drawn = CGSize(width: base.width * scale * factor, height: base.height * scale * factor)
        let origin = CGPoint(
            x: (output.width - drawn.width) / 2 + offset.width * factor,
            y: (output.height - drawn.height) / 2 + offset.height * factor
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: output, format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: drawn))
        }
        if let cgImage = rendered.cgImage, ArtCache.isTransparent(cgImage) {
            return rendered.pngData()
        }
        return rendered.jpegData(compressionQuality: 0.92)
    }

    /// Decodes a picked photo at no more than 3000 px on its long side, off the main thread.
    @concurrent
    static func downsampled(_ data: Data) async -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3000,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// A grey checkerboard, the usual sign for "see-through here".
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 12
            for row in 0..<Int((size.height / cell).rounded(.up)) {
                for column in 0..<Int((size.width / cell).rounded(.up)) {
                    let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(Path(rect), with: .color((row + column).isMultiple(of: 2) ? Color(white: 0.22) : Color(white: 0.3)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
