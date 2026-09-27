import Foundation

/// Plan 15 (M1): throttles how often a streaming answer is published into `ChatStore.messages`.
/// The server sends tens of tokens a second; publishing each one re-rendered the thread per
/// token. The first delta publishes at once (first-token latency is what feels snappy); after
/// that at most one publish per `interval`. `ChatStore` calls `flush` on a timer so a pause in
/// the stream never strands the tail of the text (held for under two intervals at worst). Pure
/// value type with an injected clock reading, so the policy is unit-tested without timers.
struct StreamingTextCoalescer {
    /// Everything received so far — always the full answer, published or not.
    private(set) var text = ""
    let interval: TimeInterval
    private var lastPublishedAt: TimeInterval?
    private var hasUnpublishedText = false

    init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Appends `delta`; returns the text to publish now, or nil when it's held for the next
    /// `flush` (the previous publish was less than `interval` ago).
    mutating func append(_ delta: String, at now: TimeInterval) -> String? {
        text += delta
        if let last = lastPublishedAt, now - last < interval {
            hasUnpublishedText = true
            return nil
        }
        lastPublishedAt = now
        hasUnpublishedText = false
        return text
    }

    /// The held-back text, once `interval` has passed since the last publish; nil when nothing
    /// new arrived or it's still too soon.
    mutating func flush(at now: TimeInterval) -> String? {
        guard hasUnpublishedText else { return nil }
        if let last = lastPublishedAt, now - last < interval { return nil }
        lastPublishedAt = now
        hasUnpublishedText = false
        return text
    }
}
