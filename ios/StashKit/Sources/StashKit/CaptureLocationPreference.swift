import Foundation

/// Per-account opt-in shared by Add and the share extension. Coordinates never reach defaults.
public struct CaptureLocationPreference {
    public struct Snapshot: Equatable, Sendable {
        public let enabled: Bool
        public let revision: String
    }

    private let defaults: UserDefaults?
    private let key: String

    public init(userId: UUID, defaults: UserDefaults? = UserDefaults(suiteName: AppGroup.identifier)) {
        self.defaults = defaults
        key = "capture.location.v1.\(userId.uuidString.lowercased())"
    }

    public var snapshot: Snapshot {
        // Refresh the shared suite before reading another process's explicit choice.
        // No app-local mirror is written on resume, so an extension opt-out wins.
        defaults?.synchronize()
        guard let record = defaults?.dictionary(forKey: key),
              let enabled = record["enabled"] as? Bool,
              let revision = record["revision"] as? String, !revision.isEmpty else {
            return Snapshot(enabled: false, revision: "")
        }
        return Snapshot(enabled: enabled, revision: revision)
    }

    public func setEnabled(_ enabled: Bool) {
        guard snapshot.enabled != enabled else { return }
        // One record keeps the consent bit and its cache-revocation identity together.
        defaults?.set(["enabled": enabled, "revision": UUID().uuidString], forKey: key)
        defaults?.synchronize()
    }
}

/// In-memory only, scoped to the consent revision that allowed the fix.
public struct CaptureLocationCache {
    private var entry: (location: CapturedLocation, fixDate: Date, revision: String)?
    public init() {}
    public mutating func store(_ location: CapturedLocation, fixDate: Date,
                               consent: CaptureLocationPreference.Snapshot, now: Date = Date()) {
        guard consent.enabled, !consent.revision.isEmpty,
              let latitude = location.latitude, let longitude = location.longitude,
              let accuracy = location.accuracyM,
              Self.isUsableFix(latitude: latitude, longitude: longitude, accuracy: accuracy,
                               fixDate: fixDate, now: now) else { entry = nil; return }
        entry = (location, fixDate, consent.revision)
    }

    public func location(consent: CaptureLocationPreference.Snapshot, now: Date = Date()) -> CapturedLocation? {
        guard consent.enabled, let entry, consent.revision == entry.revision,
              let latitude = entry.location.latitude, let longitude = entry.location.longitude,
              let accuracy = entry.location.accuracyM,
              Self.isUsableFix(latitude: latitude, longitude: longitude, accuracy: accuracy,
                               fixDate: entry.fixDate, now: now) else { return nil }
        return entry.location
    }

    public mutating func clear() { entry = nil }

    /// Five minutes from the sensor's fix timestamp, not from a later geocode response.
    /// Permit locality-level approximate fixes, reject invalid/unbounded accuracy.
    public static func isUsableFix(latitude: Double, longitude: Double, accuracy: Double,
                                   fixDate: Date, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(fixDate)
        return latitude.isFinite && longitude.isFinite && accuracy.isFinite && age.isFinite &&
            (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
            (0...5_000).contains(accuracy) && age >= -30 && age < 5 * 60
    }
}
