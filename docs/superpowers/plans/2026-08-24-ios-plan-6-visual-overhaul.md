# Stash iOS — Plan 6: Visual overhaul (web design parity)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the iOS app *usable* (the Add screen currently renders content wider than the device and clips it off both edges) and *on-brand* — same design language as gostash.it: the lavender/pink wash, white cards with violet-tinted shadows, editorial serif titles, the violet accent, and a composer that looks like the web's capture panel while staying one-gesture fast.

**Architecture:** A new app-side design-token layer (`ios/Stash/Theme/`) ports the web's actual values (extracted 2026-08-24 from `src/index.css`, `tailwind.config.ts`, `UnifiedInputPanel.tsx`, `ContentItem*.tsx`, `mockups/main-screen-redesign.html` — distilled in §Design contract below, so no task needs to re-read the web code). The Add tab is rebuilt as a branded composer card on the gradient backdrop; Library/Ask/Settings get a restyle pass on top of their existing structure. Per `docs/ETHOS.md`, parity means *design language and contracts, not pixel-cloning* — platform adaptations are named explicitly in §Decisions.

**Tech Stack:** Swift 5.10 / SwiftUI, iOS 17 minimum, XcodeGen (`ios/project.yml` — no pbxproj surgery), asset-catalog colors/SVG vectors, XCTest + XCUITest.

**Spec:** `docs/superpowers/specs/2026-08-10-stash-ios-app-design.md` Phase 7 ("Visual/design parity with the web app"), **re-sequenced ahead of Phase 6 (widgets) per Will 2026-08-24** — the app is not usable in its current form. Read also `docs/ETHOS.md` and `docs/ui-changes.md` (2026-08-11→16 card-system entry).

## Global Constraints

- Everything standing still binds: min iOS 17, worktree-branch commits (no push), warning-free builds (the two pre-existing environmental notices carried since plan 1 are allowed: multiple-matching-destinations, `appintentsmetadataprocessor` skip), exact-path `git add`, no credentials, `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`, `swift test` from `ios/StashKit` (**baseline 281/281**), sim UDID `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB` + `-derivedDataPath DerivedData`, EXPORTED `TEST_RUNNER_*` vars, `--uitest-reset-auth`, `xcodegen generate` after any `project.yml` change.
- **This is a visual plan. Zero capture/data-contract behavior changes.** The only permitted interaction changes are the ones named in §Decisions (controls relocating into the attach menu). Field semantics, routing, Outbox, gate *logic* are untouchable.
- **Every existing accessibility identifier survives.** The full inventory in play: `capture.editor`, `capture.urlchip`, `capture.attachment.remove`, `capture.photosPicker`, `capture.cameraButton`, `capture.fileButton`, `capture.voice`, `capture.toggle.public`, `capture.pin`, `capture.pin.preview`, `capture.pin.openSettings`, `capture.save`, `capture.subscriptionGate`, `capture.outboxBadge`, `capture.dismissKeyboard`, `capture.toast`, all `capture.voice.*`, all `ask.*`, all `card.*`, all `detail.*`. A control that moves into a menu carries its identifier onto the menu item; the UI test gains an open-menu step (Task 3 handles the test edits).
- **UI-suite expected profile is unchanged:** 12/15 passing + EXACTLY the 3 standing gate-blocked adjudicated failures (`testCaptureSmoke`, `testLocationPinSmoke`, `testAskSmoke` — the test account's Stripe trial is lapsed; see plan-5 wrap). Any new test must pass gate-agnostically.
- **Light mode only, locked.** The web's dark tokens are dead code (no ThemeProvider); iOS locks `.preferredColorScheme(.light)` at root rather than shipping an untested dark theme. (Tokens live in one file so dark can come later without a hunt.)
- **Never fake enrichment** (ETHOS): chips/badges render only when data exists; the favicon-plate's "preview limited · saved anyway" honesty pattern stays.
- Radii are *deliberately* inconsistent on web (composer 6 · chips 8 · controls 12 · cards 16 · pills capsule). Port them as-is; do not unify.
- Do NOT build: widgets/App Intents (now plan 7), link-metadata client-side hydration, dark mode, in-app payments, `ProviderLoader` generic-file branch, macOS. Carried ledger items from plan-5 stay carried unless named in a task.
- `docs/ui-changes.md` entry + spec phase-list amendment land in the same branch (Task 7).

---

## Design contract (extracted from web 2026-08-24 — self-contained, do not re-derive)

**Colors** (web's `--primary` is near-black ink, NOT the accent — the violet is hard-coded `violet-*` on web):

| Token | Hex | Web source |
|---|---|---|
| ink (foreground) | `#282C34` | `--foreground 220 13% 18%` |
| inkMuted | `#6B7280` | `--muted-foreground` |
| inkFaint (placeholder) | `#6B7280` @ 70% | composer placeholder CSS |
| border / input | `#E2E8F0` | `--border 214.3 31.8% 91.4%` |
| muted surface | `#F5F5F5` | `--muted` |
| secondary surface | `#E5E7EB` | `--secondary` |
| **violet (accent)** | `#8B5CF6` | send button, violet-500 |
| violetPressed | `#7C3AED` | violet-600 |
| violet300 | `#C4B5FD` | annotation bar |
| violet200 | `#DDD6FE` | hairlines |
| violet50 | `#F5F3FF` | tint surfaces |
| avatarPurple | `#C084FC` | header avatar |
| ink900 (dark pill/bubble) | `#111827` | gray-900 |
| gray800→gray950 | `#1F2937`→`#030712` | Ask pill gradient |
| destructive | `#EF4444` | `--destructive` |
| cardShadowTint | `rgba(160,120,200,0.12)` | ContentItem shadow |
| gate amber: border `#FDE68A`@70% · bg `#FFFBEB`→`#FFF7ED`@70% · text `#92400E` | | SubscriptionBanner urgent variant |
| backdrop: linear 170° `#FDF5F8`→55% `#FAEEF7`→`#F3E8FB`; glow ellipses `rgba(216,180,254,.45)` at (85%,100%) and `rgba(251,207,232,.55)` at (10%,90%) | | `mockups/main-screen-redesign.html:38-42` (the sanctioned static form of the animated web gradient) |

**Typography:** UI sans = system (SF; web uses Inter — SF is the platform-native equivalent, per ETHOS). Titles = editorial serif, **weight 400 only** (web ships PPEditorialNew-Regular in a single weight — never bold serif). iOS v1 renders serif as New York via `design: .serif` behind a `StashTheme.editorialTitle()` indirection; swapping in licensed PPEditorialNew later is a one-line change (§Open questions). Ramp in use: 11 kicker (uppercase, +0.5 tracking, medium) · 12 date/meta · 13.5 annotation · 14 body · 16 editor · 20 card title (17 on iOS 2-col cards) · 24 empty-state serif. Mono = `.monospaced()` for filename chips.

**Composer anatomy** (web `UnifiedInputPanel`): white card @ 90% opacity, **radius 6**, rest shadow `0 0 0 1px rgba(0,0,0,0.05), 0 10px 30px -18px rgba(0,0,0,0.3)`; active (focused or has content) swaps to a violet ring `0 0 0 1.5px rgba(139,92,246,0.5), 0 0 0 6px rgba(139,92,246,0.08)` + violet shadow `0 24px 48px -20px rgba(139,92,246,0.35)` with a tiny lift. Bottom row: circular **48pt** white bordered buttons — `+` attach (icon 24), location pin (icon 20, violet-tinted when active), send (icon 20; **violet bg + white icon when "hot"** = content present; violetPressed on press). Location text `posted from {label}` / `finding your location…` at 12pt muted, truncating, max ~220. Chips: white, border `#E2E8F0`, radius 8, `px-3 py-2`, 40pt thumb (radius 4), title 14 medium 2-line clamp, desc 12 muted 2-line clamp, X dismiss 24pt hit target.

**Card anatomy** (web `ContentItem*`): white, **radius 16, no border**, layered shadow `0 1px 2px rgba(0,0,0,0.06)` + `0 8px 24px rgba(160,120,200,0.12)`; hero heights 160/224 (iOS `CardHeroHeight` already matches); kicker 11 uppercase muted; serif title; description 14 muted 3-line clamp; annotation = 2pt violet300 left bar, 12pt inset, 13.5pt @ 75% ink; capsule meta chips `black @ 4%`; footer date 12 muted + location pin 12.

**Header** (web): white bar, subtle shadow; STASH wordmark = inline SVG (`src/components/StashWordmark.tsx`, viewBox `150 419 724 186`, `currentColor`) at 24pt tall, ink; then `/ August 24, 2026` in 16pt muted regular.

**Motion:** house spring ≈ `.spring(response: 0.29, dampingFraction: 0.78)` (web stiffness 320/damping 28/mass 0.7); default duration 200ms ease-out; hover-reveal idioms become always-visible on touch.

---

### Task 1: Stop the bleed — Add screen fits the screen again

The app is unusable because of one layout bug. Fix it surgically first so every later task's screenshots are legible and the app is shippable at any checkpoint. (Task 3 rebuilds this screen; these fixes are insurance, not throwaway styling.)

**Root cause** (mapped 2026-08-24): `CaptureComposerView.swift:209-270` `bottomBar` is an HStack of 7 `.bordered` controls + 14pt spacing ≈ **426pt intrinsic width vs ~361pt available** (393pt device − 32pt padding). The parent `VStack` at `:59` has no width constraint, so it adopts the child's overflow width and is centered — shifting *every* sibling ~32pt off-screen left. Secondary: `CaptureAttachmentsRow.swift:36` offsets the remove badge outside the row's bounds.

**Files:**
- Modify: `ios/Stash/Capture/CaptureComposerView.swift` (`:59`, `:209-270`)
- Modify: `ios/Stash/Capture/CaptureAttachmentsRow.swift` (`:10-39`)

- [ ] **Step 1: Constrain the composer column.** On the `VStack(alignment: .leading, spacing: 14)` at `CaptureComposerView.swift:59`, add (after the closing brace, alongside the existing `.padding()` at `:76`):

```swift
.frame(maxWidth: .infinity, alignment: .leading)
```

This alone stops overflow *propagation* — siblings pin to the true leading edge even if a child still overflows.

- [ ] **Step 2: Make the bottom bar fit.** In `bottomBar` (`:209-270`): change `HStack(spacing: 14)` → `HStack(spacing: 4)`; delete the row-wide `.buttonStyle(.bordered)` at `:269` (keep `.borderedProminent` on Save at `:333`); add `.imageScale(.medium)` where `.large` was set on the four picker/mic icons; give each icon button `.frame(minWidth: 40, minHeight: 40)` so hit targets stay ≥40pt without bordered chrome. Budget check after: 6 plain icons ≈ 40×6 + Save ~66 + spacing ≈ **≈330pt < 361pt** — fits with the Spacer breathing.

- [ ] **Step 3: Keep the remove badge inside bounds.** In `CaptureAttachmentsRow.swift`: change the X button's `.offset(x: 6, y: -6)` (`:36`) to `.offset(x: 4, y: -4)` and add `.padding(.top, 6)` + `.padding(.trailing, 6)` on the `HStack(spacing: 10)` inside the ScrollView (`:11`) so the poked-out badge renders inside the scroll view's own bounds instead of clipping at the screen edge.

- [ ] **Step 4: Build + visual verify.**

```bash
cd /path/to/worktree/ios && xcodegen generate && \
xcodebuild -project Stash.xcodeproj -scheme Stash \
  -destination 'platform=iOS Simulator,id=28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB' \
  -derivedDataPath DerivedData build 2>&1 | tail -3
xcrun simctl boot 28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB 2>/dev/null; sleep 5
xcrun simctl install 28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB DerivedData/Build/Products/Debug-iphonesimulator/Stash.app
xcrun simctl launch 28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB it.gostash.stash; sleep 3
xcrun simctl io 28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB screenshot /tmp/plan6-t1-add.png
```

Expected: BUILD SUCCEEDED, zero `: warning:`; screenshot shows the placeholder's first character, all bottom-row icons, and no content past either screen edge. Read the PNG to confirm — do not assert from memory.

- [ ] **Step 5: Run the UI capture smokes** (gate-blocked ones will adjudicate as standing failures — confirm no NEW failures):

```bash
xcodebuild -project Stash.xcodeproj -scheme Stash -derivedDataPath DerivedData \
  -destination 'platform=iOS Simulator,id=28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB' \
  test 2>&1 | tail -20
```

Expected: 12/15 pass + the 3 adjudicated (`testCaptureSmoke`, `testLocationPinSmoke`, `testAskSmoke`).

- [ ] **Step 6: Commit.**

```bash
git add ios/Stash/Capture/CaptureComposerView.swift ios/Stash/Capture/CaptureAttachmentsRow.swift
git commit -m "fix(ios): Add screen no longer overflows device width

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Theme foundation — tokens, backdrop, accent, light lock

**Files:**
- Create: `ios/Stash/Theme/Theme.swift`
- Create: `ios/Stash/Theme/StashBackground.swift`
- Modify: `ios/Stash/Assets.xcassets/AccentColor.colorset/Contents.json` (currently declares no color → system blue)
- Modify: `ios/Stash/StashApp.swift` (`:14-24` — light lock)
- Modify: `ios/Stash/Library/CardChips.swift` (`:18-29` — re-point hardcoded colors at Theme)
- Modify: `ios/project.yml` (`StashShareExtension` `sources:` gains the two Theme files, same pattern as its existing `Stash/Capture/LocationCapture.swift` entry)

**Interfaces (Produces — later tasks use these exact names):**

```swift
enum StashTheme {
    // colors (values from §Design contract)
    static let ink, inkMuted, border, muted, secondary: Color
    static let violet, violetPressed, violet300, violet200, violet50: Color
    static let ink900, avatarPurple, destructive: Color
    static let gateText, gateBorder, gateBg: Color
    static let cardShadowTint: Color            // rgba(160,120,200,0.12)
    // typography
    static func editorialTitle(_ size: CGFloat = 20) -> Font   // serif, weight .regular ONLY
    static let kicker: Font                      // 11pt medium (apply .textCase(.uppercase) + .tracking(0.5) at site)
    // radii
    enum Radius { static let composer: CGFloat = 6; static let chip: CGFloat = 8; static let control: CGFloat = 12; static let card: CGFloat = 16 }
    // motion
    static let spring: Animation                 // .spring(response: 0.29, dampingFraction: 0.78)
    static let quick: Animation                  // .easeOut(duration: 0.2)
}
extension Color { init(hex: UInt32, opacity: Double = 1) }
extension View { func stashCardShadow() -> some View }   // the two-layer card shadow
struct StashBackground: View                     // full-bleed gradient backdrop, ignoresSafeArea
```

- [ ] **Step 1: Write `ios/Stash/Theme/Theme.swift`** (complete file):

```swift
import SwiftUI

/// Design tokens ported from the web app (src/index.css, tailwind.config.ts,
/// UnifiedInputPanel/ContentItem) — contract distilled in
/// docs/superpowers/plans/2026-08-24-ios-plan-6-visual-overhaul.md.
/// Light-only by decision (web dark tokens are dead code). One file on purpose:
/// a future dark pass edits here, not a scavenger hunt.
enum StashTheme {
    // MARK: Ink & surfaces
    static let ink = Color(hex: 0x282C34)          // --foreground
    static let inkMuted = Color(hex: 0x6B7280)     // --muted-foreground
    static let border = Color(hex: 0xE2E8F0)       // --border / --input
    static let muted = Color(hex: 0xF5F5F5)        // --muted
    static let secondary = Color(hex: 0xE5E7EB)    // --secondary
    static let ink900 = Color(hex: 0x111827)       // gray-900: dark bubbles/pills

    // MARK: Accent (web hard-codes violet-*; --primary is NOT the accent)
    static let violet = Color(hex: 0x8B5CF6)
    static let violetPressed = Color(hex: 0x7C3AED)
    static let violet300 = Color(hex: 0xC4B5FD)    // annotation bar
    static let violet200 = Color(hex: 0xDDD6FE)    // hairlines
    static let violet50 = Color(hex: 0xF5F3FF)     // tint surfaces
    static let avatarPurple = Color(hex: 0xC084FC)
    static let destructive = Color(hex: 0xEF4444)

    // MARK: Subscription gate strip (web SubscriptionBanner urgent variant)
    static let gateText = Color(hex: 0x92400E)     // amber-800
    static let gateBorder = Color(hex: 0xFDE68A, opacity: 0.7)
    static let gateBg = Color(hex: 0xFFFBEB)       // amber-50

    // MARK: Card shadow tint
    static let cardShadowTint = Color(red: 160/255, green: 120/255, blue: 200/255)

    // MARK: Typography — serif is weight 400 ONLY (web ships a single
    // PPEditorialNew weight; bold serif would be synthesized and off-brand).
    static func editorialTitle(_ size: CGFloat = 20) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
    static let kicker: Font = .system(size: 11, weight: .medium)

    enum Radius {
        static let composer: CGFloat = 6   // web keeps these distinct by design —
        static let chip: CGFloat = 8       // do not unify
        static let control: CGFloat = 12
        static let card: CGFloat = 16
    }

    // MARK: Motion (web: spring 320/28/0.7; default 200ms ease-out)
    static let spring: Animation = .spring(response: 0.29, dampingFraction: 0.78)
    static let quick: Animation = .easeOut(duration: 0.2)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension View {
    /// Web card shadow: 0 1px 2px rgba(0,0,0,.06) + 0 8px 24px rgba(160,120,200,.12)
    func stashCardShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
            .shadow(color: StashTheme.cardShadowTint.opacity(0.12), radius: 12, x: 0, y: 8)
    }
}
```

- [ ] **Step 2: Write `ios/Stash/Theme/StashBackground.swift`** (complete file — static port of the mockup's sanctioned gradient, not the animated web one):

```swift
import SwiftUI

/// The signature lavender/pink wash behind every branded surface.
/// Static port of mockups/main-screen-redesign.html:38-42 (the design-intent
/// form of the web's animated composer gradient).
struct StashBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0xFDF5F8), location: 0),
                    .init(color: Color(hex: 0xFAEEF7), location: 0.55),
                    .init(color: Color(hex: 0xF3E8FB), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            EllipticalGradient(
                colors: [Color(hex: 0xD8B4FE, opacity: 0.45), .clear],
                center: UnitPoint(x: 0.85, y: 1.0),
                startRadiusFraction: 0, endRadiusFraction: 0.6
            )
            EllipticalGradient(
                colors: [Color(hex: 0xFBCFE8, opacity: 0.55), .clear],
                center: UnitPoint(x: 0.10, y: 0.90),
                startRadiusFraction: 0, endRadiusFraction: 0.65
            )
        }
        .ignoresSafeArea()
    }
}
```

- [ ] **Step 3: Set the real accent.** Overwrite `ios/Stash/Assets.xcassets/AccentColor.colorset/Contents.json` (it currently has an idiom entry with no color — that's why everything is system blue):

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0xF6", "green" : "0x5C", "red" : "0x8B" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

Tab bar selection, toggles, links, and every `Color.accentColor` use go violet app-wide with no per-view edits.

- [ ] **Step 4: Lock light mode.** In `ios/Stash/StashApp.swift`, on the root `Group` (the one switching on `session.state`, `:14-21`), add `.preferredColorScheme(.light)` alongside the existing `.environment` modifiers at `:22-23`.

- [ ] **Step 5: Re-point `CardChips.swift` colors at Theme.** Replace the literal RGB values at `:18-29` so the existing names become aliases (call sites don't churn):

```swift
extension Color {
    static let cardAnnotationBar = StashTheme.violet300
    static let cardVioletAccent = StashTheme.violet
    static let cardVioletTint = StashTheme.violet50
    static let cardRedAccent = StashTheme.destructive
    static let cardRedTint = Color(hex: 0xFEF2F2)   // red-50, was the literal
}
```

Keep the `CardHeroHeight` enum (160/224 already matches web's 10rem/14rem).

- [ ] **Step 6: Share the Theme with the extension.** In `ios/project.yml`, under the `StashShareExtension` target's `sources:` list (the block that already carries `Stash/Capture/LocationCapture.swift`, `:43-52`), add:

```yaml
- path: Stash/Theme/Theme.swift
- path: Stash/Theme/StashBackground.swift
```

- [ ] **Step 7: Build both targets + StashKit tests.**

```bash
cd ios && xcodegen generate && \
xcodebuild -project Stash.xcodeproj -scheme Stash \
  -destination 'platform=iOS Simulator,id=28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB' \
  -derivedDataPath DerivedData build 2>&1 | grep -E "(error|warning|SUCCEEDED)" | head
cd StashKit && swift test 2>&1 | tail -2
```

Expected: BUILD SUCCEEDED, no new warnings, 281/281. Launch + screenshot: tab bar tint is now violet (visible proof the asset landed).

- [ ] **Step 8: Commit.**

```bash
git add ios/Stash/Theme/Theme.swift ios/Stash/Theme/StashBackground.swift \
  ios/Stash/Assets.xcassets/AccentColor.colorset/Contents.json \
  ios/Stash/StashApp.swift ios/Stash/Library/CardChips.swift ios/project.yml
git commit -m "feat(ios): theme foundation — web design tokens, gradient backdrop, violet accent, light lock

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Add tab rebuild — the branded composer

The centerpiece. The Add tab becomes: brand header (wordmark + date) over the gradient backdrop, with the composer as a floating white card that matches the web's anatomy — editor, chips, then one bottom row: `+` attach menu · mic · location text · pin · circular send.

**Files:**
- Create: `ios/Stash/Assets.xcassets/StashWordmark.imageset/` (`stash-wordmark.svg` + `Contents.json`)
- Create: `ios/Stash/Capture/ComposerCard.swift` (shell styling + focus ring, so CaptureComposerView stays readable)
- Modify: `ios/Stash/Capture/CaptureComposerView.swift` (structure per below)
- Modify: `ios/Stash/Capture/CaptureAttachmentsRow.swift` (chip restyle)
- Modify: `ios/StashUITests/StashUITests.swift` (menu-open steps for relocated ids)

**Interfaces:**
- Consumes: `StashTheme`, `StashBackground`, `Color(hex:)`, `.stashCardShadow()` (Task 2).
- Produces: `struct ComposerCard<Content: View>: View { init(isActive: Bool, @ViewBuilder content: () -> Content) }` — white card, radius `StashTheme.Radius.composer`, rest border 1pt black@5% / active ring 1.5pt violet@50% + 6pt halo violet@8%, active shadow violet@35% radius 24 y14, `StashTheme.spring` between states. Reused by Task 6 (share extension).

- [ ] **Step 1: Wordmark asset.** Create `ios/Stash/Assets.xcassets/StashWordmark.imageset/stash-wordmark.svg`: an SVG wrapper `<svg xmlns="http://www.w3.org/2000/svg" viewBox="150 419 724 186">…</svg>` whose `<path>` elements (including `fill-rule="evenodd"` where the source sets it) are copied **verbatim** from `src/components/StashWordmark.tsx:10-35`, with `fill` attributes set to `black` (template tinting supplies color). `Contents.json`:

```json
{
  "images" : [ { "filename" : "stash-wordmark.svg", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "preserves-vector-representation" : true, "template-rendering-intent" : "template" }
}
```

Xcode ≥12 rasterizes SVG natively — no conversion tooling. Verify by rendering `Image("StashWordmark")` in Step 5's header.

- [ ] **Step 2: `ComposerCard.swift`** (complete file):

```swift
import SwiftUI

/// The web composer's shell: white card, tight 6pt radius, violet focus glow
/// when active (focused or non-empty) — UnifiedInputPanel.tsx:914-926 port.
struct ComposerCard<Content: View>: View {
    let isActive: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: StashTheme.Radius.composer, style: .continuous)
                    .fill(Color.white.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: StashTheme.Radius.composer, style: .continuous)
                    .strokeBorder(
                        isActive ? StashTheme.violet.opacity(0.5) : Color.black.opacity(0.05),
                        lineWidth: isActive ? 1.5 : 1
                    )
            )
            .background(
                // the 6pt halo ring, web's 0 0 0 6px rgba(139,92,246,0.08)
                RoundedRectangle(cornerRadius: StashTheme.Radius.composer + 6, style: .continuous)
                    .fill(StashTheme.violet.opacity(isActive ? 0.08 : 0))
                    .padding(-6)
            )
            .shadow(
                color: isActive ? StashTheme.violet.opacity(0.35) : Color.black.opacity(0.18),
                radius: isActive ? 24 : 15, x: 0, y: isActive ? 14 : 10
            )
            .scaleEffect(isActive ? 1.004 : 1)
            .animation(StashTheme.spring, value: isActive)
    }
}
```

- [ ] **Step 3: Restructure `CaptureComposerView.body`.** Target hierarchy (keep every `@State`/model binding and all logic exactly as-is; this step moves *presentation only*):

```swift
NavigationStack {
    ZStack {
        StashBackground()
        ScrollView {                             // gate strip + chips can extend; scroll beats clip
            VStack(alignment: .leading, spacing: 16) {
                brandHeader                      // wordmark + date (Step 5)
                ComposerCard(isActive: isEditorFocused || !model.isEmpty) {
                    VStack(alignment: .leading, spacing: 12) {
                        editor                   // existing, restyled Step 4
                        if let url = model.detectedURL { urlChip(url) }
                        CaptureAttachmentsRow(attachments: $model.attachments)
                        bottomRow                // Step 6
                    }
                    .padding(16)
                }
                if !subscription.canAddContent { gateStrip }   // Step 7
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    .scrollDismissesKeyboard(.interactively)
    .toolbar { /* existing outbox badge + keyboard Done toolbar items — unchanged ids */ }
    .toolbar(.hidden, for: .navigationBar)       // brandHeader replaces the "Add" large title…
}
```

…**unless** the outbox badge toolbar item stops being reachable with the bar hidden — in that case keep the navigation bar visible with `.toolbarBackground(.hidden, for: .navigationBar)` + empty title instead, and put the wordmark in a `.topBarLeading` toolbar item. Decide by running it; `capture.outboxBadge` and `capture.dismissKeyboard` must stay reachable (UI tests reference them).

`model.isEmpty` = existing emptiness check used by the Save-disable logic (text empty && attachments empty && no URL); `isEditorFocused` = existing `@FocusState` if present, else add one bound to the TextEditor.

- [ ] **Step 4: Editor restyle** (inside the existing `editor` ZStack `:157-175`): TextEditor `.scrollContentBackground(.hidden)`, `.font(.system(size: 16))`, `.frame(minHeight: 120, maxHeight: 220)`; placeholder Text becomes `"Paste a link, type a note, or add a photo…"` in `.foregroundStyle(StashTheme.inkMuted.opacity(0.7))`, same 16pt. Identifier `capture.editor` unchanged.

- [ ] **Step 5: `brandHeader`** (new private var):

```swift
private var brandHeader: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image("StashWordmark")
            .resizable().scaledToFit()
            .frame(height: 22)
            .foregroundStyle(StashTheme.ink)
        Text("/ \(Date.now.formatted(.dateTime.month(.wide).day().year()))")
            .font(.system(size: 15))
            .foregroundStyle(StashTheme.inkMuted)
        Spacer()
    }
    .padding(.top, 4)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Stash")
}
```

- [ ] **Step 6: `bottomRow`** — replaces `bottomBar` (`:209-270`). Web pattern: pickers collapse behind `+`; mic stays visible (voice capture is an iOS-first affordance); send goes circular-violet-when-hot:

```swift
private var bottomRow: some View {
    HStack(spacing: 10) {
        Menu {
            Button { showPhotosPicker = true } label: { Label("Photo Library", systemImage: "photo.on.rectangle") }
                .accessibilityIdentifier("capture.photosPicker")
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label("Camera", systemImage: "camera") }
                    .accessibilityIdentifier("capture.cameraButton")
            }
            Button { showFileImporter = true } label: { Label("Attach File", systemImage: "doc.badge.plus") }
                .accessibilityIdentifier("capture.fileButton")
            Divider()
            Toggle(isOn: $model.isPublic) { Label(model.isPublic ? "Public" : "Private", systemImage: model.isPublic ? "globe" : "lock") }
                .accessibilityIdentifier("capture.toggle.public")
        } label: {
            circleControl(icon: "plus", size: 24)
        }
        .accessibilityIdentifier("capture.attach")

        Button { /* existing voice recorder presentation */ } label: { circleControl(icon: "mic", size: 18) }
            .accessibilityIdentifier("capture.voice")
            .disabled(/* existing mic-availability + gate conditions, unchanged */)

        Spacer(minLength: 4)

        if let label = locationPreviewLabel {   // existing pinPreview data source
            Text("posted from \(label)")
                .font(.system(size: 12)).foregroundStyle(StashTheme.inkMuted)
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: 150, alignment: .trailing)
                .accessibilityIdentifier("capture.pin.preview")
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }

        Button { /* existing pin toggle action */ } label: {
            circleControl(icon: pinActive ? "mappin.circle.fill" : "mappin", size: 20,
                          tint: pinActive ? StashTheme.violet : nil,
                          bg: pinActive ? StashTheme.violet50 : .white,
                          border: pinActive ? StashTheme.violet300 : StashTheme.border)
        }
        .accessibilityIdentifier("capture.pin")

        Button { /* existing save action */ } label: {
            Group {
                if model.isSubmitting { ProgressView().tint(sendIsHot ? .white : StashTheme.inkMuted) }
                else { Image(systemName: "paperplane.fill").font(.system(size: 18)) }
            }
            .frame(width: 48, height: 48)
            .foregroundStyle(sendIsHot ? .white : Color(hex: 0x9CA3AF))
            .background(Circle().fill(sendIsHot ? StashTheme.violet : .white))
            .overlay(Circle().strokeBorder(sendIsHot ? StashTheme.violet : StashTheme.border, lineWidth: 1))
        }
        .accessibilityIdentifier("capture.save")
        .disabled(/* existing canSave/gate condition, unchanged */)
        .animation(StashTheme.quick, value: sendIsHot)
    }
}

private func circleControl(icon: String, size: CGFloat, tint: Color? = nil,
                           bg: Color = .white, border: Color = StashTheme.border) -> some View {
    Image(systemName: icon)
        .font(.system(size: size, weight: .medium))
        .foregroundStyle(tint ?? Color(hex: 0x6B7280))
        .frame(width: 48, height: 48)
        .background(Circle().fill(bg))
        .overlay(Circle().strokeBorder(border, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
}
```

`sendIsHot` = web rule: trimmed text ≥ 3 chars OR ≥ 1 attachment OR URL chip present — derive from existing model state, add as a private computed var. Width budget: 48+48 + chip(≤150) + 48+48 + spacing ≈ 352pt worst case < 361pt; the chip's `maxWidth: 150` + truncation is the shrink path. PhotosPicker moves from inline view to `.photosPicker(isPresented: $showPhotosPicker, selection: …)` modifier (iOS 16+) with the existing selection binding; camera/file continue via their existing sheet/importer state, renamed to `showCamera`/`showFileImporter` if they aren't already state-driven.

- [ ] **Step 7: `gateStrip`** — the web trial-banner idiom replaces the floating orange line (copy string unchanged — tests may match it):

```swift
private var gateStrip: some View {
    HStack(spacing: 8) {
        Image(systemName: "lock.fill").font(.footnote)
        Text("Subscribe to add new items.").font(.footnote.weight(.medium))
        Spacer(minLength: 0)
    }
    .foregroundStyle(StashTheme.gateText)
    .padding(.horizontal, 14).padding(.vertical, 10)
    .background(RoundedRectangle(cornerRadius: StashTheme.Radius.control, style: .continuous).fill(StashTheme.gateBg))
    .overlay(RoundedRectangle(cornerRadius: StashTheme.Radius.control, style: .continuous).strokeBorder(StashTheme.gateBorder))
    .accessibilityIdentifier("capture.subscriptionGate")
}
```

- [ ] **Step 8: URL chip + attachment chips to web spec.** `urlChip` (`:193-205`): white bg, `RoundedRectangle(cornerRadius: StashTheme.Radius.chip)` with 1pt `StashTheme.border` stroke, `padding(.horizontal, 12).padding(.vertical, 8)`, link icon + hostname `.font(.system(size: 14, weight: .medium)).foregroundStyle(StashTheme.ink)` + X dismiss (24pt target), id `capture.urlchip` unchanged. `CaptureAttachmentsRow.chip(for:)`: 64×64 → keep size, radius 8, add 1pt border `StashTheme.border` and white bg behind file-type chips; X badge: 22pt circle, white bg, 1pt border, `xmark` 10pt semibold ink — replaces the current system-fill look; id `capture.attachment.remove` unchanged. Toast (`:450-469`): white card, radius 12, `.stashCardShadow()`, footnote ink text (id `capture.toast`).

- [ ] **Step 9: UI test adaptation.** `grep -n "photosPicker\|cameraButton\|fileButton\|toggle.public" ios/StashUITests/StashUITests.swift` — every hit that taps one of the relocated ids gains a preceding `app.buttons["capture.attach"].tap()` (menu opens, item becomes hittable). Add a helper if ≥2 sites need it:

```swift
private func openAttachMenu(_ app: XCUIApplication) {
    app.buttons["capture.attach"].tap()
}
```

Menu items surface to XCUITest as buttons (the Toggle as a switch/button) carrying the identifiers set in Step 6.

- [ ] **Step 10: Build, run, screenshot, full UI suite.** Same commands as Task 1 Steps 4-5 (screenshot to `/tmp/plan6-t3-add.png`). Expected: BUILD SUCCEEDED zero warnings; screenshot shows gradient backdrop, wordmark header, white composer card with all controls on-screen; suite at 12/15 + 3 adjudicated. Read the screenshot; verify the focus ring by launching, tapping the editor, screenshotting again (`/tmp/plan6-t3-add-focused.png` — violet ring visible).

- [ ] **Step 11: Commit.**

```bash
git add ios/Stash/Capture/CaptureComposerView.swift ios/Stash/Capture/ComposerCard.swift \
  ios/Stash/Capture/CaptureAttachmentsRow.swift ios/Stash/Assets.xcassets/StashWordmark.imageset \
  ios/StashUITests/StashUITests.swift
git commit -m "feat(ios): rebuild Add tab as branded composer card on gradient backdrop

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Library (View tab) — cards and toolbar on the wash

**Files:**
- Modify: `ios/Stash/Library/LibraryView.swift` (`:34-64`, `:93-106`)
- Modify: `ios/Stash/Library/ItemCardView.swift` (`:29-49`)
- Modify: `ios/Stash/Library/TypeChipRow.swift` (`:9-31`)
- Modify: `ios/Stash/Library/LibraryStatePane.swift` (empty-state copy/serif)
- Modify: `ios/Stash/Library/CardChips.swift` (MetaChip/annotation polish)

**Interfaces:** Consumes `StashTheme`, `StashBackground`, `.stashCardShadow()` (Task 2). Produces nothing new.

- [ ] **Step 1: Backdrop.** In `LibraryView.body`, wrap the existing `VStack(spacing: 0)` in `ZStack { StashBackground() … }` and add `.scrollContentBackground(.hidden)` on the grid's ScrollView so the wash shows through. Keep `.searchable` — set `.toolbarBackground(.visible, for: .navigationBar)` only if the search field proves illegible over the gradient (run it and look).

- [ ] **Step 2: Card shell to web spec.** `ItemCardView.swift:41-45`: replace `.background(Color(.secondarySystemGroupedBackground))` + `.clipShape(RoundedRectangle(cornerRadius: 14))` with:

```swift
.background(Color.white, in: RoundedRectangle(cornerRadius: StashTheme.Radius.card, style: .continuous))
.clipShape(RoundedRectangle(cornerRadius: StashTheme.Radius.card, style: .continuous))
.stashCardShadow()
```

(`compositingGroup` before the shadows if hero images bleed them.) Grid spacing at `LibraryView.swift:15,95-103`: columns spacing 12 → 14, `.padding(12)` → `.padding(14)` — closer to web's 16 while keeping 2-col phone density.

- [ ] **Step 3: Card typography to contract.** In `ItemCardView.swift:34` the title is `.font(.headline).fontDesign(.serif)` — **headline is semibold; the brand serif is 400 only.** Replace with `.font(StashTheme.editorialTitle(17))`. Kicker (domain line): `.font(StashTheme.kicker)` + `.textCase(.uppercase)` + `.tracking(0.5)` + `.foregroundStyle(StashTheme.inkMuted)`. Description: `.font(.system(size: 14)).foregroundStyle(StashTheme.inkMuted)` 3-line clamp. Date footer: `.font(.system(size: 12)).foregroundStyle(StashTheme.inkMuted)`. Annotation (in `CardChips.swift` `CardAnnotation`): bar `StashTheme.violet300` 2pt wide, text `.font(.system(size: 13.5))` at `StashTheme.ink.opacity(0.75)`, 2-line clamp. MetaChip: capsule `Color.black.opacity(0.04)` bg, 11pt medium `StashTheme.ink.opacity(0.6)` (mono variant 10pt `.monospaced()`).

- [ ] **Step 4: Type chips + state panes.** `TypeChipRow`: capsule pills — selected `StashTheme.violet50` bg / `StashTheme.violet300` 1pt border / violet-700-ish text (`Color(hex: 0x6D28D9)`); unselected white@40% bg / `Color.black.opacity(0.1)` border / `StashTheme.inkMuted` text; 13pt. `LibraryStatePane` empty state: title `StashTheme.editorialTitle(24)` **"Start building your knowledge base"**, body 14pt `StashTheme.inkMuted` **"Capture ideas, notes, and insights to make them searchable and discoverable."**; no-results variant `editorialTitle(20)` **"No results found"** / **"Try adjusting your search terms or filters."** (exact web copy).

- [ ] **Step 5: Build + screenshot + suite** (as Task 1 Steps 4-5; screenshot `/tmp/plan6-t4-library.png` after tapping the View tab — drive via the existing library smoke or add the tap in the screenshot sweep of Task 7). Expected: white cards with soft violet shadow on the wash, serif-regular titles, 12/15 + 3 adjudicated.

- [ ] **Step 6: Commit.**

```bash
git add ios/Stash/Library
git commit -m "feat(ios): library restyle — web card shell, serif-400 titles, wash backdrop

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Ask + Settings + app chrome

**Files:**
- Modify: `ios/Stash/Ask/AskView.swift` (`:52-80`, `:121-128`, `:177-188`), `ios/Stash/Ask/ChatBubble.swift` (`:81`, `:106`, `:151`), `ios/Stash/Ask/ChatComposerBar.swift` (`:11-48`)
- Modify: `ios/Stash/Settings/SettingsView.swift` (light touch)
- Create: `ios/scripts/make-appicon.swift` + generated `ios/Stash/Assets.xcassets/AppIcon.appiconset/appicon-1024.png`

**Interfaces:** Consumes `StashTheme`, `StashBackground` (Task 2).

- [ ] **Step 1: Ask thread.** `AskView`: wrap thread + composer in `ZStack { StashBackground() … }` with `.scrollContentBackground(.hidden)`; drop the hard `Divider()` for `.background(.white.opacity(0.85))` on the composer area. User bubble (`ChatBubble.swift:81`): `Color.accentColor` → `StashTheme.ink900` (web's user bubble is gray-900, radius 18 stays, white text). Assistant bubble (`:106`): `StashTheme.muted.opacity(0.7)` bg, ink text. Source chips (`:151`): white bg, `StashTheme.border` 1pt, radius 12 (web's saved-item card idiom). Empty state (`:121-128`): title in `StashTheme.editorialTitle(20)`.
- [ ] **Step 2: Ask composer bar** (`ChatComposerBar.swift`): input field `RoundedRectangle(cornerRadius: 12)` fill `Color(hex: 0xF9FAFB)`, 1pt `StashTheme.border` (violet300 when focused); send button 40×40 `RoundedRectangle(cornerRadius: 12)` `StashTheme.violet` bg, white icon, `StashTheme.violetPressed` on press; mic 40×40 ghost. Ids `ask.input`/`ask.mic`/`ask.send` unchanged. Gate/error banner (`AskView.swift:177-188`): reuse the Task 3 gate-strip idiom (amber for gate, `StashTheme.destructive`-tinted variant for errors) — keep whatever identifier it carries today.
- [ ] **Step 3: Settings.** Keep `.insetGrouped` (native is right per ETHOS). Only: sign-out row `.foregroundStyle(StashTheme.destructive)`, version footer joined by a small `Image("StashWordmark")` at height 14 tinted `StashTheme.inkMuted`.
- [ ] **Step 4: Placeholder app icon** (real art is Will's call — §Open questions; declared 1024 slot is currently an EMPTY file reference, which is worse than a placeholder). Write `ios/scripts/make-appicon.swift`:

```swift
import AppKit
let size = CGSize(width: 1024, height: 1024)
let img = NSImage(size: size)
img.lockFocus()
let g = NSGradient(colors: [NSColor(srgbRed: 0x8B/255, green: 0x5C/255, blue: 0xF6/255, alpha: 1),
                            NSColor(srgbRed: 0x7C/255, green: 0x3A/255, blue: 0xED/255, alpha: 1)])!
g.draw(in: NSRect(origin: .zero, size: size), angle: -90)
let serif = NSFont.systemFont(ofSize: 640, weight: .medium).fontDescriptor.withDesign(.serif)!
let font = NSFont(descriptor: serif, size: 640)!
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
let s = NSAttributedString(string: "S", attributes: attrs)
let b = s.size()
s.draw(at: NSPoint(x: (1024 - b.width) / 2, y: (1024 - b.height) / 2 - 40))
img.unlockFocus()
let tiff = img.tiffRepresentation!, rep = NSBitmapImageRep(data: tiff)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Stash/Assets.xcassets/AppIcon.appiconset/appicon-1024.png"))
```

Run `cd ios && swift scripts/make-appicon.swift`, then set `"filename" : "appicon-1024.png"` on the existing 1024 entry in `AppIcon.appiconset/Contents.json`.

- [ ] **Step 5: Build + screenshots** (Ask tab `/tmp/plan6-t5-ask.png`, Settings `/tmp/plan6-t5-settings.png`, home screen for the icon `/tmp/plan6-t5-icon.png` via `xcrun simctl io … screenshot` after pressing home: `xcrun simctl spawn 28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB launchctl … ` is unreliable — instead just terminate the app: `xcrun simctl terminate … it.gostash.stash; sleep 1; xcrun simctl io … screenshot`). Suite: 12/15 + 3 adjudicated.
- [ ] **Step 6: Commit.**

```bash
git add ios/Stash/Ask ios/Stash/Settings/SettingsView.swift ios/scripts/make-appicon.swift \
  ios/Stash/Assets.xcassets/AppIcon.appiconset
git commit -m "feat(ios): ask/settings restyle + placeholder app icon

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Share extension — same brand, one glance

**Files:**
- Modify: `ios/StashShareExtension/ShareComposeView.swift`

**Interfaces:** Consumes `StashTheme` + `ComposerCard` (add `Stash/Capture/ComposerCard.swift` to the extension's `sources:` in `project.yml` exactly like the Theme files in Task 2 Step 6 — do that here if Task 2 didn't).

- [ ] **Step 1:** Root `.tint(StashTheme.violet)` (the extension may not compile the app's asset catalog — code tint is the reliable path; verify whether `Assets.xcassets` is in the extension target's sources before assuming). Compose card container → `ComposerCard(isActive: true)`. Save button: violet capsule, white text, `StashTheme.violetPressed` pressed. Gate line + "Sign in…" line: Task 3 gate-strip idiom (amber). "Saved to Stash"/"Saved — will sync" outcome line: 15pt medium ink with a `checkmark.circle.fill` in `StashTheme.violet`. **No layout/flow changes** — plan-5's save-and-dismiss timing, staging, and Outbox behavior are contract.
- [ ] **Step 2:** Build both targets warning-free; drive one live URL share from Safari in the sim (the plan-5 smoke `testShareExtensionURLSmoke` covers this — run it; expect its condition-aware pass) + screenshot `/tmp/plan6-t6-share.png`.
- [ ] **Step 3: Commit.**

```bash
git add ios/StashShareExtension/ShareComposeView.swift ios/project.yml
git commit -m "feat(ios): share extension brand pass — violet tint, gate strip, composer card

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Wrap — verification sweep, docs, ledger

**Files:**
- Modify: `ios/StashUITests/StashUITests.swift` (screenshot sweep test)
- Modify: `docs/ui-changes.md` (new entry, top)
- Modify: `docs/superpowers/specs/2026-08-10-stash-ios-app-design.md` (phase-list amendment)

- [ ] **Step 1: Screenshot sweep test** — one gate-agnostic UI test that visits all four tabs and attaches screenshots (a durable visual record per plan; keeps future visual regressions reviewable):

```swift
func testVisualSweepScreenshots() throws {
    let app = launchSignedInApp()   // the suite's existing launch helper — reuse its name
    for (tab, name) in [("Add", "add"), ("Ask", "ask"), ("View", "library"), ("Settings", "settings")] {
        app.tabBars.buttons[tab].tap()
        sleep(1)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "plan6-\(name)"; shot.lifetime = .keepAlways
        add(shot)
    }
}
```

(Adapt the launch helper name to the suite's actual convention — read the file first; no gate-dependent asserts, the tap targets are the tab bar itself.)

- [ ] **Step 2: Full verification battery.**

```bash
cd ios/StashKit && rm -rf .build && swift test 2>&1 | tail -2          # expect 281/281
cd .. && xcodegen generate && rm -rf DerivedData && \
xcodebuild -project Stash.xcodeproj -scheme Stash \
  -destination 'platform=iOS Simulator,id=28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB' \
  -derivedDataPath DerivedData build 2>&1 | grep -cE ": warning:"       # expect 0
xcodebuild … test 2>&1 | tail -20                                       # expect 13/16 + 3 adjudicated (15 + sweep)
cd ../.. && npm test 2>&1 | tail -3                                     # web untouched, expect all pass
```

Extract and READ the sweep's four attachment PNGs (`DerivedData/Logs/Test/*.xcresult` via `xcrun xcresulttool export`), comparing against the §Design contract: wash visible, violet accent, serif-400 titles, no clipping at either edge on any tab.

- [ ] **Step 3: `docs/ui-changes.md` entry** (newest-first, contracts-first — draft, adjust to what actually shipped):

```markdown
## 2026-08-24 · iOS visual overhaul: web design language lands on iOS (plan 6)

- **Fixed:** the Add screen rendered wider than the device (fixed-width control
  row + unconstrained VStack) — all content now fits; this was a P0 usability bug.
- **iOS now shares the web design language** via `ios/Stash/Theme/Theme.swift`,
  a one-file port of the web tokens (violet `#8B5CF6` accent, ink `#282C34`,
  card shadow `rgba(160,120,200,.12)`, radii 6/8/12/16, spring 320/28/0.7 ≈
  `.spring(response:0.29,dampingFraction:0.78)`). Change web tokens → mirror there.
- **Backdrop:** iOS uses the STATIC gradient from `mockups/main-screen-redesign.html`
  (not the animated 15s web gradient) — a deliberate platform divergence.
- **Serif titles are weight-400** (web ships one PPEditorialNew weight). iOS v1
  renders New York (`design: .serif`) behind `StashTheme.editorialTitle()` —
  PPEditorialNew bundling awaits a license decision; the swap is one line.
- **Composer controls:** photo/camera/file pickers + public toggle collapsed into
  a web-style `+` attach menu; mic, pin, and a circular violet-when-hot send stay
  visible. Accessibility ids preserved (menu items carry them).
- **Gate strip:** the subscription gate renders as the web SubscriptionBanner's
  amber strip idiom (same copy), no longer a floating orange line.
- **Light-only, locked** at root — matching web reality (dark tokens are dead code).
- Divergences (deliberate, per ETHOS): 2-col grid (web mobile is 1-col), static
  gradient, SF instead of Inter, New York serif pending font licensing.
```

- [ ] **Step 4: Spec amendment.** In `docs/superpowers/specs/2026-08-10-stash-ios-app-design.md` Phases: mark Phase 7 → `✅ *(Completed 2026-08-24 as plan 6 — re-sequenced ahead of widgets per Will; the Add screen was unusable. Plan: docs/superpowers/plans/2026-08-24-ios-plan-6-visual-overhaul.md.)*` and annotate Phase 6 (widgets) → `*(now plan 7)*`.

- [ ] **Step 5: Ledger.** Carry unchanged from plan-5 (still open, still out of scope): `teamIDProbe` comment, gate-cache `sleep(3)` poll hardening, `urlField` 5s wait, `anyElement` style inconsistency, `drainOutbox upload: nil` simplification, sweep-vs-live-card >60s edge, ProviderLoader generic-file branch, note tie-break product sign-off, Stripe decision. State them in the wrap report; touch none.

- [ ] **Step 6: Commit docs.**

```bash
git add docs/ui-changes.md docs/superpowers/specs/2026-08-10-stash-ios-app-design.md \
  ios/StashUITests/StashUITests.swift
git commit -m "docs(ios): plan-6 wrap — ui-changes entry, spec phase amendment, visual sweep test

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Decisions taken (defaults — veto any on review)

1. **Serif = New York (`design: .serif`) v1**, weight 400 everywhere a title renders, behind `StashTheme.editorialTitle()` so licensed PPEditorialNew is a one-line swap later. Rationale: PP fonts need a separate app-embedding license (the repo's Tobias/Mori are even TRIAL builds); New York is the platform's editorial serif and free of risk.
2. **Static gradient** (mockup spec), not the web's 15s animated pan — calmer on a phone, cheaper on battery, and the mockup file is the design-intent source.
3. **Pickers + public toggle move into a `+` attach menu** (web's own affordance); **mic stays visible** — voice capture is an iOS-first fast path and burying it adds friction (ETHOS).
4. **2-column grid stays** (web at phone width is 1-col) — denser scanning on a small screen; serif drops 20→17pt to fit. Flagged as a deliberate divergence in ui-changes.md.
5. **Gate keeps its copy, gains the web amber-strip styling** — the gate *logic* (client-side, fail-open, lapsed-trial test account) is untouched; the Stripe comp decision stays open.
6. **Light mode locked** — mirrors web reality; tokens are dark-ready in one file.
7. **Placeholder app icon** (violet gradient + white serif S) replaces the *empty* icon slot; real brand art is explicitly still owed.

## Open questions for Will (none block Tasks 1-2)

1. **PPEditorialNew on iOS** — do you hold (or want to buy) an app-embedding license? If yes, plan 7 adds the `.woff2 → .otf` conversion + `UIAppFonts` registration and flips `editorialTitle()`.
2. **App icon art** — placeholder S ships this plan; want real art queued (and from where)?
3. **Wordmark in the Add header** — plan renders the real SVG wordmark + date like the web header. If you'd rather keep iOS chrome minimal (no wordmark), say so and Task 3 Step 5 drops to a plain date line.

## Out of scope (unchanged from spec/plan-5)

Widgets + App Intents (plan 7) · link-metadata client hydration (composer chips show hostname only, no fake enrichment) · dark mode · in-app payments/Stripe · `ProviderLoader` generic-file branch · macOS/iPad · masonry or 3-col layouts.

---

**Status (2026-09-03): superseded — not executed as written.** What actually
shipped was commit `c4e9a5b` (`StashDesign.swift` restyled onto the
*pre-`DESIGN.md`* palette — web design language adopted app-wide, chat
sessions, app icon, share-card redesign — see `ios-app-plan.md` memory for
the full commit summary). The remaining scope (tokens re-derived to match the
now-current `DESIGN.md` verbatim, login/detail/conversations parity, real
brand icon) was consolidated into
`docs/superpowers/plans/2026-09-03-ios-plan-7-design-consolidation.md`, which
executed and shipped it.
