import SwiftUI
import SwiftData

/// "Up Next", shown in Now Playing's square in place of the cover (like the
/// equalizer). Tap a song to jump to it, swipe to remove, or tap Edit to drag
/// songs into a new order. Clear empties everything after the current song.
struct QueuePanel: View {
    /// One upcoming queue entry with its song.
    private struct Row: Identifiable {
        let entry: QueueEntry
        let track: Track
        var id: QueueEntry.ID { entry.id }
    }

    @Environment(MusicPlayer.self) private var player
    @Environment(ThemeStore.self) private var theme
    @Query private var tracks: [Track]
    @State private var editMode: EditMode = .inactive

    var body: some View {
        let lookup = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Resolve songs up front so every ForEach element is exactly one row. A
        // conditional inside ForEach makes List build every row of a shuffled
        // 1,500-song queue at once, which froze the queue.
        let rows = player.queue.upcoming.compactMap { entry in lookup[entry.trackID].map { Row(entry: entry, track: $0) } }

        VStack(spacing: 0) {
            header(count: rows.count)

            if rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.append")
                        .font(.title)
                    Text(player.queue.repeatMode == .all
                         ? "Repeat Queue is on, so the queue starts over after this song."
                         : "Nothing queued. Use “Play Next” or “Add to Queue” on any song.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(theme.secondaryText)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(rows) { row in
                        Button {
                            player.jump(to: row.entry)
                        } label: {
                            SongRow(track: row.track)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(theme.hairline)
                        .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
                    }
                    .onMove { source, destination in
                        var ids = rows.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        player.queue.reorderUpcoming(ids)
                    }
                    .onDelete { offsets in
                        player.queue.removeUpcoming(ids: Set(offsets.map { rows[$0].id }))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // The list sits inside its own panel, not under a bar, so the system's soft
                // scroll-edge blur (meant for content under toolbars) only smeared the top rows.
                .scrollEdgeEffectHidden(true, for: .all)
                .environment(\.editMode, $editMode)
            }
        }
        .nowPlayingPanel()
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Up Next")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.text)
                Text(count == 0 ? "Empty" : countLabel(count, "song"))
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            Button("Clear", role: .destructive) {
                withAnimation { player.queue.clearUpcoming() }
                editMode = .inactive
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
            .disabled(count == 0)
            Button(editMode.isEditing ? "Done" : "Edit") {
                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
            }
            .fontWeight(.semibold)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .disabled(count == 0)
        }
        .font(.subheadline)
        .tint(theme.ambientAccentLight)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}
