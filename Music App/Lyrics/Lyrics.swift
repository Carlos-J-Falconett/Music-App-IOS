import Foundation

/// A song's lyrics: synced lines (with the time each one is sung) or plain text.
/// Follows the desktop app's `lyrics.py`.
nonisolated struct Lyrics: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case synced, plain
    }

    struct Line: Codable, Sendable, Equatable, Hashable {
        /// Seconds into the song (`nil` for plain lyrics).
        var time: Double?
        var text: String
    }

    var kind: Kind
    var lines: [Line]
    /// Where they came from: "embedded", "lrclib", "demo" (later a local server).
    var source: String

    var isSynced: Bool { kind == .synced }

    /// Lyrics from raw text that may or may not be LRC: three or more timed lines make
    /// synced lyrics, anything else is plain. `nil` for empty text.
    static func from(text: String, source: String) -> Lyrics? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let synced = LRC.parse(trimmed)
        if synced.count >= 3 {
            return Lyrics(kind: .synced, lines: synced, source: source)
        }
        let plain = trimmed.components(separatedBy: .newlines).map {
            Line(time: nil, text: $0.trimmingCharacters(in: .whitespaces))
        }
        return Lyrics(kind: .plain, lines: plain, source: source)
    }

    /// The line being sung at `time` (highlighted slightly early, so it feels on time),
    /// or `nil` before the first line and for plain lyrics.
    func currentLineIndex(at time: Double, lead: Double = 0.15) -> Int? {
        guard isSynced, !lines.isEmpty else { return nil }
        let target = time + lead
        // The last line starting at or before the target (lines are sorted by time).
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if (lines[mid].time ?? 0) <= target {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// A title or artist without "feat. …" / "(with …)" parts, which confuse lookups.
    static func cleanName(_ name: String) -> String {
        name.replacing(/\s*[\(\[]?\s*(?i:feat\.?|ft\.?|featuring|with)\s.*$/, with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// LRC (timed lyrics) parsing, like the desktop's `parse_lrc`.
nonisolated enum LRC {
    /// Time-ordered lines. Handles several `[mm:ss.xx]` tags on one line, `ss:xx` and
    /// `ss.xxx` fractions, and the `[offset:ms]` tag; other `[xx:...]` metadata lines
    /// (title, artist…) are skipped.
    static func parse(_ text: String) -> [Lyrics.Line] {
        let timeTag = /\[(\d+):(\d{1,2}(?:[.:]\d{1,3})?)\]/
        let metaTag = /^\[(\w+):(.*)\]\s*$/
        var offset = 0.0
        var lines: [Lyrics.Line] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let tags = line.matches(of: timeTag)
            guard !tags.isEmpty else {
                if let meta = line.wholeMatch(of: metaTag), meta.1.lowercased() == "offset",
                   let ms = Double(meta.2.trimmingCharacters(in: .whitespaces)) {
                    offset = ms / 1000
                }
                continue
            }
            let words = line.replacing(timeTag, with: "").trimmingCharacters(in: .whitespaces)
            for tag in tags {
                let minutes = Double(tag.1) ?? 0
                let seconds = Double(tag.2.replacingOccurrences(of: ":", with: ".")) ?? 0
                lines.append(Lyrics.Line(time: max(minutes * 60 + seconds - offset, 0), text: words))
            }
        }
        // Stable for equal times, so repeated choruses keep their order.
        return lines.enumerated()
            .sorted { ($0.element.time ?? 0, $0.offset) < ($1.element.time ?? 0, $1.offset) }
            .map(\.element)
    }
}
