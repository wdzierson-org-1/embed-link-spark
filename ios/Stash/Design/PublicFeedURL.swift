import Foundation

/// The app's one `gostash.it/feed/{username}` formula — used by both `AccountSection` (Settings
/// tab, Task 7's original account-info build) and `SharingSection` (detail sheet, Fix round 1:
/// extracted here so the two call sites share one literal instead of two copies drifting apart).
enum PublicFeedURL {
    /// `nil` for a `nil` or empty `username` — callers gate their row/copy affordance on this so
    /// a bare `gostash.it/feed/` (nothing after the trailing slash) is never rendered or copied.
    static func make(username: String?) -> String? {
        guard let username, !username.isEmpty else { return nil }
        return "https://gostash.it/feed/\(username)"
    }
}
