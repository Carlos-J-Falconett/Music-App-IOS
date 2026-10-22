import MediaPlayer
import UIKit

/// Lock screen, Control Center and headphone-button support. This replaces the
/// desktop app's MPRIS integration.
final class NowPlayingBridge {
    struct Handlers {
        var play: () -> Void
        var pause: () -> Void
        var togglePlayPause: () -> Void
        var next: () -> Void
        var previous: () -> Void
        var seek: (Double) -> Void
    }

    private var artworkKey: String?
    private var artwork: MPMediaItemArtwork?

    func configure(_ handlers: Handlers) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { _ in handlers.play(); return .success }
        center.pauseCommand.addTarget { _ in handlers.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { _ in handlers.togglePlayPause(); return .success }
        center.nextTrackCommand.addTarget { _ in handlers.next(); return .success }
        center.previousTrackCommand.addTarget { _ in handlers.previous(); return .success }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            handlers.seek(event.positionTime)
            return .success
        }
    }

    /// Publishes the current song. Call after every play/pause/seek/track change.
    func update(track: Track?, elapsed: Double, duration: Double, isPlaying: Bool) {
        guard let track else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if track.coverKey == artworkKey, let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if track.coverKey != artworkKey {
            loadArtwork(for: track.coverKey)
        }
    }

    private func loadArtwork(for key: String?) {
        artworkKey = key
        artwork = nil
        guard let key else { return }
        Task {
            guard let image = await ArtCache.load(key, .full), artworkKey == key else { return }
            let artwork = Self.makeArtwork(image)
            self.artwork = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
        }
    }

    /// Built outside the main actor: MediaPlayer calls the request handler on a background queue.
    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
