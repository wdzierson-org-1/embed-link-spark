import Foundation

/// Pure builders for `CapturedLocation` — the label rule (web port, `useCaptureLocation.ts:37-45`)
/// and the `CapturedLocation` assembly for a resolved device fix. No CoreLocation/CLGeocoder import
/// here: this file only turns already-resolved strings/coordinates into the values the composer/API
/// need, so it's fully unit-testable under `swift test` without a simulator. `LocationCapture` (app
/// target, per the brief's StashKit/app split) owns the actual CLLocationManager/CLGeocoder
/// plumbing and calls these two functions once it has a fix plus a reverse-geocoded placemark.
///
/// `place` on iOS is always `placemark.locality` — there's no second "locality" field to itself
/// fall back to the way the web's BigDataCloud response carries `city`/`locality` as two separate
/// keys (`useCaptureLocation.ts:38`: `geo.city?.trim() || geo.locality?.trim()`) — so unlike the
/// web's own `buildLabel`, this port takes one pre-resolved `city` string, not two candidates to
/// itself choose between; the caller (`LocationCapture`) is the one place that maps
/// `placemark.locality` in.

/// Web parity (`useCaptureLocation.ts:37-45`, `buildLabel`) / Global Constraints ("label rule:
/// 'City, Region' when both known and different, else the non-empty one, else country"): `city`
/// and `region` both present and different → `"City, Region"`; otherwise the first non-blank of
/// city, region, country; all blank/nil → `nil`. Every parameter is trimmed and treated as absent
/// when blank, matching the web's `.trim() || undefined` collapse for each field — a placemark
/// field that comes back present-but-empty must not produce a leading-comma artifact or silently
/// win over a real fallback.
public func buildLocationLabel(city: String?, region: String?, country: String?) -> String? {
    let place = city?.trimmedNonEmpty
    let regionName = region?.trimmedNonEmpty
    let countryName = country?.trimmedNonEmpty

    if let place, let regionName, place != regionName { return "\(place), \(regionName)" }
    if let place { return place }
    if let regionName { return regionName }
    return countryName
}

/// Assembles a device-fix `CapturedLocation` (Global Constraints: `source: "device-geolocation"`;
/// `capturedAt` = the FIX time — `fixDate`, i.e. `CLLocation.timestamp`, never "now" — as ISO-8601
/// UTC; accuracy rounded to the nearest meter, same as the web's `Math.round(accuracy)`). Returns
/// `nil` whenever `buildLocationLabel` can't produce a label: a `CapturedLocation` with no
/// nameable place would render an empty "posted from" line, so the caller (`LocationCapture`)
/// treats a `nil` result as "this fix isn't usable" and falls to its own failure path rather than
/// pinning bare coordinates with nothing to show for them.
public func buildCapturedLocation(
    latitude: Double, longitude: Double, accuracy: Double?,
    city: String?, region: String?, country: String?, fixDate: Date
) -> CapturedLocation? {
    guard let label = buildLocationLabel(city: city, region: region, country: country) else { return nil }
    return CapturedLocation(
        label: label,
        latitude: latitude,
        longitude: longitude,
        accuracyM: accuracy.map { $0.rounded() },
        city: city?.trimmedNonEmpty,
        region: region?.trimmedNonEmpty,
        country: country?.trimmedNonEmpty,
        source: "device-geolocation",
        capturedAt: capturedAtFormatter.string(from: fixDate)
    )
}

// MARK: - Manual (typed) edits — Task 8, detail sheet's LocationRow

/// Builds the `CapturedLocation` for a manual (typed) location edit — port of the web's
/// `EditItemLocationSection.tsx:51-55`. Typing a label always authors `source: "manual"` with
/// ONLY that label: unlike `buildCapturedLocation` above (a resolved device fix), a manual edit
/// has no coordinates/placemark to attach — any earlier fix's `latitude`/`longitude`/`city`/
/// `region`/`country` are simply never carried forward, since they no longer describe whatever
/// place the user just typed by hand. `capturedAt` is "now" (there's no fix to timestamp);
/// injectable for tests, every non-test call site uses the default `Date()`.
public func buildManualLocation(label: String, now: Date = Date()) -> CapturedLocation {
    CapturedLocation(label: label, source: "manual", capturedAt: capturedAtFormatter.string(from: now))
}

/// Computes the next `ItemAttributes` for a `LocationRow` commit, or `nil` for a no-op — port of
/// the web's `EditItemLocationSection.tsx:39-58` `commit`. `rawValue` is the field's raw typed
/// text (untrimmed); trimmed and compared against the CURRENT location's label (both treated as
/// `""` when absent, matching the web's `label === (location?.label ?? '')`) — unchanged means
/// nothing to save, so callers should skip the write entirely rather than sending a same-value
/// PATCH. An empty trimmed value removes `location` outright; a non-empty one replaces it wholesale
/// with a fresh manual `CapturedLocation` (`buildManualLocation` above). Either way, every other
/// top-level key on `current` — `link`/`media`/`extra` — rides through untouched: this only ever
/// reassigns the `location` property of a copy of `current`, never rebuilds the blob from scratch.
///
/// Concurrency caveat (matches the web's own "sheet's item prop freezes while open" comment on
/// `EditItemLocationSection.tsx`): this function is pure and just trusts whatever `current` it's
/// given — it's the CALLER's job to pass the freshest adopted attributes at the moment of commit,
/// not a value captured once when editing started. `LocationRow` (Stash app target) does this via
/// a live `Binding` onto `ItemDetailView`'s `item.attributes`, which is arguably fresher than the
/// web's own frozen-at-open-time prop, but the same class of race remains possible in principle if
/// some other attributes-writing flow saved in between — see `LocationRow`'s own doc comment.
public func locationEditCommit(current: ItemAttributes, rawValue: String, now: Date = Date()) -> ItemAttributes? {
    let label = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard label != (current.location?.label ?? "") else { return nil }

    var next = current
    next.location = label.isEmpty ? nil : buildManualLocation(label: label, now: now)
    return next
}

/// Plain ISO-8601 UTC, no fractional seconds (e.g. `"2023-11-14T22:13:20Z"`) — `Item.swift`'s own
/// decoder tolerates either shape with or without fractional seconds on the way IN; this is the
/// way OUT, so it only needs to pick one, and whole-second precision is enough for a location fix.
private let capturedAtFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Toggle decision (review fix, Critical finding)

/// What a tap on the pin button should do next. Extracted as a pure enum + decision function
/// (below) so `LocationCapture.toggle()`'s state-machine logic — including the
/// never-start-a-second-concurrent-resolution rule the review's Critical finding was about — is
/// unit-testable under `swift test`, even though the surrounding CLLocationManager/continuation
/// plumbing that ACTS on this decision is CoreLocation-coupled and lives app-side only.
public enum LocationToggleAction: Equatable {
    /// Turn off: cancel anything in flight (if any) and clear to `.off`. Fires from ANY non-off
    /// state, including `.failed` (a second tap is what actually retries — ledgered UX polish,
    /// not fixed here) and `.ready` (turning an already-resolved pin back off).
    case turnOff
    /// A resolution is already in flight — reflect `.resolving` but do NOT start a second one.
    /// Web parity: `useCaptureLocation.ts:62-63`'s `if (inFlightRef.current) return
    /// inFlightRef.current`.
    case reuseInFlight
    /// A cached location is still within its window — adopt it immediately, no CoreLocation/
    /// geocode round trip.
    case useCache
    /// Nothing else applies — begin a fresh one-shot resolution.
    case startFresh
}

/// Pure decision table backing `LocationCapture.toggle()`. `isOff` is `state == .off` at the
/// moment of the tap; `hasInFlightResolve`/`hasCacheWithinWindow` are the two other facts the
/// live implementation already tracks (`inFlightResolve != nil`, and the 5-minute cache-window
/// check respectively). In-flight reuse takes priority over a cache hit whenever both could
/// apply — there's nothing to gain from replacing an already-running resolution with a cached
/// value that's actually staler than what's about to land.
public func decideLocationToggleAction(
    isOff: Bool, hasInFlightResolve: Bool, hasCacheWithinWindow: Bool
) -> LocationToggleAction {
    guard isOff else { return .turnOff }
    if hasInFlightResolve { return .reuseInFlight }
    if hasCacheWithinWindow { return .useCache }
    return .startFresh
}
