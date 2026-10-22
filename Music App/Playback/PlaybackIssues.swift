import Foundation
import Observation
import UIKit

/// One song that couldn't be played, with enough detail to find out why.
nonisolated struct PlaybackIssue: Codable, Identifiable, Sendable, Equatable {
    var id = UUID()
    var date: Date
    var title: String
    var artist: String
    /// The file's path inside the library (`Documents/Music/…`).
    var path: String
    /// What failed, e.g. "the audio engine wouldn't start (NSOSStatusErrorDomain 561015905)".
    var reason: String
    /// Whether the app was in the background or the phone locked at the time.
    var inBackground: Bool
    /// True when retrying after resetting the audio engine worked (the song played).
    var recovered: Bool
}

/// The last 50 playback problems, saved so they survive relaunching the app.
/// Shown in Settings → Playback Problems.
@Observable
final class PlaybackIssueLog {
    private static let key = "playbackIssues"
    static let limit = 50

    private(set) var issues: [PlaybackIssue]

    init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        issues = data.flatMap { try? JSONDecoder().decode([PlaybackIssue].self, from: $0) } ?? []
    }

    func record(_ issue: PlaybackIssue) {
        issues.insert(issue, at: 0)
        if issues.count > Self.limit { issues.removeLast(issues.count - Self.limit) }
        save()
    }

    func clear() {
        issues = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(issues) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// True while the app isn't in the foreground (lock screen, other apps).
    static var appIsInBackground: Bool {
        UIApplication.shared.applicationState != .active
    }
}
