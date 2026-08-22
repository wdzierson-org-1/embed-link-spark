import XCTest
@testable import StashKit

/// `LocationBuild`'s pure logic: the label rule (web port, `useCaptureLocation.ts:37-45`) and
/// `CapturedLocation` assembly for a resolved device fix. `LocationCapture` (app target,
/// CLLocationManager/CLGeocoder plumbing) has no unit coverage here by design — it's exercised
/// live by `testLocationPinSmoke` (StashUITests) instead; nothing in this file touches CoreLocation.
final class LocationBuildTests: XCTestCase {

    // MARK: - buildLocationLabel

    func testBothCityAndRegionDifferentJoinsWithComma() {
        XCTAssertEqual(buildLocationLabel(city: "Saratoga Springs", region: "New York", country: "United States"),
                       "Saratoga Springs, New York")
    }

    func testSameCityAndRegionReturnsJustCity() {
        XCTAssertEqual(buildLocationLabel(city: "New York", region: "New York", country: "United States"),
                       "New York")
    }

    func testCityOnly() {
        XCTAssertEqual(buildLocationLabel(city: "Brooklyn", region: nil, country: nil), "Brooklyn")
    }

    func testRegionOnly() {
        XCTAssertEqual(buildLocationLabel(city: nil, region: "New York", country: nil), "New York")
    }

    func testCountryOnly() {
        XCTAssertEqual(buildLocationLabel(city: nil, region: nil, country: "United States"), "United States")
    }

    func testAllNilReturnsNil() {
        XCTAssertNil(buildLocationLabel(city: nil, region: nil, country: nil))
    }

    /// Blank (whitespace-only or empty) strings collapse to absent, same as the web's
    /// `.trim() || undefined` — a placemark field that's present but empty must not produce a
    /// leading-comma artifact or silently win over a real fallback further down the rule.
    func testBlankStringsAreTreatedAsAbsent() {
        XCTAssertEqual(buildLocationLabel(city: "   ", region: "New York", country: nil), "New York")
        XCTAssertEqual(buildLocationLabel(city: "", region: "", country: "United States"), "United States")
        XCTAssertNil(buildLocationLabel(city: " ", region: "\n", country: ""))
    }

    func testRegionFallsBackWhenCityMissingButCountryAlsoPresent() {
        // region wins over country when city is absent — the rule order is place, region, country.
        XCTAssertEqual(buildLocationLabel(city: nil, region: "Ontario", country: "Canada"), "Ontario")
    }

    // MARK: - buildCapturedLocation

    func testBuildCapturedLocationNilLabelReturnsNil() {
        let result = buildCapturedLocation(latitude: 43.0831, longitude: -73.7846, accuracy: 10,
                                           city: nil, region: nil, country: nil, fixDate: Date())
        XCTAssertNil(result)
    }

    func testBuildCapturedLocationPopulatesFieldsAndSource() throws {
        let fixDate = Date(timeIntervalSince1970: 1_700_000_000)
        let result = buildCapturedLocation(latitude: 43.0831, longitude: -73.7846, accuracy: 12.4,
                                           city: "Saratoga Springs", region: "New York", country: "United States",
                                           fixDate: fixDate)
        let location = try XCTUnwrap(result)
        XCTAssertEqual(location.label, "Saratoga Springs, New York")
        XCTAssertEqual(location.latitude, 43.0831)
        XCTAssertEqual(location.longitude, -73.7846)
        XCTAssertEqual(location.city, "Saratoga Springs")
        XCTAssertEqual(location.region, "New York")
        XCTAssertEqual(location.country, "United States")
        XCTAssertEqual(location.source, "device-geolocation")
    }

    func testAccuracyIsRoundedToNearestWholeNumber() throws {
        let roundedDown = try XCTUnwrap(buildCapturedLocation(latitude: 0, longitude: 0, accuracy: 12.4,
                                                               city: "X", region: nil, country: nil, fixDate: Date()))
        XCTAssertEqual(roundedDown.accuracyM, 12)

        let roundedUp = try XCTUnwrap(buildCapturedLocation(latitude: 0, longitude: 0, accuracy: 12.5,
                                                             city: "X", region: nil, country: nil, fixDate: Date()))
        XCTAssertEqual(roundedUp.accuracyM, 13)
    }

    func testNilAccuracyStaysNil() throws {
        let location = try XCTUnwrap(buildCapturedLocation(latitude: 0, longitude: 0, accuracy: nil,
                                                            city: "X", region: nil, country: nil, fixDate: Date()))
        XCTAssertNil(location.accuracyM)
    }

    func testCapturedAtFormatsFixDateAsISO8601UTC() throws {
        let fixDate = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14T22:13:20Z
        let location = try XCTUnwrap(buildCapturedLocation(latitude: 0, longitude: 0, accuracy: nil,
                                                            city: "X", region: nil, country: nil, fixDate: fixDate))
        XCTAssertEqual(location.capturedAt, "2023-11-14T22:13:20Z")
    }

    /// `capturedAt` must be the FIX time, never "now" (Global Constraints: "captured_at = the FIX
    /// time"). A second, independent epoch (rather than reusing the test above's) guards against a
    /// future edit accidentally swapping in `Date()` at the call site, which would only show up as
    /// a flaky/wrong value here, not a compile error.
    func testCapturedAtIsDeterministicFromFixDateNotWallClock() throws {
        let fixDate = Date(timeIntervalSince1970: 0)   // 1970-01-01T00:00:00Z
        let location = try XCTUnwrap(buildCapturedLocation(latitude: 0, longitude: 0, accuracy: nil,
                                                            city: "X", region: nil, country: nil, fixDate: fixDate))
        XCTAssertEqual(location.capturedAt, "1970-01-01T00:00:00Z")
    }

    // MARK: - buildManualLocation (Task 8)
    //
    // The detail sheet's `LocationRow` builder for a typed (manual) edit — web port,
    // `EditItemLocationSection.tsx:51-55`. Unlike `buildCapturedLocation` above (a resolved
    // device fix), a manual edit has no coordinates/placemark to attach, ever — only a label.

    func testManualLocationHasManualSourceAndOnlyLabel() {
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14T22:13:20Z
        let location = buildManualLocation(label: "Brooklyn, New York", now: fixedNow)
        XCTAssertEqual(location.label, "Brooklyn, New York")
        XCTAssertEqual(location.source, "manual")
        XCTAssertNil(location.latitude)
        XCTAssertNil(location.longitude)
        XCTAssertNil(location.accuracyM)
        XCTAssertNil(location.city)
        XCTAssertNil(location.region)
        XCTAssertNil(location.country)
        XCTAssertEqual(location.capturedAt, "2023-11-14T22:13:20Z")
    }

    /// The exact server-facing proof `testLocationEditSmoke` (StashUITests) asserts live: a
    /// manual location's JSON has no `latitude` KEY at all — Swift's synthesized `Encodable` for
    /// an `Optional` stored property uses `encodeIfPresent`, which omits absent values rather
    /// than writing `null`. Pinned here so a regression (e.g. a future hand-written `encode(to:)`
    /// that switches to plain `encode`) fails fast in a unit test instead of only showing up as a
    /// stray `"latitude": null` on a live PATCH.
    func testManualLocationOmitsCoordinateKeysEntirelyWhenJSONEncoded() throws {
        let location = buildManualLocation(label: "Brooklyn, New York")
        let data = try JSONEncoder().encode(location)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertFalse(object.keys.contains("latitude"))
        XCTAssertFalse(object.keys.contains("longitude"))
        XCTAssertFalse(object.keys.contains("accuracy_m"))
        XCTAssertEqual(object["label"] as? String, "Brooklyn, New York")
        XCTAssertEqual(object["source"] as? String, "manual")
    }

    // MARK: - locationEditCommit (Task 8)
    //
    // The detail sheet's `LocationRow` read-modify-write — web port,
    // `EditItemLocationSection.tsx:39-58`'s `commit`. Pure so every edge case (no-op, clear,
    // sibling-key preservation, coordinate-dropping) is unit-testable without a simulator.

    func testCommitNoOpsWhenTrimmedLabelUnchanged() {
        let current = ItemAttributes(location: CapturedLocation(label: "Brooklyn", source: "manual"))
        XCTAssertNil(locationEditCommit(current: current, rawValue: "Brooklyn"))
        XCTAssertNil(locationEditCommit(current: current, rawValue: "  Brooklyn  "),
                     "surrounding whitespace alone must not count as a change")
    }

    func testCommitNoOpsWhenAbsentAndTypedEmpty() {
        let current = ItemAttributes()
        XCTAssertNil(locationEditCommit(current: current, rawValue: "   "))
    }

    func testEmptyCommitRemovesLocationKeyButPreservesRestOfBlob() throws {
        let link = LinkAttributes(flavor: "article")
        let current = ItemAttributes(location: CapturedLocation(label: "Brooklyn", source: "manual"), link: link)

        let next = try XCTUnwrap(locationEditCommit(current: current, rawValue: ""))

        XCTAssertNil(next.location)
        XCTAssertEqual(next.link, link, "clearing location must never touch sibling attribute keys")
    }

    func testNonEmptyCommitBuildsManualLocationAndDropsPriorCoordinates() throws {
        let deviceLocation = CapturedLocation(label: "Old Place", latitude: 1, longitude: 2, accuracyM: 3,
                                              city: "Old Place", region: "OP", country: "US",
                                              source: "device-geolocation", capturedAt: "2020-01-01T00:00:00Z")
        let extra: [String: JSONValue] = ["mood": .string("good")]
        let current = ItemAttributes(location: deviceLocation, extra: extra)
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

        let next = try XCTUnwrap(locationEditCommit(current: current, rawValue: "  Test City  ", now: fixedNow))

        let location = try XCTUnwrap(next.location)
        XCTAssertEqual(location.label, "Test City")
        XCTAssertEqual(location.source, "manual")
        XCTAssertNil(location.latitude)
        XCTAssertNil(location.city)
        XCTAssertEqual(location.capturedAt, "2023-11-14T22:13:20Z")
        XCTAssertEqual(next.extra, extra, "unrelated top-level keys must survive the read-modify-write")
    }

    func testChangingLabelToADifferentNonEmptyValueIsNotANoOp() {
        let current = ItemAttributes(location: CapturedLocation(label: "Brooklyn", source: "manual"))
        XCTAssertNotNil(locationEditCommit(current: current, rawValue: "Queens"))
    }

    // MARK: - decideLocationToggleAction (review fix, Critical finding)
    //
    // `LocationCapture.toggle()`'s own CLLocationManager/continuation plumbing has no unit-test
    // seam (CoreLocation-coupled, app target only — see task-6-report.md's fix addendum for why).
    // This is the pure state-machine DECISION that plumbing acts on, extracted so the actual
    // invariant the review's Critical finding is about — never start a second concurrent
    // resolution — is verifiable under `swift test`.

    func testAnyNonOffStateTurnsOff() {
        // `isOff: false` covers `.resolving`/`.ready`/`.failed` uniformly — `turnOff` fires
        // regardless of the other two facts, including `.failed` (a second tap retries; that's
        // ledgered UX polish, not something this decision changes).
        XCTAssertEqual(decideLocationToggleAction(isOff: false, hasInFlightResolve: false, hasCacheWithinWindow: false), .turnOff)
        XCTAssertEqual(decideLocationToggleAction(isOff: false, hasInFlightResolve: true, hasCacheWithinWindow: true), .turnOff)
    }

    func testOffWithInFlightResolveReusesIt() {
        XCTAssertEqual(decideLocationToggleAction(isOff: true, hasInFlightResolve: true, hasCacheWithinWindow: false), .reuseInFlight)
    }

    func testOffWithFreshCacheAndNoInFlightUsesCache() {
        XCTAssertEqual(decideLocationToggleAction(isOff: true, hasInFlightResolve: false, hasCacheWithinWindow: true), .useCache)
    }

    func testOffWithNoInFlightAndNoCacheStartsFresh() {
        XCTAssertEqual(decideLocationToggleAction(isOff: true, hasInFlightResolve: false, hasCacheWithinWindow: false), .startFresh)
    }

    /// The exact priority the Critical finding hinges on: an in-flight resolution must win over
    /// a fresh cache hit, not the other way round — there must never be a path that starts (or
    /// implicitly prefers something over) a second concurrent resolution while one is already
    /// running.
    func testInFlightResolveTakesPriorityOverAFreshCache() {
        XCTAssertEqual(decideLocationToggleAction(isOff: true, hasInFlightResolve: true, hasCacheWithinWindow: true), .reuseInFlight)
    }

    /// Pure-logic "stress" walkthrough of the exact rapid toggle→toggle→toggle cycle the review's
    /// Critical finding was about (LocationCapture's own continuation bookkeeping has no
    /// unit-test seam; this exercises the same sequence of DECISIONS a user's rapid
    /// off→on→off→on tapping would drive the state machine through).
    func testDecisionSequenceMatchesARapidOffOnOffOnToggleCycle() {
        // 1) Off, nothing cached, nothing in flight → first tap starts a fresh resolution.
        XCTAssertEqual(decideLocationToggleAction(isOff: true, hasInFlightResolve: false, hasCacheWithinWindow: false), .startFresh)
        // 2) While that's still in flight, a second tap (now .resolving, so isOff: false) turns
        //    it off — the live implementation cancels the Task and resumes its continuation here.
        XCTAssertEqual(decideLocationToggleAction(isOff: false, hasInFlightResolve: true, hasCacheWithinWindow: false), .turnOff)
        // 3) A third tap, immediately after — even if the cancelled resolution's own cleanup
        //    hasn't finished running yet (hasInFlightResolve still reads true), this must reuse
        //    it rather than start a SECOND concurrent resolution.
        XCTAssertEqual(decideLocationToggleAction(isOff: true, hasInFlightResolve: true, hasCacheWithinWindow: false), .reuseInFlight)
        // 4) Once that resolution has actually finished and cleared, a later tap recovers
        //    cleanly and starts fresh again — the cycle isn't permanently stuck.
        XCTAssertEqual(decideLocationToggleAction(isOff: true, hasInFlightResolve: false, hasCacheWithinWindow: false), .startFresh)
    }
}
