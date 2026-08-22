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
    /// `ItemStore.loadGeneration`): bumped every time a FRESH resolution starts, captured locally
    /// at the start of `resolve(generation:)`, and checked before every `state` write inside it —
    /// belt-and-suspenders alongside `Task.isCancelled` (below): a resolution superseded by a
    /// later cycle can't clobber whatever that later cycle already decided.
    private var generation = 0

    /// Review fix (Critical finding): the currently-running `resolve(generation:)` Task, if any —
    /// tracked explicitly so `toggle()` can tell "is one already in flight" apart from "nothing is
    /// happening" and never start a second concurrent resolution (web parity,
    /// `useCaptureLocation.ts:62-63`'s `if (inFlightRef.current) return inFlightRef.current`).
    /// Cleared on both normal completion (the task's own trailing cleanup, generation-guarded so a
    /// stale task's cleanup can't clobber a newer one's reference) and explicit cancellation
    /// (`cancelInFlightResolve()`).
    private var inFlightResolve: Task<Void, Never>?

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

    /// Delegates to the pure `decideLocationToggleAction` (StashKit) for WHAT to do, then acts on
    /// it. off→on: reuse an already-in-flight resolution if one exists (review fix, Critical
    /// finding — never start a second concurrent one), else a cache hit inside the 5-minute
    /// window immediately (no CoreLocation/geocode round trip), else request auth if needed and
    /// resolve a fresh fix. on→off (from ANY non-off state, including mid-resolution or a stale
    /// failure): cancels whatever's in flight (`cancelInFlightResolve()`) and goes straight back
    /// to `.off`. This is an explicit user cancel, never a failure, so no alert.
    func toggle() {
        let action = decideLocationToggleAction(
            isOff: state == .off,
            hasInFlightResolve: inFlightResolve != nil,
            hasCacheWithinWindow: cache.map { Date().timeIntervalSince($0.at) < Self.cacheWindow } ?? false
        )
        switch action {
        case .turnOff:
            cancelInFlightResolve()
            state = .off
        case .reuseInFlight:
            // Nothing to start — the already-running `resolve(generation:)` will update `state`
            // itself when it finishes; this only needs to keep reflecting `.resolving`, which it
            // already does by construction (see `cancelInFlightResolve`'s doc comment for why
            // `state == .off` and `inFlightResolve != nil` can never coexist in practice).
            state = .resolving
        case .useCache:
            if let cache { state = .ready(cache.location) }
        case .startFresh:
            authDenied = false
            state = .resolving
            generation += 1
            let thisGeneration = generation
            inFlightResolve = Task { [weak self] in
                await self?.resolve(generation: thisGeneration)
                // Generation-guarded: if a NEWER cycle has already started by the time this one
                // finishes (shouldn't happen given `toggle()` is synchronous/MainActor-serialized
                // and `reuseInFlight` prevents a second concurrent start, but cheap to guard
                // regardless), don't let this stale cleanup clobber that cycle's own reference.
                if self?.generation == thisGeneration { self?.inFlightResolve = nil }
            }
        }
    }

    /// Review fix (Critical finding): unsticks whatever `resolve(generation:)` is currently doing
    /// — a bare `Task.cancel()` alone does NOT resume a suspended `withCheckedContinuation`
    /// (CoreLocation's delegate callback / the 10s timeout Task are the only two things that
    /// normally resume `fixContinuation`; neither fires just because the wrapping Task was marked
    /// cancelled). Without this, toggling off mid-resolution left the `resolve` coroutine
    /// suspended forever on `fixContinuation`/`authorizationContinuation`, holding `self` alive —
    /// and toggling back on started a SECOND resolve whose own `requestOneShotFix()` overwrote
    /// `fixContinuation` with a new one, permanently orphaning the first (a genuine leak: Swift's
    /// runtime logs "SWIFT TASK CONTINUATION MISUSE" for a `CheckedContinuation` deallocated
    /// without ever calling `resume`).
    private func cancelInFlightResolve() {
        inFlightResolve?.cancel()
        inFlightResolve = nil
        manager.stopUpdatingLocation()
        if let continuation = fixContinuation {
            fixContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
        if let continuation = authorizationContinuation {
            authorizationContinuation = nil
            continuation.resume()
        }
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

    /// Every guard below checks BOTH `Task.isCancelled` (review fix, Critical finding: set the
    /// instant `cancelInFlightResolve()` cancels this task — the reliable signal for "the user
    /// explicitly turned the pin off, `state` is already `.off`, do NOT overwrite it with
    /// `.failed`") and the generation token (belt-and-suspenders, see its own doc comment). The
    /// final `catch` needs the SAME cancellation check for the same reason: `requestOneShotFix()`
    /// throwing a `CancellationError` (via `cancelInFlightResolve`'s explicit resume) is an
    /// intentional cancel, not a real fix failure.
    private func resolve(generation: Int) async {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            await waitForAuthorizationDecision()
        }
        guard !Task.isCancelled, generation == self.generation else { return }

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
            guard !Task.isCancelled, generation == self.generation else { return }

            let placemark = try? await geocoder.reverseGeocodeLocation(fix).first
            guard !Task.isCancelled, generation == self.generation else { return }

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
            guard !Task.isCancelled else { return }   // explicit user cancel — `.off` already set
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
            // Review fix belt (see `cancelInFlightResolve`'s doc comment for the "suspenders"
            // half): by construction this should never find a stale continuation here — the
            // `reuseInFlight` decision in `toggle()` means a second `requestOneShotFix()` call
            // can't start while one's already pending — but resuming defensively before
            // overwriting the reference costs nothing and turns "should never happen" into
            // "can't leak even if it does".
            if let stale = fixContinuation {
                fixContinuation = nil
                stale.resume(throwing: CancellationError())
            }
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
            // Same defensive belt as `requestOneShotFix()` above.
            if let stale = authorizationContinuation {
                authorizationContinuation = nil
                stale.resume()
            }
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
