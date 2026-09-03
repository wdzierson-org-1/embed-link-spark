# Stash iOS Plan 7: Design Consolidation + Web Parity Round 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the iOS app onto the current `DESIGN.md` system (tokens, typography, brand) and close the five gaps Will flagged from screenshots — app icon, login, Ask-tab conversations access, conversations list, item detail sheet — then ship TestFlight build 2.

**Architecture:** `DESIGN.md` is the single source of truth; `ios/Stash/Design/StashDesign.swift` is re-derived from it (ink/muted/faint/violet-600 tokens, Neue Montreal typography scale with SF fallback) and every screen consumes tokens rather than literals. Markdown parsing for AI text lives in StashKit (pure, tested); rendering lives in the app. Screens are rebuilt to the web reference components named per task, not pixel-cloned (ethos: behavior + contracts parity, platform-native affordances allowed).

**Tech Stack:** SwiftUI (iOS 17), StashKit, XcodeGen, fontTools (woff2→ttf), XCUITest, existing release pipeline (`ios/scripts/release.sh`, session auth).

**Spec:** `DESIGN.md` (tokens, typography table, detail-panel spec §"Components", brand rule §"Brand elements are flat", iOS section) + Will's 2026-09-03 screenshot brief (recorded verbatim in Global Constraints) + the survey of the other thread's shipped work (its plan `docs/superpowers/plans/2026-08-24-ios-plan-6-visual-overhaul.md` was NOT executed as written; what shipped is commit `c4e9a5b` — `StashDesign.swift` on the pre-DESIGN.md palette).

## Global Constraints

- **Source of truth:** `DESIGN.md`. Token values verbatim: `ink #22262f`, `muted #646b76`, `faint #959ba6`, hairline `rgba(0,0,0,.07)`, `violet-600 #6d5bd0` (accent — NOT `#8B5CF6`), `violet-300 #b6a8ef`, destructive `#c93a3a`; radii 16 (cards) / 20 (sheets); card shadow `0 1px 2px rgba(20,22,30,.05), 0 8px 24px rgba(30,33,44,.08)`. Typography table in `DESIGN.md` §Typography (panel title 500 · 28/1.2 · −0.02em; body 400 · 13.5–14.5; micro-label 600 · 11 caps · +0.11em `faint`; kicker 600 · 11 caps · +0.10em; date 400 · 12 `faint`). When `StashDesign.swift` disagrees with `DESIGN.md`, `DESIGN.md` wins and both are fixed in the same change.
- **Brand decision (Will, 2026-09-03):** the iOS app icon is the flat stitched second-S in ink `#22262f` on white — same as `public/favicon.svg`. This REVOKES `DESIGN.md`'s "iOS app icon (standing exception)" clause; Task 1 edits `DESIGN.md` in the same commit. No gradients in any icon or mark. The splash/page-wash gradient stays.
- **Fonts:** `DESIGN.md` mandates bundling PP Neue Montreal in BOTH the app and share-extension targets (appex can't read the host bundle), SF Pro fallback only on load failure. Web ships woff2 only; iOS needs TTF — convert losslessly with fontTools (`pip3 install fonttools brotli` if absent). Weights: Book(400)/BookItalic/Medium(500)/Semibold(600). PP Editorial New is NOT introduced on iOS this plan (card titles out of scope). PP Mori is retired — never add it.
- **Will's screenshot brief (verbatim intent):** "keep in-line with web interaction + look and feel… noticeable differences: the login screen, the object detail sheet, recent conversations, the ability to access recent conversations from the 'ask' tab needs to be added, and the icon treatment… update the mobile app icon and visual assets to match the web favicon (black + white S from the Stash logomark)."
- **Tags are retired** everywhere (`DESIGN.md` §Components; web has no tag UI). Remove `ItemTagsSection` from the detail sheet; do not add tag UI anywhere.
- **No emoji in product UI** (`DESIGN.md` rule 4). Iconography: SF Symbols on iOS as the Lucide analogue.
- Data lanes/ethos unchanged (`CLAUDE.md`, `docs/ETHOS.md`). Every behavior change gets a `docs/ui-changes.md` entry (iOS entries resume — none since 2026-08-29).
- Worktree `.claude/worktrees/ios-plan-7` (branch `worktree-ios-plan-7`, base `9c1f8de`): commit there, NEVER push; **re-fetch and audit `origin/main` for foreign commits before the final merge** (other sessions ship to main). Sim UDID `28F9E3CD-90E2-4D17-AFDE-D0C37316BFBB`, `derivedDataPath=DerivedData`, `xcodegen generate` after project.yml edits; StashKit floor **293**; UI suite 15 with the standing 3 gate-blocked adjudications; builds warning-free.
- UI-test a11y identifiers are contracts: when a rebuilt screen changes structure, keep existing identifiers (`settings.subscription.status`, `ask.history`, `ask.newChat`, `ask.gateError`, detail/edit identifiers used by `testEditSmoke`) or update the test in the same task — never leave a smoke silently broken.
- Deploy at wrap: `CURRENT_PROJECT_VERSION` → 2, `./ios/scripts/release.sh all` + `upload` (session auth; Xcode account `willdzierson@gmail.com` must be signed in), attach build 2 to the "Internal" group via `ios/scripts/asc-api.sh`.

## File Structure

- `ios/Stash/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (+ share-extension twin) — REPLACED with flat ink-S-on-white.
- `ios/Stash/Design/StashDesign.swift` — re-derived tokens + typography (`StashType`), font registration.
- `ios/Stash/Design/Fonts/PPNeueMontreal-{Book,BookItalic,Medium,Semibold}.ttf` — NEW (converted); referenced by both targets via `project.yml` (`UIAppFonts` in both Info.plists).
- `ios/Stash/Auth/SignInView.swift` — rebuilt (card, wordmark, pill tabs, sign-up).
- `ios/Stash/Ask/AskView.swift`, `ChatComposerBar.swift`, `ConversationsListView.swift` — header/footer parity, violet dot.
- `ios/StashKit/Sources/StashKit/Markdown/MarkdownBlocks.swift` (+ tests) — NEW pure parser; `ios/Stash/Detail/MarkdownBlocksView.swift` — NEW renderer.
- `ios/Stash/Detail/ItemDetailView.swift`, `ItemDetailContent.swift` (+ new `DetailEyebrow.swift`, `DetailURLBar.swift`, `DetailsDrawer.swift`, `SharingSection.swift`) — rebuilt per `DESIGN.md` detail-panel spec.
- `ios/StashUITests/StashUITests.swift` — identifier/flow updates.
- `DESIGN.md` (icon clause), `docs/ui-changes.md` (new iOS entry), `docs/superpowers/plans/2026-08-24-ios-plan-6-visual-overhaul.md` (superseded note), this plan (outcome).

---

### Task 1: App icon — flat ink second-S on white (both targets) + DESIGN.md brand clause

**Files:**
- Modify (binary replace): `ios/Stash/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, `ios/StashShareExtension/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
- Modify: `DESIGN.md:130-133` (remove the iOS-icon standing exception)

**Interfaces:**
- Produces: the icon Apple renders in the share sheet, springboard, and TestFlight matches `public/favicon.svg` (ink `#22262f` S, white ground). Task 8's build 2 ships it.

- [ ] **Step 1: Render the master from the favicon source.** Write `/tmp/icon.html`: `<body style="margin:0;background:#fff">` containing `public/favicon.svg`'s contents inline, sized 1024×1024, BUT replace the SVG's own `rx="20"` rounded white rect with a full-bleed white background (Apple applies the corner mask; a pre-rounded rect shows white corners as a visible inner square). Keep the glyph transform exactly (`translate(24.6,18) scale(0.3657) translate(-587.1,-424.9)` inside the 100-unit viewBox → the S sits with ~25% left/18% top margin, matching the favicon's optical placement). Screenshot: `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --screenshot=/tmp/AppIcon-1024.png --window-size=1024,1024 --force-device-scale-factor=1 file:///tmp/icon.html`.
- [ ] **Step 2: Verify bytes.** `sips -g pixelWidth -g pixelHeight -g hasAlpha /tmp/AppIcon-1024.png` → 1024/1024/no. View the PNG: ink S centered on white, no gradient, no clipped edges.
- [ ] **Step 3: Replace both PNGs** (keep the filename `AppIcon-1024.png` so both `Contents.json` stay untouched); `md5` identical across the two catalogs.
- [ ] **Step 4: DESIGN.md.** Edit the brand paragraph to: "Brand elements are flat. No gradients in buttons, icons, favicons, or marks — flat iconography on flat color (the favicon and the iOS app icon are the stitched second-S in ink `#22262f` on white, all five glyph paths). The splash gradient lives only in page washes." Add a dated line: "*2026-09-03: iOS app icon exception revoked (Will) — icon now matches the favicon.*"
- [ ] **Step 5: Verify on device sim.** `xcodegen generate` (no-op expected), build, `xcrun simctl uninstall` + install, springboard screenshot showing the flat S icon; `swift test` 293 (untouched).
- [ ] **Step 6: Commit.** `git add ios/Stash/Assets.xcassets ios/StashShareExtension/Assets.xcassets DESIGN.md && git commit -m "feat(ios): app icon is the flat ink second-S on white (matches favicon); DESIGN.md exception revoked"`

---

### Task 2: StashDesign re-derived from DESIGN.md — tokens, typography, bundled Neue Montreal

**Files:**
- Modify: `ios/Stash/Design/StashDesign.swift` (rewrite token surface; keep existing view helpers' names so call sites compile: `CircleIcon`, `CircleSubmitIcon`, `AnimatedGradient`, `StashHeader` — restyle them to tokens)
- Create: `ios/Stash/Design/Fonts/PPNeueMontreal-Book.ttf`, `-BookItalic.ttf`, `-Medium.ttf`, `-Semibold.ttf`; `ios/Stash/Design/StashType.swift`
- Modify: `ios/project.yml` (both targets: `UIAppFonts` info.properties listing the four files; extension target sources `+ path: Stash/Design/Fonts` and `+ path: Stash/Design/StashType.swift` — same shared-glue-file pattern already used for `StashDesign.swift`)
- Modify: every call site using old literals (grep `Color(hex:`, `#8B5CF6`, `.purple`, `.blue`, `.accentColor` under `ios/Stash` and `ios/StashShareExtension`) → tokens.

**Interfaces:**
- Produces (exact names later tasks use):

```swift
enum StashColor {            // DESIGN.md §Color
    static let ink = Color(hex: 0x22262F)
    static let muted = Color(hex: 0x646B76)
    static let faint = Color(hex: 0x959BA6)
    static let hairline = Color.black.opacity(0.07)
    static let violet600 = Color(hex: 0x6D5BD0)   // accent
    static let violet300 = Color(hex: 0xB6A8EF)
    static let destructive = Color(hex: 0xC93A3A)
    static let paper = Color.white
    static let wash = Color(hex: 0x14161E).opacity(0.05)   // pill-tab track / quiet fills
}
enum StashRadius { static let card: CGFloat = 16; static let sheet: CGFloat = 20; static let input: CGFloat = 12 }
struct StashShadow { static func card() -> some ViewModifier }  // 0 1 2 rgba(20,22,30,.05) + 0 8 24 rgba(30,33,44,.08)
enum StashType {              // DESIGN.md §Typography — Neue Montreal, SF fallback
    static func panelTitle() -> Font   // 500 · 28 · tracking −0.02em
    static func display() -> Font      // 600 · 32
    static func body() -> Font         // 400 · 14
    static func bodyItalic() -> Font   // 400i · 14
    static func microLabel() -> Font   // 600 · 11 (caller uppercases + tracking +0.11em)
    static func kicker() -> Font       // 600 · 11 caps · +0.10em
    static func chip() -> Font         // 500 · 11
    static func meta() -> Font         // 400 · 12
    static func mono(_ size: CGFloat = 11) -> Font
    static var isNeueMontrealAvailable: Bool  // UIFont(name: "PPNeueMontreal-Medium") != nil
}
extension View { func stashTracking(_ em: CGFloat, size: CGFloat) -> some View }  // kerning = em * size
```

- [ ] **Step 1: Convert fonts.** `python3 -c "import fontTools"` (install `fonttools brotli` via pip3 if missing — disclose). For each weight: `python3 -c "from fontTools.ttLib import TTFont; f=TTFont('src/assets/fonts/PPNeueMontreal-Book.woff2'); f.flavor=None; f.save('ios/Stash/Design/Fonts/PPNeueMontreal-Book.ttf')"`. Record each TTF's PostScript name: `python3 -c "from fontTools.ttLib import TTFont; print(TTFont('…').get('name').getDebugName(6))"` — these are the names `Font.custom(_:size:)` needs (expected `PPNeueMontreal-Book` etc.; use what the file says).
- [ ] **Step 2: Failing UI-level assertion → smoke.** Add to `ios/StashUITests/StashUITests.swift` `testDesignSystemFontsLoad`: launch, assert a debug-only label `design.fontStatus` (rendered in Settings footer in DEBUG builds) reads `"font:neue-montreal"` (not `"font:sf-fallback"`). Run → FAIL (label absent).
- [ ] **Step 3: Implement** `StashType` with `Font.custom(psName, size:)` guarded by `isNeueMontrealAvailable` else `.system(size:weight:)`; `UIAppFonts` in both Info.plists via project.yml; the DEBUG label in `SettingsView`. Restyle `CircleIcon`/`CircleSubmitIcon` (hairline border, ink glyph, violet600 submit fill), `StashHeader` (wordmark ink), `AnimatedGradient` (unchanged palette — page wash is sanctioned).
- [ ] **Step 4: Migrate call sites.** `grep -rn "Color(hex\|8B5CF6\|\.purple\|\.blue\|accentColor\|Color.gray\|\.secondary" ios/Stash ios/StashShareExtension --include=*.swift` — replace each with the token that matches DESIGN.md's role (muted text → `.muted`, tertiary → `.faint`, accent → `.violet600`, destructive → `.destructive`). Keep a table of replacements in the report.
- [ ] **Step 5: GREEN.** `xcodegen generate`; build app + extension warning-free; `testDesignSystemFontsLoad` passes on the sim (proves the appex/app font bundling works — also confirm in the SHARE EXTENSION by reading `UIFont.familyNames` in a DEBUG print, since the appex has its own bundle); `swift test` 293; `testSettingsSmoke` ×1.
- [ ] **Step 6: Commit.** `git add ios/Stash/Design ios/project.yml ios/Stash/Info.plist ios/StashShareExtension/Info.plist ios/StashUITests/StashUITests.swift <migrated files> && git commit -m "feat(ios): StashDesign re-derived from DESIGN.md — ink/violet tokens, Neue Montreal bundled in app + appex, SF fallback"`

---

### Task 3: Sign-in screen parity (card, wordmark, pill tabs, sign-up)

**Files:**
- Rewrite: `ios/Stash/Auth/SignInView.swift`
- Modify: `ios/Stash/Auth/SessionStore.swift` (add `signUp(email:password:username:phone:)` mirroring web)
- Test: `ios/StashUITests/StashUITests.swift` (sign-in flow identifiers; `testSignUpTabRenders`)

**Interfaces:**
- Consumes: `StashColor`, `StashType`, `StashRadius`, `StashShadow`, `AnimatedGradient`, `StashWordmark` imageset (exists).
- Web reference: `src/pages/Auth.tsx:16-19` (quietInput/primaryCta styles), `:190-247` (card layout), the sign-up branch (username → `user_profiles`, optional phone → `send-welcome-message`) — read it and mirror the calls through supabase-swift exactly (same table writes/edge calls; NO new server behavior).
- Produces: identifiers `auth.tab.signIn`, `auth.tab.signUp`, `auth.email`, `auth.password`, `auth.username`, `auth.phone`, `auth.submit`, `auth.error`.

- [ ] **Step 1: Failing smoke** `testSignUpTabRenders`: from signed-out state (`--uitest-reset-auth`), tap `auth.tab.signUp`, assert `auth.username` exists; tap `auth.tab.signIn`, assert it's gone. RED.
- [ ] **Step 2: Build the screen** to the web card: `AnimatedGradient` page wash at 30% opacity over `paper`; centered card (max width 400, `StashRadius.sheet`, `StashShadow.card`, 32pt padding); `StashWordmark` (ink, height 28) → "Sign in or create your account." (`StashType.body`, `.muted`) → pill tabs (track `StashColor.wash`, radius 999, selected segment `paper` with hairline + subtle shadow, `StashType.body` 500) → fields (`StashRadius.input`, hairline border, fill `violet300.opacity(0.12)` — the lavender tint in the screenshot — focus ring `violet300` 2pt) → CTA (`violet600` fill, white text, radius 12, height 44). Sign-up tab adds username (with `@` prefix + helper "Your username becomes your @handle and your public feed address.") and optional phone (+ helper copy from web). Errors in `destructive`, `auth.error`.
- [ ] **Step 3: SessionStore.signUp** mirrors `Auth.tsx` sign-up: `auth.signUp(email:password:)` → insert `user_profiles` (username/display_name) → optional `send-welcome-message` invoke when phone present. Then sign in state as the web does.
- [ ] **Step 4: GREEN + real sign-in check**: `testSignUpTabRenders` + `testSettingsSmoke` (exercises sign-in) pass. Screenshot the sign-in card next to the web screenshot for the report.
- [ ] **Step 5: Commit.** `git commit -m "feat(ios): sign-in card matches web — wordmark, pill Sign in/Sign up tabs, quiet inputs, violet CTA, sign-up flow"` (exact paths).

---

### Task 4: Ask tab + Conversations parity

**Files:**
- Modify: `ios/Stash/Ask/AskView.swift` (header → "Ask Stash / Answers from your N items"; footer links under the composer: "Start new chat · Earlier conversations"; retire the two header circle icons), `ios/Stash/Ask/ChatComposerBar.swift` (violet600 send, hairline mic, placeholder "Ask your stash…"), `ios/Stash/Ask/ConversationsListView.swift` (violet-300 dot per row; card tokens; "Conversations" panel title; search pill styling).
- Test: `StashUITests.swift` — `testAskSmoke` keeps working via the **same identifiers** `ask.history` (now the footer link) and `ask.newChat`; add `testAskFooterLinksRenderAndOpenConversations`.

**Interfaces:**
- Web reference: `src/components/ChatMole.tsx:655-673` (footer links), header block (title + "Answers from your N items" — item count from `ItemStore.totalCount` or a lightweight `select count`), `src/components/ConversationsView.tsx:82-168` (dot, rows, search).
- Produces: identifiers unchanged (`ask.history`, `ask.newChat`) + `ask.itemCount`.

- [ ] **Step 1: Failing smoke** `testAskFooterLinksRenderAndOpenConversations`: on the Ask tab, assert `ask.history` is a footer *link* with label "Earlier conversations" below the composer; tap → Conversations screen title "Conversations" exists → back. RED (identifier still lives in the header as an icon).
- [ ] **Step 2: Implement.** Header: `Ask Stash` (`StashType.panelTitle` scaled 22) + subtitle (`.muted`, live count). Welcome bubble copy: web's "Ask anything about what you've saved — answers cite the cards they came from." (keep the iOS capture hint as the composer PLACEHOLDER only: "Ask, or paste a link / 'remember:' to save"). Footer row: `Start new chat · Earlier conversations` (`StashType.meta`, `.muted`, interpunct `·`), both `Button`s with the existing identifiers. Conversations rows: 8pt `violet300` circle leading; title `StashType.body` 500 ink; excerpt `.muted` 1-line; trailing date (`.meta`, `.faint`) over "N messages"; month bucket label = micro-label style. Infinite scroll stays (documented divergence — leave the `ui-changes.md:343-345` note intact).
- [ ] **Step 3: GREEN**: new smoke + `testAskSmoke` (expected gate-blocked adjudication unchanged — the pre-gate assertions must still pass) + `testCardAnatomySmoke` untouched. Screenshots vs web.
- [ ] **Step 4: Commit.** `git commit -m "feat(ios): Ask header/footer + Conversations rows match web (footer links, violet dot, tokens)"`

---

### Task 5: Markdown blocks — StashKit parser (tested) + app renderer

**Files:**
- Create: `ios/StashKit/Sources/StashKit/Markdown/MarkdownBlocks.swift`, `ios/StashKit/Tests/StashKitTests/MarkdownBlocksTests.swift`
- Create: `ios/Stash/Detail/MarkdownBlocksView.swift`

**Interfaces:**
- Produces:

```swift
public enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)                 // inline markdown preserved for AttributedString
    case heading(level: Int, String)
    case bullets([String])                 // "- " / "* " / "• " items
    case numbered([String])                // "1. " items
    case quote(String)
    case code(String)
}
public enum MarkdownBlocks {
    public static func parse(_ text: String) -> [MarkdownBlock]
    public static func looksLikeMarkdown(_ text: String) -> Bool   // port of web src/components/EditItemContentSection.tsx:27-41 heuristic
}
```
`MarkdownBlocksView(text:)` renders: paragraphs via `Text(AttributedString(markdown:))` (bold/italic/links), bullets as `HStack { Text("•").foregroundStyle(.faint); Text(inline) }` with 16pt hanging indent, numbered with the ordinal, headings in `StashType.body` 600, quotes with a 2pt `violet600` bar, code in `StashType.mono` on `wash`. Body color `ink`, line spacing per DESIGN.md (1.55).

- [ ] **Step 1: Failing tests** (RED): `parse` of the farfetch summary in Will's screenshot ("Key features include:\n\n- Brown tortoiseshell effect\n- Brand logo…") → `[.paragraph, .bullets([5 items]), .paragraph…]`; numbered lists; `**bold**` survives inside paragraph text; blank-line paragraph splitting; CRLF input; `looksLikeMarkdown` true for "- item" lines and `**x**`, false for plain prose; a 1e5-char input parses (no quadratic blowup — time-box assert < 1s).
- [ ] **Step 2: Implement** line-based state machine (no regex backtracking hazards).
- [ ] **Step 3: GREEN** (~293 + 8). Build the view; preview with the farfetch text.
- [ ] **Step 4: Commit.** `git commit -m "feat(ios): markdown block parser (StashKit, tested) + renderer for AI text"`

---

### Task 6: Item detail sheet — structure, eyebrow, URL bar, tabs, markdown, footer, tags removed

**Files:**
- Rewrite: `ios/Stash/Detail/ItemDetailView.swift`, `ios/Stash/Detail/ItemDetailContent.swift`
- Create: `ios/Stash/Detail/DetailEyebrow.swift`, `ios/Stash/Detail/DetailURLBar.swift`
- Delete usage: `ItemTagsSection` (remove the file if nothing else references it)
- Test: `StashUITests.swift` — `testEditSmoke` identifiers preserved (title field, notes, save indicator) or updated in-task.

**Interfaces:**
- Consumes: Task 2 tokens, Task 5 `MarkdownBlocksView`, existing `ItemEditor`/`ItemPatch`, `CardMetadata` helpers (`domainOf`, favicon URL builder used by cards), `editPanelTabs` mirror already in StashKit.
- Web reference: `src/components/EditItemDetailsTab.tsx:360-401` (eyebrow, editable title/description, player strip), `EditItemContentSection.tsx` (tabs + markdown), `EditItemSheet.tsx:102-130` (footer). `DESIGN.md` §detail panel: eyebrow → title → description → annotation → media → content tabs → Details drawer → Sharing → footer.
- Produces: identifiers `detail.eyebrow`, `detail.title`, `detail.description`, `detail.urlBar`, `detail.tabs`, `detail.delete`, `detail.autosave`.

- [ ] **Step 1: Failing smoke** `testDetailSheetAnatomy`: open the UITEST-FIXTURE link item → assert `detail.eyebrow` label contains "LINK" and the domain; `detail.urlBar` exists; `detail.tabs` has "Summary"/"Original Content"/"Notes"; `detail.autosave` reads "Changes saved automatically"; the tags section identifier does NOT exist. RED.
- [ ] **Step 2: Rebuild** as one scrolling flow surface on `paper` (sheet radius 20, `Done` → keep as the iOS close affordance, styled as web's `×` top-right circle icon): eyebrow pill (type icon + uppercase type in `kicker`, `wash` fill, radius 999) + domain (`.muted`) → title (`StashType.panelTitle`, ink, inline-editable — plain `TextField` styled invisible, violet wash on focus, NOT the grey pill) → description (`.body`, `.muted`) → location row (existing `LocationRow`, restyled) → media (contained hero, radius 16, `StashShadow.card`; images/video/audio players as today) → URL bar (favicon 16pt via the card favicon helper + URL in `StashType.mono(12)` single-line truncated + trailing `arrow.up.right.square` opening the link, hairline border, radius 12; replaces the blue "Open Link") → section micro-label "NOTES & SUMMARY" / "NOTES & TRANSCRIPT" per `editPanelTabs` + pill tabs (same style as the sign-in tabs) → tab content: Summary/Original/Transcript through `MarkdownBlocksView` when `looksLikeMarkdown`, else plain body text; Notes keeps the existing TipTap renderer/append composer → footer bar (hairline top): "Delete item" (`destructive`, trash icon, existing confirm) left, "Changes saved automatically" (`.meta`, `.faint`) right, driven by the existing debounced-save state (show "Saving…" while a save is in flight).
- [ ] **Step 3: Remove tags** (`ItemTagsSection` call + file if orphaned; keep `tags` data untouched — retired UI only). Remove the relative "10 minutes ago" line from the top (date belongs in Details, Task 7).
- [ ] **Step 4: GREEN**: `testDetailSheetAnatomy` + `testEditSmoke` + `testCardAnatomySmoke`; `swift test`; screenshots for link/video/image fixtures vs the web screenshots.
- [ ] **Step 5: Commit.** `git commit -m "feat(ios): item detail sheet rebuilt to DESIGN.md — eyebrow, URL bar, pill tabs, rendered markdown, footer; tags UI retired"`

---

### Task 7: Details drawer + Sharing section

**Files:**
- Create: `ios/Stash/Detail/DetailsDrawer.swift`, `ios/Stash/Detail/SharingSection.swift`
- Modify: `ios/Stash/Detail/ItemDetailView.swift` (insert below tabs), `StashUITests.swift` (`testDetailSheetAnatomy` extended)

**Interfaces:**
- Web reference: `EditItemDetailsTab.tsx:509-574` (Sharing: lock/globe tile, "Private / Only you can see this item" vs "Public / Anyone with the link", violet switch, feed-link copy chip), `EditItemDetailsDrawer` (collapsed row: domain or "format · size · duration" summary + chevron; expanded: dotted key/value rows — saved date, type, size, duration, source, location).
- Consumes: existing `ItemEditor` public toggle (+ un-share confirmation already implemented), `CardMetadata.formatFileSizeChip/formatDurationChip`, `attributes.location`.

- [ ] **Step 1: Extend smoke** (RED): after the tabs, `detail.details` row exists with the domain (link fixture); tapping expands to show a "Saved" row; `detail.sharing` shows "Private" for the fixture.
- [ ] **Step 2: Implement** per DESIGN.md (micro-label "DETAILS" + collapsed row + dotted-leader key/value rows; micro-label "SHARING" + tile 40pt `wash` circle with `lock`/`globe` + two-line copy + `Toggle` tinted `violet600`; when public, a feed-link chip with copy-to-clipboard — reuse the existing public-URL builder).
- [ ] **Step 3: GREEN** (smokes + suite) → **Commit**: `git commit -m "feat(ios): details drawer + sharing section on the detail sheet (DESIGN.md parity)"`

---

### Task 8: Wrap — docs, consolidation record, suites ×2, TestFlight build 2

**Files:**
- Modify: `docs/ui-changes.md` (new top entry: iOS design consolidation — contracts-first for web/mac: tokens adopted, icon decision, sign-up on iOS, footer links, detail anatomy, markdown rendering, tags removed on iOS), `docs/superpowers/plans/2026-08-24-ios-plan-6-visual-overhaul.md` (append "Status: superseded — not executed as written; what shipped was c4e9a5b; remainder consolidated into plan 7"), this plan (outcome), `ios/project.yml` (`CURRENT_PROJECT_VERSION: 2`), `docs/RELEASING.md` (if any step drifted).

- [ ] **Step 1: Foreign-commit audit.** `git fetch origin && git log --oneline HEAD..origin/main` — if non-empty, merge `origin/main` INTO the worktree branch first, resolve, re-run suites, before anything else (standing rule from plan 6).
- [ ] **Step 2: Suites.** `swift test` (≥ 301), app+extension build warning-free, `npm test`, UI suite ×2 (expect exactly the standing 3 gate-blocked failures + everything else green incl. the new smokes).
- [ ] **Step 3: Docs** as listed; App Store note for Will in the outcome: iOS now supports account creation → Apple 5.1.1(v) requires in-app account deletion before *public App Store* submission (TestFlight unaffected) — carry as a named plan-8 requirement.
- [ ] **Step 4: Build 2.** `CURRENT_PROJECT_VERSION: 2` → `xcodegen generate` → commit docs+version → `./ios/scripts/release.sh all` → verify entitlements on the .ipa (both binaries: app group + keychain group) → `./ios/scripts/release.sh upload` → poll `asc-api.sh GET /v1/builds?filter[app]=6806459949&sort=-uploadedDate` until VALID → attach to group `d19f78c1-7af3-4461-9af6-1566200c251b` via `POST /v1/betaGroups/<id>/relationships/builds`.
- [ ] **Step 5: Commit** `docs(ios): plan-7 outcome; ui-changes entry; build 2` — then hand back to the coordinator for merge + push (never push from the worktree).

---

## Self-review notes (authoring time)

- **Coverage of Will's brief:** icon ✓ T1; login ✓ T3; conversations list ✓ T4; Ask-tab access ✓ T4 (footer links — the existing clock icon wasn't discoverable; identifiers preserved); detail sheet ✓ T5–T7 (incl. the raw-bullets problem in his screenshot = T5/T6 markdown); "visual assets to match favicon" ✓ T1 + wordmark already ink; commit+deploy ✓ T8.
- **Placeholder scan:** all steps carry concrete files, tokens, identifiers; web references are file:line from the survey.
- **Type consistency:** `StashColor`/`StashType`/`StashRadius`/`StashShadow` names identical across T2–T7; `MarkdownBlocks.parse`/`looksLikeMarkdown`/`MarkdownBlocksView(text:)` identical in T5/T6; identifiers listed once per task and reused by T8's suite run.
- **Known risks, accepted:** Neue Montreal on iOS is a license question in principle, but `DESIGN.md` (accepted design record) already mandates bundling it — proceed, flag in the outcome; T3 sign-up introduces the account-deletion obligation for public App Store (flagged, not blocking TestFlight); the other thread may still push to main — T8 Step 1 audits before merge.
- **Ethos check:** no new capture-time decisions; enrichment stays behind endpoints; tags retirement matches web; single-object model untouched.
