import Foundation

public actor Debouncer {
    private let interval: Duration
    private var pending: Task<Void, Never>?

    public init(interval: Duration) { self.interval = interval }

    public func call(_ action: @escaping @Sendable () async -> Void) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    /// Cancels any pending debounced call without scheduling a new one (Plan 8, fix round 1) — for
    /// a caller that's about to run its own EXPLICIT, immediate save and wants to make sure a
    /// stale debounced one can't also fire afterward (e.g. `NotesEditorModel.flushNow`, the detail
    /// sheet's Done button / `onDisappear` path).
    public func cancel() {
        pending?.cancel()
        pending = nil
    }
}
