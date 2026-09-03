import Foundation

/// The app's one `gostash.it/feed/{username}` formula — used by both `AccountSection` (Settings
/// tab, Task 7's original account-info build) and `SharingSection` (detail sheet, Fix round 1:
/// extracted here so the two call sites share one literal instead of two copies drifting apart).
enum PublicFeedURL {
    static func make(username: String?) -> String {
        "https://gostash.it/feed/\(username ?? "")"
    }
}
