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
