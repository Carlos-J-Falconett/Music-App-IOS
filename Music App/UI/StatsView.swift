import SwiftUI
import SwiftData

/// Stats tab: the same compact header as Home and Library with period chips, then a
/// hero card (listening time and a ring of the days you listened), tiles for plays,
/// songs, artists and streaks, a year heatmap, and top lists.
struct StatsView: View {
    /// Everything the screen shows, computed together off the main thread.
    nonisolated private struct Computed: Sendable {
        var summary: StatsSummary
        var daily: [Date: Double]
        var streaks: (current: Int, longest: Int)
        /// Days in the period with any listening, and the period's length in days.
        var activeDays: Int
        var periodDays: Int
    }

    /// Changes whenever sessions are added, grow, or the period changes.
    private struct RefreshKey: Equatable {
        let count: Int
        let lastSeconds: Double
        let period: StatsPeriod
        /// Changes once the library index is ready, so artist splitting uses it.
        let artistCount: Int
    }

    @Query(sort: \ListenSession.start) private var sessions: [ListenSession]
    @Environment(ThemeStore.self) private var theme
    @Environment(LibraryIndexStore.self) private var library
    @State private var period: StatsPeriod = .month
    @State private var computed: Computed?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.spacingMedium) {
                if let computed {
                    content(computed)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal, Layout.screenPadding)
            .padding(.top, Layout.spacingSmall)
            .padding(.bottom, 24)
        }
        // Fixed at the top; the cards scroll below it, never underneath.
        .pinnedHeader {
            PageHeader(title: "Stats") {
                EmptyView()
            } below: {
                ChipPicker(options: StatsPeriod.allCases, selection: $period) { $0.title }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Stats")
        .backdropScreen()
        // The tab stays alive after its first visit, so recomputing the whole
        // history in `body` on every song change made skipping songs stutter.
        // Now it's recalculated in the background only when the data changes.
        .task(id: RefreshKey(count: sessions.count, lastSeconds: sessions.last?.listenedSeconds ?? 0,
                             period: period, artistCount: library.index.knownKeys.count)) {
            // Split each session's artist text with the library's rules (cached per text).
            let known = library.index.knownKeys
            var splitCache: [String: [String]] = [:]
            let records = sessions.map { session in
                let artists = splitCache[session.artist] ?? {
                    let names = ArtistCredits.parse(session.artist, known: known).all
                    splitCache[session.artist] = names
                    return names
                }()
                return SessionRecord(
                    start: session.start, seconds: session.listenedSeconds, counted: session.counted, trackID: session.trackID,
                    title: session.title, artist: session.artist, album: session.album, genre: session.genre,
                    artists: artists
                )
            }
            let result = await Self.compute(records, period: period)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.standard) { computed = result }
        }
    }

    @concurrent
    private static func compute(_ records: [SessionRecord], period: StatsPeriod) async -> Computed {
        let daily = StatsCalendar.dailySeconds(records)
        let (active, length) = activity(daily: daily, period: period)
        return Computed(
            summary: StatsSummary(records: records, period: period),
            daily: daily,
            streaks: StatsCalendar.streaks(days: Set(daily.keys)),
            activeDays: active,
            periodDays: length
        )
    }

    /// Days with listening in the period, and how many days the period covers
    /// (All Time runs from the first day you listened).
    nonisolated static func activity(daily: [Date: Double], period: StatsPeriod, today: Date = .now,
                                     calendar: Calendar = .current) -> (active: Int, length: Int) {
        let end = calendar.startOfDay(for: today)
        let listened = daily.filter { $0.value > 0 }.keys
        let length: Int
        if let days = period.days {
            length = days
        } else if let first = listened.min() {
            length = (calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: end).day ?? 0) + 1
        } else {
            length = 1
        }
        let start = calendar.date(byAdding: .day, value: -(length - 1), to: end) ?? end
        let active = listened.filter { $0 >= start && $0 <= end }.count
        return (min(active, length), max(length, 1))
    }

    @ViewBuilder
    private func content(_ computed: Computed) -> some View {
        let summary = computed.summary
        hero(computed)

        GlassEffectContainer(spacing: 12) {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    tile("Plays", "\(summary.plays)", "play.circle.fill")
                    tile("Songs", "\(summary.songCount)", "music.note")
                    tile("Artists", "\(summary.artistCount)", "music.mic")
                }
                GridRow {
                    tile("Current Streak", days(computed.streaks.current), "flame.fill")
                        .gridCellColumns(2)
                    tile("Best", days(computed.streaks.longest), "trophy.fill")
                }
            }
        }

        card("Past Year", systemImage: "calendar") {
            HeatmapView(dailySeconds: computed.daily)
                .aspectRatio(53.0 / 7.0, contentMode: .fit)
        }

        ranked("Top Artists", "music.mic", summary.topArtists)
        ranked("Top Albums", "square.stack", summary.topAlbums)
        ranked("Top Songs", "music.note", summary.topSongs)
        ranked("Top Genres", "guitars", summary.topGenres)
    }

    private func days(_ count: Int) -> String { count == 1 ? "1 day" : "\(count) days" }

    // MARK: Hero

    /// Listening time for the period, with a glowing ring of the days you listened.
    private func hero(_ computed: Computed) -> some View {
        let fraction = Double(computed.activeDays) / Double(computed.periodDays)
        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Listening Time")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.color(.heading))
                Text(formatListeningTime(computed.summary.totalSeconds))
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy).monospacedDigit())
                    .foregroundStyle(theme.text)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Listened on \(computed.activeDays) of \(days(computed.periodDays))")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer(minLength: 0)
            ActivityRing(fraction: fraction)
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)   // the text above says the same
        }
        .padding(20)
        .legibleOnGlass()
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    // MARK: Tiles and cards

    private func tile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(theme.ambientAccentLight)
            Text(value)
                .font(.title3.weight(.heavy).monospacedDigit())
                .foregroundStyle(theme.text)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .legibleOnGlass()
        .glassCard(cornerRadius: Layout.rowCornerRadius, glow: false)
        .accessibilityElement(children: .combine)
    }

    private func card<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.heavy))
                .foregroundStyle(theme.color(.pageTitle))
                .labelStyle(StatsCardTitleStyle(iconColor: theme.ambientAccentLight))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .legibleOnGlass()
        .glassCard(glow: false)
    }

    @ViewBuilder
    private func ranked(_ title: String, _ icon: String, _ items: [RankedItem]) -> some View {
        card(title, systemImage: icon) {
            if items.isEmpty {
                Text("Nothing played in this period yet.")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .center, spacing: 10) {
                        // Rank badge: the top spot takes the accent.
                        Text("\(index + 1)")
                            .font(.caption.weight(.heavy).monospacedDigit())
                            .foregroundStyle(index == 0 ? theme.ambientAccentText : theme.text)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(index == 0 ? theme.ambientAccent : theme.text.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(theme.text)
                                .lineLimit(1)
                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text("\(formatListeningTime(item.seconds)) · \(Int((item.fraction * 100).rounded()))%")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(theme.secondaryText)
                    }
                    GeometryReader { geometry in
                        let bar = theme.color(.statBars)
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.text.opacity(0.1))
                            Capsule()
                                .fill(LinearGradient(colors: [bar, bar.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: geometry.size.width * item.fraction)
                                .shadow(color: bar.opacity(0.5), radius: 4)
                        }
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Card titles in Stats: a tinted icon before the heading.
private struct StatsCardTitleStyle: LabelStyle {
    let iconColor: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(iconColor).font(.headline)
            configuration.title
        }
    }
}

/// A glowing ring filled to `fraction`, in the glow colors (artwork or theme).
private struct ActivityRing: View {
    let fraction: Double

    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let ring = AngularGradient(colors: [theme.glowPrimary, theme.glowSecondary, theme.glowPrimary], center: .center)
        ZStack {
            Circle().stroke(theme.text.opacity(0.12), lineWidth: 11)
            Circle()
                .trim(from: 0, to: max(min(fraction, 1), 0.001))
                .stroke(ring, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: reduceTransparency ? .clear : theme.glowPrimary.opacity(0.6), radius: 8)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.headline.weight(.heavy).monospacedDigit())
                .foregroundStyle(theme.text)
        }
        .animation(Motion.standard, value: fraction)
    }
}

/// A year of days (53 weeks × 7), each colored by how long you listened.
struct HeatmapView: View {
    let dailySeconds: [Date: Double]
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        let color = theme.color(.heatmap)
        let empty = theme.text.opacity(0.08)
        Canvas { context, size in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            let weekday = calendar.component(.weekday, from: today) - calendar.firstWeekday
            let todayRow = (weekday + 7) % 7
            let columns = 53
            let gap: CGFloat = 2
            let cell = min((size.width - gap * CGFloat(columns - 1)) / CGFloat(columns), (size.height - gap * 6) / 7)

            for column in 0..<columns {
                for row in 0..<7 {
                    let daysAgo = (columns - 1 - column) * 7 + (todayRow - row)
                    guard daysAgo >= 0, let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
                    let seconds = dailySeconds[day] ?? 0
                    let rect = CGRect(
                        x: CGFloat(column) * (cell + gap), y: CGFloat(row) * (cell + gap),
                        width: cell, height: cell
                    )
                    let path = Path(roundedRect: rect, cornerRadius: cell * 0.32)
                    if seconds <= 0 {
                        context.fill(path, with: .color(empty))
                    } else {
                        // 4 intensity steps: under 15 min, under 1 h, under 2 h, more.
                        let level: Double = seconds < 900 ? 0.3 : seconds < 3600 ? 0.55 : seconds < 7200 ? 0.8 : 1
                        context.fill(path, with: .color(color.opacity(level)))
                    }
                }
            }
        }
        .accessibilityLabel("Listening heatmap for the past year")
    }
}
