import UIKit
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

/// Stores cover art and artist pictures on disk in three sizes:
/// - `.full`: long side up to 2048 px, used for the sharp backdrop and large covers.
/// - `.thumb`: 256 px, used in lists and grids.
/// - `.blur`: the desktop app's pre-baked blur (shrink so the short side is 24 px,
///   then scale back up to 96 → 384 px). Scaled to fill, it gives a soft, cheap blur.
nonisolated enum ArtCache {
    enum Variant: String, Sendable {
        case full, thumb, blur
    }

    /// Decoded images kept in memory, limited by size as well as count: one decoded
    /// `.full` cover can take 16 MB, so a count limit alone could hold gigabytes.
    nonisolated(unsafe) private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()

    /// Saves image data and returns its key (a hash, so the same picture is stored once).
    ///
    /// Pictures with see-through areas (a cut-out artist on a transparent background)
    /// keep their transparency: the full and thumbnail sizes are saved as PNG instead
    /// of JPEG, which would fill the background in. `hasTransparency(_:)` tells them apart.
    static func store(_ data: Data) -> String? {
        let key = SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
        if exists(key) { return key }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let full = downsample(source, maxPixel: 2048),
              let thumb = downsample(source, maxPixel: 256) else { return nil }

        try? FileManager.default.createDirectory(at: LibraryLocations.artDirectory, withIntermediateDirectories: true)
        if isTransparent(thumb) {
            guard writeImage(full, to: url(for: key, .full, transparent: true), type: .png) else { return nil }
            _ = writeImage(thumb, to: url(for: key, .thumb, transparent: true), type: .png)
        } else {
            guard writeImage(full, to: url(for: key, .full), type: .jpeg, quality: 0.92) else { return nil }
            _ = writeImage(thumb, to: url(for: key, .thumb), type: .jpeg, quality: 0.85)
        }
        if let blurred = makeBlur(from: thumb) {
            _ = writeImage(blurred, to: url(for: key, .blur), type: .jpeg, quality: 0.9)
        }
        return key
    }

    /// Where a variant lives. Transparent pictures' full and thumbnail sizes are PNGs.
    static func url(for key: String, _ variant: Variant, transparent: Bool = false) -> URL {
        let ext = transparent && variant != .blur ? "png" : "jpg"
        return LibraryLocations.artDirectory.appending(path: "\(key)-\(variant.rawValue).\(ext)")
    }

    /// True for pictures stored with transparency (see `store(_:)`).
    static func hasTransparency(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: key, .full, transparent: true).path)
    }

    nonisolated(unsafe) private static let aspects = NSCache<NSString, NSNumber>()

    /// Width ÷ height of a stored picture, read from the file's header (no decoding),
    /// so layouts can make room for it before the image itself has loaded.
    static func aspectRatio(of key: String) -> CGFloat? {
        if let cached = aspects.object(forKey: key as NSString) { return CGFloat(cached.doubleValue) }
        let file = url(for: key, .full, transparent: hasTransparency(key))
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double, height > 0 else { return nil }
        aspects.setObject(NSNumber(value: width / height), forKey: key as NSString)
        return CGFloat(width / height)
    }

    private static func exists(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: key, .full).path) || hasTransparency(key)
    }

    /// True when an image has an alpha channel and noticeably see-through pixels.
    /// (Many opaque PNGs carry an unused alpha channel, so the pixels are checked.)
    static func isTransparent(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let side = 32
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.clear(CGRect(x: 0, y: 0, width: side, height: side))
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        // At least 2% of the picture clearly see-through.
        let clear = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] < 230 }.count
        return clear >= side * side / 50
    }

    /// The image if it's already decoded in memory (never touches the disk), so views
    /// can show it immediately.
    static func cachedImage(for key: String, _ variant: Variant) -> UIImage? {
        memory.object(forKey: "\(key)-\(variant.rawValue)" as NSString)
    }

    /// Loads an image from memory or disk. Call off the main thread for large variants.
    static func image(for key: String, _ variant: Variant) -> UIImage? {
        let cacheKey = "\(key)-\(variant.rawValue)" as NSString
        if let cached = memory.object(forKey: cacheKey) { return cached }
        let path = variant != .blur && hasTransparency(key) ? url(for: key, variant, transparent: true).path : url(for: key, variant).path
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        let decoded = image.preparingForDisplay() ?? image
        memory.setObject(decoded, forKey: cacheKey, cost: decodedBytes(decoded))
        return decoded
    }

    /// Stores image data off the main actor (used for artist pictures picked in Photos).
    @concurrent
    static func storeInBackground(_ data: Data) async -> String? {
        store(data)
    }

    /// Async wrapper that keeps disk reads and decoding off the main actor.
    @concurrent
    static func load(_ key: String, _ variant: Variant) async -> UIImage? {
        image(for: key, variant)
    }

    /// Memory a decoded image occupies (4 bytes per pixel).
    private static func decodedBytes(_ image: UIImage) -> Int {
        if let cgImage = image.cgImage { return cgImage.bytesPerRow * cgImage.height }
        return Int(image.size.width * image.scale * image.size.height * image.scale) * 4
    }

    // MARK: Image processing

    private static func downsample(_ source: CGImageSource, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Desktop blur recipe: 24 px short side → 96 → 384, smoothing on each step.
    static func makeBlur(from image: CGImage) -> CGImage? {
        var current = image
        for shortSide in [24.0, 96.0, 384.0] {
            guard let next = resize(current, shortSide: shortSide) else { return nil }
            current = next
        }
        return current
    }

    private static func resize(_ image: CGImage, shortSide: Double) -> CGImage? {
        let width = Double(image.width), height = Double(image.height)
        let scale = shortSide / max(min(width, height), 1)
        let size = CGSize(width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    /// Writes a JPEG (with `quality`) or a PNG (keeps transparency).
    private static func writeImage(_ image: CGImage, to url: URL, type: UTType, quality: Double = 0.9) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            return false
        }
        let options: [CFString: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: quality] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
