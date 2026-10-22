import SwiftUI
import SwiftData
import PhotosUI

/// One artist with the numbers shown in the Artists list.
struct ArtistSummary: Identifiable {
    let id: String          // artist key
    let name: String
    let songCount: Int
    let albumCount: Int
    let artKey: String?
    /// The group they belong to (e.g. "TWICE" for SANA), if any.
    let groupName: String?
}

/// One album of an artist, with its songs in track order.
struct AlbumGroup: Identifiable {
    var id: String { name }
    let name: String
    let year: Int?
    let artKey: String?
    let tracks: [Track]
}

/// Picks the picture for an artist: their own image, else their group's image
/// (so TWICE members show TWICE's picture until they get their own), else nil
/// (callers then fall back to an album cover).
enum ArtistArtwork {
    static func customKey(for artistKey: String, images: [String: String], index: ArtistIndex) -> String? {
        images[artistKey] ?? index.groupOf[artistKey].flatMap { images[$0] }
    }

    static func imageMap(_ images: [ArtistImage]) -> [String: String] {
        Dictionary(images.map { ($0.artistKey, $0.artKey) }, uniquingKeysWith: { first, _ in first })
    }

    static func styleMap(_ styles: [ArtistBackdropStyle]) -> [String: BackdropStyle] {
        Dictionary(styles.map { ($0.artistKey, $0.style) }, uniquingKeysWith: { first, _ in first })
    }

    /// The artist's own background settings, else their group's (they share its image).
    static func style(for artistKey: String, styles: [String: BackdropStyle], index: ArtistIndex) -> BackdropStyle? {
        styles[artistKey] ?? index.groupOf[artistKey].flatMap { styles[$0] }
    }

    /// Each artist has one image again (the background). A build briefly had a separate
    /// `ArtistBackground`; this moves any of those into `ArtistImage` (the background
    /// wins, since that's what showed behind the player) and deletes them. Runs at launch.
    static func mergeLegacyBackgrounds(in context: ModelContext) {
        guard let backgrounds = try? context.fetch(FetchDescriptor<ArtistBackground>()), !backgrounds.isEmpty else { return }
        let images = (try? context.fetch(FetchDescriptor<ArtistImage>())) ?? []
        for background in backgrounds {
            if let image = images.first(where: { $0.artistKey == background.artistKey }) {
                image.artKey = background.artKey
            } else {
                context.insert(ArtistImage(artistKey: background.artistKey, artKey: background.artKey))
            }
            context.delete(background)
        }
        try? context.save()
    }

    /// Height of the picture area at the top of an artist's page, measured from the top
    /// of the screen: the picture's own height at full width, but at least 42% of the
    /// screen (so very wide pictures still get room) and at most 62% (so the name, Play
    /// and the start of the discography are always on screen).
    /// With Fill Screen the picture covers the whole screen, so the area is the 62% maximum.
    static func heroHeight(imageAspect: CGFloat, screen: CGSize, fillsScreen: Bool = false) -> CGFloat {
        guard imageAspect > 0, screen.width > 0, screen.height > 0 else { return 0 }
        if fillsScreen { return screen.height * 0.62 }
        return min(max(screen.width / imageAspect, screen.height * 0.42), screen.height * 0.62)
    }
}

enum LibraryGrouping {
    /// Every artist in the index (individual artists, after splitting credits). Their
    /// circle shows their latest album's cover (the artist image is the background).
    static func artists(index: ArtistIndex, tracks: [Track], keys: [String]? = nil) -> [ArtistSummary] {
        let lookup = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (keys ?? index.artistKeys).compactMap { key -> ArtistSummary? in
            let songs = index.songs(for: key, in: lookup)
            guard !songs.isEmpty else { return nil }
            return ArtistSummary(
                id: key,
                name: index.name(for: key),
                songCount: songs.count,
                albumCount: Set(songs.map(\.album)).count,
                artKey: latestAlbumCover(of: songs, artistKey: key, index: index),
                groupName: index.groupOf[key].map(index.name(for:))
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The cover of an artist's newest album: the latest year (an album's year is its
    /// earliest song's), then the most recently imported. Albums they own (Album Artist,
    /// else main artist) come first, so a guest spot on someone else's new album doesn't
    /// replace their own; a group member with no solo albums gets the group's newest.
    static func latestAlbumCover(of songs: [Track], artistKey: String, index: ArtistIndex) -> String? {
        let withCovers = songs.filter { $0.coverKey != nil }
        let own = withCovers.filter { index.albumOwnerKey(of: $0) == artistKey }
        let albums = Dictionary(grouping: own.isEmpty ? withCovers : own, by: \.album)
        func rank(_ album: [Track]) -> (Int, Date) {
            (album.compactMap(\.year).min() ?? Int.min, album.map(\.addedAt).max() ?? .distantPast)
        }
        return albums.values.max { rank($0) < rank($1) }?.first?.coverKey
    }

    /// Groups an artist's songs by album. The year and cover come from the **whole**
    /// album (every song with that name and album owner), so an album shows the same
    /// year on every artist's page, even when a featured song has a different year tag.
    static func albums(from tracks: [Track], library: [Track], index: ArtistIndex) -> [AlbumGroup] {
        let byName = Dictionary(grouping: library, by: \.album)
        return Dictionary(grouping: tracks, by: \.album)
            .map { name, songs in
                let whole = wholeAlbum(name, owner: songs.first.map(index.albumOwnerKey(of:)), in: byName, index: index) ?? songs
                return AlbumGroup(
                    name: name,
                    year: whole.compactMap(\.year).min(),
                    artKey: whole.first { $0.coverKey != nil }?.coverKey ?? songs.first { $0.coverKey != nil }?.coverKey,
                    tracks: sortedByTrackNumber(songs)
                )
            }
            .sorted { ($0.year ?? Int.max, $0.name) < ($1.year ?? Int.max, $1.name) }
    }

    /// Every song on the album `name` owned by `owner` (Album Artist, else primary artist).
    static func wholeAlbum(_ name: String, owner: String?, in byName: [String: [Track]], index: ArtistIndex) -> [Track]? {
        guard let owner, let candidates = byName[name] else { return nil }
        let songs = candidates.filter { index.albumOwnerKey(of: $0) == owner }
        return songs.isEmpty ? nil : songs
    }

    static func sortedByTrackNumber(_ tracks: [Track]) -> [Track] {
        tracks.sorted { ($0.trackNumber ?? Int.max, $0.title) < ($1.trackNumber ?? Int.max, $1.title) }
    }
}

/// Artists tab: every artist, each circle showing their latest album's cover. Featured artists and group
/// members get their own entries. Hidden artists stay listed (dimmed, with an
/// eye-slash) so their page is always one tap away.
struct ArtistsView: View {
    @Query private var tracks: [Track]
    @Query private var hiddenArtists: [HiddenArtist]
    @Environment(LibraryIndexStore.self) private var library
    @Environment(ListeningTotalsStore.self) private var listening
    /// Chosen with the Sort button in the Library header.
    @AppStorage("artistSort") private var sort: CollectionSort = .name

    var body: some View {
        let hidden = hiddenArtists.keys
        // Only a listening sort reads the totals, so name sorts aren't redone every time
        // a session is saved during playback (every 30 s).
        let totals = sort.listeningOrder != nil ? listening.totals : .empty
        let artists = sort.sorted(
            library.artists,
            name: \.name, songCount: \.songCount, listening: { totals.artist($0.id) }
        )
        ScrollView {
            if tracks.isEmpty {
                EmptyLibraryView()
            } else {
                VStack(alignment: .leading, spacing: Layout.spacingMedium) {
                    SectionHeader(title: "All Artists", detail: [countLabel(artists.count, "artist"), hidden.isEmpty ? nil : "\(hidden.count) hidden", sort.label]
                        .compactMap { $0 }.joined(separator: " · "))
                        .padding(.horizontal, Layout.screenPadding)
                    // Three large circles per row.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 20) {
                        ForEach(artists) { artist in
                            let isHidden = hidden.contains(artist.id)
                            NavigationLink(value: LibraryRoute.artist(artist.id)) {
                                ArtistCircle(
                                    name: artist.name, artKey: artist.artKey,
                                    detail: circleDetail(artist, isHidden: isHidden, totals: totals),
                                    isHidden: isHidden
                                )
                            }
                            .buttonStyle(.plain)
                            .hideArtistMenu(artistKey: artist.id, isHidden: isHidden)
                        }
                    }
                    .padding(.horizontal, Layout.screenPadding)
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Artists")
        .backdropScreen()
    }

    /// "Hidden", the number the list is sorted by (listening sorts), or the song count.
    private func circleDetail(_ artist: ArtistSummary, isHidden: Bool, totals: ListeningTotals) -> String {
        if isHidden { return "Hidden" }
        if let order = sort.listeningOrder { return order.detail(totals.artist(artist.id)) }
        return countLabel(artist.songCount, "song")
    }
}

/// One artist in the Artists list.
struct ArtistRow: View {
    let artist: ArtistSummary
    var isHidden = false
    /// With a listening sort, the number the list is sorted by (e.g. "12 plays").
    var listeningDetail: String?

    @Environment(ThemeStore.self) private var theme

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(artKey: artist.artKey, isCircle: true)
                .frame(width: Layout.largeRowArtwork, height: Layout.largeRowArtwork)
                .saturation(isHidden ? 0 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(artist.name)
                    .font(.headline)
                    .foregroundStyle(theme.color(.songTitle))
                    .lineLimit(1)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isHidden {
                Image(systemName: "eye.slash")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityHidden(true)   // the row's value already says "Hidden"
            }
        }
        .opacity(isHidden ? 0.75 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isHidden ? "Hidden" : "")
    }

    private var detail: String {
        if isHidden { return "Hidden · \(countLabel(artist.songCount, "song"))" }
        if let listeningDetail { return "\(listeningDetail) · \(countLabel(artist.songCount, "song"))" }
        let counts = "\(countLabel(artist.albumCount, "album")) · \(countLabel(artist.songCount, "song"))"
        return artist.groupName.map { "\($0) · \(counts)" } ?? counts
    }
}

extension View {
    /// Long-press "Hide Artist" / "Unhide Artist".
    func hideArtistMenu(artistKey: String, isHidden: Bool) -> some View {
        modifier(HideArtistMenu(artistKey: artistKey, isHidden: isHidden))
    }
}

private struct HideArtistMenu: ViewModifier {
    let artistKey: String
    let isHidden: Bool

    func body(content: Content) -> some View {
        content.contextMenu {
            HideArtistButton(artistKey: artistKey, isHidden: isHidden)
        }
    }
}

/// The Hide / Unhide button, shared by the long-press menu and the artist page menu.
struct HideArtistButton: View {
    let artistKey: String
    let isHidden: Bool

    @Environment(MusicPlayer.self) private var player
    @Environment(LibraryIndexStore.self) private var library
    @Environment(\.modelContext) private var context

    var body: some View {
        Button(
            isHidden ? "Unhide Artist" : "Hide Artist",
            systemImage: isHidden ? "eye" : "eye.slash"
        ) {
            HiddenArtistActions.setHidden(!isHidden, artistKey: artistKey, context: context, player: player, index: library.index)
        }
    }
}

/// An artist's page. Their image (their own, else their group's, else an album cover)
/// fills the top of the screen behind the page, with room to see it; their name and
/// Play / Shuffle sit at its lower edge, and the discography starts below and scrolls
/// up over it. It lists every song they're credited on (main or featured) plus, for
/// groups, members' songs on the group's albums. This page always plays everything,
/// even when the artist is hidden.
struct ArtistDetailView: View {
    let artistKey: String

    @Query private var tracks: [Track]
    @Query private var artistImages: [ArtistImage]
    @Query private var backdropStyles: [ArtistBackdropStyle]
    @Query private var hiddenArtists: [HiddenArtist]
    @Environment(LibraryIndexStore.self) private var library
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var context
    @State private var showPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var cropSource: CropSource?
    @State private var showGroupPicker = false
    @State private var showStyleEditor = false
    /// This page's own picture (not the playing song's), once loaded.
    @State private var hero: ArtistHeroImage?
    /// The list's full size and the height of the bars above it.
    @State private var screen: CGSize = .zero
    @State private var topInset: CGFloat = 0
    /// Shows the name in the navigation bar once the big name has scrolled away.
    @State private var showsBarTitle = false

    private var customImage: ArtistImage? { artistImages.first { $0.artistKey == artistKey } }
    private var ownStyle: ArtistBackdropStyle? { backdropStyles.first { $0.artistKey == artistKey } }

    /// How far the name block overlaps the bottom of the picture (its faded edge).
    private static let nameOverlap: CGFloat = 64

    var body: some View {
        let index = library.index
        let lookup = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let songs = index.songs(for: artistKey, in: lookup)
        let albums = LibraryGrouping.albums(from: songs, library: tracks, index: index)
        let name = index.name(for: artistKey)
        let isHidden = hiddenArtists.keys.contains(artistKey)
        let groupName = index.groupOf[artistKey].map(index.name(for:))
        // Their image (or their group's), else their latest album's cover, like their circle.
        let custom = ArtistArtwork.customKey(for: artistKey, images: ArtistArtwork.imageMap(artistImages), index: index)
        let artKey = custom ?? LibraryGrouping.latestAlbumCover(of: songs, artistKey: artistKey, index: index)
        // Their background settings (or their group's), else the standard look.
        let style = ArtistArtwork.style(for: artistKey, styles: ArtistArtwork.styleMap(backdropStyles), index: index)
            ?? .standard(isArtistImage: custom != nil, isTransparent: hero?.isTransparent ?? false)
        // The shape comes from the file's header, so the space is right from the first
        // frame instead of jumping once the picture has loaded.
        let aspect = artKey.flatMap(ArtCache.aspectRatio(of:)) ?? hero?.aspect
        let heroHeight = aspect.map { ArtistArtwork.heroHeight(imageAspect: $0, screen: screen, fillsScreen: style.page.fillsScreen) } ?? 0
        // Empty space above the name, so the picture shows; the list starts below the bars.
        let gap = max(heroHeight - topInset - Self.nameOverlap, 0)

        List {
            artistHeader(
                name: name,
                subtitle: groupName.map { "Member of \($0)" },
                detail: [isHidden ? "Hidden" : nil, countLabel(albums.count, "album"), countLabel(songs.count, "song")]
                    .compactMap { $0 }.joined(separator: " · "),
                playTracks: albums.flatMap(\.tracks)
            )
            .padding(.top, gap)
            .plainListRow()

            ForEach(albums) { album in
                Section {
                    SongListSection(tracks: album.tracks, showsArtwork: false, subtitle: { track in
                        // "with Bad Bunny" on a featured artist's page; the member's name on a group's page.
                        index.subtitle(for: track.id, onPageOf: artistKey) ?? ""
                    })
                } header: {
                    NavigationLink(value: LibraryRoute.album(artistKey: artistKey, album: album.name)) {
                        AlbumHeader(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .libraryListStyle()
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(container: geometry.containerSize, topInset: geometry.contentInsets.top,
                          scrolled: geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, metrics in
            if screen != metrics.container { screen = metrics.container }
            if topInset != metrics.topInset { topInset = metrics.topInset }
            let pastName = metrics.scrolled > gap + 40
            if showsBarTitle != pastName { withAnimation(Motion.standard) { showsBarTitle = pastName } }
        }
        .navigationTitle(name)   // the back button title on pages opened from here
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The big name is on the picture, so the bar only shows it once it scrolls away.
            ToolbarItem(placement: .principal) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(theme.color(.pageTitle))
                    .lineLimit(1)
                    .opacity(showsBarTitle ? 1 : 0)
                    .accessibilityHidden(!showsBarTitle)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Artist Options", systemImage: "ellipsis") {
                    HideArtistButton(artistKey: artistKey, isHidden: isHidden)
                    Divider()
                    // A PhotosPicker can't open from inside a Menu (that's why the old
                    // button did nothing), so the menu item presents it separately.
                    Button("Choose Artist Image…", systemImage: "photo.on.rectangle") { showPhotoPicker = true }
                    if customImage != nil {
                        Button("Remove Artist Image", systemImage: "trash", role: .destructive) {
                            if let customImage { context.delete(customImage) }
                            try? context.save()
                        }
                    }
                    Button("Adjust Background…", systemImage: "slider.horizontal.3") { showStyleEditor = true }
                        .disabled(hero == nil)
                    Divider()
                    Button(groupName.map { "Member of \($0)…" } ?? "Member of…", systemImage: "person.3") {
                        showGroupPicker = true
                    }
                }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedPhoto, matching: .images)
        .task(id: pickedPhoto) { await loadPickedPhoto() }
        .sheet(item: $cropSource) { source in
            ArtistImageCropper(image: source.image, artistName: name) { data in
                Task { await saveImage(data) }
            }
        }
        .sheet(isPresented: $showGroupPicker) {
            GroupPickerSheet(memberKey: artistKey)
        }
        .fullScreenCover(isPresented: $showStyleEditor) {
            if let hero {
                BackdropStyleEditor(artistName: name, image: hero, style: style,
                                    standard: .standard(isArtistImage: hero.isArtistImage, isTransparent: hero.isTransparent)) { saveStyle($0) }
            }
        }
        .scrollContentBackground(.hidden)
        .containerBackground(for: .navigation) {
            if let hero, hero.key == artKey {
                ArtistPageBackdrop(image: hero, style: style)
                    .transition(.opacity)
            } else {
                // Nothing loaded (or no picture at all): the usual backdrop.
                BackdropView()
            }
        }
        .animation(Motion.standard, value: hero?.key)
        .task(id: artKey) { await loadHero(artKey, isArtistImage: custom != nil) }
    }

    /// Big name, member line and counts, then Play / Shuffle, over the picture's lower edge.
    private func artistHeader(name: String, subtitle: String?, detail: String, playTracks: [Track]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(theme.color(.pageTitle))
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.headline)
                        .foregroundStyle(theme.text.opacity(0.9))
                        .lineLimit(1)
                }
                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.text.opacity(0.8))
            }
            // Straight on the picture (no glass), so it gets a strong shadow.
            .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
            .shadow(color: .black.opacity(0.45), radius: 12)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            PlayShuffleRow(tracks: playTracks)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    /// Loads this page's picture: the full version, the blurred one, and its shape.
    private func loadHero(_ key: String?, isArtistImage: Bool) async {
        guard let key else { hero = nil; return }
        guard hero?.key != key else { return }
        async let blurred = ArtCache.load(key, .blur)
        async let sharp = ArtCache.load(key, .full)
        async let colors = ArtworkPalette.colors(for: key)
        let loaded = await (blurred, sharp, colors)
        guard !Task.isCancelled, let sharp = loaded.1, sharp.size.height > 0 else { return }
        hero = ArtistHeroImage(key: key, blurred: loaded.0, sharp: sharp, isTransparent: ArtCache.hasTransparency(key),
                              isArtistImage: isArtistImage, colors: loaded.2)
    }

    /// Saves this artist's own background settings; `nil` (Reset) goes back to the
    /// standard look (or their group's settings).
    private func saveStyle(_ style: BackdropStyle?) {
        switch (style, ownStyle) {
        case (let style?, let existing?): existing.style = style
        case (let style?, nil): context.insert(ArtistBackdropStyle(artistKey: artistKey, style: style))
        case (nil, let existing?): context.delete(existing)
        case (nil, nil): break
        }
        try? context.save()
    }

    /// Loads the picked photo (downsampled, so 48 MP photos don't use hundreds of MB) for framing.
    private func loadPickedPhoto() async {
        guard let pickedPhoto,
              let data = try? await pickedPhoto.loadTransferable(type: Data.self),
              let image = await ArtistImageCropper.downsampled(data) else { return }
        self.pickedPhoto = nil
        cropSource = CropSource(image: image)
    }

    /// Stores the framed image (plus its thumbnail and blurred versions) as this artist's image.
    private func saveImage(_ data: Data) async {
        guard let key = await ArtCache.storeInBackground(data) else { return }
        if let customImage {
            customImage.artKey = key
        } else {
            context.insert(ArtistImage(artistKey: artistKey, artKey: key))
        }
        try? context.save()
    }
}

/// The list's size, the bars' height above it, and how far it has scrolled.
private struct ScrollMetrics: Equatable {
    let container: CGSize
    let topInset: CGFloat
    let scrolled: CGFloat
}

/// A photo waiting to be framed.
struct CropSource: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// "Member of…": link an artist to a group by hand, for files without an Album Artist tag.
private struct GroupPickerSheet: View {
    let memberKey: String

    @Query private var tracks: [Track]
    @Query private var groupLinks: [ArtistGroupLink]
    @Environment(LibraryIndexStore.self) private var library
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let index = library.index
        let manual = groupLinks.first { $0.memberKey == memberKey }
        // A group found from Album Artist tags (shown when there's no manual choice).
        let automatic = manual == nil ? index.groupOf[memberKey] : nil
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = library.artists
            // Not the artist themself, and not their own members.
            .filter { $0.id != memberKey && index.groupOf[$0.id] != memberKey }
            .filter { text.isEmpty || $0.name.localizedStandardContains(text) }

        NavigationStack {
            List {
                if let automatic {
                    Section {
                        Label("Member of \(index.name(for: automatic)) (from Album Artist tags)", systemImage: "tag")
                    } footer: {
                        Text("Picking a group below replaces it.")
                    }
                }
                Section {
                    Button {
                        if let manual { context.delete(manual) }
                        try? context.save()
                        dismiss()
                    } label: {
                        HStack {
                            Text(automatic == nil ? "Not in a Group" : "Use Album Artist Tags")
                            Spacer()
                            if manual == nil { Image(systemName: "checkmark") }
                        }
                    }
                    ForEach(candidates) { artist in
                        Button {
                            setGroup(artist.id, replacing: manual)
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkView(artKey: artist.artKey, isCircle: true)
                                    .frame(width: 36, height: 36)
                                Text(artist.name)
                                Spacer()
                                if manual?.groupKey == artist.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a group")
            .navigationTitle("Member of")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
    }

    private func setGroup(_ groupKey: String, replacing existing: ArtistGroupLink?) {
        if let existing {
            existing.groupKey = groupKey
        } else {
            context.insert(ArtistGroupLink(memberKey: memberKey, groupKey: groupKey))
        }
        try? context.save()
        dismiss()
    }
}

/// Album cover, name and year used as a section header.
struct AlbumHeader: View {
    let album: AlbumGroup
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(artKey: album.artKey, cornerRadius: Layout.rowArtworkCornerRadius)
                .frame(width: Layout.largeRowArtwork, height: Layout.largeRowArtwork)
            VStack(alignment: .leading, spacing: 3) {
                Text(album.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.color(.songTitle))
                    .lineLimit(1)
                Text([album.year.map(String.init), countLabel(album.tracks.count, "song")]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(theme.text.opacity(0.75))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
        }
        .textCase(nil)
        .legibleOnGlass()
        .padding(10)
        // Pinned while its album scrolls, so it gets a glass backing like `SectionHeader`.
        // No blurred glow: one per album, redrawn while pinned during scrolling.
        .glassCard(cornerRadius: Layout.rowCornerRadius, emphasis: 1.3, glow: false)
        .padding(.horizontal, -4)
        .padding(.top, 6)
    }
}

/// One album as it appears on an artist's page: that artist's songs on it
/// (for a featured artist, just the songs they're on).
struct AlbumDetailView: View {
    let artistKey: String
    let album: String

    @Query private var tracks: [Track]
    @Environment(LibraryIndexStore.self) private var library

    var body: some View {
        let index = library.index
        let lookup = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let songs = LibraryGrouping.sortedByTrackNumber(
            index.songs(for: artistKey, in: lookup).filter { $0.album == album }
        )
        let total = songs.reduce(0) { $0 + $1.duration }
        let whole = LibraryGrouping.wholeAlbum(album, owner: songs.first.map(index.albumOwnerKey(of:)),
                                               in: Dictionary(grouping: tracks, by: \.album), index: index) ?? songs

        // Albums are opened from an artist's page (or a search, which leaves hidden
        // artists out), so they always play every song.
        List {
            DetailHeader(
                artKey: whole.first { $0.coverKey != nil }?.coverKey,
                title: album,
                subtitle: index.name(for: artistKey),
                detail: [whole.compactMap(\.year).min().map(String.init), countLabel(songs.count, "song"), formatListeningTime(total)]
                    .compactMap { $0 }.joined(separator: " · "),
                playTracks: songs
            )
            .plainListRow()

            SongListSection(tracks: songs, showsArtwork: false, subtitle: { track in
                index.subtitle(for: track.id, onPageOf: artistKey) ?? ""
            })
        }
        .libraryListStyle()
        .navigationTitle(album)
        .navigationBarTitleDisplayMode(.inline)
        .backdropScreen()
    }
}
