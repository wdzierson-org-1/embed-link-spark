# Reminders — Plan 2 of 3: iOS

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reminder chips in the share sheet, the View tab badge with the due count, due-first ordering in the View grid, and the card chip / Due overlay / dismiss on iOS.

**Architecture:** `StashKit` gains the two columns on `Item`, a `ReminderRules` mirror of the web logic, a `reminder` case on `ItemPatch`, a `remindAt` parameter through `CaptureAPI` → `ShareIntake` → `Outbox`, and a `ReminderStore` that owns the due list. `MainTabView` owns the store (so the badge exists before the tab opens) and injects it into `LibraryView`, which merges the due block above its paginated list. Keyset pagination on `created_at` is untouched.

**Tech Stack:** SwiftUI (iOS 17 floor), `StashKit` Swift package (XCTest via `swift test`), supabase-swift 2.54, XcodeGen, XCUITest.

**Spec:** `docs/superpowers/specs/2026-09-06-reminders-design.md`

## Global Constraints

- `ReminderRules.dueWindow = 24 * 60 * 60` seconds. State: `none` (no `remindAt`), `cleared` (`reminderClearedAt` set, or `now ≥ remindAt + 24h`), `scheduled` (`now < remindAt`), `due` (otherwise). Identical to web `src/utils/reminders.ts`.
- Presets `[1, 3, 5]` days; send the absolute instant as ISO-8601 with fractional seconds and `Z`.
- Set writes `remind_at` + nulls `reminder_cleared_at`, `reminder_notified_at`. Dismiss writes `reminder_cleared_at = now`. Never write `reminder_notified_at`.
- Share sheet: chips are optional, default none, never block Save. Save copy when chosen: `Saved · back in N day(s)` / queued `Saved — will sync · back in N day(s)`.
- Wire columns list must match web: `Item.listColumns` gains `,remind_at,reminder_cleared_at`.
- Requires Plan 1 Task 1 (columns exist in production) and Task 2 (endpoints accept `remind_at`) before device testing.
- Build/test: `cd ios && xcodegen generate` after any `project.yml` change; unit tests `cd ios/StashKit && swift test`; UI tests and simulator recipe in memory `ios-app-plan` and `ios/README.md`. Test accounts and fixtures: memory `ios-app-plan`.
- Do not touch `ItemDetailView`, the in-app composer, or MCP.

---

## File map

| File | Responsibility |
|---|---|
| `ios/StashKit/Sources/StashKit/Models/Item.swift` | `remindAt`, `reminderClearedAt`, coding keys, list columns |
| `ios/StashKit/Sources/StashKit/ReminderRules.swift` | State, presets, ordering, label, ISO helpers |
| `ios/StashKit/Sources/StashKit/ItemEditor.swift` | `ItemPatch.reminder` (set / clear) → REST body |
| `ios/StashKit/Sources/StashKit/CaptureAPI.swift` | `remindAt:` on the three capture calls |
| `ios/StashKit/Sources/StashKit/ShareIntake.swift` | `submit(_:note:location:remindAt:)`, outbox payload |
| `ios/StashKit/Sources/StashKit/Outbox.swift` | Forward `remind_at` on drain |
| `ios/StashKit/Sources/StashKit/ReminderStore.swift` | Due list + count, refresh, dismiss, set |
| `ios/StashKit/Sources/StashKit/RealtimeObserver.swift` | Optional channel suffix |
| `ios/StashShareExtension/ShareComposeView.swift` | Chip row above Save, done copy |
| `ios/Stash/MainTabView.swift` | Owns `ReminderStore`, badge, refresh triggers |
| `ios/Stash/Library/LibraryView.swift` | Due block merged above the page |
| `ios/Stash/Library/ItemCardView.swift` | Footer chip, Due overlay, dismiss |
| `ios/StashKit/Tests/StashKitTests/Reminder*.swift`, `ItemDecodingTests.swift`, `ItemEditorTests.swift`, `CaptureAPITests.swift`, `ShareIntakeTests.swift`, `OutboxTests.swift` | Tests |
| `ios/StashUITests/StashUITests.swift` | Share-sheet chip UI test |
| `docs/ui-changes.md` | iOS paragraph in the 2026-09-06 reminders entry |

---

### Task 1: `Item` columns + `ReminderRules`

**Files:**
- Modify: `ios/StashKit/Sources/StashKit/Models/Item.swift`
- Create: `ios/StashKit/Sources/StashKit/ReminderRules.swift`
- Test: `ios/StashKit/Tests/StashKitTests/ItemDecodingTests.swift`, create `ios/StashKit/Tests/StashKitTests/ReminderRulesTests.swift`

**Interfaces:**
- Produces: `Item.remindAt: Date?`, `Item.reminderClearedAt: Date?` (init params default `nil`); `enum ReminderState { none, scheduled, due, cleared }`; `enum ReminderRules` with `dueWindow`, `presets`, `remindAt(days:now:)`, `state(remindAt:clearedAt:now:)`, `orderDueFirst(_:now:)`, `label(remindAt:clearedAt:now:)`, `isoString(_:)`, `isoDate(_:)`; `Item.reminderState(now:)`.

- [ ] **Step 1: Failing decoding test**

Append to `ItemDecodingTests`:

```swift
    func testDecodesReminderColumns() throws {
        let json = """
        {"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4e","type":"text","title":"r","content":null,
         "url":null,"file_path":null,"description":null,"summary":null,
         "created_at":"2026-09-06T12:00:00+00:00","mime_type":null,"is_public":false,
         "supplemental_note":null,"remind_at":"2026-09-09T12:00:00+00:00","reminder_cleared_at":null}
        """.data(using: .utf8)!
        let item = try decoder.decode(Item.self, from: json)
        XCTAssertEqual(item.remindAt, ISO8601DateFormatter().date(from: "2026-09-09T12:00:00Z"))
        XCTAssertNil(item.reminderClearedAt)
    }

    func testMissingReminderColumnsDecodeAsNil() throws {
        let json = """
        {"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4f","type":"text","title":null,"content":null,
         "url":null,"file_path":null,"description":null,"summary":null,
         "created_at":"2026-09-06T12:00:00+00:00","mime_type":null,"is_public":false,"supplemental_note":null}
        """.data(using: .utf8)!
        let item = try decoder.decode(Item.self, from: json)
        XCTAssertNil(item.remindAt)
        XCTAssertNil(item.reminderClearedAt)
    }

    func testListColumnsIncludeReminderColumns() {
        XCTAssertTrue(Item.listColumns.hasSuffix(",attributes,remind_at,reminder_cleared_at"))
    }
```

- [ ] **Step 2: Failing rules test**

`ReminderRulesTests.swift`:

```swift
import XCTest
@testable import StashKit

final class ReminderRulesTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-09-06T12:00:00Z")!
    func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testStateBoundaries() {
        XCTAssertEqual(ReminderRules.state(remindAt: nil, clearedAt: nil, now: now), .none)
        XCTAssertEqual(ReminderRules.state(remindAt: date("2026-09-06T12:00:01Z"), clearedAt: nil, now: now), .scheduled)
        XCTAssertEqual(ReminderRules.state(remindAt: date("2026-09-06T12:00:00Z"), clearedAt: nil, now: now), .due)
        XCTAssertEqual(ReminderRules.state(remindAt: date("2026-09-05T12:00:01Z"), clearedAt: nil, now: now), .due)
        XCTAssertEqual(ReminderRules.state(remindAt: date("2026-09-05T12:00:00Z"), clearedAt: nil, now: now), .cleared)
        XCTAssertEqual(ReminderRules.state(remindAt: date("2026-09-09T12:00:00Z"), clearedAt: now, now: now), .cleared)
    }

    func testPresetsAndRemindAt() {
        XCTAssertEqual(ReminderRules.presets, [1, 3, 5])
        XCTAssertEqual(ReminderRules.remindAt(days: 3, now: now), date("2026-09-09T12:00:00Z"))
    }

    func testISORoundTripUsesFractionalSecondsAndZ() {
        let s = ReminderRules.isoString(date("2026-09-09T12:00:00Z"))
        XCTAssertEqual(s, "2026-09-09T12:00:00.000Z")
        XCTAssertEqual(ReminderRules.isoDate(s), date("2026-09-09T12:00:00Z"))
        XCTAssertEqual(ReminderRules.isoDate("2026-09-09T12:00:00+00:00"), date("2026-09-09T12:00:00Z"))
        XCTAssertNil(ReminderRules.isoDate("soon"))
    }

    func testOrderDueFirst() {
        func item(_ name: String, remind: String?, cleared: String? = nil) -> Item {
            Item(id: UUID(), type: .text, title: name, content: nil, url: nil, filePath: nil,
                 description: nil, summary: nil, pageBody: nil, supplementalNote: nil, mimeType: nil,
                 isPublic: false, createdAt: now, remindAt: remind.map(date), reminderClearedAt: cleared.map(date))
        }
        let items = [
            item("newest", remind: "2026-09-10T00:00:00Z"),
            item("plain", remind: nil),
            item("due-later", remind: "2026-09-06T09:00:00Z"),
            item("expired", remind: "2026-09-01T00:00:00Z"),
            item("due-earlier", remind: "2026-09-05T20:00:00Z"),
            item("dismissed", remind: "2026-09-06T01:00:00Z", cleared: "2026-09-06T02:00:00Z"),
        ]
        XCTAssertEqual(ReminderRules.orderDueFirst(items, now: now).map(\.title),
                       ["due-earlier", "due-later", "newest", "plain", "expired", "dismissed"])
    }

    func testLabel() {
        XCTAssertNil(ReminderRules.label(remindAt: nil, clearedAt: nil, now: now))
        XCTAssertEqual(ReminderRules.label(remindAt: date("2026-09-06T12:00:00Z"), clearedAt: nil, now: now), "Due")
        XCTAssertEqual(ReminderRules.label(remindAt: date("2026-09-06T17:00:00Z"), clearedAt: nil, now: now), "in 5h")
        XCTAssertEqual(ReminderRules.label(remindAt: date("2026-09-06T12:10:00Z"), clearedAt: nil, now: now), "in 1h")
        XCTAssertEqual(ReminderRules.label(remindAt: date("2026-09-09T12:00:00Z"), clearedAt: nil, now: now), "in 3d")
        XCTAssertEqual(ReminderRules.label(remindAt: date("2026-09-08T18:00:00Z"), clearedAt: nil, now: now), "in 3d")
        XCTAssertNil(ReminderRules.label(remindAt: date("2026-09-01T00:00:00Z"), clearedAt: nil, now: now))
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `cd ios/StashKit && swift test --filter 'ReminderRulesTests|ItemDecodingTests'`
Expected: compile errors (`remindAt`, `ReminderRules` undefined).

- [ ] **Step 4: Extend `Item`**

In `Item.swift`:
- properties after `attributes`: `public var remindAt: Date?` and `public var reminderClearedAt: Date?` with a doc comment `/// Explicit reminder columns — state is derived by ReminderRules, never stored.`
- `CodingKeys`: add `case remindAt = "remind_at"` and `case reminderClearedAt = "reminder_cleared_at"`.
- memberwise init: add trailing parameters `remindAt: Date? = nil, reminderClearedAt: Date? = nil` and assign.
- `init(from:)`: add `remindAt = try container.decodeIfPresent(Date.self, forKey: .remindAt)` and the same for `reminderClearedAt`.
- `listColumns`: append `,remind_at,reminder_cleared_at`.

- [ ] **Step 5: Write `ReminderRules.swift`**

```swift
import Foundation

/// Mirror of web `src/utils/reminders.ts`. Spec:
/// docs/superpowers/specs/2026-09-06-reminders-design.md. Keep the two in step.
public enum ReminderState: Equatable, Sendable { case none, scheduled, due, cleared }

public enum ReminderRules {
    /// A reminder is due for exactly this long after `remindAt` unless cleared.
    public static let dueWindow: TimeInterval = 24 * 60 * 60
    public static let presets: [Int] = [1, 3, 5]

    public static func remindAt(days: Int, now: Date = Date()) -> Date {
        now.addingTimeInterval(TimeInterval(days) * 24 * 60 * 60)
    }

    public static func state(remindAt: Date?, clearedAt: Date?, now: Date = Date()) -> ReminderState {
        guard let remindAt else { return .none }
        if clearedAt != nil { return .cleared }
        if now < remindAt { return .scheduled }
        if now < remindAt.addingTimeInterval(dueWindow) { return .due }
        return .cleared
    }

    /// Due items first (longest-waiting first), everything else in incoming order.
    public static func orderDueFirst(_ items: [Item], now: Date = Date()) -> [Item] {
        let due = items.filter { $0.reminderState(now: now) == .due }
            .sorted { ($0.remindAt ?? .distantPast) < ($1.remindAt ?? .distantPast) }
        let rest = items.filter { $0.reminderState(now: now) != .due }
        return due + rest
    }

    public static func label(remindAt: Date?, clearedAt: Date?, now: Date = Date()) -> String? {
        switch state(remindAt: remindAt, clearedAt: clearedAt, now: now) {
        case .due: return "Due"
        case .scheduled:
            let seconds = remindAt!.timeIntervalSince(now)
            if seconds < 24 * 60 * 60 { return "in \(max(1, Int((seconds / 3600).rounded(.up))))h" }
            return "in \(Int((seconds / 86_400).rounded(.up)))d"
        case .none, .cleared: return nil
        }
    }

    // ISO-8601 with fractional seconds and a trailing Z — the exact shape the
    // web's `Date.toISOString()` produces, so PostgREST text filters and JSON
    // bodies agree byte-for-byte across clients.
    private static let writer: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plainReader = ISO8601DateFormatter()

    public static func isoString(_ date: Date) -> String { writer.string(from: date) }
    public static func isoDate(_ string: String) -> Date? {
        writer.date(from: string) ?? plainReader.date(from: string)
    }
}

public extension Item {
    func reminderState(now: Date = Date()) -> ReminderState {
        ReminderRules.state(remindAt: remindAt, clearedAt: reminderClearedAt, now: now)
    }
    func reminderLabel(now: Date = Date()) -> String? {
        ReminderRules.label(remindAt: remindAt, clearedAt: reminderClearedAt, now: now)
    }
}
```

- [ ] **Step 6: Run the two suites**

Run: `cd ios/StashKit && swift test --filter 'ReminderRulesTests|ItemDecodingTests'`
Expected: all pass. Then the whole package: `swift test` — green (the memberwise init change has defaults, so existing call sites compile).

- [ ] **Step 7: Commit**

```bash
git add ios/StashKit/Sources/StashKit/Models/Item.swift ios/StashKit/Sources/StashKit/ReminderRules.swift ios/StashKit/Tests/StashKitTests/ItemDecodingTests.swift ios/StashKit/Tests/StashKitTests/ReminderRulesTests.swift
git commit -m "feat(ios/reminders): Item reminder columns + ReminderRules (state, ordering, label, ISO)"
```

---

### Task 2: `ItemPatch.reminder` (set / clear)

**Files:**
- Modify: `ios/StashKit/Sources/StashKit/ItemEditor.swift:10-80`
- Test: `ios/StashKit/Tests/StashKitTests/ItemEditorTests.swift`

**Interfaces:**
- Produces: `enum ReminderPatch: Equatable, Sendable { case set(Date), clear(Date) }`; `ItemPatch.reminder: ReminderPatch?`; `restBody` emits `remind_at` + null `reminder_cleared_at` + null `reminder_notified_at` for `.set`, and `reminder_cleared_at` for `.clear`.

- [ ] **Step 1: Failing test**

Append to `ItemEditorTests`:

```swift
    func testReminderSetPatchNullsClearedAndNotified() {
        let at = ISO8601DateFormatter().date(from: "2026-09-09T12:00:00Z")!
        let body = ItemPatch(reminder: .set(at)).restBody
        XCTAssertEqual(body["remind_at"] as? String, "2026-09-09T12:00:00.000Z")
        XCTAssertTrue(body.keys.contains("reminder_cleared_at"))
        XCTAssertNil(body["reminder_cleared_at"] ?? nil)
        XCTAssertTrue(body.keys.contains("reminder_notified_at"))
        XCTAssertNil(body["reminder_notified_at"] ?? nil)
        XCTAssertFalse(ItemPatch(reminder: .set(at)).isEmpty)
        XCTAssertFalse(ItemPatch(reminder: .set(at)).touchesTextFields)
    }

    func testReminderClearPatchStampsClearedOnly() {
        let now = ISO8601DateFormatter().date(from: "2026-09-06T12:00:00Z")!
        let body = ItemPatch(reminder: .clear(now)).restBody
        XCTAssertEqual(body["reminder_cleared_at"] as? String, "2026-09-06T12:00:00.000Z")
        XCTAssertNil(body["remind_at"] ?? nil)
        XCTAssertFalse(body.keys.contains("remind_at"))
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ios/StashKit && swift test --filter ItemEditorTests`
Expected: compile error, no `reminder:` parameter.

- [ ] **Step 3: Implement**

In `ItemEditor.swift`, above `ItemPatch`:

```swift
/// Reminder writes ride the same PATCH path as every other field. `.set` also
/// nulls the cleared/notified stamps so a re-set reminder is fresh; `.clear`
/// touches only `reminder_cleared_at`. Contract: PLATFORM_API.md → Reminders.
public enum ReminderPatch: Equatable, Sendable {
    case set(Date)
    case clear(Date)
}
```

In `ItemPatch`: add `public var reminder: ReminderPatch?`, an init parameter `reminder: ReminderPatch? = nil` (assign it), include `&& reminder == nil` in `isEmpty`, and at the end of `restBody` before `return body`:

```swift
        switch reminder {
        case .set(let at):
            body["remind_at"] = ReminderRules.isoString(at)
            body.updateValue(nil, forKey: "reminder_cleared_at")
            body.updateValue(nil, forKey: "reminder_notified_at")
        case .clear(let at):
            body["reminder_cleared_at"] = ReminderRules.isoString(at)
        case nil:
            break
        }
```

`touchesTextFields` is unchanged (reminders never trigger an embedding refresh).

- [ ] **Step 4: Run tests**

Run: `cd ios/StashKit && swift test --filter ItemEditorTests`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add ios/StashKit/Sources/StashKit/ItemEditor.swift ios/StashKit/Tests/StashKitTests/ItemEditorTests.swift
git commit -m "feat(ios/reminders): ItemPatch.reminder set/clear"
```

---

### Task 3: `remindAt` through `CaptureAPI`, `ShareIntake`, and the outbox

**Files:**
- Modify: `ios/StashKit/Sources/StashKit/CaptureAPI.swift:34-64`, `ios/StashKit/Sources/StashKit/ShareIntake.swift:101-256`, `ios/StashKit/Sources/StashKit/Outbox.swift:316-335`
- Test: `CaptureAPITests.swift`, `ShareIntakeTests.swift`, `OutboxTests.swift`

**Interfaces:**
- Produces: `CaptureAPI.addNote(content:title:isPublic:attributes:remindAt:accessToken:)`, `addURL(_:note:isPublic:attributes:remindAt:accessToken:)`, `addFile(path:mimeType:fileSize:content:isPublic:attributes:remindAt:accessToken:)` — `remindAt: Date? = nil` inserted before `accessToken`; body key `remind_at` (ISO string) only when non-nil. `ShareIntake.submit(_:note:location:remindAt:)` with `remindAt: Date? = nil`. Outbox payload key `remind_at`.

- [ ] **Step 1: Failing tests**

`CaptureAPITests` (uses the existing `RecordingPoster`):

```swift
    func testAddNoteSendsRemindAtOnlyWhenPresent() async throws {
        let poster = RecordingPoster()
        let api = CaptureAPI(poster: poster)
        let at = ISO8601DateFormatter().date(from: "2026-09-09T12:00:00Z")!
        _ = try? await api.addNote(content: "x", title: nil, isPublic: false, remindAt: at, accessToken: "jwt")
        _ = try? await api.addNote(content: "y", title: nil, isPublic: false, accessToken: "jwt")
        XCTAssertEqual(poster.calls[0].body["remind_at"] as? String, "2026-09-09T12:00:00.000Z")
        XCTAssertNil(poster.calls[1].body["remind_at"])
    }
```

`ShareIntakeTests`:

```swift
    func testRemindAtReachesEveryUnitLiveAndQueued() async throws {
        let at = ISO8601DateFormatter().date(from: "2026-09-09T12:00:00Z")!
        // live
        let poster = RecordingPoster()
        let intake = makeIntake(poster: poster)
        _ = await intake.submit([.url("https://example.com"), .text("hi")], note: nil, location: nil, remindAt: at)
        XCTAssertEqual(poster.calls.map { $0.body["remind_at"] as? String },
                       ["2026-09-09T12:00:00.000Z", "2026-09-09T12:00:00.000Z"])
        // queued (poster fails → outbox)
        let failing = RecordingPoster(); failing.failAll = true
        let outbox = Outbox(directory: dir)
        let queued = makeIntake(poster: failing, outbox: outbox)
        let result = await queued.submit([.url("https://example.com")], note: nil, location: nil, remindAt: at)
        XCTAssertEqual(result, ShareIntakeResult(queued: 1))
        let entries = try outbox.pending()
        XCTAssertEqual(entries.first?.payload["remind_at"], "2026-09-09T12:00:00.000Z")
    }
```

(`RecordingPoster.failAll` and `Outbox.pending()` — use whatever the existing test doubles expose for "make the live send throw" and "read queued entries"; `OutboxTests.swift` shows both. Adapt the two names, not the assertions.)

`OutboxTests`:

```swift
    func testDrainForwardsRemindAt() async throws {
        let outbox = Outbox(directory: dir)
        try outbox.enqueue(.note, payload: ["content": "n", "is_public": "false", "remind_at": "2026-09-09T12:00:00.000Z"])
        let poster = RecordingPoster()
        _ = await outbox.drain(api: CaptureAPI(poster: poster), accessToken: { "jwt" })
        XCTAssertEqual(poster.calls.first?.body["remind_at"] as? String, "2026-09-09T12:00:00.000Z")
    }
```

(match `drain`'s real signature from `OutboxTests.swift`.)

- [ ] **Step 2: Run to verify failure**

Run: `cd ios/StashKit && swift test --filter 'CaptureAPITests|ShareIntakeTests|OutboxTests'`
Expected: compile errors on the new parameters.

- [ ] **Step 3: `CaptureAPI`**

Add `remindAt: Date? = nil` before `accessToken` on all three methods and, after `addAttributes(attributes, to: &body)` in each: `if let remindAt { body["remind_at"] = ReminderRules.isoString(remindAt) }`.

- [ ] **Step 4: `ShareIntake`**

- `submit(_ objects:note:location:remindAt: Date? = nil)`; pass `remindAt` into `handleURL`, `handleText`, `handleFile` (add a `remindAt: Date?` parameter to each, and to `enqueueFile`).
- Live sends: pass `remindAt: remindAt` to the `capture.add…` calls.
- Fallback payloads: after building `payload` in each handler and in `enqueueFile`: `if let remindAt { payload["remind_at"] = ReminderRules.isoString(remindAt) }`.

- [ ] **Step 5: `Outbox.send`**

In `send(_:api:accessToken:)`: `let remindAt = entry.payload["remind_at"].flatMap(ReminderRules.isoDate)` and pass `remindAt: remindAt` to each of the three `api.add…` calls.

- [ ] **Step 6: Run the package tests**

Run: `cd ios/StashKit && swift test`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add ios/StashKit/Sources/StashKit/CaptureAPI.swift ios/StashKit/Sources/StashKit/ShareIntake.swift ios/StashKit/Sources/StashKit/Outbox.swift ios/StashKit/Tests/StashKitTests/CaptureAPITests.swift ios/StashKit/Tests/StashKitTests/ShareIntakeTests.swift ios/StashKit/Tests/StashKitTests/OutboxTests.swift
git commit -m "feat(ios/reminders): remind_at through CaptureAPI, ShareIntake and the outbox"
```

---

### Task 4: Share-sheet chips

**Files:**
- Modify: `ios/StashShareExtension/ShareComposeView.swift` (state near :37, `pinnedSaveBar` at :561-591, `save()` at :602-645, `doneView` at :648)
- Test: `ios/StashUITests/StashUITests.swift`

**Interfaces:**
- Consumes: `ShareIntake.submit(_:note:location:remindAt:)`, `ReminderRules.presets`, `ReminderRules.remindAt(days:)`.
- Accessibility identifiers: `share.remind.1d`, `share.remind.3d`, `share.remind.5d`; existing `share.save`, `share.outcome`.

- [ ] **Step 1: State + chip row**

Add `@State private var remindDays: Int? = nil` next to `note`. Add:

```swift
    // MARK: - Reminder chips (spec: optional, default none, never gates Save)

    private var reminderRow: some View {
        HStack(spacing: 8) {
            Text("Remind me")
                .font(StashType.meta())
                .foregroundStyle(StashColor.muted)
            ForEach(ReminderRules.presets, id: \.self) { days in
                let selected = remindDays == days
                Button {
                    remindDays = selected ? nil : days
                } label: {
                    Text(days == 1 ? "1 day" : "\(days) days")
                        .font(StashType.chip())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(selected ? .white : StashColor.ink)
                        .background(selected ? StashColor.violet600 : StashColor.wash, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("share.remind.\(days)d")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityLabel(selected ? "Remind me in \(days) \(days == 1 ? "day" : "days"), selected" : "Remind me in \(days) \(days == 1 ? "day" : "days")")
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.15), value: remindDays)
    }
```

In `pinnedSaveBar`, inside the `VStack(spacing: 10)`, insert `reminderRow` between the `gateMessage` block and the Save `Button` (and keep it hidden when `!canAddContent`: wrap as `if canAddContent { reminderRow }`).

- [ ] **Step 2: Thread into `save()` and the done copy**

Replace the submit + message block:

```swift
        let remindAt = remindDays.map { ReminderRules.remindAt(days: $0) }
        let result = await intake.submit(objects, note: trimmedNote.isEmpty ? nil : trimmedNote,
                                         location: location, remindAt: remindAt)

        let suffix = remindDays.map { " · back in \($0) \($0 == 1 ? "day" : "days")" } ?? ""
        let message: String
        if result.queued > 0 {
            message = "Saved — will sync" + suffix
        } else if result.saved > 0 {
            message = "Saved to Stash" + suffix
        } else {
            message = "Couldn't save — try again"
        }
```

In `doneView`, change both `message == "Saved to Stash"` checks to `message.hasPrefix("Saved to Stash")`.

- [ ] **Step 3: UI test**

Append to `StashUITests.swift` next to the existing share-extension smoke (reuse its launch/setup helper — the URL-share smoke that reads `share.outcome`):

```swift
    func testShareSheetReminderChipSelectsAndReportsInOutcome() throws {
        let share = launchShareSheetWithURL()          // the existing helper this file's share smoke uses
        let chip = share.buttons["share.remind.3d"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()
        XCTAssertTrue(chip.isSelected)
        chip.tap()                                     // toggles off
        XCTAssertFalse(chip.isSelected)
        chip.tap()
        share.buttons["share.save"].tap()
        let outcome = share.staticTexts["share.outcome"]
        XCTAssertTrue(outcome.waitForExistence(timeout: 15))
        XCTAssertTrue(outcome.label.hasPrefix("Saved"))
        XCTAssertTrue(outcome.label.hasSuffix("back in 3 days"))
    }
```

- [ ] **Step 4: Build and run**

```bash
cd ios && xcodegen generate
```

Then the simulator build + UI-test recipe from memory `ios-app-plan` (`xcodebuild test -scheme Stash -only-testing:StashUITests/StashUITests/testShareSheetReminderChipSelectsAndReportsInOutcome …`). Expected: pass. Also re-run the existing share smoke to confirm the unchanged `"Saved to Stash"` path still matches.

- [ ] **Step 5: Verify the row on the server**

After the UI test (it saves a real item on the `will+uitest` account), query via the Management API: `select title, remind_at from items where user_id = '<uitest uid>' order by created_at desc limit 1` → `remind_at` ≈ now + 3 days. Delete the probe item.

- [ ] **Step 6: Commit**

```bash
git add ios/StashShareExtension/ShareComposeView.swift ios/StashUITests/StashUITests.swift
git commit -m "feat(ios/reminders): share-sheet Remind me chips (1/3/5 days) above Save"
```

---

### Task 5: `ReminderStore`

**Files:**
- Create: `ios/StashKit/Sources/StashKit/ReminderStore.swift`, `ios/StashKit/Tests/StashKitTests/ReminderStoreTests.swift`
- Modify: `ios/StashKit/Sources/StashKit/RealtimeObserver.swift:8`

**Interfaces:**
- Produces: `protocol DueItemsFetching { func fetchDueCandidates(userId: UUID, now: Date) async throws -> [Item] }`; `SupabaseDueItemsFetcher`; `@MainActor @Observable final class ReminderStore` with `dueItems: [Item]`, `dueCount: Int`, `refresh()`, `tick()`, `dismiss(_ id: UUID)`, `set(_ id: UUID, days: Int)`; `RealtimeObserver.observeItems(userId:channelSuffix:onChange:)` (`channelSuffix: String = ""`).
- Consumes: `ItemPatching` (`ItemEditor.swift`), `ItemPatch.reminder` (Task 2), `ReminderRules` (Task 1).

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import StashKit

final class StubDueFetcher: DueItemsFetching, @unchecked Sendable {
    var rows: [Item] = []
    var calls = 0
    func fetchDueCandidates(userId: UUID, now: Date) async throws -> [Item] { calls += 1; return rows }
}

final class RecordingPatcher: ItemPatching, @unchecked Sendable {
    var patches: [(UUID, ItemPatch)] = []
    var shouldThrow = false
    func patch(itemId: UUID, patch: ItemPatch) async throws -> Item {
        patches.append((itemId, patch))
        if shouldThrow { throw StubFetchError() }
        return Item(id: itemId, type: .text, title: nil, content: nil, url: nil, filePath: nil,
                    description: nil, summary: nil, pageBody: nil, supplementalNote: nil,
                    mimeType: nil, isPublic: false, createdAt: Date())
    }
    func deleteItemCascade(itemId: UUID) async throws { fatalError("unused") }
    func itemTags(itemId: UUID) async throws -> [StashTag] { fatalError("unused") }
    func addTag(named: String, userId: UUID, itemId: UUID) async throws { fatalError("unused") }
    func removeTag(tagId: UUID, itemId: UUID) async throws { fatalError("unused") }
    func suggestTags(title: String, content: String, description: String, available: [String]) async throws -> [String] { fatalError("unused") }
}

@MainActor
final class ReminderStoreTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-09-06T12:00:00Z")!
    func item(_ name: String, remindAt: String) -> Item {
        Item(id: UUID(), type: .text, title: name, content: nil, url: nil, filePath: nil, description: nil,
             summary: nil, pageBody: nil, supplementalNote: nil, mimeType: nil, isPublic: false,
             createdAt: now, remindAt: ISO8601DateFormatter().date(from: remindAt))
    }

    func testRefreshKeepsOnlyDueRowsSortedByRemindAt() async {
        let fetcher = StubDueFetcher()
        fetcher.rows = [item("later", remindAt: "2026-09-06T09:00:00Z"),
                        item("expired", remindAt: "2026-09-01T00:00:00Z"),
                        item("earlier", remindAt: "2026-09-05T20:00:00Z")]
        let store = ReminderStore(userId: UUID(), fetcher: fetcher, patcher: RecordingPatcher(), now: { self.now })
        await store.refresh()
        XCTAssertEqual(store.dueItems.map(\.title), ["earlier", "later"])
        XCTAssertEqual(store.dueCount, 2)
    }

    func testTickDropsItemsThatExpireWithoutANetworkCall() async {
        let fetcher = StubDueFetcher()
        fetcher.rows = [item("edge", remindAt: "2026-09-05T12:30:00Z")]   // due until 12:30 today
        var clock = now
        let store = ReminderStore(userId: UUID(), fetcher: fetcher, patcher: RecordingPatcher(), now: { clock })
        await store.refresh()
        XCTAssertEqual(store.dueCount, 1)
        clock = now.addingTimeInterval(31 * 60)
        store.tick()
        XCTAssertEqual(store.dueCount, 0)
        XCTAssertEqual(fetcher.calls, 1)
    }

    func testDismissIsOptimisticAndWritesClear() async {
        let fetcher = StubDueFetcher()
        let due = item("d", remindAt: "2026-09-06T09:00:00Z")
        fetcher.rows = [due]
        let patcher = RecordingPatcher()
        let store = ReminderStore(userId: UUID(), fetcher: fetcher, patcher: patcher, now: { self.now })
        await store.refresh()
        await store.dismiss(due.id)
        XCTAssertEqual(store.dueCount, 0)
        XCTAssertEqual(patcher.patches.count, 1)
        XCTAssertEqual(patcher.patches[0].0, due.id)
        XCTAssertEqual(patcher.patches[0].1.reminder, .clear(now))
    }

    func testDismissFailureRestoresTheItem() async {
        let fetcher = StubDueFetcher()
        let due = item("d", remindAt: "2026-09-06T09:00:00Z")
        fetcher.rows = [due]
        let patcher = RecordingPatcher(); patcher.shouldThrow = true
        let store = ReminderStore(userId: UUID(), fetcher: fetcher, patcher: patcher, now: { self.now })
        await store.refresh()
        await store.dismiss(due.id)
        XCTAssertEqual(store.dueCount, 1)
        XCTAssertNotNil(store.lastError)
    }

    func testSetWritesSetPatch() async {
        let patcher = RecordingPatcher()
        let store = ReminderStore(userId: UUID(), fetcher: StubDueFetcher(), patcher: patcher, now: { self.now })
        let id = UUID()
        await store.set(id, days: 3)
        XCTAssertEqual(patcher.patches[0].1.reminder, .set(now.addingTimeInterval(3 * 86_400)))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ios/StashKit && swift test --filter ReminderStoreTests`
Expected: compile errors.

- [ ] **Step 3: Implement `ReminderStore.swift`**

```swift
import Foundation
import Observation
import Supabase

public protocol DueItemsFetching: Sendable {
    /// Rows that MIGHT be due: uncleared, remind_at already reached. The store
    /// applies the 24h window locally so a ticking clock can expire rows
    /// without another round trip.
    func fetchDueCandidates(userId: UUID, now: Date) async throws -> [Item]
}

public struct SupabaseDueItemsFetcher: DueItemsFetching {
    public init() {}
    public func fetchDueCandidates(userId: UUID, now: Date) async throws -> [Item] {
        let data = try await StashClient.shared
            .from("items")
            .select(Item.listColumns)
            .eq("user_id", value: userId.uuidString)
            .is("reminder_cleared_at", value: nil)
            .lte("remind_at", value: ReminderRules.isoString(now))
            .gt("remind_at", value: ReminderRules.isoString(now.addingTimeInterval(-ReminderRules.dueWindow)))
            .order("remind_at", ascending: true)
            .execute().data
        return try Item.decoder.decode([Item].self, from: data)
    }
}

/// Owns the "due right now" list for the View tab badge and top-of-grid block.
/// Owned by MainTabView (so the badge exists before the tab is opened) and
/// injected into LibraryView through the environment.
@MainActor @Observable
public final class ReminderStore {
    public private(set) var dueItems: [Item] = []
    public private(set) var lastError: String?
    public var dueCount: Int { dueItems.count }

    private var candidates: [Item] = []
    private let userId: UUID
    private let fetcher: DueItemsFetching
    private let patcher: ItemPatching
    private let now: () -> Date

    public init(userId: UUID, fetcher: DueItemsFetching = SupabaseDueItemsFetcher(),
                patcher: ItemPatching = SupabaseItemPatcher(), now: @escaping () -> Date = { Date() }) {
        self.userId = userId
        self.fetcher = fetcher
        self.patcher = patcher
        self.now = now
    }

    public func refresh() async {
        do {
            candidates = try await fetcher.fetchDueCandidates(userId: userId, now: now())
            lastError = nil
        } catch {
            lastError = "Couldn't check reminders."
        }
        tick()
    }

    /// Re-derive the due list from the cached candidates at the current instant.
    public func tick() {
        let t = now()
        dueItems = ReminderRules.orderDueFirst(candidates.filter { $0.reminderState(now: t) == .due }, now: t)
    }

    public func dismiss(_ id: UUID) async {
        let snapshot = candidates
        candidates.removeAll { $0.id == id }
        tick()
        do {
            _ = try await patcher.patch(itemId: id, patch: ItemPatch(reminder: .clear(now())))
            lastError = nil
        } catch {
            candidates = snapshot
            tick()
            lastError = "Couldn't remove the reminder."
        }
    }

    public func set(_ id: UUID, days: Int) async {
        do {
            _ = try await patcher.patch(itemId: id, patch: ItemPatch(reminder: .set(ReminderRules.remindAt(days: days, now: now()))))
            lastError = nil
        } catch {
            lastError = "Couldn't set the reminder."
        }
    }
}
```

If `.is("reminder_cleared_at", value: nil)` does not type-check against supabase-swift 2.54, use `.filter("reminder_cleared_at", operator: "is", value: "null")` — same PostgREST query.

- [ ] **Step 4: `RealtimeObserver` channel suffix**

Change the signature to `observeItems(userId: UUID, channelSuffix: String = "", onChange: …)` and the channel name to `"items-changes-\(userId.uuidString.lowercased())\(channelSuffix)"`. Existing callers compile unchanged.

- [ ] **Step 5: Run tests**

Run: `cd ios/StashKit && swift test`
Expected: green including the five new tests.

- [ ] **Step 6: Commit**

```bash
git add ios/StashKit/Sources/StashKit/ReminderStore.swift ios/StashKit/Sources/StashKit/RealtimeObserver.swift ios/StashKit/Tests/StashKitTests/ReminderStoreTests.swift
git commit -m "feat(ios/reminders): ReminderStore (due list, tick, dismiss, set) + realtime channel suffix"
```

---

### Task 6: Tab badge, due block in the View grid, card chip + Due overlay + dismiss

**Files:**
- Modify: `ios/Stash/MainTabView.swift`, `ios/Stash/Library/LibraryView.swift:14-47, 60-66, 181-190`, `ios/Stash/Library/ItemCardView.swift:33-67, 247-256, 290-300`

**Interfaces:**
- Consumes: `ReminderStore` (Task 5), `Item.reminderState(now:)`, `Item.reminderLabel(now:)` (Task 1).
- Produces: `ItemCardView(item:now:onDismissReminder:)` — `now: Date = Date()`, `onDismissReminder: (() -> Void)? = nil`. Accessibility identifiers `card.reminder`, `card.reminder.dismiss`, `card.due`.

- [ ] **Step 1: `MainTabView` owns the store, shows the badge, refreshes**

```swift
    @State private var reminders: ReminderStore
    @Environment(\.scenePhase) private var scenePhase
```

In `init(userId:)` add `_reminders = State(initialValue: ReminderStore(userId: userId))`.

Replace the View tab entry with:

```swift
            LibraryView(userId: userId)
                .tabItem { Label("View", systemImage: "square.grid.2x2") }
                .tag(MainTab.view)
                // Due-reminder count; SwiftUI hides the badge at zero.
                .badge(reminders.dueCount)
```

On the `TabView` add:

```swift
        .environment(reminders)
        .task { await reminders.refresh() }
        // Own channel (suffix) so this subscription and LibraryView's don't share a name.
        .task { await RealtimeObserver().observeItems(userId: userId, channelSuffix: "-reminders") { await reminders.refresh() } }
        // Reminders cross their boundaries silently; re-derive once a minute while visible.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                reminders.tick()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reminders.refresh() } }
        }
```

- [ ] **Step 2: `LibraryView` merges the due block**

Add `@Environment(ReminderStore.self) private var reminders` (this view is always hosted by `MainTabView`; previews/tests that construct it standalone must inject a `ReminderStore`). Replace `filteredItems`:

```swift
    /// Due reminders first (ReminderStore, remind_at asc), then the paginated
    /// chronological page minus any of those ids. Local search applies to both.
    private var orderedItems: [Item] {
        let dueIds = Set(reminders.dueItems.map(\.id))
        return reminders.dueItems + store.items.filter { !dueIds.contains($0.id) }
    }

    private var filteredItems: [Item] {
        query.isEmpty ? orderedItems : orderedItems.filter { $0.matches(searchQuery: query) }
    }
```

In `grid`, the card label becomes:

```swift
                    } label: {
                        ItemCardView(item: item, onDismissReminder: {
                            Task { await reminders.dismiss(item.id) }
                        })
                    }
```

`refreshable` and the first `.task` also refresh reminders: `.refreshable { await store.refresh(); await reminders.refresh() }`.

- [ ] **Step 3: `ItemCardView` chip, overlay, dismiss**

Add properties:

```swift
    var now: Date = Date()
    var onDismissReminder: (() -> Void)? = nil
```

Footer:

```swift
    private var footer: some View {
        HStack(spacing: 8) {
            Text(Self.footerDateFormatter.string(from: item.createdAt))
                .font(StashType.meta())
                .foregroundStyle(.tertiary)
            reminderChip
            if let label = item.attributes.location?.label, !label.isEmpty {
                locationBadge(label)
            }
        }
    }

    // MARK: - Reminder chip (DESIGN.md → Reminder chip; web ReminderChip.tsx)

    @ViewBuilder private var reminderChip: some View {
        let state = item.reminderState(now: now)
        if let label = item.reminderLabel(now: now) {
            if state == .due {
                HStack(spacing: 4) {
                    Image(systemName: "bell.fill").font(.system(size: 9))
                    Text(label)
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                        // The card itself is a Button; a high-priority tap here wins over it.
                        .highPriorityGesture(TapGesture().onEnded { onDismissReminder?() })
                        .accessibilityIdentifier("card.reminder.dismiss")
                        .accessibilityLabel("Remove reminder")
                        .accessibilityAddTraits(.isButton)
                }
                .font(StashType.chip())
                .foregroundStyle(StashColor.violet600)
                .padding(.leading, 8)
                .padding(.vertical, 2)
                .background(StashColor.violet600.opacity(0.10), in: Capsule())
                .accessibilityIdentifier("card.reminder")
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "clock").font(.system(size: 9))
                    Text(label)
                }
                .font(StashType.meta())
                .foregroundStyle(.tertiary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Reminder \(label)")
                .accessibilityIdentifier("card.reminder")
            }
        }
    }

    @ViewBuilder private var duePill: some View {
        if item.reminderState(now: now) == .due {
            Text("Due")
                .font(StashType.chip())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(StashColor.violet600, in: Capsule())
                .padding(8)
                .accessibilityIdentifier("card.due")
        }
    }
```

Replace `.overlay(alignment: .topTrailing) { stickyBadge }` with:

```swift
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) { duePill; stickyBadge }
        }
```

- [ ] **Step 4: Build, run on the simulator, verify**

```bash
cd ios && xcodegen generate
```

Build the `Stash` scheme for the simulator (recipe in memory `ios-app-plan`), launch with `--uitest-tab-view` on the `will+uitest` account, then:

1. Set a reminder on the web (Plan 1) or via SQL `update items set remind_at = now() - interval '5 minutes', reminder_cleared_at = null where id = '<id>'`. Within ~1 s (realtime) the View tab shows badge `1`, the card sits first with the violet `Due` pill and chip.
2. Tap the × on the chip: card drops back into its chronological slot, badge disappears, and `select reminder_cleared_at from items where id = '<id>'` is set.
3. `update items set remind_at = now() + interval '3 days', reminder_cleared_at = null …` → footer shows `in 3d`, no badge.
4. Background and foreground the app → badge/state re-derived (scenePhase refresh).
5. Tap the card body (not the ×) → detail sheet opens as before.

- [ ] **Step 5: Unit tests still green**

Run: `cd ios/StashKit && swift test`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add ios/Stash/MainTabView.swift ios/Stash/Library/LibraryView.swift ios/Stash/Library/ItemCardView.swift
git commit -m "feat(ios/reminders): View tab badge, due block first in the grid, card chip + Due pill + dismiss"
```

---

### Task 7: Docs + hand-off

**Files:**
- Modify: `docs/ui-changes.md` (the `2026-09-06 · Reminders` entry written by Plan 1)

- [ ] **Step 1: Replace the "iOS (plan 2)" bullet with what shipped**

```markdown
- **iOS (shipped):** share sheet — `Remind me · 1 day · 3 days · 5 days` chips
  above Save (`share.remind.{1,3,5}d`), tap again to deselect, never blocks
  Save; done copy appends `· back in N days`. Queued shares carry `remind_at`
  in the outbox payload. View tab — `.badge(dueCount)` from `ReminderStore`
  (owned by `MainTabView`, refreshed on launch / foreground / realtime, 60 s
  local tick); due block first in the grid above the `created_at` page;
  card footer chip (`card.reminder`, × = `card.reminder.dismiss`) and a
  violet `Due` overlay (`card.due`). Writes go through `ItemPatch.reminder`
  (`.set` / `.clear`). Not in this cut on iOS: setting a reminder from a card
  or the in-app composer.
```

- [ ] **Step 2: Commit and finish**

```bash
git add docs/ui-changes.md
git commit -m "docs(reminders): iOS shipped notes in the ui-changes entry"
```

Then `superpowers:finishing-a-development-branch`. A TestFlight build follows the release recipe in `docs/RELEASING.md`; note the build number in the plan's outcome section.

---

## Self-review

- Spec coverage: model + list columns (T1), derived state mirror (T1), set/dismiss writes (T2), capture parameter incl. offline outbox (T3), share-sheet chips + copy (T4), due query + store + tick + realtime suffix (T5), badge + ordering + card chip/pill/dismiss + refresh triggers (T6), ui-changes (T7). In-app composer, card-level set on iOS, detail sheet: out of scope per spec.
- Names: `ReminderRules`, `ReminderState`, `ReminderPatch`, `ItemPatch.reminder`, `ReminderStore`, `DueItemsFetching`, `fetchDueCandidates`, `observeItems(userId:channelSuffix:onChange:)`, `submit(_:note:location:remindAt:)`, `card.reminder`, `card.reminder.dismiss`, `card.due`, `share.remind.Nd` — consistent across tasks.
