# Stash iOS — Plan 1: Foundation (add-file API + app scaffold + auth + View tab)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `add-file` edge function, and a signed-in SwiftUI app on the simulator showing the user's real stash (grid, filters, search, realtime enrichment updates, read-only item detail).

**Architecture:** Thin native client per `docs/PLATFORM_API.md` and the approved spec (`docs/superpowers/specs/2026-08-10-stash-ios-app-design.md`). All intelligence stays in Supabase edge functions. The Xcode project is *generated* from a committed `ios/project.yml` by XcodeGen (declarative targets — extensions in later plans are project.yml edits, not pbxproj surgery); building/running/screenshotting the simulator goes through XcodeBuildMCP.

**Tech Stack:** Swift 5.10 / SwiftUI, local SPM package `StashKit`, [supabase-swift](https://github.com/supabase/supabase-swift) `from: 2.0.0` (Auth/PostgREST/Storage/Realtime), XcodeGen, XcodeBuildMCP, Deno edge function (supabase-js 2.50.2, matching `add-note`).

**Plan sequence** (each plan = working software; later plans get written when their predecessor ships): **1 (this): add-file + scaffold + auth + View tab** → 2: capture (Add tab, uploads, Outbox, edit/delete/tags) → 3: share extension → 4: voice notes + Ask tab → 5: widgets/App Intents/Settings/TestFlight.

## Global Constraints

- Tab order **Add · Ask · View · Settings** (spec, Will's order). Add/Ask/Settings are placeholder panes in this plan; launch selection is **View** until the Add composer exists (plan 2 flips it).
- Min iOS **17.0**; `StashKit` platforms `[.iOS(.v17), .macOS(.v14)]` so `swift test` runs natively on the Mac.
- Bundle id `it.gostash.stash`; app display name **Stash**; simulator target **iPhone 15 Pro**. NO app-group/keychain-group entitlements in this plan (plan 3 adds them; costs one dev re-sign-in, zero real users affected).
- Supabase project `uqqsgmwkvslaomzxptnp`; the URL + anon key are public constants (same as committed web client `src/integrations/supabase/client.ts:5-6`).
- Item owner is always derived server-side from the JWT. `add-file` must reject `file_path` not prefixed `<jwt-user-id>/`.
- Edge functions deploy with `supabase functions deploy <name>` from repo root, then **verify with `supabase functions list`** (lesson: undeployed functions surface as CORS errors in browsers).
- Never commit credentials. The UI-test account email is `will+uitest@dzierson.com`; its password is injected at execution time from project memory into `ios/.env.test.local` (gitignored) — the orchestrator provides it, tasks `source` it.
- Every task ends in a commit on `main` (no push). Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- supabase-swift API drift: the code below targets v2.x. If a call doesn't compile, check `~/…/DerivedData` checkouts or the package README for the current signature and adapt — do not downgrade the package.

---

### Task 1: `add-file` edge function — auth, validation, typed insert

**Files:**
- Create: `supabase/functions/add-file/index.ts`
- Modify: `supabase/config.toml` (only if it contains per-function entries for `add-note` — mirror them for `add-file`; if there are none, change nothing)

**Interfaces:**
- Consumes: existing `items` table; JWT auth pattern from `supabase/functions/add-note/index.ts:32-54`.
- Produces: `POST /add-file` accepting `{ file_path, mime_type, file_size?, content?, title?, is_public? }` → `{ success: true, item }` (200). Errors: 401 missing/invalid token, 400 missing `file_path`/`mime_type`, 403 foreign `file_path` prefix, 405 non-POST. Task 2 relies on the returned `item.id` and the `deriveItemType` mapping below.

- [ ] **Step 1: Write the function (insert path only — enrichment is Task 2)**

```ts
// supabase/functions/add-file/index.ts
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

// Mirrors the web's routing: image/* → image, audio/* → audio, video/* → video,
// everything else that reaches this endpoint is a document (pdf, docx, …)
export const deriveItemType = (mime: string): 'image' | 'audio' | 'video' | 'document' => {
  if (mime.startsWith('image/')) return 'image';
  if (mime.startsWith('audio/')) return 'audio';
  if (mime.startsWith('video/')) return 'video';
  return 'document';
};

const fileNameFrom = (path: string) => path.split('/').pop() ?? 'file';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: corsHeaders });
  if (req.method !== 'POST') return json(405, { error: 'Method not allowed' });

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Owner always derived from the verified JWT, never the body
    const token = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '').trim();
    if (!token) return json(401, { error: 'Missing authorization token' });
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) return json(401, { error: 'Invalid or expired token' });

    const { file_path, mime_type, file_size, content, title, is_public = false } = await req.json();
    if (!file_path || typeof file_path !== 'string') return json(400, { error: 'file_path is required' });
    if (!mime_type || typeof mime_type !== 'string') return json(400, { error: 'mime_type is required' });
    if (!file_path.startsWith(`${user.id}/`)) {
      return json(403, { error: 'file_path must be inside your own storage folder' });
    }

    const type = deriveItemType(mime_type);
    const fileName = fileNameFrom(file_path);
    const itemTitle = title || fileName;
    // Same placeholder the web writes for in-flight documents
    // (src/utils/contentProcessor.ts:484)
    const placeholderDescription =
      type === 'document' ? 'PDF file uploaded - text extraction in progress' : null;

    const { data: item, error } = await supabase
      .from('items')
      .insert({
        user_id: user.id,
        type,
        title: itemTitle,
        content: content || null,
        description: placeholderDescription,
        file_path,
        file_size: file_size ?? null,
        mime_type,
        is_public,
        visibility: is_public ? 'public' : 'private',
      })
      .select()
      .single();

    if (error) return json(500, { error: 'Failed to create item', details: error.message });

    return json(200, { success: true, item });
  } catch (e) {
    return json(500, { error: 'Internal server error', details: e instanceof Error ? e.message : 'Unknown' });
  }
});
```

- [ ] **Step 2: Check `supabase/config.toml`** — if it has an `[functions.add-note]` (or similar) block, add an identical `[functions.add-file]` block; otherwise skip.

- [ ] **Step 3: Deploy and verify listed**

```bash
cd /Users/will/Appdev/embed-link-spark
supabase functions deploy add-file
supabase functions list | grep add-file   # must appear as deployed
```

- [ ] **Step 4: Contract tests via curl** (env from gitignored `ios/.env.test.local`, created by the orchestrator: `STASH_TEST_EMAIL`, `STASH_TEST_PASSWORD`)

```bash
source ios/.env.test.local
BASE="https://uqqsgmwkvslaomzxptnp.supabase.co"
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE"
JWT=$(curl -s -X POST "$BASE/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d "{\"email\":\"$STASH_TEST_EMAIL\",\"password\":\"$STASH_TEST_PASSWORD\"}" | jq -r .access_token)
UID=$(curl -s "$BASE/auth/v1/user" -H "apikey: $ANON" -H "Authorization: Bearer $JWT" | jq -r .id)

# 401 without token
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$BASE/functions/v1/add-file" \
  -H "apikey: $ANON" -H "Content-Type: application/json" -d '{}'          # expect 401
# 400 missing file_path
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$BASE/functions/v1/add-file" \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d '{"mime_type":"image/png"}'                                          # expect 400
# 403 foreign prefix
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$BASE/functions/v1/add-file" \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d '{"file_path":"someone-else/x.png","mime_type":"image/png"}'         # expect 403
```

Expected: `401`, `400`, `403` in order. (Happy path lands in Task 2's E2E, which uploads real files first.)

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/add-file/index.ts supabase/config.toml
git commit -m "feat: add-file edge function — JWT-authed typed insert for uploaded files"
```

---

### Task 2: `add-file` enrichment dispatch + end-to-end proof

**Files:**
- Modify: `supabase/functions/add-file/index.ts` (add enrichment between insert and response)

**Interfaces:**
- Consumes: `analyze-image` (`{ itemId, imageUrl }` — writes description/page_body + re-embeds itself), `transcribe-audio` (stateless `{ audioUrl, fileName }` → `{ transcription, description }`), `quick-pdf-summary` (`{ fileUrl, itemId, fileName }` — writes description), `extract-pdf-text` (`{ fileUrl, itemId }` — writes page_body + summary + embeddings), `generate-embeddings` (`{ itemId, textContent }`). Public file URL shape: `${SUPABASE_URL}/storage/v1/object/public/stash-media/${file_path}`.
- Produces: async enrichment matching the web pipeline, but **audio/video transcription is post-response** (the web blocks capture on Whisper inline — `src/utils/contentProcessor.ts:444-471`; this endpoint must not).

- [ ] **Step 1: Add enrichment before the success return** (insert code from Task 1 unchanged above this):

```ts
    // --- enrichment: after-response, never blocks capture ---
    const publicUrl = `${Deno.env.get('SUPABASE_URL')}/storage/v1/object/public/stash-media/${file_path}`;

    const enrich = async () => {
      try {
        if (type === 'image') {
          // analyze-image writes description + page_body (OCR) and re-embeds the item
          await supabase.functions.invoke('analyze-image', {
            body: { itemId: item.id, imageUrl: publicUrl },
          });
        } else if (type === 'audio' || type === 'video') {
          const { data: t, error: tErr } = await supabase.functions.invoke('transcribe-audio', {
            body: { audioUrl: publicUrl, fileName },
          });
          if (tErr) throw tErr;
          // Transcript is captured source → page_body (content model,
          // migration 20260810120000); description is the short AI summary
          await supabase.from('items').update({
            page_body: t.transcription || null,
            description: t.description || null,
          }).eq('id', item.id);
          const text = [itemTitle, content, t.transcription, t.description].filter(Boolean).join(' ');
          if (text.trim()) {
            await supabase.functions.invoke('generate-embeddings', {
              body: { itemId: item.id, textContent: text },
            });
          }
        } else {
          // document: baseline embedding first so it's searchable even if
          // extraction never lands (mirrors contentProcessor.ts:580-594)
          const baseline = [itemTitle, fileName, content].filter(Boolean).join(' ');
          if (baseline.trim()) {
            await supabase.functions.invoke('generate-embeddings', {
              body: { itemId: item.id, textContent: baseline },
            });
          }
          await supabase.functions.invoke('quick-pdf-summary', {
            body: { fileUrl: publicUrl, itemId: item.id, fileName },
          });
          // writes page_body + summary + content embeddings itself
          await supabase.functions.invoke('extract-pdf-text', {
            body: { fileUrl: publicUrl, itemId: item.id },
          });
        }
      } catch (e) {
        console.error('add-file enrichment failed (non-fatal):', e);
      }
    };

    const runtime = (globalThis as { EdgeRuntime?: { waitUntil: (p: Promise<unknown>) => void } }).EdgeRuntime;
    const p = enrich();
    runtime?.waitUntil?.(p);
```

- [ ] **Step 2: Redeploy** — `supabase functions deploy add-file && supabase functions list | grep add-file`

- [ ] **Step 3: E2E image path** (continues the Task 1 shell session):

```bash
# 1x1 transparent png fixture
echo 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' | base64 -d > /tmp/stash-test.png
curl -s -X POST "$BASE/storage/v1/object/stash-media/$UID/e2e-test.png" \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: image/png" \
  --data-binary @/tmp/stash-test.png
ITEM=$(curl -s -X POST "$BASE/functions/v1/add-file" \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d "{\"file_path\":\"$UID/e2e-test.png\",\"mime_type\":\"image/png\",\"content\":\"e2e note\"}")
echo "$ITEM" | jq '.success,.item.type'      # expect: true, "image"
ID=$(echo "$ITEM" | jq -r .item.id)
for i in $(seq 1 20); do sleep 5; DESC=$(curl -s "$BASE/rest/v1/items?id=eq.$ID&select=description" \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT" | jq -r '.[0].description'); \
  [ "$DESC" != "null" ] && break; done; echo "description: $DESC"   # expect non-null within ~100s
```

- [ ] **Step 4: E2E audio path** — real speech via macOS `say`, so Whisper has something to transcribe:

```bash
say -o /tmp/stash-e2e.aiff "This is a Stash voice note test"
afconvert /tmp/stash-e2e.aiff /tmp/stash-e2e.m4a -f m4af -d aac
curl -s -X POST "$BASE/storage/v1/object/stash-media/$UID/e2e-test.m4a" \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: audio/mp4" \
  --data-binary @/tmp/stash-e2e.m4a
AID=$(curl -s -X POST "$BASE/functions/v1/add-file" \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d "{\"file_path\":\"$UID/e2e-test.m4a\",\"mime_type\":\"audio/mp4\"}" | jq -r .item.id)
for i in $(seq 1 24); do sleep 5; PB=$(curl -s "$BASE/rest/v1/items?id=eq.$AID&select=page_body" \
  -H "apikey: $ANON" -H "Authorization: Bearer $JWT" | jq -r '.[0].page_body'); \
  [ "$PB" != "null" ] && break; done; echo "transcript: $PB"
```

Expected: transcript contains "stash voice note" (case-insensitive) — this is the exact pipeline plan 4's voice notes ride on.

- [ ] **Step 5: Clean up test rows + files, then commit**

```bash
curl -s -X DELETE "$BASE/rest/v1/items?id=in.($ID,$AID)" -H "apikey: $ANON" -H "Authorization: Bearer $JWT"
curl -s -X DELETE "$BASE/storage/v1/object/stash-media" -H "apikey: $ANON" -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" -d "{\"prefixes\":[\"$UID/e2e-test.png\",\"$UID/e2e-test.m4a\"]}"
git add supabase/functions/add-file/index.ts
git commit -m "feat: add-file async enrichment (vision/whisper/pdf) with E2E-verified pipeline"
```

*(Document-type E2E is deliberately deferred to plan 2's capture work, where a real PDF fixture ships with the repo — hand-rolled minimal PDFs are a flaky test of the extractor, not of add-file.)*

---

### Task 3: Document `add-file` in the platform contract

**Files:**
- Modify: `docs/PLATFORM_API.md:48-50` (the "intended next step" paragraph)

**Interfaces:**
- Produces: the documented contract every later plan (share extension, voice notes) codes against.

- [ ] **Step 1: Replace the placeholder paragraph** ("Files (images, PDFs, audio) currently upload via…") with:

```markdown
### `POST /add-file` — save an uploaded file

Upload to Storage first (`stash-media/<userId>/<name>.<ext>`), then:

​```json
{ "file_path": "<userId>/…", "mime_type": "image/png", "file_size": 1234,
  "content": "optional note", "title": "optional", "is_public": false }
​```

Returns `{ success, item }` fast. Type derives from MIME (image/audio/video,
else document). Enrichment continues server-side after the response: vision
description + OCR for images, Whisper transcript into `page_body` for
audio/video, quick summary + full text extraction for documents, embeddings
for all — realtime delivers the upgrades. `file_path` must sit inside the
caller's own folder (403 otherwise).
```

- [ ] **Step 2: Commit** — `git add docs/PLATFORM_API.md && git commit -m "docs: add-file contract in platform API"`

---

### Task 4: iOS workspace scaffold + tab skeleton, building on the simulator

**Files:**
- Create: `ios/.gitignore`, `ios/project.yml`, `ios/StashKit/Package.swift`, `ios/StashKit/Sources/StashKit/StashConfig.swift`, `ios/StashKit/Tests/StashKitTests/StashConfigTests.swift`, `ios/Stash/StashApp.swift`, `ios/Stash/MainTabView.swift`, `ios/Stash/Assets.xcassets` (empty catalog with AccentColor + AppIcon placeholders)

**Interfaces:**
- Produces: generated `ios/Stash.xcodeproj` (never committed); `StashConfig.supabaseURL: URL`, `StashConfig.supabaseAnonKey: String`, `StashConfig.publicStorageURL(for path: String) -> URL`; `MainTab` enum (`add, ask, view, settings`). Every later task builds inside this workspace.

- [ ] **Step 1: Preflight tooling**

```bash
which xcodegen || brew install xcodegen
xcodebuild -version    # expect Xcode 26.x
```

- [ ] **Step 2: Write the scaffold files**

`ios/.gitignore`:
```gitignore
Stash.xcodeproj/
DerivedData/
.env.test.local
*.xcuserstate
```

`ios/project.yml`:
```yaml
name: Stash
options:
  bundleIdPrefix: it.gostash
  deploymentTarget:
    iOS: "17.0"
packages:
  StashKit:
    path: StashKit
targets:
  Stash:
    type: application
    platform: iOS
    sources: [Stash]
    dependencies:
      - package: StashKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: it.gostash.stash
        MARKETING_VERSION: 0.1.0
        CURRENT_PROJECT_VERSION: 1
        TARGETED_DEVICE_FAMILY: "1"
        SWIFT_VERSION: "5.10"
    info:
      path: Stash/Info.plist
      properties:
        CFBundleDisplayName: Stash
        UILaunchScreen: {}
        ITSAppUsesNonExemptEncryption: false
```

`ios/StashKit/Package.swift`:
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StashKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "StashKit", targets: ["StashKit"])],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
    ],
    targets: [
        .target(name: "StashKit", dependencies: [.product(name: "Supabase", package: "supabase-swift")]),
        .testTarget(name: "StashKitTests", dependencies: ["StashKit"]),
    ]
)
```

`ios/StashKit/Sources/StashKit/StashConfig.swift`:
```swift
import Foundation

public enum StashConfig {
    public static let supabaseURL = URL(string: "https://uqqsgmwkvslaomzxptnp.supabase.co")!
    // Public anon key — same value the committed web client ships
    public static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE"

    public static func publicStorageURL(for path: String) -> URL {
        supabaseURL.appending(path: "/storage/v1/object/public/stash-media/\(path)")
    }
}
```

`ios/StashKit/Tests/StashKitTests/StashConfigTests.swift`:
```swift
import XCTest
@testable import StashKit

final class StashConfigTests: XCTestCase {
    func testPublicStorageURL() {
        let url = StashConfig.publicStorageURL(for: "abc/file.png")
        XCTAssertEqual(url.absoluteString,
            "https://uqqsgmwkvslaomzxptnp.supabase.co/storage/v1/object/public/stash-media/abc/file.png")
    }
}
```

`ios/Stash/StashApp.swift`:
```swift
import SwiftUI

@main
struct StashApp: App {
    var body: some Scene {
        WindowGroup { MainTabView() }
    }
}
```

`ios/Stash/MainTabView.swift`:
```swift
import SwiftUI

enum MainTab: Hashable { case add, ask, view, settings }

struct MainTabView: View {
    // Launch on View until the Add composer exists (plan 2 flips this to .add)
    @State private var selection: MainTab = .view

    var body: some View {
        TabView(selection: $selection) {
            PlaceholderPane(title: "Add", note: "Capture arrives in plan 2")
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(MainTab.add)
            PlaceholderPane(title: "Ask", note: "Ask Stash arrives in plan 4")
                .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(MainTab.ask)
            Text("View")   // replaced by LibraryView in Task 10
                .tabItem { Label("View", systemImage: "square.grid.2x2") }
                .tag(MainTab.view)
            PlaceholderPane(title: "Settings", note: "Settings arrive in plan 5")
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
    }
}

struct PlaceholderPane: View {
    let title: String
    let note: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.title2.bold())
            Text(note).foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3: Generate, test, build, run**

```bash
cd /Users/will/Appdev/embed-link-spark/ios
xcodegen generate
(cd StashKit && swift test)     # StashConfigTests passes
```

Then via **XcodeBuildMCP** (preferred): build the `Stash` scheme of `ios/Stash.xcodeproj` for the iPhone 15 Pro simulator, boot it, install + launch `it.gostash.stash`, and take a screenshot showing the 4-tab bar in the order **Add · Ask · View · Settings**. Raw fallback if the MCP is unavailable:

```bash
xcodebuild -project Stash.xcodeproj -scheme Stash \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
xcrun simctl boot "iPhone 15 Pro" || true
xcrun simctl install "iPhone 15 Pro" ~/Library/Developer/Xcode/DerivedData/Stash-*/Build/Products/Debug-iphonesimulator/Stash.app
xcrun simctl launch "iPhone 15 Pro" it.gostash.stash
xcrun simctl io "iPhone 15 Pro" screenshot /tmp/stash-plan1-task4.png
```

Expected: app launches; tab bar shows Add · Ask · View · Settings; View tab selected.

- [ ] **Step 4: Commit**

```bash
git add ios/.gitignore ios/project.yml ios/StashKit ios/Stash
git commit -m "feat(ios): XcodeGen workspace, StashKit package, 4-tab skeleton building on simulator"
```

---

### Task 5: `Item` model + resilient decoding

**Files:**
- Create: `ios/StashKit/Sources/StashKit/Models/Item.swift`
- Test: `ios/StashKit/Tests/StashKitTests/ItemDecodingTests.swift`

**Interfaces:**
- Produces: `ItemType` (`text|link|image|audio|video|document|collection|unknown`), `Item: Codable, Identifiable, Hashable, Sendable` with `id: UUID, type: ItemType, title: String?, content: String?, url: String?, filePath: String?, description: String?, summary: String?, pageBody: String?, supplementalNote: String?, mimeType: String?, isPublic: Bool, createdAt: Date`. Card queries select the same columns as web `ITEM_LIST_COLUMNS` (`src/hooks/useItems.ts:7-20`); `pageBody` only arrives on detail fetches (it can be tens of KB — `src/utils/editPanelTabs.ts:52-55`).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import StashKit

final class ItemDecodingTests: XCTestCase {
    let decoder = Item.decoder   // JSONDecoder configured by the model file

    func testDecodesListRow() throws {
        let json = """
        {"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4b","type":"link","title":"A page",
         "content":null,"url":"https://example.com","file_path":"u1/x.png",
         "description":"short","summary":null,"created_at":"2026-08-10T14:03:22.123456+00:00",
         "mime_type":null,"is_public":false,"supplemental_note":null}
        """.data(using: .utf8)!
        let item = try decoder.decode(Item.self, from: json)
        XCTAssertEqual(item.type, .link)
        XCTAssertEqual(item.title, "A page")
        XCTAssertNil(item.pageBody)
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.year,
            from: item.createdAt), 2026)
    }

    func testUnknownTypeDoesNotThrow() throws {
        let json = """
        {"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4c","type":"hologram","title":null,
         "content":null,"url":null,"file_path":null,"description":null,"summary":null,
         "created_at":"2026-08-10T14:03:22+00:00","mime_type":null,"is_public":true,
         "supplemental_note":null}
        """.data(using: .utf8)!
        XCTAssertEqual(try decoder.decode(Item.self, from: json).type, .unknown)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `cd ios/StashKit && swift test 2>&1 | tail -5` → FAIL: `Item` not found.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum ItemType: String, Codable, Sendable, CaseIterable {
    case text, link, image, audio, video, document, collection
    case unknown   // forward-compat: never crash on a type this build predates

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ItemType(rawValue: raw) ?? .unknown
    }
}

public struct Item: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var type: ItemType
    public var title: String?
    public var content: String?
    public var url: String?
    public var filePath: String?
    public var description: String?
    public var summary: String?
    public var pageBody: String?
    public var supplementalNote: String?
    public var mimeType: String?
    public var isPublic: Bool
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type, title, content, url, description, summary
        case filePath = "file_path"
        case pageBody = "page_body"
        case supplementalNote = "supplemental_note"
        case mimeType = "mime_type"
        case isPublic = "is_public"
        case createdAt = "created_at"
    }

    // Postgres timestamptz comes back as ISO8601 with variable fractional digits
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath,
                debugDescription: "Unparseable date: \(s)"))
        }
        return d
    }()

    /// Columns the card grid selects — mirror of web ITEM_LIST_COLUMNS.
    public static let listColumns =
        "id,type,title,content,url,file_path,description,summary,created_at,mime_type,is_public,supplemental_note"
    public static let detailColumns = listColumns + ",page_body"
}
```

- [ ] **Step 4: Run tests** — `swift test 2>&1 | tail -5` → PASS.
- [ ] **Step 5: Commit** — `git add ios/StashKit && git commit -m "feat(ios): Item model with resilient type + timestamptz decoding"`

---

### Task 6: `MessageRouting` port (documented client contract)

**Files:**
- Create: `ios/StashKit/Sources/StashKit/MessageRouting.swift`
- Test: `ios/StashKit/Tests/StashKitTests/MessageRoutingTests.swift`

**Interfaces:**
- Consumes: rules of `src/utils/moleRouting.ts` (the reference implementation named in PLATFORM_API.md).
- Produces: `enum RoutedMessage: Equatable { case saveURL(url: String, note: String); case saveNote(String); case ask }` and `func classifyMessage(_ raw: String) -> RoutedMessage`. Plan 2's composer and plan 4's Ask tab both consume this.

- [ ] **Step 1: Table-driven failing tests** (each row mirrors the TS behavior exactly):

```swift
import XCTest
@testable import StashKit

final class MessageRoutingTests: XCTestCase {
    func testRouting() {
        let cases: [(String, RoutedMessage)] = [
            ("remember: buy milk", .saveNote("buy milk")),
            ("SAVE:  spaced  ", .saveNote("spaced")),
            ("note: https://x.com is great", .saveNote("https://x.com is great")),  // prefix wins over URL
            ("https://example.com/a?b=c", .saveURL(url: "https://example.com/a?b=c", note: "")),
            ("read this https://example.com/post.", .saveURL(url: "https://example.com/post", note: "read this")),
            // TS removes the FULL raw match ("https://x.com/y),") from the note, then trims
            ("https://x.com/y), context after", .saveURL(url: "https://x.com/y", note: "context after")),
            ("what did I save about tokyo?", .ask),
            ("   ", .ask),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(classifyMessage(input), expected, "input: \(input)")
        }
    }
}
```

- [ ] **Step 2: Run to verify failure** — `swift test 2>&1 | tail -5` → FAIL.
- [ ] **Step 3: Implement**

```swift
import Foundation

public enum RoutedMessage: Equatable, Sendable {
    case saveURL(url: String, note: String)
    case saveNote(String)
    case ask
}

// Port of src/utils/moleRouting.ts — keep rules few and predictable.
public func classifyMessage(_ raw: String) -> RoutedMessage {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    if let match = text.firstMatch(of: /^(?i)(remember|save|note):\s*/) {
        return .saveNote(String(text[match.range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    if let match = text.firstMatch(of: /https?:\/\/[^\s]+/) {
        var url = String(match.output)
        while let last = url.last, ".,!?;)]".contains(last) { url.removeLast() }
        let note = text.replacingOccurrences(of: String(match.output), with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return .saveURL(url: url, note: note)
    }

    return .ask
}
```

- [ ] **Step 4: Run tests** — PASS. (If the `(?i)` inline flag or trailing-punct strip behaves differently from TS on an edge case, match the TS: the TS strips `[.,!?;)\]]+` only from the END of the URL, and note assembly removes the *original* matched URL string.)
- [ ] **Step 5: Commit** — `git commit -am "feat(ios): message routing port with table-driven contract tests"`

---

### Task 7: Pure-logic ports — search, processing flag, content tabs, thumbnails

**Files:**
- Create: `ios/StashKit/Sources/StashKit/ItemRules.swift`
- Test: `ios/StashKit/Tests/StashKitTests/ItemRulesTests.swift`

**Interfaces:**
- Consumes: `Item` (Task 5), `StashConfig.publicStorageURL` (Task 4).
- Produces: `Item.matches(searchQuery: String) -> Bool`; `Item.isProcessingDocument: Bool`; `ContentTabsConfig`/`ContentTabKey` + `contentTabsConfig(for type: ItemType) -> ContentTabsConfig`; `Item.thumbnailURL: URL?`. Tasks 10–12 consume all four.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import StashKit

final class ItemRulesTests: XCTestCase {
    func fixture(type: ItemType = .text, title: String? = nil, content: String? = nil,
                 url: String? = nil, description: String? = nil, summary: String? = nil,
                 filePath: String? = nil, supplementalNote: String? = nil) -> Item {
        Item(id: UUID(), type: type, title: title, content: content, url: url,
             filePath: filePath, description: description, summary: summary,
             pageBody: nil, supplementalNote: supplementalNote, mimeType: nil,
             isPublic: false, createdAt: .now)
    }

    func testSearchMatchesSameFieldsAsWeb() {
        // web searches title, content, description, url, supplemental_note — NOT summary/page_body
        XCTAssertTrue(fixture(title: "Tokyo Guide").matches(searchQuery: "tokyo"))
        XCTAssertTrue(fixture(url: "https://ramen.jp").matches(searchQuery: "RAMEN"))
        XCTAssertTrue(fixture(supplementalNote: "sticky").matches(searchQuery: "stick"))
        XCTAssertFalse(fixture(summary: "only in summary").matches(searchQuery: "only"))
        XCTAssertTrue(fixture().matches(searchQuery: "   "))   // blank query matches all
    }

    func testDocumentProcessingFlag() {
        XCTAssertTrue(fixture(type: .document).isProcessingDocument)
        XCTAssertFalse(fixture(type: .document, summary: "done").isProcessingDocument)
        XCTAssertFalse(fixture(type: .image).isProcessingDocument)
    }

    func testContentTabs() {
        XCTAssertEqual(contentTabsConfig(for: .link).tabs.map(\.key), [.summary, .original, .notes])
        XCTAssertEqual(contentTabsConfig(for: .audio).tabs.map(\.key), [.notes, .transcript])
        XCTAssertEqual(contentTabsConfig(for: .audio).defaultTab, .notes)
        XCTAssertEqual(contentTabsConfig(for: .image).tabs.map(\.key), [.notes])
    }

    func testThumbnailRule() {
        XCTAssertNil(fixture().thumbnailURL)
        XCTAssertEqual(fixture(filePath: "https://cdn.example.com/x.jpg").thumbnailURL?.host(),
                       "cdn.example.com")
        XCTAssertEqual(fixture(filePath: "u1/pic.png").thumbnailURL,
                       StashConfig.publicStorageURL(for: "u1/pic.png"))
    }
}
```

- [ ] **Step 2: Run to verify failure**, then **Step 3: Implement**

```swift
import Foundation

public extension Item {
    /// Port of src/utils/itemSearch.ts — same five fields, substring, case-insensitive.
    func matches(searchQuery: String) -> Bool {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return [title, content, description, url, supplementalNote]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(q) }
    }

    /// Port of src/utils/documentProcessing.ts — summary is the one reliable signal.
    var isProcessingDocument: Bool { type == .document && (summary ?? "").isEmpty }

    /// file_path is either a storage path or a full remote URL (both exist in prod).
    var thumbnailURL: URL? {
        guard let filePath, !filePath.isEmpty else { return nil }
        if filePath.hasPrefix("http") { return URL(string: filePath) }
        return StashConfig.publicStorageURL(for: filePath)
    }
}

public enum ContentTabKey: Sendable, Equatable { case summary, original, notes, transcript }
public struct ContentTab: Sendable, Equatable {
    public let key: ContentTabKey
    public let label: String
}
public struct ContentTabsConfig: Sendable, Equatable {
    public let title: String
    public let defaultTab: ContentTabKey
    public let tabs: [ContentTab]
}

/// Port of src/utils/editPanelTabs.ts.
public func contentTabsConfig(for type: ItemType) -> ContentTabsConfig {
    switch type {
    case .link, .document:
        return .init(title: "Notes & Summary", defaultTab: .summary, tabs: [
            .init(key: .summary, label: "Summary"),
            .init(key: .original, label: "Original Content"),
            .init(key: .notes, label: "Notes"),
        ])
    case .audio, .video:
        return .init(title: "Notes & Transcript", defaultTab: .notes, tabs: [
            .init(key: .notes, label: "Notes"),
            .init(key: .transcript, label: "Transcript"),
        ])
    default:
        return .init(title: "Notes", defaultTab: .notes, tabs: [.init(key: .notes, label: "Notes")])
    }
}

/// Detail views need summary/page_body fetched (list omits page_body).
public func needsSourceContent(_ type: ItemType) -> Bool {
    contentTabsConfig(for: type).tabs.contains { $0.key != .notes }
}
```

- [ ] **Step 4: Run tests** — PASS. **Step 5: Commit** — `git commit -am "feat(ios): item rules ports (search/processing/tabs/thumbnails)"`

---

### Task 8: Supabase client, session store, sign-in screen

**Files:**
- Create: `ios/StashKit/Sources/StashKit/StashClient.swift`, `ios/Stash/Auth/SessionStore.swift`, `ios/Stash/Auth/SignInView.swift`
- Modify: `ios/Stash/StashApp.swift` (root gate)

**Interfaces:**
- Consumes: `StashConfig` (Task 4).
- Produces: `StashClient.shared: SupabaseClient`; `SessionStore` (`@MainActor @Observable`) with `state: SessionState` (`.loading | .signedOut | .signedIn(userId: UUID)`), `signIn(email:password:) async`, `signOut() async`, `errorMessage: String?`. Tasks 9–12 consume `StashClient.shared` and `userId`.

- [ ] **Step 1: Implement** (no unit tests — this is a thin SDK wrapper; the verification is the on-simulator sign-in below. Session persistence uses supabase-swift's default keychain storage; plan 3 swaps in an app-group storage and everyone re-signs-in once.)

`StashClient.swift`:
```swift
import Foundation
import Supabase

public enum StashClient {
    public static let shared = SupabaseClient(
        supabaseURL: StashConfig.supabaseURL,
        supabaseKey: StashConfig.supabaseAnonKey
    )
}
```

`SessionStore.swift`:
```swift
import Foundation
import Observation
import StashKit
import Supabase

enum SessionState: Equatable {
    case loading
    case signedOut
    case signedIn(userId: UUID)
}

@MainActor @Observable
final class SessionStore {
    private(set) var state: SessionState = .loading
    var errorMessage: String?

    func start() async {
        // Zombie-session lesson: any failure here (incl. "Auth session missing")
        // means signed-out — show the sign-in screen, never an error loop.
        do {
            let session = try await StashClient.shared.auth.session
            state = .signedIn(userId: session.user.id)
        } catch {
            state = .signedOut
        }
        for await change in StashClient.shared.auth.authStateChanges {
            switch change.event {
            case .signedIn, .tokenRefreshed, .initialSession:
                if let user = change.session?.user { state = .signedIn(userId: user.id) }
            case .signedOut, .userDeleted:
                state = .signedOut
            default: break
            }
        }
    }

    func signIn(email: String, password: String) async {
        errorMessage = nil
        do {
            _ = try await StashClient.shared.auth.signIn(email: email, password: password)
        } catch {
            errorMessage = "Sign-in failed. Check your email and password."
        }
    }

    func signOut() async {
        try? await StashClient.shared.auth.signOut()
        state = .signedOut
    }
}
```

`SignInView.swift`:
```swift
import SwiftUI

struct SignInView: View {
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Stash").font(.largeTitle.bold())
            Text("Sign in with your gostash.it account")
                .foregroundStyle(.secondary)
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(.password)
            if let error = session.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            Button {
                busy = true
                Task { await session.signIn(email: email, password: password); busy = false }
            } label: {
                if busy { ProgressView() } else { Text("Sign In").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || email.isEmpty || password.isEmpty)
            Text("New here? Create your account at gostash.it")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
    }
}
```

`StashApp.swift` (replace body):
```swift
import SwiftUI
import StashKit

@main
struct StashApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            Group {
                switch session.state {
                case .loading: ProgressView()
                case .signedOut: SignInView()
                case .signedIn(let userId): MainTabView(userId: userId)
                }
            }
            .environment(session)
            .task { await session.start() }
        }
    }
}
```

Give `MainTabView` a `let userId: UUID` property (placeholder panes unchanged) and a toolbar-less temporary sign-out: add `.onLongPressGesture { Task { await session.signOut() } }` NOT — instead put a proper `Menu` in Task 10's LibraryView toolbar; until then sign-out is exercised by deleting the app from the simulator.

- [ ] **Step 2: Build + verify on simulator** — regenerate (`xcodegen generate`), build + launch via XcodeBuildMCP (fallback commands as in Task 4). Manually verify: sign-in screen appears; wrong password shows the error line; correct test-account credentials (from `ios/.env.test.local`, typed via simulator keyboard or `xcrun simctl` paste) land on the tab skeleton; relaunching the app skips sign-in (session persisted). Screenshot both states.
- [ ] **Step 3: Commit** — `git add ios && git commit -m "feat(ios): auth session store + sign-in flow against production Supabase"`

---

### Task 9: `ItemStore` — pages, cursor, filters (logic under test)

**Files:**
- Create: `ios/StashKit/Sources/StashKit/ItemStore.swift`
- Test: `ios/StashKit/Tests/StashKitTests/ItemStoreTests.swift`

**Interfaces:**
- Consumes: `Item` (Task 5).
- Produces: `TypeFilter` enum (`all, links, notes, docs, media, collections`) with `var predicateTypes: [ItemType]?`; `protocol ItemsFetching: Sendable { func fetchPage(userId: UUID, before: Date?, types: [ItemType]?, tagIds: [UUID]) async throws -> [Item]; func fetchDetail(id: UUID) async throws -> Item }`; `SupabaseItemsFetcher` (real impl); `@MainActor @Observable final class ItemStore` with `items: [Item]`, `typeFilter`, `selectedTagIds`, `isLoading`, `hasMore`, `func refresh() async`, `func loadMoreIfNeeded(current: Item) async`, `func applyDetail(_ item: Item)`. Page size 50. Tasks 10–12 consume this.

- [ ] **Step 1: Failing tests for the merge/cursor logic** (stub fetcher; the real fetcher is verified on-device in Task 10):

```swift
import XCTest
@testable import StashKit

final class StubFetcher: ItemsFetching, @unchecked Sendable {
    var pages: [[Item]] = []
    var calls: [(before: Date?, types: [ItemType]?)] = []
    func fetchPage(userId: UUID, before: Date?, types: [ItemType]?, tagIds: [UUID]) async throws -> [Item] {
        calls.append((before, types))
        return pages.isEmpty ? [] : pages.removeFirst()
    }
    func fetchDetail(id: UUID) async throws -> Item { fatalError("unused") }
}

@MainActor
final class ItemStoreTests: XCTestCase {
    func makeItem(minutesAgo: Int) -> Item {
        Item(id: UUID(), type: .text, title: "t\(minutesAgo)", content: nil, url: nil,
             filePath: nil, description: nil, summary: nil, pageBody: nil,
             supplementalNote: nil, mimeType: nil, isPublic: false,
             createdAt: Date(timeIntervalSinceNow: Double(-60 * minutesAgo)))
    }

    func testPaginationAdvancesCursorAndStops() async {
        let fetcher = StubFetcher()
        let first = (0..<50).map(makeItem)
        let second = (50..<70).map(makeItem)
        fetcher.pages = [first, second]
        let store = ItemStore(userId: UUID(), fetcher: fetcher, pageSize: 50)

        await store.refresh()
        XCTAssertEqual(store.items.count, 50)
        XCTAssertTrue(store.hasMore)

        await store.loadMoreIfNeeded(current: store.items.last!)
        XCTAssertEqual(store.items.count, 70)
        XCTAssertFalse(store.hasMore)                       // short page → no more
        XCTAssertEqual(fetcher.calls.count, 2)
        XCTAssertEqual(fetcher.calls[1].before, first.last!.createdAt)  // cursor = oldest loaded
    }

    func testRefreshDedupesById() async {
        let fetcher = StubFetcher()
        let a = makeItem(minutesAgo: 1)
        fetcher.pages = [[a], [a]]                          // same row returned twice
        let store = ItemStore(userId: UUID(), fetcher: fetcher, pageSize: 1)
        await store.refresh()
        await store.loadMoreIfNeeded(current: a)
        XCTAssertEqual(store.items.count, 1)
    }

    func testFilterChangeResetsPaging() async {
        let fetcher = StubFetcher()
        fetcher.pages = [[makeItem(minutesAgo: 1)], [makeItem(minutesAgo: 2)]]
        let store = ItemStore(userId: UUID(), fetcher: fetcher, pageSize: 50)
        await store.refresh()
        store.typeFilter = .links
        await store.refresh()
        XCTAssertEqual(fetcher.calls.last?.types, [ItemType.link])
        XCTAssertNil(fetcher.calls.last?.before)            // cursor reset
    }
}
```

- [ ] **Step 2: Run to verify failure**, then **Step 3: Implement**

```swift
import Foundation
import Observation
import Supabase

public enum TypeFilter: String, CaseIterable, Sendable {
    case all, links, notes, docs, media, collections

    public var predicateTypes: [ItemType]? {
        switch self {
        case .all: return nil
        case .links: return [.link]
        case .notes: return [.text]
        case .docs: return [.document]
        case .media: return [.image, .audio, .video]
        case .collections: return [.collection]
        }
    }

    public var label: String {
        switch self {
        case .all: "All"; case .links: "Links"; case .notes: "Notes"
        case .docs: "Docs"; case .media: "Media"; case .collections: "Collections"
        }
    }
}

public protocol ItemsFetching: Sendable {
    func fetchPage(userId: UUID, before: Date?, types: [ItemType]?, tagIds: [UUID]) async throws -> [Item]
    func fetchDetail(id: UUID) async throws -> Item
}

public struct SupabaseItemsFetcher: ItemsFetching {
    let pageSize: Int
    public init(pageSize: Int = 50) { self.pageSize = pageSize }

    public func fetchPage(userId: UUID, before: Date?, types: [ItemType]?, tagIds: [UUID]) async throws -> [Item] {
        // RLS scopes rows to the JWT owner; user_id filter kept for parity with web
        var query = StashClient.shared
            .from("items")
            .select(tagIds.isEmpty ? Item.listColumns : Item.listColumns + ",item_tags!inner(tag_id)")
            .eq("user_id", value: userId.uuidString)
        if let types { query = query.in("type", values: types.map(\.rawValue)) }
        if !tagIds.isEmpty { query = query.in("item_tags.tag_id", values: tagIds.map(\.uuidString)) }
        if let before {
            query = query.lt("created_at", value: ISO8601DateFormatter().string(from: before))
        }
        let data = try await query
            .order("created_at", ascending: false)
            .limit(pageSize)
            .execute().data
        return try Item.decoder.decode([Item].self, from: data)
    }

    public func fetchDetail(id: UUID) async throws -> Item {
        let data = try await StashClient.shared.from("items")
            .select(Item.detailColumns).eq("id", value: id.uuidString)
            .single().execute().data
        return try Item.decoder.decode(Item.self, from: data)
    }
}

@MainActor @Observable
public final class ItemStore {
    public private(set) var items: [Item] = []
    public private(set) var isLoading = false
    public private(set) var hasMore = true
    public var typeFilter: TypeFilter = .all
    public var selectedTagIds: [UUID] = []
    public var loadError: String?

    private let userId: UUID
    private let fetcher: ItemsFetching
    private let pageSize: Int

    public init(userId: UUID, fetcher: ItemsFetching, pageSize: Int = 50) {
        self.userId = userId
        self.fetcher = fetcher
        self.pageSize = pageSize
    }

    public func refresh() async {
        await load(reset: true)
    }

    public func loadMoreIfNeeded(current: Item) async {
        guard hasMore, !isLoading, current.id == items.last?.id else { return }
        await load(reset: false)
    }

    /// Merge a full detail fetch (with page_body) back into the list.
    public func applyDetail(_ item: Item) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) { items[idx] = item }
    }

    private func load(reset: Bool) async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        let cursor = reset ? nil : items.last?.createdAt
        do {
            let page = try await fetcher.fetchPage(userId: userId, before: cursor,
                                                   types: typeFilter.predicateTypes,
                                                   tagIds: selectedTagIds)
            if reset { items = page } else {
                let known = Set(items.map(\.id))
                items += page.filter { !known.contains($0.id) }
            }
            hasMore = page.count == pageSize
        } catch {
            loadError = "Couldn't load your stash. Pull to retry."
        }
    }
}
```

- [ ] **Step 4: Run tests** — PASS. **Step 5: Commit** — `git commit -am "feat(ios): ItemStore with cursor pagination, filters, dedupe (tested)"`

---

### Task 10: View tab — grid, cards, search, chips, tag filter

**Files:**
- Create: `ios/Stash/Library/LibraryView.swift`, `ios/Stash/Library/ItemCardView.swift`, `ios/Stash/Library/TagFilterSheet.swift`, `ios/StashKit/Sources/StashKit/TagsAPI.swift`
- Modify: `ios/Stash/MainTabView.swift` (View tab hosts `LibraryView(userId:)`)

**Interfaces:**
- Consumes: `ItemStore`, `SupabaseItemsFetcher` (Task 9), `Item.matches/thumbnailURL/isProcessingDocument` (Task 7), `SessionStore.signOut` (Task 8).
- Produces: `LibraryView` with `onSelect(Item)` hook (Task 12 presents detail from it); `StashTag: Codable` (`id: UUID, name: String, usageCount: Int` from columns `id,name,usage_count`) + `fetchTags(userId:) async throws -> [StashTag]` (ordered `usage_count desc`).

- [ ] **Step 1: Implement `TagsAPI.swift`**

```swift
import Foundation

public struct StashTag: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let usageCount: Int
    enum CodingKeys: String, CodingKey { case id, name, usageCount = "usage_count" }
}

public func fetchTags(userId: UUID) async throws -> [StashTag] {
    let data = try await StashClient.shared.from("tags")
        .select("id,name,usage_count")
        .eq("user_id", value: userId.uuidString)
        .order("usage_count", ascending: false)
        .execute().data
    return try JSONDecoder().decode([StashTag].self, from: data)
}
```

- [ ] **Step 2: Implement the views.** `LibraryView`: `.searchable` text bound to local filter (`store.items.filter { $0.matches(searchQuery: query) }` — same semantics as the web toolbar, plus a footer hint "Ask Stash searches inside pages too"); horizontal `TypeFilter` chip row driving `store.typeFilter` (+ `Task { await store.refresh() }` on change); toolbar: item count, tag-filter button (badge when active), avatar `Menu` with **Sign Out**; `LazyVGrid` (2 columns) of `ItemCardView` with `.onAppear { Task { await store.loadMoreIfNeeded(current: item) } }` on each card; `.refreshable { await store.refresh() }`; empty-state and `loadError` panes. `ItemCardView`: `AsyncImage(url: item.thumbnailURL)` top (fixed 4:3, gray placeholder, hidden when nil), type icon + title (2 lines), description (3 lines), relative date; shimmering `redacted` overlay on `item.isProcessingDocument`; yellow sticky-note corner badge when `supplementalNote` is non-nil and `isPublic`. `TagFilterSheet`: fetches via `fetchTags`, multi-select list writing `store.selectedTagIds`, Clear button. Keep every view under ~120 lines; extract subviews rather than growing files.
- [ ] **Step 3: Build, run, verify against production** with the test account — REQUIREMENTS: grid shows the account's real items; type chips narrow (server-side — watch the count change); a tag selection filters; search narrows locally; scroll to bottom pages in older items; pull-to-refresh works; sign-out returns to SignInView. Screenshot grid + filter sheet.
- [ ] **Step 4: Commit** — `git add ios && git commit -m "feat(ios): View tab — paginated grid, search, type chips, tag filter"`

---

### Task 11: Realtime enrichment updates

**Files:**
- Create: `ios/StashKit/Sources/StashKit/Debouncer.swift`, `ios/StashKit/Sources/StashKit/RealtimeObserver.swift`
- Test: `ios/StashKit/Tests/StashKitTests/DebouncerTests.swift`
- Modify: `ios/Stash/Library/LibraryView.swift` (`.task { … }` wiring)

**Interfaces:**
- Consumes: `ItemStore.refresh()` (Task 9).
- Produces: `Debouncer` (`init(interval: Duration)`, `func call(_ action: @escaping @Sendable () async -> Void)`); `RealtimeObserver` with `func observeItems(userId: UUID, onChange: @escaping @Sendable () async -> Void) async` — channel `items-changes-<userId>`, postgres_changes `*` on `public.items` filtered `user_id=eq.<userId>`, exactly the web subscription (`src/hooks/useItems.ts:114-131`), coalesced at 400 ms.

- [ ] **Step 1: Failing debouncer test**

```swift
import XCTest
@testable import StashKit

final class DebouncerTests: XCTestCase {
    func testCoalescesBurstsToOneCall() async throws {
        let counter = Counter()
        let debouncer = Debouncer(interval: .milliseconds(50))
        for _ in 0..<5 { await debouncer.call { await counter.increment() } }
        try await Task.sleep(for: .milliseconds(200))
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }
}
actor Counter { var value = 0; func increment() { value += 1 } }
```

- [ ] **Step 2: Run to verify failure**, then **Step 3: Implement**

```swift
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
```

```swift
import Foundation
import Supabase

public final class RealtimeObserver: Sendable {
    public init() {}

    /// Runs until the surrounding .task is cancelled (view disappears / sign-out).
    public func observeItems(userId: UUID, onChange: @escaping @Sendable () async -> Void) async {
        let channel = StashClient.shared.channel("items-changes-\(userId.uuidString.lowercased())")
        let changes = channel.postgresChange(AnyAction.self, schema: "public",
                                             table: "items",
                                             filter: "user_id=eq.\(userId.uuidString)")
        await channel.subscribe()
        let debouncer = Debouncer(interval: .milliseconds(400))
        for await _ in changes {
            await debouncer.call(onChange)
        }
        await channel.unsubscribe()
    }
}
```

- [ ] **Step 4: Wire into LibraryView** — `.task { await RealtimeObserver().observeItems(userId: userId) { await store.refresh() } }`. Run debouncer test → PASS.
- [ ] **Step 5: Live verify** — app open on simulator; on gostash.it (or via a `curl` PATCH to `items` with the test JWT changing a title) edit an item; the card updates within ~1–2 s without pull-to-refresh. Also verify the `add-file` E2E from Task 2 re-run makes a new card appear and then gain its description as enrichment lands — this is the marquee realtime demo. Screenshot before/after.
- [ ] **Step 6: Commit** — `git add ios && git commit -m "feat(ios): realtime items subscription with 400ms debounce (tested)"`

---

### Task 12: Item detail (read-only) + TipTap notes renderer + plan wrap

**Files:**
- Create: `ios/Stash/Detail/ItemDetailView.swift`, `ios/StashKit/Sources/StashKit/TipTapRenderer.swift`
- Test: `ios/StashKit/Tests/StashKitTests/TipTapRendererTests.swift`
- Modify: `ios/Stash/Library/LibraryView.swift` (card tap presents detail sheet)

**Interfaces:**
- Consumes: `contentTabsConfig`/`needsSourceContent` (Task 7), `SupabaseItemsFetcher.fetchDetail` + `ItemStore.applyDetail` (Task 9).
- Produces: `renderTipTap(_ raw: String?) -> AttributedString` — parses Novel/TipTap JSON (`{"type":"doc","content":[…]}`); non-JSON input passes through as plain text. Plan 2's editor builds on this file.

- [ ] **Step 1: Failing renderer tests**

```swift
import XCTest
@testable import StashKit

final class TipTapRendererTests: XCTestCase {
    func testPlainTextPassthrough() {
        XCTAssertEqual(String(renderTipTap("just text").characters), "just text")
        XCTAssertEqual(String(renderTipTap(nil).characters), "")
    }

    func testDocWithParagraphHeadingAndBullets() {
        let doc = """
        {"type":"doc","content":[
          {"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Title"}]},
          {"type":"paragraph","content":[{"type":"text","text":"Hello "},
            {"type":"text","marks":[{"type":"bold"}],"text":"bold"}]},
          {"type":"bulletList","content":[
            {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"one"}]}]},
            {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"two"}]}]}]}
        ]}
        """
        let out = String(renderTipTap(doc).characters)
        XCTAssertTrue(out.contains("Title"))
        XCTAssertTrue(out.contains("Hello bold"))
        XCTAssertTrue(out.contains("• one"))
        XCTAssertTrue(out.contains("• two"))
    }
}
```

- [ ] **Step 2: Run to verify failure**, then **Step 3: Implement**

```swift
import Foundation

/// Minimal read-only renderer for Novel/TipTap JSON stored in items.content.
/// Handles doc/paragraph/heading/bulletList/orderedList/listItem/text with
/// bold+italic marks; anything unrecognized falls back to its text content.
/// Non-JSON input (plain-text notes are valid platform-wide) passes through.
public func renderTipTap(_ raw: String?) -> AttributedString {
    guard let raw, !raw.isEmpty else { return AttributedString() }
    guard raw.hasPrefix("{"),
          let data = raw.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          root["type"] as? String == "doc"
    else { return AttributedString(raw) }

    var out = AttributedString()
    render(nodes: root["content"] as? [[String: Any]] ?? [], into: &out, listDepth: 0)
    while out.characters.last == "\n" { out.removeSubrange(out.index(beforeCharacter: out.endIndex)..<out.endIndex) }
    return out
}

private func render(nodes: [[String: Any]], into out: inout AttributedString, listDepth: Int) {
    for node in nodes {
        let type = node["type"] as? String
        let children = node["content"] as? [[String: Any]] ?? []
        switch type {
        case "text":
            var run = AttributedString(node["text"] as? String ?? "")
            let marks = (node["marks"] as? [[String: Any]] ?? []).compactMap { $0["type"] as? String }
            if marks.contains("bold") { run.inlinePresentationIntent = .stronglyEmphasized }
            if marks.contains("italic") {
                run.inlinePresentationIntent = marks.contains("bold")
                    ? [.stronglyEmphasized, .emphasized] : .emphasized
            }
            out += run
        case "heading":
            var heading = AttributedString()
            render(nodes: children, into: &heading, listDepth: listDepth)
            heading.inlinePresentationIntent = .stronglyEmphasized
            out += heading + AttributedString("\n\n")
        case "paragraph":
            render(nodes: children, into: &out, listDepth: listDepth)
            out += AttributedString(listDepth > 0 ? "\n" : "\n\n")
        case "bulletList", "orderedList":
            render(nodes: children, into: &out, listDepth: listDepth + 1)
            out += AttributedString("\n")
        case "listItem":
            out += AttributedString(String(repeating: "  ", count: max(0, listDepth - 1)) + "• ")
            render(nodes: children, into: &out, listDepth: listDepth)
        default:
            render(nodes: children, into: &out, listDepth: listDepth)
        }
    }
}
```

- [ ] **Step 4: Run tests** — PASS.
- [ ] **Step 5: Build `ItemDetailView`** — sheet presented from card tap. Header: type icon + editable-looking but read-only title, description, relative date, public badge + sticky note (yellow card, only when `isPublic` and `supplementalNote` non-nil). Hero image for image items (`AsyncImage` full width). Content section: `Picker(.segmented)` over `contentTabsConfig(for: item.type).tabs`; `.summary` → `item.summary` text or empty-state "No summary yet — generate one on the web for now"; `.original` → `item.pageBody` (monospaced-ish, scrollable) or "Nothing captured yet"; `.transcript` → `item.pageBody` or "Transcription in progress…"; `.notes` → `Text(renderTipTap(item.content))` or "No notes yet". On appear, when `needsSourceContent(item.type)` run `fetchDetail` and `store.applyDetail(_:)` to fill `pageBody`/`summary`. Link items get a "Open Link" button (`Link(destination:)`); audio playback is plan 4 (transcript still readable now).
- [ ] **Step 6: Full verification pass** — `cd ios/StashKit && swift test` (**all** suites green: Config, ItemDecoding, MessageRouting, ItemRules, ItemStore, Debouncer, TipTapRenderer); rebuild; on simulator open one real item of each available type (link/text/image/document/audio) and screenshot each detail; confirm a document mid-extraction shows the shimmer card and a "Transcription in progress…"/empty source state rather than junk.
- [ ] **Step 7: Commit** — `git add ios && git commit -m "feat(ios): read-only item detail with content tabs + TipTap notes renderer"`

---

## Self-review notes (done at authoring time)

- **Spec coverage (plan-1 slice):** add-file ✓ (T1–3), scaffold + tab order ✓ (T4), auth incl. zombie-session rule ✓ (T8), View grid/search/chips/tag-filter/pagination ✓ (T9–10), realtime ✓ (T11), detail tabs + TipTap + sticky note + processing shimmer ✓ (T12). Deliberately out (later plans, per spec): capture, edit, delete, Outbox, share ext, voice, Ask, widgets, Settings tab (sign-out lives in the View toolbar until then), audio playback, document-type E2E fixture.
- **Type consistency:** `Item.decoder` (T5) used by fetcher (T9); `ItemsFetching` signature identical in stub (T9 tests) and `SupabaseItemsFetcher`; `contentTabsConfig(for:)` consumed in T12 matches T7; `MainTabView(userId:)` change in T8 supersedes T4's argless init.
- **Known risk, accepted:** supabase-swift Realtime/PostgREST call signatures drift between minor versions — Global Constraints tells the implementer to adapt to the pinned version rather than downgrade.
- **Deliberate deviation:** Tasks 10 and 12's SwiftUI *assembly* steps are specified in exhaustive prose (every element, binding, and consumed interface named) rather than full code listings — the logic they compose is 100% code-specified and unit-tested in Tasks 5–9/12, and the deliverable is verified by on-simulator screenshots. Everything else in this plan is literal code.
