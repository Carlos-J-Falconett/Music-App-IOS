import Foundation

/// A plain copy of a `ListenSession`, so the stats math is easy to test.
nonisolated struct SessionRecord: Sendable {
    var start: Date
    var seconds: Double
    var counted: Bool
    var trackID: UUID
    var title: String
    var artist: String
    var album: String
    var genre: String
    /// The individual artists on the song ("Bad Bunny & Chuwi" → both). Empty means
    /// just `artist`. Filled in by the Stats screen using the library's credit rules.
    var artists: [String] = []

    /// Who gets credit for this session in the artist stats.
    var creditedArtists: [String] { artists.isEmpty ? [artist] : artists }
}

/// Rolling periods, like the desktop app (7 / 30 / 365 days, or all time).
nonisolated enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case week, month, year, allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .allTime: "All Time"
        }
    }

    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .year: 365
        case .allTime: nil
        }
    }
}

/// One entry in a top list.
nonisolated struct RankedItem: Identifiable, Sendable, Equatable {
    var id: String
    var title: String
    var subtitle: String?
    var seconds: Double
    var plays: Int
    /// Share of the period's total listening time (0…1).
    var fraction: Double
}

/// Totals and top lists for one period.
nonisolated struct StatsSummary: Sendable {
    var totalSeconds: Double = 0
    var plays = 0
    var songCount = 0
    var artistCount = 0
    var topArtists: [RankedItem] = []
    var topAlbums: [RankedItem] = []
    var topSongs: [RankedItem] = []
    var topGenres: [RankedItem] = []

    init(records: [SessionRecord], period: StatsPeriod, now: Date = .now, limit: Int = 5) {
        let inPeriod: [SessionRecord]
        if let days = period.days {
            let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
            inPeriod = records.filter { $0.start >= cutoff }
        } else {
            inPeriod = records
        }

        totalSeconds = inPeriod.reduce(0) { $0 + $1.seconds }
        plays = inPeriod.filter(\.counted).count
        songCount = Set(inPeriod.map(\.trackID)).count
        artistCount = Set(inPeriod.flatMap { $0.creditedArtists.map(Track.key(for:)) }).count

        let total = max(totalSeconds, 1)
        func rank(_ key: (SessionRecord) -> String, title: (SessionRecord) -> String, subtitle: (SessionRecord) -> String?) -> [RankedItem] {
            Dictionary(grouping: inPeriod, by: key)
                .map { id, sessions in
                    let seconds = sessions.reduce(0) { $0 + $1.seconds }
                    return RankedItem(
                        id: id, title: title(sessions[0]), subtitle: subtitle(sessions[0]),
                        seconds: seconds, plays: sessions.filter(\.counted).count, fraction: seconds / total
                    )
                }
                .sorted { ($0.seconds, $1.title) > ($1.seconds, $0.title) }
                .prefix(limit)
                .map { $0 }
        }

        // Every credited artist gets the session's time, so "Bad Bunny & Chuwi" counts
        // for both instead of being its own artist.
        topArtists = Dictionary(grouping: inPeriod.flatMap { record in record.creditedArtists.map { (name: $0, record: record) } },
                                by: { Track.key(for: $0.name) })
            .map { key, entries in
                let seconds = entries.reduce(0) { $0 + $1.record.seconds }
                return RankedItem(id: key, title: entries[0].name, subtitle: nil, seconds: seconds,
                                  plays: entries.filter(\.record.counted).count, fraction: min(seconds / total, 1))
            }
            .sorted { ($0.seconds, $1.title) > ($1.seconds, $0.title) }
            .prefix(limit)
            .map { $0 }
        topAlbums = rank({ Track.key(for: $0.artist) + "|" + $0.album }, title: \.album, subtitle: \.artist)
        topSongs = rank({ $0.trackID.uuidString }, title: \.title, subtitle: \.artist)
        topGenres = rank(\.genre, title: \.genre, subtitle: { _ in nil })
    }
}

/// Day-based stats: the heatmap and listening streaks.
nonisolated enum StatsCalendar {
    /// Seconds listened per day, keyed by the start of each day.
    static func dailySeconds(_ records: [SessionRecord], calendar: Calendar = .current) -> [Date: Double] {
        records.reduce(into: [:]) { days, record in
            days[calendar.startOfDay(for: record.start), default: 0] += record.seconds
        }
    }

    /// Current and longest run of consecutive listening days. Like the desktop app,
    /// the current streak may end yesterday if nothing has been played yet today.
    static func streaks(days: Set<Date>, today: Date = .now, calendar: Calendar = .current) -> (current: Int, longest: Int) {
        let normalized = Set(days.map { calendar.startOfDay(for: $0) })
        guard !normalized.isEmpty else { return (0, 0) }

        func previousDay(_ day: Date) -> Date {
            calendar.date(byAdding: .day, value: -1, to: day) ?? day.addingTimeInterval(-86_400)
        }

        var current = 0
        var day = calendar.startOfDay(for: today)
        if !normalized.contains(day) { day = previousDay(day) }
        while normalized.contains(day) {
            current += 1
            day = previousDay(day)
        }

        var longest = 0
        var run = 0
        var last: Date?
        for day in normalized.sorted() {
            if let last, calendar.date(byAdding: .day, value: 1, to: last) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            last = day
        }
        return (current, longest)
    }
}
