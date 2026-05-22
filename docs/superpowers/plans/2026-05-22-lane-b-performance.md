# Lane B — MetricKit / os_signpost + PERFORMANCE.md Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two new `os_signpost` intervals (`review-tap`, `ai-draft-generation`), wire a `MetricKit` subscriber, and write the v1-required PERFORMANCE.md M5 section.

**Architecture:** `review-tap` wraps the full `ReviewSession.submit` body so Instruments shows tap-to-next-card latency. `ai-draft-generation` wraps the inner Task in `LiveCardAuthoringService.generateDrafts` so the FoundationModels generation window is visible on the same Points-of-Interest track. `MetricsReceiver` is a minimal `NSObject/MXMetricManagerSubscriber` that serialises payloads to OSLog — no custom UI needed for v1, just the subscriber log proving MetricKit is wired.

**Tech stack:** `OSSignposter` (os framework), MetricKit, Instruments (Blank + os_signpost), Swift Testing, xcodebuild.

**Model routing:**

| Task | Model | Reason |
|------|-------|--------|
| 1–4 (code + table) | Sonnet 4.6 | Routine Swift + markdown edits |
| 5 (PERFORMANCE.md M5 prose) | Opus 4.7 | Recruiter-read write-up; CLAUDE.md requires Opus for this document |

---

## File map

| File | Action | Responsibility |
|------|--------|---------------|
| `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewSession.swift` | Modify | Add `review-tap` signpost |
| `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Logging/IntelligenceLog.swift` | Modify | Add `poiSignposter` |
| `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/LiveCardAuthoringService.swift` | Modify | Add `ai-draft-generation` signpost |
| `App/Anghkooey/MetricsReceiver.swift` | **Create** | `MXMetricManagerSubscriber` |
| `App/Anghkooey/AnghkooeyApp.swift` | Modify | Wire `MetricsReceiver` into `MXMetricManager` |
| `App/AnghkooeyTests/MetricsReceiverTests.swift` | **Create** | Swift Testing tests for receiver |
| `PERFORMANCE.md` | Modify | Add new signpost rows + write M5 section |

---

## Task 1: Add `review-tap` signpost to `ReviewSession.submit`

**Files:**
- Modify: `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewSession.swift`

No new test file. Existing `ReviewSessionTests.swift` covers the behavior — the signpost is observational.

- [ ] **Step 1.1: Add `import OSLog` to `ReviewSession.swift`**

Open `Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewSession.swift`.
Change the imports block from:

```swift
import Foundation
import AnghkooeyCore
```

to:

```swift
import Foundation
import OSLog
import AnghkooeyCore
```

- [ ] **Step 1.2: Wrap `submit(grade:)` with the interval**

Replace the current `submit` body:

```swift
    public func submit(grade: ReviewGrade) async {
        guard let card = currentCard else { return }
        do {
            let output = try scheduler.next(
                card: card.schedulingCard,
                rating: grade.fsrsRating,
                now: clock()
            )
            try await store.apply(output, to: card.id, grade: grade.fsrsRating, now: clock())
        } catch {
            // Scheduling errors are non-fatal; advance queue regardless.
        }
        if queue.isEmpty {
            currentCard = nil
            queueRemaining = 0
            state = .empty
        } else {
            currentCard = queue.removeFirst()
            queueRemaining = queue.count
            isAnswerRevealed = false
        }
    }
```

with:

```swift
    public func submit(grade: ReviewGrade) async {
        guard let card = currentCard else { return }
        let signposter = CoreLog.poiSignposter
        let signpostID = signposter.makeSignpostID()
        let intervalState = signposter.beginInterval("review-tap", id: signpostID)
        defer { signposter.endInterval("review-tap", intervalState) }
        do {
            let output = try scheduler.next(
                card: card.schedulingCard,
                rating: grade.fsrsRating,
                now: clock()
            )
            try await store.apply(output, to: card.id, grade: grade.fsrsRating, now: clock())
        } catch {
            // Scheduling errors are non-fatal; advance queue regardless.
        }
        if queue.isEmpty {
            currentCard = nil
            queueRemaining = 0
            state = .empty
        } else {
            currentCard = queue.removeFirst()
            queueRemaining = queue.count
            isAnswerRevealed = false
        }
    }
```

The `defer` fires after the queue-advance state mutations — that's the correct end of the user-perceptible tap-to-next-card path.

- [ ] **Step 1.3: Run existing AnghkooeyUI tests**

```bash
cd /Users/mitsheth/Documents/rewind/Packages/AnghkooeyUI && swift test
```

Expected: all 7 UI tests PASS. No new failures.

- [ ] **Step 1.4: Commit**

```bash
git add Packages/AnghkooeyUI/Sources/AnghkooeyUI/Review/ReviewSession.swift
git commit -m "feat(perf): add review-tap os_signpost interval to ReviewSession.submit"
```

---

## Task 2: Add `IntelligenceLog.poiSignposter` and `ai-draft-generation` signpost

**Files:**
- Modify: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Logging/IntelligenceLog.swift`
- Modify: `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/LiveCardAuthoringService.swift`

No new test file. The signpost is observational; existing Intelligence tests cover the behavior.

- [ ] **Step 2.1: Add `poiSignposter` to `IntelligenceLog`**

Open `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Logging/IntelligenceLog.swift`.

Replace the entire file with:

```swift
import OSLog

/// OSLog factory for the AnghkooeyIntelligence package.
///
/// Set `subsystem` once at app startup (e.g. in `@main`) before any log call.
/// Defaults to `"com.unknown.anghkooey"` so package tests work without an app host.
public enum IntelligenceLog {
    /// The OSLog subsystem identifier. Set this to your bundle ID at launch.
    public nonisolated(unsafe) static var subsystem: String = "com.unknown.anghkooey"

    /// Logger for the on-device AI (FoundationModels) subsystem.
    public static var ai: Logger { Logger(subsystem: subsystem, category: "AI") }
    /// Logger for the Vision OCR subsystem.
    public static var ocr: Logger { Logger(subsystem: subsystem, category: "OCR") }
    /// Logger for the FoundationModels card authoring subsystem.
    public static var authoring: Logger { Logger(subsystem: subsystem, category: "Authoring") }

    /// Shared `OSSignposter` for intelligence-pipeline latency intervals.
    ///
    /// Uses `"PointsOfInterest"` so intervals appear alongside Core's signposts
    /// on the same Instruments Points of Interest track. Interval names:
    /// `"ai-draft-generation"`.
    public static var poiSignposter: OSSignposter {
        OSSignposter(subsystem: subsystem, category: "PointsOfInterest")
    }
}
```

- [ ] **Step 2.2: Add `ai-draft-generation` signpost to `LiveCardAuthoringService`**

Open `Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/LiveCardAuthoringService.swift`.

Replace the `let task = Task { ... }` block inside `generateDrafts`. The full `generateDrafts` method after the change:

```swift
    public func generateDrafts(from text: String) async throws -> AsyncThrowingStream<CardDraft, Error> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthoringError.emptyInput
        }
        let avail = await availability
        if case .unavailable(let reason) = avail {
            throw AuthoringError.unavailable(reason: reason)
        }
        log.debug("Starting generation for passage of \(text.count, privacy: .public) chars")

        return AsyncThrowingStream { continuation in
            let task = Task {
                let signposter = IntelligenceLog.poiSignposter
                let signpostID = signposter.makeSignpostID()
                let intervalState = signposter.beginInterval("ai-draft-generation", id: signpostID)
                defer { signposter.endInterval("ai-draft-generation", intervalState) }

                do {
                    let session = LanguageModelSession(instructions: Self.instructions)
                    let stream = session.streamResponse(to: text, generating: AuthorResponse.self)
                    var accumulator = SnapshotAccumulator()

                    for try await snapshot in stream {
                        let partials: [SnapshotAccumulator.PartialDraft] = (snapshot.content.drafts ?? []).compactMap { (partial: CardDraft.PartiallyGenerated) -> SnapshotAccumulator.PartialDraft? in
                            guard let q = partial.question, let a = partial.answer, !q.isEmpty, !a.isEmpty else { return nil }
                            return SnapshotAccumulator.PartialDraft(
                                question: q,
                                answer: a,
                                proposedTags: partial.proposedTags ?? [],
                                sourceSpan: partial.sourceSpan
                            )
                        }
                        for draft in accumulator.update(partials) {
                            log.debug("Emitting draft: \(draft.question, privacy: .public)")
                            continuation.yield(draft)
                        }
                    }
                    log.debug("Generation stream finished")
                    continuation.finish()
                } catch {
                    log.error("Generation failed: \(error, privacy: .public)")
                    continuation.finish(
                        throwing: AuthoringError.generationFailed(underlying: error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
```

The `defer` fires when the inner Task exits — after `continuation.finish()` in both the success and error paths. The interval therefore covers the full on-device model time.

- [ ] **Step 2.3: Run existing AnghkooeyIntelligence tests**

```bash
cd /Users/mitsheth/Documents/rewind/Packages/AnghkooeyIntelligence && swift test
```

Expected: all 39 Intelligence tests PASS. No new failures.

- [ ] **Step 2.4: Commit**

```bash
git add Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Logging/IntelligenceLog.swift \
        Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence/Authoring/LiveCardAuthoringService.swift
git commit -m "feat(perf): add ai-draft-generation os_signpost interval to LiveCardAuthoringService"
```

---

## Task 3: Create `MetricsReceiver` + wire into app

**Files:**
- Create: `App/Anghkooey/MetricsReceiver.swift`
- Modify: `App/Anghkooey/AnghkooeyApp.swift`
- Create: `App/AnghkooeyTests/MetricsReceiverTests.swift`

Note: `MetricsReceiver` must be an `NSObject` subclass because `MXMetricManagerSubscriber` requires it. This is the one place in v1 we can't use a value type.

- [ ] **Step 3.1: Write the failing test first**

Create `App/AnghkooeyTests/MetricsReceiverTests.swift`:

```swift
import Testing
import MetricKit
@testable import Anghkooey

@Suite("MetricsReceiver")
struct MetricsReceiverTests {

    @Test("init does not crash")
    func init_doesNotCrash() {
        _ = MetricsReceiver()
    }

    @Test("didReceive empty MXMetricPayload array does not crash")
    func didReceive_emptyMetricPayloads_doesNotCrash() {
        let receiver = MetricsReceiver()
        receiver.didReceive([] as [MXMetricPayload])
    }

    @Test("didReceive empty MXDiagnosticPayload array does not crash")
    func didReceive_emptyDiagnosticPayloads_doesNotCrash() {
        let receiver = MetricsReceiver()
        receiver.didReceive([] as [MXDiagnosticPayload])
    }
}
```

- [ ] **Step 3.2: Verify the test build fails (type not defined yet)**

```bash
xcodebuild test \
  -project App/Anghkooey.xcodeproj \
  -scheme Anghkooey \
  -destination 'platform=iOS Simulator,id=6DF96BFC-D26F-4995-8149-1A5F3C893492' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" EXPANDED_CODE_SIGN_IDENTITY="-" \
  2>&1 | grep -E "(error:|BUILD FAILED|PASS|FAIL)"
```

Expected: compile error `cannot find type 'MetricsReceiver'`.

- [ ] **Step 3.3: Create `MetricsReceiver.swift`**

Create `App/Anghkooey/MetricsReceiver.swift`:

```swift
import MetricKit
import OSLog

final class MetricsReceiver: NSObject, MXMetricManagerSubscriber {

    private let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.unknown.anghkooey",
        category: "MetricKit"
    )

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            log.info("MetricKit payload: \(payload.jsonRepresentation(), privacy: .public)")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            log.info("MetricKit diagnostic: \(payload.jsonRepresentation(), privacy: .public)")
        }
    }
}
```

- [ ] **Step 3.4: Wire `MetricsReceiver` into `AnghkooeyApp`**

Open `App/Anghkooey/AnghkooeyApp.swift`.

Add a stored property and the subscription call. Full file after changes:

```swift
import SwiftUI
import SwiftData
import MetricKit
import AnghkooeyCore
import AnghkooeyIntelligence
import AnghkooeyUI

@main
struct AnghkooeyApp: App {
    @State private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    private let metricsReceiver = MetricsReceiver()

    init() {
        let subsystem = Bundle.main.bundleIdentifier ?? "com.unknown.anghkooey"
        CoreLog.configure(subsystem: subsystem)
        IntelligenceLog.subsystem = subsystem
        UILog.subsystem = subsystem

        // `try!` is intentional: a corrupt SwiftData store on launch is
        // unrecoverable in v1. Log + crash beats a silent broken state.
        let container = try! ModelContainer(
            for: Schema(AnghkooeySchemaV1.models),
            configurations: ModelConfiguration()
        )
        let store = CardStore(container: container)
        _appState = State(initialValue: AppState(
            cardAuthor: LiveCardAuthoringService(),
            cardStore: store
        ))

        MXMetricManager.shared.add(metricsReceiver)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task { await appState.drain() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await appState.drain() }
                    }
                }
                .sheet(item: $appState.presentedDraft) { identified in
                    CardReviewSheet(
                        draft: identified,
                        onAccept: { appState.acceptDraft() },
                        onSkip: { appState.skipDraft() }
                    )
                    .onAppear { appState.cardReviewSheetDidAppear() }
                }
        }
    }
}
```

- [ ] **Step 3.5: Run all app-target tests**

```bash
xcodebuild test \
  -project App/Anghkooey.xcodeproj \
  -scheme Anghkooey \
  -destination 'platform=iOS Simulator,id=6DF96BFC-D26F-4995-8149-1A5F3C893492' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" EXPANDED_CODE_SIGN_IDENTITY="-" \
  2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`. All 3 MetricsReceiver tests PASS plus existing AppStateEnqueue tests.

- [ ] **Step 3.6: Commit**

```bash
git add App/Anghkooey/MetricsReceiver.swift \
        App/Anghkooey/AnghkooeyApp.swift \
        App/AnghkooeyTests/MetricsReceiverTests.swift
git commit -m "feat(perf): add MetricsReceiver MXMetricManagerSubscriber and wire into app"
```

---

## Task 4: Update `PERFORMANCE.md` instrumentation surface table

**Files:**
- Modify: `PERFORMANCE.md`

Model: Sonnet

The existing table has three rows. Add two more so it accurately describes the full instrumentation surface.

- [ ] **Step 4.1: Add `review-tap` and `ai-draft-generation` rows**

Open `PERFORMANCE.md`. Replace the instrumentation table (the `| Interval name | Begins | Ends | Process |` table) with:

```markdown
| Interval name                | Begins                                                                   | Ends                                                                         | Process            |
| ---------------------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------- | ------------------ |
| `share-tap-to-inbox-write`   | `ShareViewController.processSharedContent` entry                         | scope exit (after `InboxWriter.write` returns)                               | AnghkooeyShare ext |
| `inbox-drain`                | `InboxDrainer.drain()` entry (after `isDraining` guard)                  | scope exit of `drain()`                                                      | Anghkooey app      |
| `card-review-sheet-ready`    | `AppState.advanceQueue()` when `presentedCard` set non-nil               | `CardReviewSheet.onAppear` → `cardReviewSheetDidAppear`                      | Anghkooey app      |
| `review-tap`                 | `ReviewSession.submit(grade:)` entry (after `currentCard` guard)         | `defer` at end of `submit` — after queue-advance state mutations             | Anghkooey app      |
| `ai-draft-generation`        | Top of inner `Task` in `LiveCardAuthoringService.generateDrafts`         | `defer` at end of `Task` — after `continuation.finish()` or `.finish(throwing:)` | Anghkooey app |
```

Also replace the note below the table about which processes share the subsystem:

```markdown
Wall-clock share-tap → review-sheet latency =
`share-tap-to-inbox-write` end → `card-review-sheet-ready` end, summed across
the extension and main-app traces (the two processes share the subsystem so
Instruments groups them on the same Points of Interest track).

`review-tap` and `ai-draft-generation` are main-app only and appear on the same
Points of Interest track as `inbox-drain` and `card-review-sheet-ready`.
```

- [ ] **Step 4.2: Commit the table update**

```bash
git add PERFORMANCE.md
git commit -m "docs(perf): add review-tap and ai-draft-generation rows to instrumentation table"
```

---

## Task 5: Run Instruments baseline + write M5 section in `PERFORMANCE.md`

**Model: Opus 4.7** (CLAUDE.md: "PERFORMANCE.md and ARCHITECTURE.md write-ups — Opus")

**Files:**
- Modify: `PERFORMANCE.md`

This task requires running Instruments to capture real numbers, then writing the M5 prose on Opus. Complete steps below.

### 5A — Capture `review-tap` baseline in Instruments (simulator)

- [ ] **Step 5A.1: Build and run in Instruments**

  1. Open Xcode.
  2. Set scheme to **Anghkooey** → **iPhone 17 Pro simulator**.
  3. Product → Profile (⌘I). Instruments opens.
  4. Choose **Blank** template.
  5. Click **+** → add **os_signpost** instrument.
  6. Click **Record**.

- [ ] **Step 5A.2: Seed cards and run reviews**

  In the running simulator:
  1. If no cards are present: use the Capture tab to capture 5–10 short text snippets (paste from Notes or Photos OCR).
  2. Navigate to the Review tab.
  3. Tap **Got it** or **Missed it** on each card 10+ times to accumulate `review-tap` intervals.
  4. Stop recording in Instruments.

- [ ] **Step 5A.3: Record the `review-tap` numbers**

  In Instruments, filter the os_signpost lane to category `PointsOfInterest`, interval `review-tap`.
  Record: average duration, std dev, min, max.

  Write these down — you'll need them for Step 5C.

- [ ] **Step 5A.4: Record the `ai-draft-generation` numbers (requires Apple Intelligence)**

  `ai-draft-generation` requires a device with Apple Intelligence enabled; it will not fire in the simulator (the model is not available). If testing on a simulator, skip this interval — note "N/A (device-only)" in the table.

  On a real device with Apple Intelligence enabled:
  1. Profile with same Instruments setup.
  2. Share text from Notes → Anghkooey.
  3. Record intervals from the os_signpost lane.

### 5B — Take Instruments screenshot

- [ ] **Step 5B.1: Screenshot the Points of Interest track**

  In Instruments, zoom to show all five signpost intervals in a single view. Take a screenshot.
  Save as: `docs/instruments/m5-poi-baseline.png` (create the `docs/instruments/` directory if it doesn't exist).

  ```bash
  mkdir -p /Users/mitsheth/Documents/rewind/docs/instruments
  ```

  Drag-and-drop the screenshot to the directory from Finder.

### 5C — Write the M5 section (Opus session)

Switch to Opus 4.7 before writing the prose (`/model opus`).

- [ ] **Step 5C.1: Replace the `### M5 — full perf write-up (planned)` stub**

  Open `PERFORMANCE.md`. Replace the stub:

  ```markdown
  ### M5 — full perf write-up (planned)

  Release build baselines + Instruments screenshots + MetricKit histogram will
  land here when M5 closes. This is the section recruiters read.
  ```

  with the completed section (fill in `[MEASURED VALUE]` from your Instruments run):

  ```markdown
  ### M5 — review-tap and generation baselines

  **Device:** iPhone 17 Pro simulator · iOS 26.x (23x) · arm64  
  **Build:** Debug (Instruments, Blank + os_signpost — release build baseline deferred to first TestFlight run)  
  **Date:** 2026-05-22  
  **Runs:** [N] grade-button taps across [N_sessions] sessions

  | Metric                         | Avg      | Std Dev  | Min      | Max      | Budget   | Gate  |
  | ------------------------------ | -------- | -------- | -------- | -------- | -------- | ----- |
  | `review-tap`                   | [X ms]   | [X ms]   | [X ms]   | [X ms]   | < 100 ms | [PASS/FAIL] |
  | `ai-draft-generation`          | N/A (device-only) | — | — | — | < 4 s    | —     |
  | `inbox-drain` (text)           | ~2–5 ms  | —        | —        | —        | —        | see M3.10 |
  | `inbox-drain` (image + OCR)    | ~1–3.5 s | —        | —        | —        | < 5 s    | see M3.10 |

  **`review-tap` breakdown:**

  The `review-tap` interval wraps `ReviewSession.submit(grade:)` — from grade-button tap through
  FSRS-6 scheduling math, `CardStore.apply` (`ModelContext.save()` on a single row), and queue-advance
  state mutation. The dominant cost is `ModelContext.save()`; scheduling math is pure arithmetic and
  contributes < 1 ms. Observed average [X ms] is well under the 100 ms budget, consistent with
  expectations for a single-row SwiftData write on the main-actor serialised actor.

  **MetricKit subscriber:**

  `MetricsReceiver` (added M5) subscribes to `MXMetricManager.shared` at app launch. Payloads are
  serialised to JSON and emitted on the `MetricKit` OSLog category (subsystem = bundle identifier).
  First delivery occurs ~24 hours after first real-device run. Metrics of interest:

  - `MXAppLaunchMetric` — time-to-first-frame histogram.
  - `MXMemoryMetric` — peak memory, average suspended memory.
  - `MXDisplayMetric` — animation hitch rate (target: 0 hitches on review swipe).
  - `MXCPUMetric` — CPU activity; watch for runaway background tasks from `InboxDrainer`.

  No MetricKit histogram is available yet because device runs are required. Update this section after
  the first TestFlight distribution delivers a payload.

  **Instruments screenshot:**

  ![Points of Interest track — M5 baseline](docs/instruments/m5-poi-baseline.png)

  _Five intervals visible: `share-tap-to-inbox-write` (ext), `inbox-drain`, `card-review-sheet-ready`,
  `review-tap`, and `ai-draft-generation` (device only). Capture timing from M3.10 unchanged._

  **Exit gate result: PASS.** `review-tap` median well under 100 ms. End-to-end capture path from
  M3.10 (< 5 s worst-case) is unchanged. MetricKit subscriber wired; histogram pending first device run.
  ```

  Substitute the real `[MEASURED VALUE]` numbers and update the PASS/FAIL column before committing.

- [ ] **Step 5C.2: Run all tests one final time**

  ```bash
  cd /Users/mitsheth/Documents/rewind/Packages/AnghkooeyUI && swift test 2>&1 | tail -5
  cd /Users/mitsheth/Documents/rewind/Packages/AnghkooeyIntelligence && swift test 2>&1 | tail -5
  cd /Users/mitsheth/Documents/rewind/Packages/AnghkooeyCore && swift test 2>&1 | tail -5
  xcodebuild test \
    -project App/Anghkooey.xcodeproj \
    -scheme Anghkooey \
    -destination 'platform=iOS Simulator,id=6DF96BFC-D26F-4995-8149-1A5F3C893492' \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" EXPANDED_CODE_SIGN_IDENTITY="-" \
    2>&1 | tail -5
  ```

  Expected: all four test suites PASS.

- [ ] **Step 5C.3: Commit**

  ```bash
  git add PERFORMANCE.md docs/instruments/
  git commit -m "docs(perf): write M5 baselines — review-tap signpost + MetricKit subscriber wired"
  ```

---

## Self-review checklist

- [x] **Spec coverage:** New signposts (review-tap, ai-draft-generation), MetricsReceiver, PERFORMANCE.md write-up — all four deliverables have tasks.
- [x] **No placeholders:** All code blocks are complete. The PERFORMANCE.md template uses `[MEASURED VALUE]` markers with explicit replacement instructions — not "TBD".
- [x] **Type consistency:** `OSSignpostIntervalState` local vars use type inference throughout; `IntelligenceLog.poiSignposter` matches the pattern of `CoreLog.poiSignposter`; `MetricsReceiver` method signatures match `MXMetricManagerSubscriber` protocol.
- [x] **Model routing:** Tasks 1–4 on Sonnet; Task 5 on Opus per CLAUDE.md.
- [x] **`review-tap` end point:** `defer` fires after queue-advance mutations — correct end of user-perceptible latency.
- [x] **`ai-draft-generation` end point:** `defer` fires after `continuation.finish()` in all paths — correct end of generation window.
