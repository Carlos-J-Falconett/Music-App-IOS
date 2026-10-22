import SwiftUI

/// Full-screen Now Playing over the artist backdrop, top to bottom:
/// - a top bar: close, the title with the album, and the album cover toggle;
/// - a swipeable square with three pages (Cover · Queue · Equalizer) and a glass
///   switcher under it;
/// - the song's title and artist with Favorite and Add to Playlist;
/// - the wave visualizer, edge to edge;
/// - the glowing timeline and the transport controls. There's no volume slider:
///   on a phone the device's buttons control volume.
///
/// The Cover page shows nothing by default, so the artist backdrop is the picture;
/// the photo button puts the album cover there instead.
struct NowPlayingView: View {
    @Environment(MusicPlayer.self) private var player
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    @Environment(LibraryIndexStore.self) private var library
    @AppStorage(PreferenceKeys.nowPlayingShowsCover) private var showsCover = false
    /// The page the square is showing; also drives the scroll position.
    @State private var page: NowPlayingPage? = .cover
    @State private var showPlaylistPicker = false

    var body: some View {
        ZStack {
            BackdropView()
            veil
            if let track = player.currentTrack {
                content(for: track)
            } else {
                ContentUnavailableView("Nothing Playing", systemImage: "music.note")
                    .foregroundStyle(theme.text)
            }
        }
        .sheet(isPresented: $showPlaylistPicker) {
            if let track = player.currentTrack {
                PlaylistPickerSheet(tracks: [track])
            }
        }
    }

    /// Focus-view veil from the desktop CSS, so text stays readable over any image.
    private var veil: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: .black.opacity(0.72), location: 0),
                .init(color: .black.opacity(0.35), location: 0.3),
                .init(color: .clear, location: 0.55),
            ], startPoint: .bottom, endPoint: .top)
            LinearGradient(stops: [
                .init(color: .black.opacity(0.35), location: 0),
                .init(color: .clear, location: 0.18),
            ], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func content(for track: Track) -> some View {
        VStack(spacing: 12) {
            topBar(for: track)

            // The square's size comes from a plain placeholder, and the pages are laid
            // over it. A List (the queue) sized by the surrounding layout could feed back
            // into it while a song change re-laid out the screen, which hung the app.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                // Fills the width on large phones (392 pt on a 15 Pro Max) and shrinks on short screens.
                .frame(maxWidth: 400, maxHeight: 400)
                .overlay { pager(for: track) }
                .layoutPriority(-1)

            pageSwitcher

            songInfo(for: track)

            WaveVisualizer()
                .frame(height: 104)
                // Edge to edge: out past the page margins.
                .padding(.horizontal, -24)

            // No volume slider: on a phone the side buttons control volume.
            VStack(spacing: 14) {
                ScrubberView()
                TransportControls()
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: Top bar

    private func topBar(for track: Track) -> some View {
        HStack(spacing: 12) {
            GlassCircleButton(title: "Close", systemImage: "chevron.down") { dismiss() }
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text("Now Playing")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(theme.text)
                Text(track.album)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            GlassCircleButton(
                title: showsCover ? "Hide Album Cover" : "Show Album Cover",
                systemImage: showsCover ? "photo.fill" : "photo",
                foreground: showsCover ? theme.ambientAccentLight : nil
            ) {
                withAnimation(Motion.standard) {
                    showsCover.toggle()
                    page = .cover
                }
            }
        }
    }

    // MARK: Pages

    /// Cover · Lyrics · Queue · Equalizer, side by side; swipe or use the switcher to change page.
    private func pager(for track: Track) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(NowPlayingPage.allCases) { item in
                    pageContent(item, track: track)
                        .containerRelativeFrame(.horizontal)
                        .id(item)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func pageContent(_ item: NowPlayingPage, track: Track) -> some View {
        switch item {
        case .cover:
            ZStack {
                if showsCover {
                    ArtworkView(artKey: track.coverKey, variant: .full, cornerRadius: Layout.cardCornerRadius)
                        .overlay {
                            RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                                .strokeBorder(GlowRim.gradient(theme), lineWidth: 1.5)
                        }
                        .ambientGlow(radius: 9, strength: 0.5)
                        // Inset more than the glow's reach (about twice its radius, plus the
                        // second halo's offset), so it fades out before the page's edge instead
                        // of being cut off in a visible straight line.
                        .padding(26)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                } else {
                    // Keeps the square's space so the controls don't move.
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .lyrics:
            LyricsPage(track: track)
        case .queue:
            QueuePanel()
        case .equalizer:
            EqualizerView()
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .nowPlayingPanel()
        }
    }

    /// Glass switcher under the square: one icon per page, the current one tinted.
    private var pageSwitcher: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(NowPlayingPage.allCases) { item in
                    let isCurrent = (page ?? .cover) == item
                    Button {
                        withAnimation(reduceMotion ? nil : Motion.standard) { page = item }
                    } label: {
                        Label(item.title, systemImage: item.systemImage)
                            .labelStyle(.iconOnly)
                            .font(.subheadline.weight(.bold))
                            // Padding (not a fixed size) so the capsules grow with the text size.
                            .padding(.horizontal, isCurrent ? 18 : 11)
                            .padding(.vertical, 7)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isCurrent ? theme.ambientAccentText : theme.secondaryText)
                    .glassEffect(isCurrent ? .regular.tint(theme.ambientAccent).interactive() : .regular.tint(theme.glassTint).interactive(), in: .capsule)
                    // The selected capsule's glass tint didn't always follow a new song's
                    // colors; a new identity per color redraws it.
                    .id("\(item.id)-\(isCurrent ? theme.glowPrimaryRGBA.hex : "")")
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                }
            }
        }
        .animation(Motion.standard, value: page)
    }

    // MARK: Song info

    /// The artist line, tappable: opens the artist's page (closing Now Playing). With
    /// several credited artists ("A & B", "feat. C") it offers a menu to pick one.
    @ViewBuilder
    private func artistLink(for track: Track) -> some View {
        let index = library.index
        let keys = artistKeys(for: track, index: index)
        let label = HStack(spacing: 4) {
            Text(track.artist)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .opacity(0.7)
        }
        .font(.headline.weight(.medium))
        .foregroundStyle(theme.text.opacity(0.85))
        .contentShape(.rect)

        if keys.count > 1 {
            Menu {
                ForEach(keys, id: \.self) { key in
                    Button(index.name(for: key), systemImage: "music.mic") { openArtist(key) }
                }
            } label: { label }
            .accessibilityLabel("Artists: \(track.artist)")
            .accessibilityHint("Opens an artist's page.")
        } else if let key = keys.first {
            Button { openArtist(key) } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel("Artist: \(track.artist)")
                .accessibilityHint("Opens the artist's page.")
        } else {
            label
        }
    }

    /// Main then featured artists that have a page, without repeats.
    private func artistKeys(for track: Track, index: ArtistIndex) -> [String] {
        let names = index.credits(for: track.id)?.all ?? []
        var seen = Set<String>()
        let keys = names.map(Track.key(for:)).filter { !index.songIDs(for: $0).isEmpty && seen.insert($0).inserted }
        return keys.isEmpty ? [index.primaryKey(of: track)] : keys
    }

    private func openArtist(_ key: String) {
        appState.pendingRoute = .artist(key)
        dismiss()
    }

    private func songInfo(for track: Track) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(theme.color(.songTitle))
                    .lineLimit(2)
                artistLink(for: track)
            }
            .legibleOnGlass()
            Spacer(minLength: 8)
            GlassCircleButton(
                title: track.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: track.isFavorite ? "heart.fill" : "heart",
                foreground: track.isFavorite ? theme.favorite : nil
            ) {
                player.toggleFavorite(track)
            }
            .symbolEffect(.bounce, value: track.isFavorite)
            GlassCircleButton(title: "Add to Playlist", systemImage: "text.badge.plus") {
                showPlaylistPicker = true
            }
        }
    }
}

/// Compact player shown above the tab bar. Tap it to open Now Playing.
struct MiniPlayerView: View {
    @Environment(MusicPlayer.self) private var player
    @Environment(AppState.self) private var appState
    @Environment(ThemeStore.self) private var theme
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(artKey: player.currentTrack?.coverKey, cornerRadius: 9)
                .frame(width: 34, height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(GlowRim.gradient(theme), lineWidth: 1.2)
                }
                .ambientGlow(radius: 8, strength: player.isPlaying ? 0.55 : 0.25)
                .animation(Motion.standard, value: player.isPlaying)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.currentTrack?.title ?? "Not Playing")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                if placement != .inline, let artist = player.currentTrack?.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            if placement != .inline {
                Button(action: player.next) {
                    Image(systemName: "forward.fill")
                        .frame(width: 40, height: 40)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Next")
            }
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(theme.text)
        .legibleOnGlass()
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Same tint as the tab bar (Themes → Glass Panel Tint / Glass Opacity), a little
        // stronger so list rows scrolling behind it don't compete with its text.
        .background(theme.color(.panelTint).opacity(min(theme.glassOpacity + 0.25, 1)))
        .overlay(alignment: .bottom) { progressLine }
        .contentShape(.rect)
        .onTapGesture { appState.showNowPlaying = true }
        // VoiceOver: the whole bar acts as an "Open Now Playing" button; play/next stay reachable.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(player.currentTrack.map { "Now playing: \($0.title) by \($0.artist)" } ?? "Not Playing")
        .accessibilityAction(named: "Open Now Playing") { appState.showNowPlaying = true }
    }

    /// Thin two-color progress line along the bottom edge. Position isn't observable,
    /// so it redraws twice a second while playing and not at all while paused.
    private var progressLine: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !player.isPlaying)) { _ in
            let duration = player.engine.duration
            let fraction = duration > 0 ? min(max(player.engine.currentTime / duration, 0), 1) : 0
            GeometryReader { geometry in
                Capsule()
                    .fill(LinearGradient(colors: [theme.glowPrimary, theme.glowSecondary], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * fraction, height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
