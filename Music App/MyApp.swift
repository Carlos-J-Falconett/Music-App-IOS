import SwiftUI
import SwiftData

@main struct MyApp: App {
    private let container: ModelContainer
    @State private var player: MusicPlayer
    @State private var theme: ThemeStore
    @State private var appState: AppState
    @State private var backdrop: BackdropModel
    @State private var libraryIndex = LibraryIndexStore()
    @State private var listeningTotals = ListeningTotalsStore()
    @State private var lyrics: LyricsStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: Track.self, Playlist.self, ListenSession.self, ArtistImage.self, ArtistBackground.self, ArtistBackdropStyle.self, SavedTheme.self, HiddenArtist.self,
                ArtistGroupLink.self
            )
        } catch {
            fatalError("Could not open the music library database: \(error)")
        }
        self.container = container
        self.player = MusicPlayer(context: container.mainContext)
        self.theme = ThemeStore()
        self.appState = AppState()
        self.backdrop = BackdropModel()
        var sources = MediaSources.standard
        #if DEBUG
        // Simulator testing: the demo library's made-up songs get generated lyrics.
        if DemoLibrary.isRequested { sources.lyrics.insert(DemoLyricsProvider(), at: 0) }
        #endif
        self.lyrics = LyricsStore(sources: sources)
        Typography.configureNavigationBars()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .backdropLoader()
                .artworkPaletteLoader()
                .libraryIndexing()
                .listeningTotalsLoader()
                .environment(libraryIndex)
                .environment(listeningTotals)
                .environment(lyrics)
                .environment(player)
                .environment(theme)
                .environment(appState)
                .environment(backdrop)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    // Write the in-progress listening session when leaving the app.
                    if phase != .active {
                        player.saveState()
                        theme.saveNow()
                    }
                }
                .task {
                    // One-time: read the Album Artist of songs imported before it was saved.
                    await LibraryActions.backfillAlbumArtists(in: container.mainContext)
                    // One-time: read the audio format of songs imported before it was saved.
                    await LibraryActions.backfillAudioFormats(in: container.mainContext)
                    // One-time: artists have one image again; fold in any separate backgrounds.
                    ArtistArtwork.mergeLegacyBackgrounds(in: container.mainContext)
                }
                #if DEBUG
                .task {
                    // Simulator testing: SUN_DEMO_LIBRARY=1 fills an empty library with generated songs.
                    if DemoLibrary.isRequested {
                        await DemoLibrary.seedIfEmpty(context: container.mainContext)
                        await DemoLibrary.seedCreditExamplesIfMissing(context: container.mainContext)
                        await DemoLibrary.seedArtistPicturesIfMissing(context: container.mainContext)
                        await DemoLibrary.seedFormatExamplesIfMissing(context: container.mainContext)
                    }
                    if TagCheck.runOnLaunch {
                        await TagCheck.run(context: container.mainContext)
                    }
                    guard LibraryDiagnostics.runOnLaunch else { return }
                    try? await Task.sleep(for: .seconds(3))
                    await LibraryDiagnostics.run(player: player, context: container.mainContext)
                }
                #endif
        }
        .modelContainer(container)
    }
}
