import SwiftUI
import SwiftData

/// The Media Server row in Settings, showing whether it's set up.
struct MediaServerSettingsSection: View {
    @Environment(ServerSyncStore.self) private var sync
    @Environment(ThemeStore.self) private var theme
    @AppStorage(ServerSyncStore.addressKey) private var address = ""

    var body: some View {
        Section {
            NavigationLink {
                MediaServerSettingsView()
            } label: {
                SettingsRowLabel(title: "Media Server", systemImage: "externaldrive.connected.to.line.below.fill",
                                 tile: theme.waveBottom.color, value: status)
            }
            .settingsRow()
        } footer: {
            Text("Download new music from your media server at home, over Tailscale.")
                .settingsFooter()
        }
    }

    private var status: String {
        if let progress = sync.progress { return "Syncing \(progress.downloaded)" }
        return MediaServerClient.normalizedURL(address) != nil && ServerTokenStore.hasToken ? "Set Up" : "Not Set Up"
    }
}

/// Settings → Media Server: the server's address, the device token (stored in the
/// Keychain, never shown again), a connection test with the server's libraries, and
/// Sync Now with progress.
struct MediaServerSettingsView: View {
    @Environment(ServerSyncStore.self) private var sync
    @Environment(ThemeStore.self) private var theme
    @Environment(\.modelContext) private var context
    @AppStorage(ServerSyncStore.addressKey) private var address = ""
    @AppStorage(ServerSyncStore.syncOnLaunchKey) private var syncOnLaunch = false
    @State private var tokenDraft = ""
    @State private var hasToken = ServerTokenStore.hasToken
    @State private var replacingToken = false
    @State private var test: TestState = .idle
    @State private var libraries: [ServerLibrary] = []

    private enum TestState: Equatable {
        case idle, testing, connected, failed(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("https://your-pc.your-tailnet.ts.net", text: $address)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .settingsRow()
            } header: {
                Text("Server Address")
            } footer: {
                Text("The server's Tailscale address. Tailscale must be connected on this iPhone (turn on VPN On Demand in the Tailscale app so it reconnects by itself).")
                    .settingsFooter()
            }

            Section {
                if hasToken && !replacingToken {
                    Label("Token saved in the Keychain", systemImage: "key.fill")
                        .foregroundStyle(theme.text)
                        .settingsRow()
                    Button("Replace Token…", systemImage: "arrow.triangle.2.circlepath") { replacingToken = true }
                        .settingsRow()
                    Button("Remove Token", systemImage: "trash", role: .destructive) {
                        ServerTokenStore.remove()
                        hasToken = false
                        test = .idle
                    }
                    .settingsRow()
                } else {
                    SecureField("Paste the device token", text: $tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .settingsRow()
                    Button("Save Token", systemImage: "key") {
                        if ServerTokenStore.save(tokenDraft) {
                            hasToken = true
                            replacingToken = false
                        }
                        tokenDraft = ""
                    }
                    .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .settingsRow()
                }
            } header: {
                Text("Device Token")
            } footer: {
                Text("This iPhone's token from the server's config.toml. It's stored only in the iOS Keychain and never shown again. If it's changed on the server, paste the new one here.")
                    .settingsFooter()
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        SettingsRowLabel(title: "Test Connection", systemImage: "antenna.radiowaves.left.and.right", tile: theme.accent)
                        if test == .testing { ProgressView() }
                    }
                }
                .disabled(test == .testing || MediaServerClient.normalizedURL(address) == nil)
                .settingsRow()

                switch test {
                case .connected:
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(theme.ambientAccentLight)
                        .settingsRow()
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.text)
                        .font(.subheadline)
                        .settingsRow()
                default:
                    EmptyView()
                }

                ForEach(libraries.filter(\.isMusic)) { library in
                    Toggle(isOn: Binding(get: { sync.isEnabled(library.name) }, set: { sync.setEnabled(library.name, $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(library.name == "hires" ? "High-Res" : library.name.capitalized)
                            Text(libraryDetail(library))
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                    .tint(theme.ambientAccent)
                    .settingsRow()
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("After a successful test, the server's music libraries are listed here: turn one off to skip it when syncing. High-Res songs are saved in their own folder, and Settings → Duplicates decides which copy shows when a song is in both.")
                    .settingsFooter()
            }

            Section {
                if let progress = sync.progress {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SettingsRowLabel(title: "Syncing \(progress.library == "hires" ? "High-Res" : progress.library.capitalized)",
                                             systemImage: "arrow.down.circle.fill", tile: theme.accent,
                                             value: progress.total > 0 ? "\(progress.checked) / \(progress.total)" : "\(progress.checked)")
                            Button("Stop", role: .cancel) { sync.cancel() }
                                .buttonStyle(.glass)
                                .tint(theme.ambientAccent)
                        }
                        if progress.total > 0 {
                            ProgressView(value: Double(min(progress.checked, progress.total)), total: Double(progress.total))
                                .tint(theme.ambientAccent)
                                .accessibilityLabel("Songs checked")
                        }
                        Text(countLabel(progress.downloaded, "song") + " downloaded")
                            .font(.subheadline)
                            .foregroundStyle(theme.secondaryText)
                        if let current = progress.current {
                            ProgressView(value: progress.currentFraction) {
                                Text(current).font(.footnote).lineLimit(1)
                            }
                            .tint(theme.ambientAccentLight)
                            .foregroundStyle(theme.secondaryText)
                        }
                    }
                    .settingsRow()
                } else {
                    Button {
                        sync.start(client: MediaServerClient.configured(address: address), context: context)
                    } label: {
                        SettingsRowLabel(title: "Sync Now", systemImage: "arrow.down.circle.fill", tile: theme.accent)
                    }
                    .disabled(!hasToken || MediaServerClient.normalizedURL(address) == nil)
                    .settingsRow()
                }

                if let error = sync.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(theme.text)
                        .settingsRow()
                } else if let summary = sync.lastSummary {
                    Text(summaryText(summary))
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                        .settingsRow()
                }

                NavigationLink {
                    ServerSongsView()
                } label: {
                    SettingsRowLabel(title: "Songs from the Server", systemImage: "music.note.list", tile: theme.favorite,
                                     value: "\(serverSongCount)")
                }
                .settingsRow()

                Toggle("Sync When Sun Opens", isOn: $syncOnLaunch)
                    .tint(theme.ambientAccent)
                    .settingsRow()
            } header: {
                Text("Sync")
            } footer: {
                Text("Downloads songs that are new or changed on the server, so they play offline. Songs removed on the server stay on your phone. Keep the app open for a big first sync: iOS pauses it shortly after you leave, and the next sync picks up where it stopped.")
                    .settingsFooter()
            }
        }
        .foregroundStyle(theme.text)
        .navigationTitle("Media Server")
        .navigationBarTitleDisplayMode(.inline)
        .backdropScreen()
    }

    private var serverSongCount: Int {
        (try? context.fetchCount(FetchDescriptor<Track>(predicate: #Predicate { $0.serverKey != nil }))) ?? 0
    }

    private func libraryDetail(_ library: ServerLibrary) -> String {
        guard library.available else { return "Drive not connected to the PC" }
        return library.count.map { countLabel($0, "song") } ?? "Available"
    }

    private func summaryText(_ summary: ServerSyncStore.Summary) -> String {
        var parts = [summary.cancelled ? "Stopped" : "Synced \(summary.date.formatted(date: .omitted, time: .shortened))",
                     "\(summary.downloaded) downloaded", "\(summary.added) new in your library"]
        if summary.updated > 0 { parts.append("\(summary.updated) updated") }
        if !summary.unavailable.isEmpty { parts.append("skipped \(summary.unavailable.joined(separator: ", ")) (drive not connected)") }
        return parts.joined(separator: " · ") + "."
    }

    /// Health first (no token: tells "server reachable" apart from "token wrong"), then the libraries.
    private func testConnection() async {
        guard let url = MediaServerClient.normalizedURL(address) else { return }
        test = .testing
        let client = MediaServerClient(baseURL: url, token: ServerTokenStore.token ?? "")
        do {
            _ = try await client.health()
            guard hasToken else {
                test = .failed("The server is reachable. Now paste the device token.")
                return
            }
            libraries = try await client.libraries()
            test = .connected
        } catch {
            test = .failed((error as? MediaServerError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

/// Every song downloaded from the media server. Songs you already had in another copy
/// (e.g. an MP3) are marked: the library shows one copy, chosen in Settings → Duplicates
/// (Lossless keeps the server's FLAC), so they don't appear as new songs.
struct ServerSongsView: View {
    @Environment(LibraryIndexStore.self) private var library
    @Environment(ThemeStore.self) private var theme
    @Query(filter: #Predicate<Track> { $0.serverKey != nil },
           sort: [SortDescriptor(\Track.artist), SortDescriptor(\Track.album)])
    private var serverSongs: [Track]

    init() {}

    var body: some View {
        List {
            if serverSongs.isEmpty {
                ContentUnavailableView("No Songs from the Server Yet", systemImage: "arrow.down.circle",
                                       description: Text("Use Sync Now to download music from your media server."))
                    .foregroundStyle(theme.text)
                    .plainListRow()
            } else {
                SectionHeader(title: countLabel(serverSongs.count, "song"), detail: detail)
                    .plainListRow()
                SongListSection(tracks: serverSongs)
            }
        }
        .libraryListStyle()
        .navigationTitle("Songs from the Server")
        .navigationBarTitleDisplayMode(.inline)
        .backdropScreen()
    }

    /// How many server songs replaced a copy you already had, and how many are hidden.
    private var detail: String {
        let replacing = Set(library.keptCopy.values)
        let hiddenCopies = library.index.hiddenCopies
        var parts: [String] = []
        let shownInPlace = serverSongs.count(where: { replacing.contains($0.id) })
        if shownInPlace > 0 { parts.append("\(shownInPlace) shown in place of a copy you already had") }
        let hidden = serverSongs.count(where: { hiddenCopies.contains($0.id) })
        if hidden > 0 { parts.append("\(hidden) hidden as duplicates") }
        return parts.isEmpty ? "Downloaded from your media server" : parts.joined(separator: " · ")
    }
}
