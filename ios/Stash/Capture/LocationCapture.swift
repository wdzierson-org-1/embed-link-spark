import CoreLocation
import Foundation
import Observation
import StashKit

/// Drives the composer's pin toggle: a one-shot CoreLocation fix, reverse-geocoded via
/// `CLGeocoder`, assembled into a `CapturedLocation` by StashKit's pure `LocationBuild` builders.
/// App-side (not StashKit) by design — CLLocationManager/CLGeocoder are platform APIs StashKit
/// deliberately stays free of, same "app owns the platform touch point" precedent as
/// `CaptureViewModel`'s injected `upload`/`downscale` closures.
///
/// Web port: `useCaptureLocation.ts`. `state` mirrors its `status` (`idle`/`locating`/`ready`/
/// `error`) with an explicit `.off` standing in for the web's separate `enabled` flag — nothing
/// here ever needs "enabled" independent of what `state` already says.
///
/// `NSObject` subclass: `CLLocationManagerDelegate` is an `@objc` protocol that requires
/// `NSObjectProtocol` conformance, same as any other CoreLocation delegate — this doesn't conflict
/// with `@Observable` (Apple's own CoreLocation sample code combines them the same way).
@MainActor
@Observable
final class LocationCapture: NSObject {
    enum State: Equatable {
        case off
        case resolving
        case ready(CapturedLocation)
        case failed
    }

    private(set) var state: State = .off
    /// Set at the start of every resolution attempt that reaches an authorization check, true only
    /// if that check ends in `.denied`/`.restricted`. Drives whether the composer's failure alert
    /// also offers a "Open Settings" button (Task 6 brief: "auth denied → same alert + Settings
    /// deep-link button") — a plain fix/geocode failure (permission already granted) gets the same
    /// alert copy but no such button, since there's nothing to fix in Settings for that case.
    private(set) var authDenied = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    /// A resolved location plus when it resolved — reused by `toggle()` on a re-toggle within the
    /// 5-minute window (Task 6 brief: "5-minute cache"), independent of `state` (which does go back
    /// to `.off` when the user toggles off; the cache deliberately does not, so turning the pin back
    /// on a minute later doesn't re-run CoreLocation + a network geocode for the same fix).
    private var cache: (location: CapturedLocation, at: Date)?

    /// Generation token (same idiom as `SubscriptionStore.refreshGeneration`/
    /// `ItemStore.loadGeneration`): bumped by every `toggle()` call, captured locally at the start
    /// of `resolve(generation:)`, and checked before every `state` write inside it — so a
    /// resolution superseded by a later toggle (off, or a fresh on-cycle) can't clobber whatever
    /// that later call already decided, without needing Task-cancellation plumbing.
    private var generation = 0

    private var fixContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<Void, Never>?

    private static let cacheWindow: TimeInterval = 5 * 60
    private static let fixTimeout: TimeInterval = 10

    override init() {
        super.init()
        manager.delegate = self
    }

    /// The location to attach to a submit happening RIGHT NOW — `nil` for `.off`/`.resolving`/
    /// `.failed` (only `.ready` has one). `CaptureComposerView` wires this into
    /// `CaptureViewModel`'s injected `awaitPendingLocation` hook via `awaitResolution(timeout:)`
    /// below, never reads it directly for that purpose.
    var currentLocation: CapturedLocation? {
        if case .ready(let location) = state { return location }
        return nil
    }

    /// off→on: reuse a cache hit inside the 5-minute window immediately (no CoreLocation/geocode
    /// round trip); otherwise request auth if needed and resolve a fresh fix. on→off (from ANY
    /// non-off state, including mid-resolution or a stale failure): cancels this pin's claim on
    /// whatever's still in flight (via the generation bump — see its own doc comment) and goes
    /// straight back to `.off`. This is an explicit user cancel, never a failure, so no alert.
    func toggle() {
        generation += 1

        guard state == .off else {
            state = .off
            return
        }

        if let cache, Date().timeIntervalSince(cache.at) < Self.cacheWindow {
            state = .ready(cache.location)
            return
        }

        authDenied = false
        state = .resolving
        let thisGeneration = generation
        Task { await resolve(generation: thisGeneration) }
    }

    /// The app-side half of `CaptureViewModel.awaitPendingLocation(timeout:)`'s injected hook
    /// (Task 6 brief: "submit() waits ≤2.5s on .resolving … then proceeds with whatever
    /// resolved"). Returns immediately for every state but `.resolving` (`.off`/`.failed` have
    /// nothing to wait for; `.ready` is already resolved) — polls at a coarse 100ms interval
    /// otherwise, bounded by `timeout`, and returns whatever `currentLocation` reads once either
    /// the state has moved on or the deadline passes, whichever comes first.
    func awaitResolution(timeout: TimeInterval) async -> CapturedLocation? {
        guard state == .resolving else { return currentLocation }
        let deadline = Date().addingTimeInterval(timeout)
        while state == .resolving, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return currentLocation
    }

    // MARK: - Resolution

    private func resolve(generation: Int) async {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            await waitForAuthorizationDecision()
        }
        guard generation == self.generation else { return }   // superseded while awaiting auth

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .denied, .restricted:
            authDenied = true
            state = .failed
            return
        default:
            // Still `.notDetermined` (e.g. the app backgrounded mid-prompt and the user never
            // actually answered it) — a plain failure, not specifically "denied": there is no
            // Settings toggle to flip yet for a decision that was never made.
            state = .failed
            return
        }

        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        do {
            let fix = try await requestOneShotFix()
            guard generation == self.generation else { return }   // superseded while awaiting the fix

            let placemark = try? await geocoder.reverseGeocodeLocation(fix).first
            guard generation == self.generation else { return }   // superseded while awaiting the geocode

            guard let built = buildCapturedLocation(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                accuracy: fix.horizontalAccuracy >= 0 ? fix.horizontalAccuracy : nil,
                city: placemark?.locality,
                region: placemark?.administrativeArea,
                country: placemark?.country,
                fixDate: fix.timestamp
            ) else {
                state = .failed   // geocode succeeded but came back with nothing nameable
                return
            }
            cache = (built, Date())
            state = .ready(built)
        } catch {
            state = .failed
        }
    }

    /// One-shot fix (Task 6 brief: `desiredAccuracy kCLLocationAccuracyHundredMeters`, 10s
    /// timeout). `CLLocationManager.requestLocation()` calls its delegate exactly once — either
    /// `didUpdateLocations` or `didFailWithError` — and stops itself automatically, but Apple
    /// doesn't document a guaranteed give-up time, so this races it against an explicit 10s timer
    /// rather than relying on the manager's own internal timeout.
    private func requestOneShotFix() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            fixContinuation = continuation
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.fixTimeout))
                self?.timeoutFixIfStillPending()
            }
        }
    }

    private func timeoutFixIfStillPending() {
        guard let continuation = fixContinuation else { return }
        fixContinuation = nil
        manager.stopUpdatingLocation()
        continuation.resume(throwing: LocationCaptureError.timedOut)
    }

    private func waitForAuthorizationDecision() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
        }
    }

    fileprivate func completeFix(with result: Result<CLLocation, Error>) {
        guard let continuation = fixContinuation else { return }
        fixContinuation = nil
        continuation.resume(with: result)
    }

    fileprivate func completeAuthorizationWaitIfDecided() {
        guard manager.authorizationStatus != .notDetermined, let continuation = authorizationContinuation else { return }
        authorizationContinuation = nil
        continuation.resume()
    }
}

private enum LocationCaptureError: Error {
    case timedOut
}

extension LocationCapture: CLLocationManagerDelegate {
    // CoreLocation calls delegate methods on an arbitrary (non-main) queue/thread — same
    // `nonisolated` + `Task { @MainActor in … }` hop `AudioRecorderController`/`DictationController`
    // already use for their own NotificationCenter callbacks, applied here to CLLocationManager's.

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.completeFix(with: .success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.completeFix(with: .failure(error)) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.completeAuthorizationWaitIfDecided() }
    }
}
