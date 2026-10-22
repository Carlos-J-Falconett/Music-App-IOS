import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Top-level tabs. On iPhone the tab bar and mini player use Liquid Glass and float
/// over the artist backdrop that every page shows behind its content.
enum AppTab: Hashable {
    case home, library, stats, settings, search
}

struct RootView: View {
    @Environment(MusicPlayer.self) private var player
    @Environment(AppState.self) private var appState
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var context
    @State private var selection: AppTab = .home
    /// Each library tab's navigation path, so pages can be opened from code (`AppState.pendingRoute`).
    /// Every library page is a `LibraryRoute`, so a plain array works and its last page can be checked.
    @State private var paths: [AppTab: [LibraryRoute]] = [:]

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                libraryStack(.home) { HomeView() }
            }
            // Songs, Albums, Artists, Genres and Playlists, switched with chips. Four tabs
            // plus search fit without iOS folding any into a "More" tab (six didn't).
            Tab("Library", systemImage: "square.stack", value: AppTab.library) {
                libraryStack(.library) { LibraryView() }
            }
            Tab("Stats", systemImage: "chart.bar.fill", value: AppTab.stats) {
                libraryStack(.stats) { StatsView() }
            }
            // Settings holds the theme and Add Music.
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack { SettingsView() }
                    .themedTabBar()
            }
            // The round glass search button pinned at the end of the tab bar.
            Tab(value: AppTab.search, role: .search) {
                libraryStack(.search) { SearchView() }
            }
        }
        // Selected tabs follow the artwork (or the theme's Primary with Match Artwork off).
        .tint(theme.ambientAccent)
        .fontDesign(.rounded)
        // The tab bar and mini player always stay full size while scrolling.
        .tabBarMinimizeBehavior(.never)
        .tabViewBottomAccessory(isEnabled: player.currentTrack != nil) {
            MiniPlayerView()
        }
        .onChange(of: appState.pendingRoute) { _, route in
            guard let route else { return }
            // Opens on the current tab when it has library pages; Settings doesn't, so Library.
            let target: AppTab = selection == .settings ? .library : selection
            selection = target
            // Already on that page (e.g. opened it, then went to Now Playing): don't stack a copy.
            if paths[target]?.last != route {
                paths[target, default: []].append(route)
            }
            appState.pendingRoute = nil
        }
        .fullScreenCover(isPresented: $appState.showNowPlaying) {
            NowPlayingView()
                .fontDesign(.rounded)
        }
        .sheet(isPresented: playlistPickerBinding) {
            if let tracks = appState.playlistPickerTracks {
                PlaylistPickerSheet(tracks: tracks)
                    .fontDesign(.rounded)
            }
        }
        .fileImporter(
            isPresented: $appState.showImporter,
            allowedContentTypes: [.audio, .folder],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { await importFiles(urls) }
        }
        .overlay(alignment: .top) {
            if appState.isImporting || appState.importMessage != nil {
                importBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring, value: appState.isImporting)
        .animation(.spring, value: appState.importMessage)
        .alert("Playback Problem", isPresented: Binding(
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } }
        )) {
            Button("OK") { player.errorMessage = nil }
        } message: {
            Text(player.errorMessage ?? "")
        }
    }

    /// A tab's navigation stack with every library destination.
    private func libraryStack<Content: View>(_ tab: AppTab, @ViewBuilder root: () -> Content) -> some View {
        NavigationStack(path: Binding(
            get: { paths[tab] ?? [] },
            set: { paths[tab] = $0 }
        )) {
            root().libraryDestinations()
        }
        .themedTabBar()
    }

    /// The root only shows the playlist picker while Now Playing is closed
    /// (Now Playing presents its own copy).
    private var playlistPickerBinding: Binding<Bool> {
        Binding(
            get: { appState.playlistPickerTracks != nil && !appState.showNowPlaying },
            set: { if !$0 { appState.playlistPickerTracks = nil } }
        )
    }

    private var importBanner: some View {
        HStack(spacing: 10) {
            if appState.isImporting {
                ProgressView()
                Text("Importing music…")
            } else if let message = appState.importMessage {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accent)
                Text(message)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(theme.text)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(theme.glassTint), in: .capsule)
        .padding(.top, 4)
    }

    private func importFiles(_ urls: [URL]) async {
        appState.isImporting = true
        let added = await LibraryActions.importFiles(urls, into: context)
        appState.isImporting = false
        appState.importMessage = added == 1 ? "Added 1 song" : "Added \(added) songs"
        try? await Task.sleep(for: .seconds(2.5))
        appState.importMessage = nil
    }
}

extension View {
    /// Tints the tab bar's glass with the theme's panel color and Glass Opacity,
    /// and keeps it visible however far the list is scrolled.
    func themedTabBar() -> some View {
        modifier(ThemedTabBar())
    }
}

private struct ThemedTabBar: ViewModifier {
    @Environment(ThemeStore.self) private var theme

    func body(content: Content) -> some View {
        content
            .toolbarBackground(theme.glassTint, for: .tabBar)
            .toolbarBackgroundVisibility(.visible, for: .tabBar)
    }
}
