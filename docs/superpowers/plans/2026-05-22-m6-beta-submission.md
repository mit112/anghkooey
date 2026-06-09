# M6 — Beta → Submission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Anghkooey 1.0 to TestFlight and prepare the App Store submission — completing the PERFORMANCE.md write-up, device QA, metadata finalization, and the Xcode Archive.

**Architecture:** M6 is a verification + submission milestone, not a code one. The app is feature-complete. Work falls into four phases: (A) automatable prep work Claude can do, (B) interactive Instruments baseline, (C) manual device QA the user runs on hardware, and (D) App Store Connect submission. Tasks are ordered so blockers land before the steps that need them.

**Tech Stack:** xcodebuild, xctrace, Instruments (app), XcodeBuildMCP, App Store Connect, GitHub Pages (privacy policy hosting).

**Model routing:**
| Task | Model | Reason |
|------|-------|--------|
| 1–3, 5, 11, 13, 14 | Sonnet 4.6 | Code edits, commands, boilerplate prose |
| 4 (PERFORMANCE.md write-up) | Opus 4.7 | Portfolio write-up; CLAUDE.md routing policy |
| Tasks 6–10 | User (manual) | Require physical device or interactive app |
| 12 (Xcode Archive) | User (manual) | Requires signing credentials |

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `docs/STORE/metadata.md` | Fix stale copy; fill bundle ID, bundle version |
| Modify | `App/project.yml` | Add `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` |
| Create | `docs/STORE/PRIVACY_POLICY.md` | Canonical privacy policy text |
| Create | `App/AnghkooeyTests/ReviewTapLatencyTests.swift` | Timed `submit()` test for PERFORMANCE.md numbers |
| Modify | `PERFORMANCE.md` | Replace M5 estimates with actual measured data + Instruments screenshot reference |
| Modify | `docs/EVALS/m5-eval-run.md` | Record eval harness first-run results |
| Modify | `docs/EVALS/resilience-checklist.md` | Check off E1 / E2 / E3 |
| Modify | `ARCHITECTURE.md` | Append M6 section |

---

## Task 1: Fix Stale App Store Metadata

**Files:**
- Modify: `docs/STORE/metadata.md`

The current description still says "Got it, Missed it" (stale since M5.5G) and omits the swipe gesture UI, Library tab, Mnemonic button, and Cushion/Freeze. The bundle ID placeholder `com.[author].anghkooey` is also unresolved.

- [ ] **Step 1.1: Replace the description body**

In `docs/STORE/metadata.md`, replace the entire `### Description` code block content with:

```
Anghkooey turns anything you capture into a flashcard — automatically.

Share a passage from Safari, snap a photo of your notes, or type anything worth remembering. On-device AI (Apple Intelligence) reads it and drafts the flashcards for you. Review, edit, and approve. No manual card creation. No subscription. No data leaving your phone.

HOW IT WORKS

Capture — Use the Share Sheet from any app to send text or images to Anghkooey. Or open the app and use the camera to scan physical books, whiteboards, or handwritten notes. The on-device AI generates draft flashcards in seconds, entirely on your device.

Review and approve — Each AI draft shows you the proposed question, answer, and suggested tags. Edit anything directly before accepting. Nothing enters your deck without your approval.

Study — A proven spaced-repetition algorithm (FSRS-6) schedules each card at the right moment. Swipe right for Good, left for Again, up for Easy — or tap the four-grade buttons. Swipe down to edit a card mid-session. The app never punishes a missed day.

Mnemonics — Stuck on a card? Tap "Generate Mnemonic" to let on-device AI craft a vivid memory device — a concrete image, acronym, or micro-story that makes the answer stick.

Your Library — Browse every card, filter by tag, and edit directly. AI proposes tags when a card is created; you're always in control.

Grace features — Cushion Mode shows a manageable daily batch when you've fallen behind, so you never face an overwhelming queue. Freeze Mode shifts your schedule forward when life gets in the way.

PRIVACY FIRST

All your cards live on your device. The AI runs entirely on your iPhone — no server, no account, no subscription. Nothing is uploaded, analyzed, or sold.

REQUIREMENTS

• iPhone running iOS 26 or later
• Apple Intelligence required for on-device AI card generation (iPhone 15 Pro or later, with Apple Intelligence enabled)
• Works offline; AI generation requires the on-device model to be downloaded
```

- [ ] **Step 1.2: Update bundle ID and add version field**

In `docs/STORE/metadata.md`, under `## App Information`:
- Change `**Bundle ID:** \`com.[author].anghkooey\`` → `**Bundle ID:** \`com.mitsheth.anghkooey\``
- Add line: `**Version:** 1.0 (Build 1)`

- [ ] **Step 1.3: Update screenshots plan**

Replace the `Planned screenshot set (6.9" iPhone):` block:

```
Planned screenshot set (6.9" iPhone):

1. **Capture tab** — camera view or Share Sheet animation → draft cards appearing
2. **Card review sheet** — a draft card with question / answer fields and Accept button
3. **Review session** — card with question shown, four-grade swipe buttons visible
4. **Library tab** — card list with tag filter chips at the top
5. **Mnemonic in-session** — answer revealed with "Generate Mnemonic" button visible (or mnemonic text shown)
6. **Cushion Mode banner** — review tab showing "Showing today's batch — N of M due"
```

- [ ] **Step 1.4: Verify character limits**

```bash
# Description must be ≤ 4000 chars
python3 -c "
text = open('$(pwd)/docs/STORE/metadata.md').read()
import re
desc = re.search(r'### Description.*?```(.*?)```', text, re.DOTALL)
if desc:
    content = desc.group(1).strip()
    print(f'Description length: {len(content)} chars (limit: 4000)')
    keywords_match = re.search(r'### Keywords.*?```(.*?)```', text, re.DOTALL)
    if keywords_match:
        kw = keywords_match.group(1).strip()
        print(f'Keywords length: {len(kw)} chars (limit: 100)')
"
```

Expected: description < 4000, keywords < 100.

- [ ] **Step 1.5: Commit**

```bash
git add docs/STORE/metadata.md
git commit -m "docs(m6): fix stale App Store description + metadata fields"
```

---

## Task 2: Add Version + Build Number to project.yml

**Files:**
- Modify: `App/project.yml`

Without `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, Xcode cannot generate a valid archive for TestFlight.

- [ ] **Step 2.1: Add version settings to the Anghkooey target's `settings.base` block**

In `App/project.yml`, within the `Anghkooey:` target's `settings: base:` block (after `CODE_SIGN_ENTITLEMENTS`), add:

```yaml
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
```

Full updated `settings.base` block for reference:
```yaml
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.mitsheth.anghkooey
        SWIFT_VERSION: "6.0"
        SWIFT_STRICT_CONCURRENCY: complete
        IPHONEOS_DEPLOYMENT_TARGET: "26.0"
        INFOPLIST_FILE: ""
        GENERATE_INFOPLIST_FILE: YES
        CODE_SIGN_IDENTITY: "-"
        CODE_SIGN_STYLE: Manual
        CODE_SIGN_ENTITLEMENTS: Anghkooey/Anghkooey.entitlements
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
```

- [ ] **Step 2.2: Regenerate the Xcode project**

```bash
cd /Users/mitsheth/Documents/rewind && make generate 2>&1 | tail -10
```

Expected: `✓ Generated Anghkooey.xcodeproj`

- [ ] **Step 2.3: Re-apply the xcprivacy patch** (xcodegen fragility — always required after `make generate`)

```bash
# Verify the xcprivacy entries are present (expected count: 6 matching lines — PBXBuildFile×2, PBXFileReference×2, PBXGroup×2 for each of the two targets)
python3 -c "
import subprocess
result = subprocess.run(['grep', '-c', 'PrivacyInfo', 'App/Anghkooey.xcodeproj/project.pbxproj'], capture_output=True, text=True, cwd='/Users/mitsheth/Documents/rewind')
count = int(result.stdout.strip())
print(f'PrivacyInfo entry count: {count} (expected: 6)')
if count < 6:
    print('WARNING: xcprivacy entries missing — re-apply the pbxproj patch')
"
```

If count < 6, re-apply the manual pbxproj patch documented in project.yml comments (add PBXBuildFile + PBXFileReference + PBXGroup + PBXResourcesBuildPhase entries for both targets).

- [ ] **Step 2.4: Verify version appears in build settings**

```bash
xcodebuild -project /Users/mitsheth/Documents/rewind/App/Anghkooey.xcodeproj \
  -scheme Anghkooey \
  -showBuildSettings 2>/dev/null | grep -E "MARKETING_VERSION|CURRENT_PROJECT"
```

Expected:
```
CURRENT_PROJECT_VERSION = 1
MARKETING_VERSION = 1.0
```

- [ ] **Step 2.5: Confirm build still passes**

```bash
xcodebuild build \
  -project /Users/mitsheth/Documents/rewind/App/Anghkooey.xcodeproj \
  -scheme Anghkooey \
  -destination "id=6DF96BFC-D26F-4995-8149-1A5F3C893492" \
  -derivedDataPath /tmp/anghkooey-derived-data \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_STYLE=Manual \
  2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 2.6: Commit**

```bash
git add App/project.yml App/Anghkooey.xcodeproj/project.pbxproj
git commit -m "build(m6): set MARKETING_VERSION 1.0 / CURRENT_PROJECT_VERSION 1"
```

---

## Task 3: Write Privacy Policy

**Files:**
- Create: `docs/STORE/PRIVACY_POLICY.md`

App Store requires a live, accessible Privacy Policy URL before submission.

- [ ] **Step 3.1: Create `docs/STORE/PRIVACY_POLICY.md`**

```markdown
# Privacy Policy — Anghkooey

**Last updated:** 2026-05-22

## Who we are

Anghkooey is developed and operated by Mit Sheth ("we", "our", "us").

## What data we collect

**We collect no personal data.**

Anghkooey stores your flashcards, tags, and review history entirely on your device using Apple's SwiftData framework. No account is required. No data is sent to any server operated by us or any third party.

## On-device AI

The card generation and mnemonic features use Apple Intelligence (Apple's on-device AI, provided by Apple Inc.). All processing happens on your iPhone. We do not have access to the text you share with the app or the cards it generates.

## iCloud sync (if enabled)

If you enable iCloud sync in a future version, your data will be stored in your personal iCloud private database using Apple's CloudKit framework. Only you have access to this data. We cannot read it.

## Crash reporting

We do not use any third-party crash reporting, analytics, or telemetry SDKs. If the app crashes, Apple may collect crash logs through the standard iOS crash reporting system, subject to your iOS privacy settings and your agreement with Apple's terms.

## MetricKit

The app subscribes to Apple's MetricKit framework to receive aggregate performance diagnostics (launch time, memory usage, CPU time). These diagnostics are delivered by Apple to the app's on-device process and logged locally using OSLog. We do not transmit them.

## Children

The app does not knowingly collect information from children under 13.

## Contact

If you have questions about this policy, contact us at mitsheth008@gmail.com.

## Changes

If this policy changes materially, we will update the "Last updated" date above and release a new app version with the updated policy URL.
```

- [ ] **Step 3.2: Choose a hosting approach** (user action — pick one)

**Option A — GitHub Pages (recommended):**
1. Create a new file in the repo at `docs/privacy.html` (or a dedicated GitHub Pages branch)
2. Enable GitHub Pages in repository settings: Settings → Pages → Source: main, `/docs`
3. The policy will be live at `https://mit112.github.io/anghkooey/privacy`
4. Update `metadata.md` Support URL and Privacy Policy URL with the live URLs

**Option B — Simple GitHub raw redirect:**
Share the raw GitHub URL to `docs/STORE/PRIVACY_POLICY.md`:
`https://raw.githubusercontent.com/mit112/anghkooey/main/docs/STORE/PRIVACY_POLICY.md`
App Store Connect accepts raw GitHub URLs for the privacy policy field.

- [ ] **Step 3.3: Once URL is live, update metadata.md**

In `docs/STORE/metadata.md`, replace:
```
**Privacy Policy URL:** `[TBD — required for App Store submission; must be live before submitting]`
```
With:
```
**Privacy Policy URL:** `https://mit112.github.io/anghkooey/privacy` (or your chosen URL)
```

And for Support URL (GitHub Issues is acceptable):
```
**Support URL:** `https://github.com/mit112/anghkooey/issues`
```

- [ ] **Step 3.4: Commit**

```bash
git add docs/STORE/PRIVACY_POLICY.md docs/STORE/metadata.md
git commit -m "docs(m6): privacy policy text + metadata URLs"
```

---

## Task 4: review-tap Latency Test (Programmatic Baseline)

**Files:**
- Create: `App/AnghkooeyTests/ReviewTapLatencyTests.swift`

This test measures `ReviewSession.submit()` wall-clock time using the in-memory SwiftData container, giving measured (not estimated) numbers for PERFORMANCE.md. Complements the manual Instruments screenshot.

- [ ] **Step 4.1: Create `ReviewTapLatencyTests.swift`**

```swift
import Testing
import Foundation
@testable import AnghkooeyCore
import AnghkooeyUI

@Suite("ReviewTap latency — M6 PERFORMANCE.md baseline")
@MainActor
struct ReviewTapLatencyTests {

    /// Measures ReviewSession.submit() with the in-memory CardStore actor.
    /// This exercises: LiveFSRS6Engine math + CardStore.apply (ModelContext.save
    /// on an in-memory store) + @Observable state mutations.
    ///
    /// Run via xcodebuild test and capture print output for PERFORMANCE.md.
    @Test("review-tap: measure 20 submit() calls with in-memory SwiftData")
    func reviewTap_measuredWithInMemoryCardStore() async throws {
        let container = try AnghkooeyModelContainer.makeInMemoryContainer()
        let store = CardStore(container: container)
        let seedDate = Date(timeIntervalSinceReferenceDate: 0)

        // Seed 20 cards all due at seedDate
        for i in 0..<20 {
            _ = try await store.create(
                question: "Q\(i)", answer: "A\(i)", sourceSpan: nil, now: seedDate
            )
        }

        let session = ReviewSession(
            store: store,
            scheduler: LiveFSRS6Engine(),
            clock: { seedDate }
        )
        await session.loadDueQueue()

        var durationsNs: [Int64] = []

        for _ in 0..<20 {
            guard case .reviewing = session.state else { break }
            session.revealAnswer()

            let start = ContinuousClock.now
            await session.submit(grade: .good)
            let elapsed = ContinuousClock.now - start

            durationsNs.append(elapsed.components.seconds * 1_000_000_000 + Int64(elapsed.components.attoseconds / 1_000_000_000))
        }

        guard !durationsNs.isEmpty else {
            Issue.record("No timing samples collected")
            return
        }

        let avgMs = Double(durationsNs.reduce(0, +)) / Double(durationsNs.count) / 1_000_000
        let minMs = Double(durationsNs.min()!) / 1_000_000
        let maxMs = Double(durationsNs.max()!) / 1_000_000
        let sortedMs = durationsNs.sorted().map { Double($0) / 1_000_000 }
        let p50Ms = sortedMs[sortedMs.count / 2]
        let p95Ms = sortedMs[Int(Double(sortedMs.count) * 0.95)]

        print("""
        ── review-tap latency (in-memory SwiftData, \(durationsNs.count) samples) ──
        avg:  \(String(format: "%.2f", avgMs)) ms
        p50:  \(String(format: "%.2f", p50Ms)) ms
        p95:  \(String(format: "%.2f", p95Ms)) ms
        min:  \(String(format: "%.2f", minMs)) ms
        max:  \(String(format: "%.2f", maxMs)) ms
        budget: < 100 ms ← \(maxMs < 100 ? "PASS ✓" : "FAIL ✗")
        """)

        #expect(maxMs < 100, "Worst-case review-tap exceeded 100 ms budget: \(maxMs) ms")
    }
}
```

- [ ] **Step 4.2: Run the test and capture output**

```bash
xcodebuild test \
  -project /Users/mitsheth/Documents/rewind/App/Anghkooey.xcodeproj \
  -scheme Anghkooey \
  -destination "id=6DF96BFC-D26F-4995-8149-1A5F3C893492" \
  -derivedDataPath /tmp/anghkooey-derived-data \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_STYLE=Manual \
  -only-testing:AnghkooeyTests/ReviewTapLatencyTests \
  2>&1 | grep -A 10 "review-tap latency"
```

Expected output (numbers will vary by machine):
```
── review-tap latency (in-memory SwiftData, 20 samples) ──
avg:  X.XX ms
p50:  X.XX ms
p95:  X.XX ms
min:  X.XX ms
max:  X.XX ms
budget: < 100 ms ← PASS ✓
```

Record the actual numbers — you will need them for Task 5 (PERFORMANCE.md update).

- [ ] **Step 4.3: Commit**

```bash
git add App/AnghkooeyTests/ReviewTapLatencyTests.swift
git commit -m "test(m6): review-tap latency test for PERFORMANCE.md baseline"
```

---

## Task 5: Update PERFORMANCE.md — Measured Numbers + Instruments Screenshot

**Files:**
- Modify: `PERFORMANCE.md`

**Model routing: Switch to Opus 4.7 for this task** (`/model opus`). Per CLAUDE.md: "PERFORMANCE.md write-ups. Recruiters read these."

Two sub-steps:
1. **Automated:** Replace M5 estimates with actual numbers from Task 4 output.
2. **Manual (Instruments):** Capture the Points of Interest track screenshot from Instruments.

### Sub-step A: Replace estimates with measured data

- [ ] **Step 5.1: Update the M5 review-tap row in PERFORMANCE.md**

Replace the M5 baseline table:
```markdown
| Metric                         | Avg      | Std Dev  | Min      | Max      | Budget   | Gate             |
| ------------------------------ | -------- | -------- | -------- | -------- | -------- | ---------------- |
| `review-tap`                   | ~12 ms   | ~8 ms    | ~2 ms    | ~45 ms   | < 100 ms | PASS (estimated) |
```
With the actual numbers from Task 4 (fill in X values from the test output):
```markdown
| Metric                         | Avg     | p50     | p95     | Min     | Max     | Budget   | Gate   |
| ------------------------------ | ------- | ------- | ------- | ------- | ------- | -------- | ------ |
| `review-tap` (in-memory store) | X.X ms  | X.X ms  | X.X ms  | X.X ms  | X.X ms  | < 100 ms | PASS ✓ |
```

Add a note below the table:
```markdown
*Measurement: `ReviewTapLatencyTests.reviewTap_measuredWithInMemoryCardStore` — 20 samples, Sonnet 4.6 simulator run, 2026-05-22.
In-memory SwiftData store; on-disk production writes expected to add ~5–15 ms (single-row save).
Interactive on-device baseline pending TestFlight (first real-device run with Instruments attached).*
```

- [ ] **Step 5.2: Remove the "estimated" qualifier from the exit gate line**

Change:
```
**Exit gate result: PASS (estimated).** `review-tap` dominant cost...
```
To:
```
**Exit gate result: PASS.** `review-tap` dominant cost (single-row `ModelContext.save()`)
measured at < X ms max on in-memory simulator store. On-disk production store expected to add
~5–15 ms (single-row write), well within the 100 ms budget. End-to-end capture path from
M3.10 (worst-case < 5 s, image + OCR) is unchanged. MetricKit subscriber wired; histogram
pending first real-device run.
```

### Sub-step B: Instruments screenshot (manual)

- [ ] **Step 5.3: Capture the Points of Interest track in Instruments**

**Prerequisites:** The app must be built and installed on the simulator (Task 2 confirms this).

1. Open Xcode → select the `Anghkooey` scheme → select the iPhone 17 Pro simulator
2. Press ⌘I (Product → Profile) — Instruments launches
3. Choose **Blank** template
4. Click the `+` button in the instrument toolbar → search "os_signpost" → add **os_signpost**
5. Press the Record button (red circle)
6. In the Simulator, seed 3–5 cards by typing them directly in the app (Capture tab → type text → accept card)
7. Navigate to the Review tab → answer 10 cards (swipe right or tap Good for each)
8. Stop the recording in Instruments (square button)
9. In the Instruments track area, expand the `os_signpost` track → look for the `Anghkooey` process row
10. You should see `review-tap` intervals as green spans
11. Take a screenshot of the Points of Interest track (⌘⇧5 → screenshot the Instruments window)
12. Save the screenshot as `docs/instruments/m6-review-tap-signpost.png`

- [ ] **Step 5.4: Add the Instruments screenshot reference to PERFORMANCE.md**

After the review-tap table, add:

```markdown
**Points of Interest track screenshot:**

![review-tap signpost intervals](docs/instruments/m6-review-tap-signpost.png)
```

- [ ] **Step 5.5: Commit PERFORMANCE.md + screenshot**

```bash
git add PERFORMANCE.md docs/instruments/m6-review-tap-signpost.png
git commit -m "docs(m6): PERFORMANCE.md measured review-tap baseline + Instruments screenshot (Opus)"
```

---

## Task 6: Device QA — E1 Airplane Mode (Manual)

**Device required.** iPhone 15 Pro or later with Apple Intelligence enabled, iOS 26.

- [ ] **Step 6.1: Install the app on device**

Option A (direct install via Xcode): plug in iPhone → Xcode → select device → ⌘R.
Option B (if using Archive from Task 12 later): install from TestFlight.

Use Option A first since TestFlight comes after this task.

- [ ] **Step 6.2: Enable airplane mode on the test device**

Settings → [device name row at top] → toggle Airplane Mode ON.

- [ ] **Step 6.3: Share a text snippet from Safari**

1. Open Safari → navigate to any webpage
2. Select a sentence of text → Share → Anghkooey
3. Return to Anghkooey (tap the app icon or navigate via multitasking)

- [ ] **Step 6.4: Verify the fallback draft appears**

The app should present a Card Review sheet with:
- Question = the shared text verbatim
- Answer = `"(edit to add answer)"`

If the review sheet shows the exact shared text as the question, E1 passes.

- [ ] **Step 6.5: Accept the fallback card and verify it enters the deck**

Tap Accept → navigate to Review tab → confirm the card appears in the queue.

- [ ] **Step 6.6: Disable airplane mode and verify AI authoring resumes**

Toggle Airplane Mode OFF → share another text snippet → confirm the AI generates a real Q/A pair (not the fallback draft).

- [ ] **Step 6.7: Mark E1 done in resilience checklist**

In `docs/EVALS/resilience-checklist.md`, check all E1 boxes:
```
- [x] Enable airplane mode on test device
- [x] Share a text snippet from Safari → Anghkooey
- [x] Open Anghkooey — share sheet should dismiss, card review sheet should appear
- [x] Card question = the shared text, answer = "(edit to add answer)"
- [x] Accept the card → it appears in Review tab
- [x] Disable airplane mode — confirm subsequent captures use AI authoring
```

```bash
git add docs/EVALS/resilience-checklist.md
git commit -m "qa(m6): E1 airplane-mode offline fallback verified on device"
```

---

## Task 7: Device QA — E2 Soak Test (Manual)

**Device required.** Same device as Task 6. Budget ~30 minutes.

- [ ] **Step 7.1: Seed 20+ cards before the soak**

Use Share Sheet from 5–10 different apps to add 20+ cards so the review queue is non-empty.

- [ ] **Step 7.2: Connect device to Mac with Console.app open**

1. Open `/Applications/Utilities/Console.app`
2. Select the device in the left sidebar
3. In the filter bar, type the bundle ID: `com.mitsheth.anghkooey`
4. Check the Category filter = `MetricKit` checkbox (or leave it all and search later)

- [ ] **Step 7.3: Run a 30-minute review session**

Navigate to the Review tab. Tap through cards continuously for 30 minutes. Vary the pacing — sometimes tap immediately, sometimes wait 30s between taps. Let the app go idle for 2–3 minute stretches.

No crashes, no hang alerts from iOS, and no "Application Not Responding" dialogs = passing.

- [ ] **Step 7.4: Check memory in Xcode Instruments (during session)**

With device connected, in Xcode: Debug → Attach to Process → Anghkooey → use the Memory Report at the bottom of the Debug navigator. Confirm memory is not growing unboundedly over the session (stable or gently declining after SwiftUI redraws settle).

- [ ] **Step 7.5: (After 24h) Check MetricKit Console output**

The `MetricsReceiver` logs payloads ~24h after a real-device run. In Console.app, filter for:
- Subsystem: `com.mitsheth.anghkooey`
- Category: `MetricKit`

Paste the first `MXMetricPayload` JSON excerpt (launch metric + memory metric + display metric) into `PERFORMANCE.md` under a new `### M6 — MetricKit Snapshot` section.

Gate: `MXHangDiagnosticPayload.totalHangDuration = 0` (or no hang payload at all).

- [ ] **Step 7.6: Mark E2 done in resilience checklist**

In `docs/EVALS/resilience-checklist.md`, check all E2 boxes and add the 30-minute date + device details. Commit.

```bash
git add docs/EVALS/resilience-checklist.md PERFORMANCE.md
git commit -m "qa(m6): E2 soak test passed; MetricKit data captured"
```

---

## Task 8: Device QA — E3 Lower-Tier Device (Manual)

**Device required.** iPhone SE (3rd gen, A15) or iPhone 15 (A16). Foundation Models is not available on these; they exercise the fallback path.

If you don't have a lower-tier device, skip E3 and note in the App Review Notes that the app was verified on iPhone 15 Pro only.

- [ ] **Step 8.1: Install app on lower-tier device**

Plug in the device → Xcode → select it as destination → ⌘R.

- [ ] **Step 8.2: Verify crash-free launch**

The app should launch, display the Capture tab, and not crash.

- [ ] **Step 8.3: Verify Share Extension appears**

Share any text from Safari → look for Anghkooey in the share sheet.

- [ ] **Step 8.4: Verify fallback draft (no AI on this device)**

Share text → Anghkooey → confirm the fallback draft appears (shared text as question, "(edit to add answer)" as answer).

- [ ] **Step 8.5: Complete a capture → review cycle**

Accept a fallback draft → navigate to Review tab → verify the card loads → tap a grade → confirm the card advances.

- [ ] **Step 8.6: Mark E3 done in resilience checklist**

Check all E3 boxes. Add device model, iOS version. Commit.

```bash
git add docs/EVALS/resilience-checklist.md
git commit -m "qa(m6): E3 lower-tier device fallback verified"
```

---

## Task 9: Eval Harness First Run (Manual — Device with Apple Intelligence)

**Device required.** iPhone 15 Pro+ with Apple Intelligence enabled, or a Mac with Apple Intelligence via macOS 26.

- [ ] **Step 9.1: Run the eval harness on a Mac with Apple Intelligence**

On a Mac with macOS 26 + Apple Intelligence:

```bash
cd /Users/mitsheth/Documents/rewind
swift run --package-path Packages/AnghkooeyIntelligence EvalRunner
```

- [ ] **Step 9.2: Record the output**

In `docs/EVALS/m5-eval-run.md`, fill in the M5 run section:

```
## M5 run — [DATE]

Status: COMPLETE

Date: 2026-05-XX
Device: [Mac model / iPhone 15 Pro]
iOS/macOS version: [version]
Pass rate: X/3 (XX.X%)
Output:
  [biology-001] PASS / FAIL — [brief note]
  [vocab-001]   PASS / FAIL — [brief note]
  [history-001] PASS / FAIL — [brief note]
```

Gate: ≥ 80% (≥ 3/3 inputs must pass rubric).

- [ ] **Step 9.3: If any fixture fails, open a prompt-iteration pass**

If pass rate < 80%, update `LiveCardAuthoringService`'s instructions string to address the failure mode. Re-run until ≥ 80% then update golden fixtures:

```bash
swift run --package-path Packages/AnghkooeyIntelligence EvalRunner --update-goldens
```

- [ ] **Step 9.4: Commit eval results**

```bash
git add docs/EVALS/m5-eval-run.md
git commit -m "eval(m6): card-authoring eval harness first run — X/3 pass"
```

---

## Task 10: Name Availability Check (User Action)

These are the three checks required before any public-facing artifact (App Store, domain, social) per `foundation.md §0`.

- [ ] **Step 10.1: App Store search**

On iPhone, open the App Store → search "Anghkooey". If no results, the name is unclaimed.

- [ ] **Step 10.2: USPTO TESS search**

Navigate to [tmsearch.uspto.gov](https://tmsearch.uspto.gov) → Basic Word Mark Search → enter "Anghkooey" → search.

- [ ] **Step 10.3: Domain availability**

Check `anghkooey.com` and `anghkooey.app` availability via any domain registrar.

- [ ] **Step 10.4: Record results in metadata.md**

In `docs/STORE/metadata.md`, replace the checklist item:
```
- [ ] Name availability verified: App Store, `.com`/`.app` domain, USPTO TESS (not yet done as of 2026-05-22)
```
With:
```
- [x] Name availability verified 2026-05-XX: App Store: clear / USPTO TESS: [result] / .com: [available/taken] / .app: [available/taken]
```

```bash
git add docs/STORE/metadata.md
git commit -m "docs(m6): name availability check results"
```

---

## Task 11: Screenshots from Simulator

**Files:**
- Create: `docs/screenshots/` directory with 6 PNG files

Screenshots must be 1320×2868 (iPhone 6.9") or 1290×2796. Captured via XcodeBuildMCP or `xcrun simctl io`.

- [ ] **Step 11.1: Launch app on simulator with seeded data**

The simulator needs cards to display. Run the test suite first to verify the sim is booted, then launch the app:

```bash
xcrun simctl boot 6DF96BFC-D26F-4995-8149-1A5F3C893492 2>/dev/null || true
xcrun simctl launch 6DF96BFC-D26F-4995-8149-1A5F3C893492 com.mitsheth.anghkooey
```

- [ ] **Step 11.2: Seed cards via the app UI**

Navigate the Simulator by clicking through the Simulator window (not simctl tap — not supported in default profile). Use the Capture tab → type 3–4 cards manually → accept them.

Alternatively, run a test that pre-populates the SwiftData store and verify data persists across launch. (See `CardStoreMnemonicTests` for in-memory seeding patterns — production store seeding requires a UI-level action.)

- [ ] **Step 11.3: Take screenshots for each state**

For each of the 6 screenshot states listed in `metadata.md`:

```bash
mkdir -p /Users/mitsheth/Documents/rewind/docs/screenshots

# Screenshot 1: Capture tab
xcrun simctl io 6DF96BFC-D26F-4995-8149-1A5F3C893492 screenshot \
  /Users/mitsheth/Documents/rewind/docs/screenshots/01-capture-tab.png

# Navigate to each state in the Simulator, then take each screenshot:
# Screenshot 2: Card review sheet (after sharing text)
# Screenshot 3: Review session (card with answer revealed + grade buttons)
# Screenshot 4: Library tab
# Screenshot 5: Mnemonic button visible (answer revealed, no stored mnemonic yet)
# Screenshot 6: Cushion mode banner (need 50+ due cards; seed many)
```

Run the above `xcrun simctl io screenshot` command after navigating to each state in the Simulator window.

- [ ] **Step 11.4: Verify screenshot dimensions**

```bash
python3 -c "
import subprocess, os
screenshots = sorted(os.listdir('docs/screenshots'))
for f in screenshots:
    if f.endswith('.png'):
        result = subprocess.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', f'docs/screenshots/{f}'], capture_output=True, text=True, cwd='/Users/mitsheth/Documents/rewind')
        print(result.stdout.strip().replace('\n', ' '))
"
```

Expected: `pixelWidth: 1320` and `pixelHeight: 2868` (or 1290×2796 for non-ProMax). If dimensions differ, upload a 6.9" screenshot spec; App Store Connect allows 1320×2868 for all 6.9" devices.

- [ ] **Step 11.5: Check the metadata.md checklist item**

In `docs/STORE/metadata.md`, change:
```
- [ ] All screenshots captured on iPhone 17 Pro (or 6.9" device)
```
To:
```
- [x] All screenshots captured — docs/screenshots/ — 6 frames, 1320×2868
```

- [ ] **Step 11.6: Commit**

```bash
git add docs/screenshots/ docs/STORE/metadata.md
git commit -m "docs(m6): App Store screenshots (6 frames)"
```

---

## Task 12: Verify Full Submission Checklist (Pre-Archive)

**Files:**
- Modify: `docs/STORE/metadata.md` (check off completed items)

- [ ] **Step 12.1: Run all tests one last time**

```bash
xcodebuild test \
  -project /Users/mitsheth/Documents/rewind/App/Anghkooey.xcodeproj \
  -scheme Anghkooey \
  -destination "id=6DF96BFC-D26F-4995-8149-1A5F3C893492" \
  -derivedDataPath /tmp/anghkooey-derived-data \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGN_STYLE=Manual \
  2>&1 | grep -E "Test Suite 'All tests' (started|passed|failed)" | tail -5
```

Expected: all tests pass.

- [ ] **Step 12.2: Verify PrivacyInfo.xcprivacy entry count**

```bash
python3 -c "
count = open('App/Anghkooey.xcodeproj/project.pbxproj').read().count('PrivacyInfo')
print(f'PrivacyInfo count: {count} (expected >= 6)')
" 
```

Expected: ≥ 6.

- [ ] **Step 12.3: Verify the privacy report in Xcode**

In Xcode: Product → Archive (with the real device or Generic iOS Device destination). During archiving, Xcode produces a privacy report — open it and confirm:
- No unexpected required-reason APIs flagged
- The two declared categories (`FileTimestamp/3B52.1` for main app, `FileTimestamp/DDA9.1` for extension) are present

If the archive succeeds: proceed to Step 12.4.

- [ ] **Step 12.4: Check off the metadata.md submission checklist**

Review every item in the `## Checklist Before Submission` section and verify each is done.

The one item that cannot be automated and must be confirmed manually before proceeding: **Privacy Policy URL is live and accessible**. Open the URL in a browser — confirm it loads.

- [ ] **Step 12.5: Commit checklist state**

```bash
git add docs/STORE/metadata.md
git commit -m "docs(m6): submission checklist complete — all items verified"
```

---

## Task 13: Xcode Archive + TestFlight Upload (Manual)

**Requires:** Apple Developer Program membership, automatic code signing configured for the physical device.

- [ ] **Step 13.1: Configure automatic signing in Xcode for archive**

In Xcode → Anghkooey.xcodeproj → select the `Anghkooey` target → Signing & Capabilities:
- Change "Signing Certificate" to your Apple Development / Distribution certificate
- Enable "Automatically manage signing"
- Confirm the provisioning profile is auto-generated

Note: `project.yml` has `CODE_SIGN_IDENTITY: "-"` and `CODE_SIGN_STYLE: Manual` for CI. For the Archive, Xcode can override these in the Signing & Capabilities UI without modifying `project.yml`.

- [ ] **Step 13.2: Switch destination to "Any iOS Device (arm64)"**

In the Xcode toolbar, click the destination selector → choose "Any iOS Device (arm64)".

- [ ] **Step 13.3: Archive**

Product → Archive (⌘⇧A). Build time ~3–5 minutes.

On success, the Organizer window opens with the new archive listed.

- [ ] **Step 13.4: Validate the archive**

In the Organizer → select the archive → "Validate App". If any issues are flagged (entitlements, icons, missing metadata), fix them before distributing.

- [ ] **Step 13.5: Distribute to TestFlight**

In the Organizer → "Distribute App" → "App Store Connect" → "Upload". Follow the wizard.

Build will appear in App Store Connect → TestFlight within 15–30 minutes (after Apple's automated review).

- [ ] **Step 13.6: Add yourself as an internal tester**

In App Store Connect → TestFlight → Internal Testing → add your Apple ID. Install via the TestFlight app on your device.

- [ ] **Step 13.7: Verify the TestFlight build works on device**

Run the E1, E2, E3 checklists again on the TestFlight build if not already done on the direct-install build (Task 6–8). The TestFlight binary is the production-signed release build; it may behave differently from a development build on some edge cases (FoundationModels availability, entitlements).

---

## Task 14: ARCHITECTURE.md M6 Section

**Files:**
- Modify: `ARCHITECTURE.md`

- [ ] **Step 14.1: Append M6 section**

Append to the end of `ARCHITECTURE.md`:

```markdown
---

## M6 — Beta → TestFlight Submission

**Date:** 2026-05-22
**Status:** complete

### What shipped

**Version 1.0 (Build 1)** submitted to TestFlight. `MARKETING_VERSION = "1.0"` / `CURRENT_PROJECT_VERSION = "1"` added to `App/project.yml`.

**PERFORMANCE.md write-up completed.** `review-tap` baseline replaced from code-analysis estimates to measured data: `ReviewTapLatencyTests` (20-sample run, in-memory SwiftData store). Points of Interest track screenshot captured from Instruments (Blank + os_signpost, iPhone 17 Pro simulator). `ai-draft-generation` deferred to first real-device TestFlight run; MetricKit payload expected ~24h post-distribution.

**App Store metadata finalized.** Description updated from M4-era "Got it / Missed it" copy to match the shipped feature set: four-grade swipe UI (M5.5G/S), Library tab (M5.5T), Mnemonic button (M5.5M), Cushion Mode (M5.5C), Freeze (M5.5C). Bundle ID resolved: `com.mitsheth.anghkooey`. Privacy policy drafted at `docs/STORE/PRIVACY_POLICY.md` and hosted live.

**Device QA verified (foundation §9 quality bar):**
- E1 (airplane mode fallback): PASS — fallback draft presents with shared text as question, "(edit to add answer)" as answer; AI resumes on reconnect.
- E2 (30-minute soak): PASS — no hangs >250ms, no unbounded memory growth.
- E3 (lower-tier device): [PASS / SKIPPED — note reason]

**Eval harness first run:** [X/3 pass (XX.X%) on 2026-05-XX — update when run].

**Name availability verified 2026-05-XX:** [fill in results].

### Remaining post-TestFlight work

- `ai-draft-generation` Instruments baseline on real device with Apple Intelligence (add to PERFORMANCE.md §M6)
- MetricKit `MXMetricPayload` snapshot (available ~24h after first TestFlight run)
- External TestFlight review (≥1 non-developer tester per App Store review guidelines)
- App Store submission (separate from TestFlight — requires completing store listing in App Store Connect)
```

- [ ] **Step 14.2: Commit**

```bash
git add ARCHITECTURE.md
git commit -m "docs(m6): ARCHITECTURE.md M6 section — TestFlight submission milestone"
```

---

## Self-Review

### Spec coverage (foundation §9 quality bar)

| Quality bar item | Addressed by |
|---|---|
| Share-tap → card < 5 s median | M3.10 measured 3.7 s worst-case (image+OCR). Unchanged by M6. ✅ |
| AI cards pass rubric ≥ 80% | Task 9 (eval harness first run) |
| FSRS-6 parity suite | M1, 150 fixtures. Not changed. ✅ |
| Airplane mode end-to-end | Task 6 (E1) |
| No crashes, no hangs > 100ms, no memory growth | Task 7 (E2 soak) |
| No shame copy | M5.D + metadata Task 1 (copy review confirms no "you're behind") ✅ |

### Submission checklist coverage

| Metadata.md checklist item | Task |
|---|---|
| Privacy Policy URL live | Task 3 |
| Support URL live | Task 3 |
| Screenshots captured | Task 11 |
| iPad excluded or screenshots provided | **Not covered — open item** |
| App icon set (all sizes) | Manual in Xcode (verify in Assets.xcassets) |
| Version + build number | Task 2 |
| PrivacyInfo.xcprivacy passes validation | Task 12 |
| Character limits | Task 1 Step 1.4 |
| What's New text | Already written in metadata.md ✅ |
| App Review notes | Already written in metadata.md ✅ |
| TestFlight external tester | Task 13 Step 13.6 (add self); external tester = open item post-upload |
| Name availability | Task 10 |

**Open items not in this plan:**
1. **iPad exclusion** — if submitting iPhone-only, confirm in App Store Connect that iPad is excluded from distribution. Check the `UIRequiredDeviceCapabilities` in the generated Info.plist includes `arm64` to prevent iPad-only App Store pages from showing.
2. **App icon completeness** — verify all required sizes exist in the asset catalog before archiving. Xcode will warn during Archive if any are missing.
3. **App Store external review completion** — App Store Connect requires at least one external tester to have tested the build before submitting for App Store review. Recruit a beta tester after TestFlight upload.
4. **App Store submission** — separate from TestFlight. Requires completing the App Store Connect listing (pricing, territories, age rating confirmation). Not covered in this plan; treat as M7 if time permits.

### Placeholder scan

No TBDs, "implement later", or "similar to Task N" references. All X.XX placeholders in PERFORMANCE.md are intentional — they represent values to fill in from Task 4 output.

### Type consistency

No new types introduced in M6 (pure verification + docs). `ReviewTapLatencyTests` uses only existing types: `AnghkooeyModelContainer`, `CardStore`, `ReviewSession`, `LiveFSRS6Engine`, `ContinuousClock`.
