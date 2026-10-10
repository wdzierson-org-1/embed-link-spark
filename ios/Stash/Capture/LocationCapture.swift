import CoreLocation
import Foundation
import Observation
import StashKit

/// One-shot capture location. Consent is shared per account; fixes stay in memory.
/// Passive appearances only use an existing OS grant. Only an explicit app tap can
/// request permission, and the extension never presents the system permission prompt.
@MainActor @Observable
final class LocationCapture: NSObject {
    enum State: Equatable {
        case off, resolving, ready(CapturedLocation), failed
    }

    private(set) var state: State = .off
    private(set) var enabled = false
    private(set) var authDenied = false
    private(set) var permissionRequired = false
    var requiresAppPermission: Bool { !allowsAuthorizationRequest && (permissionRequired || authDenied) }

    private let preference: CaptureLocationPreference
    private let allowsAuthorizationRequest: Bool
    private var consent: CaptureLocationPreference.Snapshot
    private var cache = CaptureLocationCache()
    private var manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var generation = 0
    private var inFlightResolve: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var fixContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var active = false
    private static let fixTimeout: TimeInterval = 10

    init(userId: UUID, allowsAuthorizationRequest: Bool = true) {
        let preference = CaptureLocationPreference(userId: userId)
        let consent = preference.snapshot
        self.preference = preference
        self.consent = consent
        self.enabled = consent.enabled
        self.allowsAuthorizationRequest = allowsAuthorizationRequest
        super.init()
        manager.delegate = self
    }

    /// Recheck shared consent at attachment time as well as appearance: a concurrent
    /// opt-out must win over a previously resolved location in another capture surface.
    var currentLocation: CapturedLocation? {
        synchronizeConsent()
        guard enabled, isAuthorized else { return nil }
        return cache.location(consent: consent)
    }

    func toggle() { setEnabled(!preference.snapshot.enabled) }
    func enable() { setEnabled(true) }

    func setEnabled(_ value: Bool) {
        preference.setEnabled(value)
        synchronizeConsent()
        guard value else { return }
        active = true
        startResolution(allowPrompt: allowsAuthorizationRequest)
    }

    /// Called on appearance and foreground. It never implicitly prompts for permission.
    func resume() {
        active = true
        synchronizeConsent()
        guard enabled else { return }
        startResolution(allowPrompt: false)
    }

    /// Warm while editing/preparing a capture, without duplicate one-shot requests.
    func warmIfEnabled() {
        synchronizeConsent()
        guard active, enabled, inFlightResolve == nil else { return }
        if let location = currentLocation { state = .ready(location); return }
        startResolution(allowPrompt: false)
    }

    /// Surface dismissal/background cancels work and clears coordinates, never consent.
    func stop() {
        active = false
        cancelResolution()
        cache.clear()
        state = .off
    }

    /// Timeout zero is immediate for Save. The existing Outbox hook may briefly wait
    /// after durability; coordinate readiness never waits for reverse geocoding.
    func awaitResolution(timeout: TimeInterval) async -> CapturedLocation? {
        if let location = currentLocation { return location }
        guard timeout > 0, timeout.isFinite, enabled else { return nil }
        let deadline = Date().addingTimeInterval(min(timeout, 2.5))
        while state == .resolving, Date() < deadline, !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return nil }
            if let location = currentLocation { return location }
        }
        return currentLocation
    }

    private var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    private func synchronizeConsent() {
        let fresh = preference.snapshot
        guard fresh != consent || !fresh.enabled else { return }
        cancelResolution()
        cache.clear()
        consent = fresh
        enabled = fresh.enabled
        state = .off
        authDenied = false
        permissionRequired = false
    }

    private func startResolution(allowPrompt: Bool) {
        guard active, enabled, inFlightResolve == nil else { return }
        authDenied = false
        permissionRequired = false
        // A new manager per request also identifies queued callbacks from a cancelled
        // request: they cannot complete the continuation belonging to its replacement.
        manager.delegate = nil
        manager.stopUpdatingLocation()
        manager = CLLocationManager()
        manager.delegate = self
        switch manager.authorizationStatus {
        case .denied, .restricted:
            authDenied = true
            cache.clear()
            state = .failed
            return
        case .notDetermined where !allowPrompt:
            permissionRequired = true
            state = .failed
            return
        default: break
        }
        state = cache.location(consent: consent).map(State.ready) ?? .resolving
        generation += 1
        let token = generation
        inFlightResolve = Task { [weak self] in
            await self?.resolve(generation: token, allowPrompt: allowPrompt)
            if self?.generation == token { self?.inFlightResolve = nil }
        }
    }

    private func isCurrent(_ token: Int) -> Bool {
        synchronizeConsent()
        return !Task.isCancelled && active && enabled && generation == token
    }

    private func cancelResolution() {
        generation += 1
        inFlightResolve?.cancel()
        inFlightResolve = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        manager.stopUpdatingLocation()
        manager.delegate = nil
        geocoder.cancelGeocode()
        if let continuation = fixContinuation {
            fixContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
        if let continuation = authorizationContinuation {
            authorizationContinuation = nil
            continuation.resume()
        }
    }

    private func resolve(generation token: Int, allowPrompt: Bool) async {
        guard isCurrent(token) else { return }
        if manager.authorizationStatus == .notDetermined, allowPrompt {
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        guard isCurrent(token) else { return }
        guard isAuthorized else {
            authDenied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
            permissionRequired = manager.authorizationStatus == .notDetermined
            cache.clear()
            state = .failed
            return
        }
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        do {
            let fix = try await requestOneShotFix(generation: token)
            guard isCurrent(token) else { return }
            let coordinates = CapturedLocation(
                label: "Current location", latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude, accuracyM: fix.horizontalAccuracy.rounded(),
                source: "device-geolocation", capturedAt: ISO8601DateFormatter().string(from: fix.timestamp))
            cache.store(coordinates, fixDate: fix.timestamp, consent: consent)
            state = .ready(coordinates)

            // A slow/offline geocoder only affects the friendly label. The validated
            // coordinate payload is already available to a capture made right now.
            let placemark = try? await geocoder.reverseGeocodeLocation(fix).first
            guard isCurrent(token), isAuthorized else { return }
            if let named = buildCapturedLocation(latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude, accuracy: fix.horizontalAccuracy,
                city: placemark?.locality, region: placemark?.administrativeArea,
                country: placemark?.country, fixDate: fix.timestamp),
               CaptureLocationCache.isUsableFix(latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude, accuracy: fix.horizontalAccuracy, fixDate: fix.timestamp) {
                cache.store(named, fixDate: fix.timestamp, consent: consent)
                state = .ready(named)
            }
        } catch {
            guard isCurrent(token) else { return }
            state = cache.location(consent: consent).map(State.ready) ?? .failed
        }
    }

    private func requestOneShotFix(generation token: Int) async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            fixContinuation = continuation
            manager.requestLocation()
            timeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(Self.fixTimeout)) } catch { return }
                guard let self, self.generation == token else { return }
                self.completeFix(with: .failure(LocationCaptureError.timedOut), managerID: ObjectIdentifier(self.manager))
                self.manager.stopUpdatingLocation()
            }
        }
    }

    fileprivate func received(_ locations: [CLLocation], managerID: ObjectIdentifier) {
        guard ObjectIdentifier(manager) == managerID else { return }
        // Core Location may first deliver a cached or invalid fix. Keep the bounded
        // request pending for a usable sample rather than attaching unreliable data.
        guard let fix = locations.last(where: {
            CaptureLocationCache.isUsableFix(latitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude, accuracy: $0.horizontalAccuracy, fixDate: $0.timestamp)
        }) else { return }
        completeFix(with: .success(fix), managerID: managerID)
    }

    fileprivate func completeFix(with result: Result<CLLocation, Error>, managerID: ObjectIdentifier) {
        guard ObjectIdentifier(manager) == managerID, let continuation = fixContinuation else { return }
        fixContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(with: result)
    }

    fileprivate func authorizationChanged(managerID: ObjectIdentifier) {
        guard ObjectIdentifier(manager) == managerID,
              manager.authorizationStatus != .notDetermined else { return }
        if let continuation = authorizationContinuation {
            authorizationContinuation = nil
            continuation.resume()
        } else if active, enabled, !isAuthorized {
            cancelResolution()
            cache.clear()
            authDenied = true
            state = .failed
        }
    }
}

private enum LocationCaptureError: Error { case timedOut }

extension LocationCapture: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.received(locations, managerID: ObjectIdentifier(manager)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.completeFix(with: .failure(error), managerID: ObjectIdentifier(manager)) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.authorizationChanged(managerID: ObjectIdentifier(manager)) }
    }
}
