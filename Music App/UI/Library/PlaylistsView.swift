import SwiftUI
import SwiftData

/// Playlists tab: Favorites first, then the user's playlists.
struct PlaylistsView: View {
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @Query(filter: #Predicate<Track> { $0.isFavorite }) private var favorites: [Track]
    @Query private var tracks: [Track]
    @Environment(\.modelContext) private var context
    @Environment(ThemeStore.self) private var theme
    /// Set by the New Playlist button in the Library header.
    @Binding var showNewPlaylist: Bool
    @State private var newName = ""

    var body: some View {
        let covers = Dictionary(tracks.map { ($0.id, $0.coverKey) }, uniquingKeysWith: { first, _ in first })
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.spacingSmall) {
                SectionHeader(title: "Playlists", detail: playlists.isEmpty ? nil : countLabel(playlists.count, "playlist"))
                    .padding(.horizontal, Layout.screenPadding)
                GlassEffectContainer(spacing: 12) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        // Favorites always comes first.
                        NavigationLink(value: LibraryRoute.favorites) {
                            CoverCard(artKey: nil, title: "Favorites", detail: countLabel(favorites.count, "song"),
                                      symbol: "heart.fill", symbolColor: theme.favorite)
                        }
                        .buttonStyle(.plain)
                        ForEach(playlists) { playlist in
                            NavigationLink(value: LibraryRoute.playlist(playlist.id)) {
                                CoverCard(
                                    artKey: playlist.trackIDs.lazy.compactMap { covers[$0] ?? nil }.first,
                                    title: playlist.name, detail: countLabel(playlist.trackIDs.count, "song")
                                )
                            }
                            .buttonStyle(.plain)
                            // A grid has no swipe-to-delete, so deleting lives in the long-press menu.
                            .contextMenu {
                                Button("Delete Playlist", systemImage: "trash", role: .destructive) {
                                    context.delete(playlist)
                                    try? context.save()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Layout.screenPadding)
                }
                if playlists.isEmpty {
                    Text("Tap \(Image(systemName: "text.badge.plus")) to make your first playlist.")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                        .legibleOnGlass()
                        .padding(.horizontal, Layout.screenPadding)
                        .padding(.top, Layout.spacingSmall)
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("Playlists")
        .onChange(of: showNewPlaylist) { _, showing in
            if showing { newName = "" }
        }
        .alert("New Playlist", isPresented: $showNewPlaylist) {
            TextField("Name", text: $newName)
            Button("Create") { createPlaylist() }
            Button("Cancel", role: .cancel) {}
        }
        .backdropScreen()
    }

    private func createPlaylist() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        context.insert(Playlist(name: name))
        try? context.save()
    }
}

/// Favorite songs.
struct FavoritesView: View {
    @Query(filter: #Predicate<Track> { $0.isFavorite }, sort: \Track.title) private var favorites: [Track]

    var body: some View {
        TrackListScreen(title: "Favorites", tracks: favorites, symbol: "heart.fill")
    }
}

/// One playlist: play, reorder (Edit), remove and rename.
struct PlaylistDetailView: View {
    let playlistID: UUID

    @Query private var playlists: [Playlist]
    @Query private var tracks: [Track]
    @Environment(MusicPlayer.self) private var player
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showRename = false
    @State private var newName = ""

    init(playlistID: UUID) {
        self.playlistID = playlistID
        _playlists = Query(filter: #Predicate<Playlist> { $0.id == playlistID })
    }

    var body: some View {
        if let playlist = playlists.first {
            content(for: playlist)
        } else {
            ContentUnavailableView("Playlist Not Found", systemImage: "music.note.list")
                .backdropScreen()
        }
    }

    private func content(for playlist: Playlist) -> some View {
        let lookup = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let songs = playlist.trackIDs.compactMap { lookup[$0] }

        // Playlists play every song in them, including songs by hidden artists.
        return List {
            DetailHeader(
                artKey: songs.first { $0.coverKey != nil }?.coverKey,
                title: playlist.name,
                detail: [countLabel(songs.count, "song"), formatListeningTime(songs.reduce(0) { $0 + $1.duration })]
                    .joined(separator: " · "),
                playTracks: songs
            )
            .plainListRow()
            if songs.isEmpty {
                Text("Add songs with the “Add to Playlist…” menu on any song.")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .legibleOnGlass()
                    .plainListRow()
            }
            // Offsets are used as ids because a song can be in a playlist twice.
            ForEach(Array(songs.enumerated()), id: \.offset) { index, track in
                Button {
                    player.play(songs, startAt: index)
                } label: {
                    SongRow(track: track)
                }
                .buttonStyle(.plain)
                .trackActions(track)
                .glassRow()
            }
            .onMove { source, destination in
                playlist.trackIDs = songs.map(\.id)
                playlist.trackIDs.move(fromOffsets: source, toOffset: destination)
                try? context.save()
            }
            .onDelete { offsets in
                playlist.trackIDs = songs.map(\.id)
                playlist.trackIDs.remove(atOffsets: offsets)
                try? context.save()
            }
        }
        .libraryListStyle()
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Rename", systemImage: "pencil") {
                        newName = playlist.name
                        showRename = true
                    }
                    Button("Delete Playlist", systemImage: "trash", role: .destructive) {
                        context.delete(playlist)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
        .alert("Rename Playlist", isPresented: $showRename) {
            TextField("Name", text: $newName)
            Button("Save") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { playlist.name = name }
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        }
        .backdropScreen()
    }
}

/// Sheet for adding songs to a playlist (opened from any song's menu).
struct PlaylistPickerSheet: View {
    let tracks: [Track]

    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showNewPlaylist = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Button("New Playlist…", systemImage: "plus") {
                    newName = ""
                    showNewPlaylist = true
                }
                ForEach(playlists) { playlist in
                    Button {
                        add(to: playlist)
                    } label: {
                        LabeledContent(playlist.name, value: "\(playlist.trackIDs.count)")
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .alert("New Playlist", isPresented: $showNewPlaylist) {
                TextField("Name", text: $newName)
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    let playlist = Playlist(name: name)
                    context.insert(playlist)
                    add(to: playlist)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func add(to playlist: Playlist) {
        playlist.trackIDs += tracks.map(\.id)
        try? context.save()
        dismiss()
    }
}
