import XCTest
@testable import StashKit

final class CaptureLocationPreferenceTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private let user = UUID()
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        suite = "CaptureLocationPreferenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testFreshAccountDefaultsOffWithoutCreatingConsent() {
        let preference = CaptureLocationPreference(userId: user, defaults: defaults)
        XCTAssertFalse(preference.snapshot.enabled)
        XCTAssertTrue(defaults.persistentDomain(forName: suite)?.isEmpty ?? true)
    }

    func testExplicitChoicePersistsBetweenIndependentCaptureSurfaces() {
        let app = CaptureLocationPreference(userId: user, defaults: defaults)
        let share = CaptureLocationPreference(userId: user, defaults: UserDefaults(suiteName: suite)!)
        app.setEnabled(true)
        XCTAssertTrue(share.snapshot.enabled)
        XCTAssertEqual(app.snapshot, share.snapshot)
        share.setEnabled(false)
        XCTAssertFalse(app.snapshot.enabled)
    }

    func testAnotherAccountNeverInheritsConsentOrCachedLocation() {
        let first = CaptureLocationPreference(userId: user, defaults: defaults)
        let second = CaptureLocationPreference(userId: UUID(), defaults: defaults)
        first.setEnabled(true)
        var cache = CaptureLocationCache()
        cache.store(location, fixDate: now, consent: first.snapshot, now: now)
        XCTAssertFalse(second.snapshot.enabled)
        XCTAssertNil(cache.location(consent: second.snapshot, now: now))
        second.setEnabled(true)
        XCTAssertNil(cache.location(consent: second.snapshot, now: now))
        XCTAssertTrue(first.snapshot.enabled)
    }

    func testOptOutAndReenableCannotResurrectAnEarlierLocation() {
        let app = CaptureLocationPreference(userId: user, defaults: defaults)
        let share = CaptureLocationPreference(userId: user, defaults: UserDefaults(suiteName: suite)!)
        app.setEnabled(true)
        var cache = CaptureLocationCache()
        cache.store(location, fixDate: now, consent: app.snapshot, now: now)
        XCTAssertNotNil(cache.location(consent: app.snapshot, now: now))
        share.setEnabled(false)
        XCTAssertNil(cache.location(consent: app.snapshot, now: now))
        share.setEnabled(true)
        XCTAssertTrue(app.snapshot.enabled)
        XCTAssertNil(cache.location(consent: app.snapshot, now: now), "Off then on in another process revokes the old fix")
        cache.store(location, fixDate: now, consent: app.snapshot, now: now)
        XCTAssertNotNil(cache.location(consent: app.snapshot, now: now))
    }

    func testCacheExpiresFromFixTimeNotGeocodingCompletion() {
        let preference = CaptureLocationPreference(userId: user, defaults: defaults)
        preference.setEnabled(true)
        var cache = CaptureLocationCache()
        cache.store(location, fixDate: now.addingTimeInterval(-299), consent: preference.snapshot, now: now)
        XCTAssertNotNil(cache.location(consent: preference.snapshot, now: now))
        XCTAssertNil(cache.location(consent: preference.snapshot, now: now.addingTimeInterval(1)))
    }

    func testInvalidStaleAndUnreliableFixesAreRejected() {
        func valid(_ latitude: Double = 40, _ longitude: Double = -74, _ accuracy: Double = 100,
                   _ date: Date? = nil) -> Bool {
            CaptureLocationCache.isUsableFix(latitude: latitude, longitude: longitude,
                                             accuracy: accuracy, fixDate: date ?? now, now: now)
        }
        XCTAssertTrue(valid())
        XCTAssertTrue(valid(40, -74, 5_000), "Approximate permission can still supply a locality-level fix")
        XCTAssertFalse(valid(.nan))
        XCTAssertFalse(valid(91))
        XCTAssertFalse(valid(40, 181))
        XCTAssertFalse(valid(40, -74, -1))
        XCTAssertFalse(valid(40, -74, .infinity))
        XCTAssertFalse(valid(40, -74, 5_001))
        XCTAssertFalse(valid(40, -74, 100, now.addingTimeInterval(-300)))
        XCTAssertFalse(valid(40, -74, 100, now.addingTimeInterval(60)))
    }

    func testOnlyConsentIsPersistedAndStoppingCacheDoesNotDisableIt() throws {
        let preference = CaptureLocationPreference(userId: user, defaults: defaults)
        preference.setEnabled(true)
        var cache = CaptureLocationCache()
        cache.store(location, fixDate: now, consent: preference.snapshot, now: now)
        cache.clear()
        XCTAssertNil(cache.location(consent: preference.snapshot, now: now))
        XCTAssertTrue(preference.snapshot.enabled)
        let values = try XCTUnwrap(defaults.persistentDomain(forName: suite))
        XCTAssertEqual(values.count, 1)
        let record = try XCTUnwrap(values.values.first as? [String: Any])
        XCTAssertEqual(Set(record.keys), ["enabled", "revision"])
    }

    private var location: CapturedLocation {
        CapturedLocation(label: "Current location", latitude: 40, longitude: -74,
                         accuracyM: 100, source: "device-geolocation")
    }
}
