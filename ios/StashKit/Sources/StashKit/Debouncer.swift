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
}
