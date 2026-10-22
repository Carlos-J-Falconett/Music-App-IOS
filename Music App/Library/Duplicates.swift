import Foundation

/// Which copy of a song stays when the library has several (Settings → Duplicates).
/// The other copies stay on the phone but are left out of lists, search, shuffle and
/// artist pages; switching the setting brings them back at once.
enum DuplicatePreference: String, CaseIterable, Identifiable {
    /// Any lossless copy beats a compressed one; among equals, the one imported first.
    case lossless
    /// Lossless first, then the highest sample rate and bit depth (hi-res), then the
    /// highest bitrate; among equals, the one imported first.
    case bestQuality

    static let storageKey = "duplicatePreference"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lossless: "Lossless"
        case .bestQuality: "Best Quality"
        }
    }

    var detail: String {
        switch self {
        case .lossless: "Keeps a lossless copy (FLAC, ALAC, WAV, AIFF) over MP3 or AAC. Between two lossless copies, the one added first stays."
        case .bestQuality: "Keeps the best copy: lossless first, then the highest sample rate and bit depth (hi-res), then the highest bitrate."
        }
    }
}

/// Finds songs that are in the library more than once: the same title and main artist,
/// with lengths within 3 seconds. So a single and its album version match, while live
/// versions and remixes (different lengths) don't.
nonisolated enum DuplicateFinder {
    struct Candidate: Sendable {
        let id: UUID
        let title: String
        /// The main artist's key (from the artist index).
        let artistKey: String
        let duration: Double
        let isLossless: Bool
        let format: AudioFormat?
        let addedAt: Date
    }

    static let durationTolerance = 3.0

    /// Each hidden copy, mapped to the copy kept in its place.
    static func hiddenCopies(_ candidates: [Candidate], keeping preference: DuplicatePreference) -> [UUID: UUID] {
        // Songs with an unknown length (0) can't be matched safely.
        let groups = Dictionary(grouping: candidates.filter { $0.duration > 0 }) {
            "\($0.artistKey)\u{1F}\(normalizedTitle($0.title))"
        }
        var hidden: [UUID: UUID] = [:]
        for group in groups.values where group.count > 1 {
            // Within a title, copies whose lengths are within 3 s of the cluster's first.
            var cluster: [Candidate] = []
            for candidate in group.sorted(by: { $0.duration < $1.duration }) {
                if let first = cluster.first, candidate.duration - first.duration > durationTolerance {
                    resolve(cluster, preference, into: &hidden)
                    cluster = []
                }
                cluster.append(candidate)
            }
            resolve(cluster, preference, into: &hidden)
        }
        return hidden
    }

    private static func resolve(_ cluster: [Candidate], _ preference: DuplicatePreference, into hidden: inout [UUID: UUID]) {
        guard cluster.count > 1,
              let keep = cluster.max(by: { isBetter($1, than: $0, preference) }) else { return }
        for copy in cluster where copy.id != keep.id { hidden[copy.id] = keep.id }
    }

    /// True when `a` should be kept over `b`.
    static func isBetter(_ a: Candidate, than b: Candidate, _ preference: DuplicatePreference) -> Bool {
        if a.isLossless != b.isLossless { return a.isLossless }
        if preference == .bestQuality {
            let qa = (a.format?.sampleRate ?? 0, a.format?.bitDepth ?? 0, a.format?.bitRate ?? 0)
            let qb = (b.format?.sampleRate ?? 0, b.format?.bitDepth ?? 0, b.format?.bitRate ?? 0)
            if qa != qb { return qa > qb }
        }
        // The copy imported first stays (then a stable order, so the choice never flips).
        if a.addedAt != b.addedAt { return a.addedAt < b.addedAt }
        return a.id.uuidString < b.id.uuidString
    }

    /// Titles compared without case, accents or extra spaces.
    static func normalizedTitle(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
