import XCTest
import Supabase
@testable import StashKit

final class RealtimeChangeTests: XCTestCase {
    func testDecodesInsertUpdateAndDeletePayloads() {
        let id = UUID()
        let record: [String: AnyJSON] = ["id": .string(id.uuidString.lowercased()), "title": .string("x")]
        XCTAssertEqual(ItemChange(event: .insert, record: record, oldRecord: [:]), .upsert(id))
        XCTAssertEqual(ItemChange(event: .update, record: record, oldRecord: ["id": .string(id.uuidString)]), .upsert(id))
        // Default replica identity: a delete carries only the primary key in old_record.
        XCTAssertEqual(ItemChange(event: .delete, record: [:], oldRecord: ["id": .string(id.uuidString)]), .delete(id))
        XCTAssertNil(ItemChange(event: .insert, record: ["title": .string("no id")], oldRecord: [:]))
        XCTAssertNil(ItemChange(event: .delete, record: [:], oldRecord: ["id": .string("not-a-uuid")]))
    }

    func testLaterChangeToTheSameIdWins() {
        let a = UUID(), b = UUID()
        var batch = ItemChangeBatch()
        batch.add(.upsert(a))
        batch.add(.delete(a))
        batch.add(.delete(b))
        batch.add(.upsert(b))
        XCTAssertEqual(batch.deleted, [a])
        XCTAssertEqual(batch.upserted, [b])
    }

    func testCoalescerDeliversOneBatchPerWindow() async throws {
        let recorder = BatchRecorder()
        let coalescer = ItemChangeCoalescer(interval: .milliseconds(40)) { await recorder.record($0) }
        let a = UUID(), b = UUID(), c = UUID()
        await coalescer.add(.upsert(a))
        await coalescer.add(.upsert(b))
        await coalescer.add(.upsert(a))
        await coalescer.add(.delete(c))
        try await Task.sleep(for: .milliseconds(150))

        let batches = await recorder.batches
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.upserted, [a, b])
        XCTAssertEqual(batches.first?.deleted, [c])
    }

    func testDeliveriesNeverOverlapAndLateChangesFormTheNextBatch() async throws {
        let recorder = BatchRecorder(deliveryDelay: .milliseconds(80))
        let coalescer = ItemChangeCoalescer(interval: .milliseconds(20)) { await recorder.record($0) }
        let a = UUID(), b = UUID()
        await coalescer.add(.upsert(a))
        try await Task.sleep(for: .milliseconds(40))      // first batch is now being delivered
        await coalescer.add(.upsert(b))
        try await Task.sleep(for: .milliseconds(250))

        let batches = await recorder.batches
        let maxConcurrent = await recorder.maxConcurrent
        XCTAssertEqual(batches.map(\.upserted), [[a], [b]])
        XCTAssertEqual(maxConcurrent, 1, "an older batch's re-read can never land after a newer one's")
    }

    func testCancelDropsUndeliveredChanges() async throws {
        let recorder = BatchRecorder()
        let coalescer = ItemChangeCoalescer(interval: .milliseconds(30)) { await recorder.record($0) }
        await coalescer.add(.upsert(UUID()))
        await coalescer.cancel()
        try await Task.sleep(for: .milliseconds(100))
        let batches = await recorder.batches
        XCTAssertTrue(batches.isEmpty)
    }
}

private actor BatchRecorder {
    private(set) var batches: [ItemChangeBatch] = []
    private(set) var maxConcurrent = 0
    private var concurrent = 0
    private let deliveryDelay: Duration

    init(deliveryDelay: Duration = .zero) { self.deliveryDelay = deliveryDelay }

    func record(_ batch: ItemChangeBatch) async {
        concurrent += 1
        maxConcurrent = max(maxConcurrent, concurrent)
        batches.append(batch)
        if deliveryDelay > .zero { try? await Task.sleep(for: deliveryDelay) }
        concurrent -= 1
    }
}
