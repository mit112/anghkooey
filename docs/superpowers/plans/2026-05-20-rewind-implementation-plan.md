# Rewind — Strategic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement tasks. Tasks use checkbox (`- [ ]`) syntax. This document is the strategic plan + the detailed task breakdown for **M0 only**. Per-milestone detailed task plans for M1–M6 are produced just-in-time as we enter each milestone, written next to this file (`2026-MM-DD-rewind-m1-core.md`, etc.).

**Goal:** Ship Rewind v1 — an on-device, privacy-first spaced-repetition iOS app whose wedge is "capture in under 10 seconds, FoundationModels writes the card, FSRS-6 schedules it, queue never shames you."

**Architecture:** SPM-modularized iOS 26 app, Swift 6 strict concurrency, SwiftData local-first, FoundationModels for card authoring, FSRS-6 ported from a reference implementation with a parity test suite, Share Sheet + Vision OCR for capture. Three feature packages (`RewindCore`, `RewindIntelligence`, `RewindUI`) consumed by a thin app target.

**Tech Stack:** Swift 6.x · SwiftUI · SwiftData · FoundationModels (`LanguageModelSession`, `@Generable`) · Vision (`VNRecognizeTextRequest`) · Swift Testing (primary) · XCTest (UI tests only) · OSLog · MetricKit · `os_signpost` · Share Extension · AppIntents (architectural seam for v1.1).

**Authoritative inputs:**
- `foundation.md` — product scope (wins on conflicts).
- `ios-skill-map-2026.md` — engineering-skill targets (wins on conflicts about *why* a technology was chosen).
- `CLAUDE.md` — project guardrails and anti-patterns.

---

## 0. Blocking Decisions (resolve before M0 begins)

These come from `foundation.md §0`. M0 must not start until each row has a final answer recorded here.

| # | Decision | Default (from foundation.md) | Status |
|---|---|---|---|
| 1 | **Product name** | **Anghkooey** — tagline: *remember everything* | **RESOLVED 2026-05-20.** Package names rename: `AnghkooeyCore` / `AnghkooeyIntelligence` / `AnghkooeyUI`. Bundle ID convention: `com.<author>.anghkooey`. App Store / domain / public push still pending — verify name availability (App Store search, USPTO TESS, `.com` / `.app` domain) before first public artifact. |
| 2 | **iOS version floor** | iOS 26 only | **Resolved 2026-05-20.** |
| 3 | **Monetization** | Free in v1. No paywall, no IAP. Only sunk cost is Apple Developer Program ($99/yr). | **Resolved 2026-05-20.** |
| 4 | **Distribution** | iPhone first; iPad/Mac post-launch; never watchOS | **Resolved 2026-05-20.** |
| 5 | **MVP success metric** | Showcase / portfolio product. No user-growth target. "Done" = meets §9 Quality Bar in `foundation.md` + author is willing to show it to recruiters/friends. No v1 telemetry. | **Resolved 2026-05-20.** |
| 6 | **Public GitHub remote from M0** | Yes — public repo created at start of M0. | **Resolved 2026-05-20.** Repo + GitHub Actions CI exist from day one. |

**Consequences of #5 (showcase framing) for the plan:**
- M6 changes shape — no external TestFlight cohort needed. Internal TestFlight (1 week) + a personal-network beta is sufficient. App Store submission becomes optional, not the success criterion. "Repo + README + working device build" is the actual ship.
- Drop the "crash-free sessions ≥99.5%" and "≥20 testers" exit gates from M6; replace with "no crashes during a personal 30-min daily-use period across 7 days."
- Telemetry remains explicitly out of scope (was already implied by `foundation.md §4`).
- Portfolio-quality artifacts get sharper priority: `PERFORMANCE.md`, `ARCHITECTURE.md`, eval-harness output, prompt-iteration ADRs. Recruiters read these; users don't.

**Consequences of #6 (public repo from start) for the plan:**
- The earlier "name doesn't need to appear clean in local history" carve-out **no longer applies**. The very first commit pushed to the public remote must use Anghkooey naming throughout. M0.1 must rename the working directory and all artifacts before the first push.
- Public-repo hygiene becomes a M0 task: `LICENSE` (MIT or similar), public-facing `README.md`, no leaked paths or PII, `.gitignore` audited.
- Issue templates + a `CONTRIBUTING.md` are optional but cheap; defer to M5 unless you want them earlier.
- GitHub Actions macOS minutes are unmetered on public repos — CI cost stays $0.

---

## 1. LLM-Coding Guardrails (non-negotiable)

This project is built with an LLM in the loop. The rules below exist to prevent the four failure modes the user named: hallucination, scope creep, bugs, and context exhaustion.

### 1.1 Anti-hallucination

- **No invented APIs.** Before referencing any FoundationModels, SwiftData, Vision, ActivityKit, or AppIntents type, the agent must read either the official header or current Apple documentation via Context7 / WebFetch. If a symbol cannot be confirmed in <2 lookups, the agent stops and asks.
- **FSRS math is a port, not a derivation.** Every formula, parameter, and edge case mirrors a named reference implementation (default: `open-spaced-repetition/rs-fsrs` at a pinned commit). No "from-memory" math.
- **Verification before claim.** A task is not "done" until: tests pass on the command line *and* the agent has pasted the green output into the task's checkbox transcript. The phrase "tests should pass" without evidence is a plan failure.
- **Read before write.** Before editing a file, the agent reads it. Before introducing a new pattern, the agent greps for an existing one.

### 1.2 Anti-scope-creep

- **`foundation.md §4` is the v1 contract.** Anything in §4's "Out of Scope" list is rejected by default during implementation. Adding it requires an explicit user decision recorded in this plan, not a code comment.
- **No "while I'm in here" refactors.** Changes outside the task's stated files require a separate task.
- **No speculative abstractions.** If a protocol has one implementation today, it stays a concrete type until a second implementation lands. (Exception: cross-module service boundaries with `Mock*` implementations — that's a stated project convention.)
- **Cut-line discipline.** Every milestone has a written cut-line (§5). If the milestone slips, cut from the cut-line — don't extend the deadline silently.

### 1.3 Context discipline

- **One milestone, one detailed plan, one session-arc.** Detailed task plans are generated when we enter a milestone, not in advance. Stale TDD steps for code two months out are not a plan; they're noise.
- **Per-task subagent dispatch.** M0–M6 tasks are executed via `superpowers:subagent-driven-development` so the main session stays small and the per-task agent gets only the context it needs.
- **No re-reading source-of-truth files repeatedly.** `foundation.md`, `CLAUDE.md`, and this plan are loaded once per session; subsequent references quote inline.
- **Plans live under `docs/superpowers/plans/` only.** No scattering of `notes.md`, `temp.md`, or session-summary files in the repo root.
- **Model routing per the policy in `CLAUDE.md` ("Model routing policy").** Default Sonnet, escalate to Opus only for FSRS port, AI prompt engineering, ADRs, milestone reviews, perf/arch write-ups, and stuck-debugging. Subagents dispatched with `model: "sonnet"` unless the task is on the Opus list.

### 1.4 Bug containment

- Swift 6 strict concurrency is on from day one. No `@unchecked Sendable` without a comment naming the invariant.
- The FSRS engine is the most safety-critical module; it gets the most aggressive test coverage and a parity harness (§4.1) before *any* UI consumes it.
- AI-generated cards never silently enter the deck. The user-review step is a hard architectural rule, not a UX preference.

---

## 2. Architecture

### 2.1 Module boundaries

```
App Target (Rewind.app)
├── depends on → RewindUI
├── depends on → RewindIntelligence
├── depends on → RewindCore
│
ShareExtension Target (RewindShare.appex)
├── depends on → RewindCore (App Group write only)

RewindCore                     // Pure logic, no UIKit/SwiftUI
├── Models: Card, ReviewLog, Tag, (Collection?)
├── Persistence: SwiftData ModelContainer factory + migrations
├── Scheduling: FSRS6Engine + 21-param weights + parity fixtures
├── Capture inbox: app-group-backed queue read by main app
└── No imports of: SwiftUI, UIKit, FoundationModels, Vision

RewindIntelligence             // System-AI-facing
├── CardAuthor: LanguageModelSession wrapper + @Generable types
├── OCR: VNRecognizeTextRequest pipeline + text cleanup
├── Eval harness: input fixtures, output rubric, regression runner
└── Depends on RewindCore for the target schema only

RewindUI                       // SwiftUI views, design system
├── Review: swipe-to-grade stack, haptics
├── Capture: in-app camera view, review-and-approve sheet
├── Library: tag-first list, search, filters
├── Cushion / Freeze controls
└── Depends on RewindCore + RewindIntelligence

App Target
├── Composition root (DI wiring)
├── Scene + AppDelegate
├── PrivacyInfo.xcprivacy
└── No business logic. Pure assembly. (AppIntents land in v1.1 — module seam exists, no v1 entries.)
```

**Rule:** the App target contains zero business logic. If a feature can be written and tested without launching the app, it lives in a package.

### 2.2 Cross-module service convention

Every service that crosses a module boundary ships as a protocol + a production type + a mock type, all in the same file:

```
RewindCore/Sources/RewindCore/Scheduling/SchedulerService.swift
  - protocol SchedulerService { ... }
  - struct LiveSchedulerService: SchedulerService { ... }   // production
  - struct MockSchedulerService: SchedulerService { ... }   // for tests + previews
```

This is the StreakSync/FlickSwiper convention the author already uses; reaffirmed here so the LLM doesn't invent a different pattern.

### 2.3 Concurrency model

- Swift 6 strict concurrency on for every package.
- `async/await` only. No GCD. No completion handlers in new code.
- SwiftData `ModelContext` access is actor-isolated; the persistence layer exposes async APIs.
- `LanguageModelSession` calls live on a dedicated actor inside `RewindIntelligence`.

### 2.4 Logging

- Each package owns its own `Logger+Categories.swift` with categories scoped to that package's concerns. **Subsystem string is injected at the composition root**, not read from `Bundle.main` (which resolves differently inside the Share Extension and would silently split logs across two subsystems).
- `RewindCore` categories: `Scheduling`, `Persistence`, `CaptureInbox`. `RewindIntelligence`: `AI`, `OCR`. `RewindUI`: `Review`, `Library`, `Capture`. App target injects the bundle ID at startup.
- No `print` in committed code.
- `os_signpost` instruments wrapped around: card generation, scheduler updates, SwiftData fetches over 50 items.

### 2.5 Error handling

- Domain errors are `enum`s conforming to `Error` and `LocalizedError`, defined alongside the type that throws them.
- No `try?` in production code paths that affect persisted state — failures must be either handled or propagated.
- The FSRS engine never throws; it returns `Result` only where the input cannot be validated (e.g., negative elapsed time).

### 2.6 Skill-gap defense

Each architectural choice traces to a skill-gap from `ios-skill-map-2026.md` Phase 2:

| Choice | Closes gap |
|---|---|
| SPM modularization (`RewindCore` / `RewindIntelligence` / `RewindUI`) | #6 SPM modularization |
| FoundationModels with `@Generable` | #1 Foundation Models framework |
| Swift Testing primary, parameterized FSRS tests | #7 Swift Testing |
| OSLog + `os_signpost` + MetricKit + `PERFORMANCE.md` deliverable | #5 Instruments / MetricKit |
| Vision `VNRecognizeTextRequest` | #11 Vision exposure |
| AppIntents stubs even in v1 | #2 App Intents / Siri |
| SwiftData container designed for CloudKit private DB (v1.1) | #4 CloudKit sync |
| Widget seam reserved (no impl in v1) | #3 WidgetKit |

If a future task drops one of these defenses, the task must justify it in this table.

---

## 3. Repository conventions

- **Layout:**
  ```
  Rewind/                          (or final product name)
  ├── App/                         Xcode project + app target sources
  ├── Packages/
  │   ├── RewindCore/
  │   ├── RewindIntelligence/
  │   └── RewindUI/
  ├── docs/
  │   ├── superpowers/plans/       this file + per-milestone plans
  │   ├── PERFORMANCE.md           shipped before v1, M5 deliverable
  │   ├── ARCHITECTURE.md          one-pager, updated per milestone
  │   └── DECISIONS/               ADRs, numbered (0001-name.md)
  ├── foundation.md                source of truth (do not edit lightly)
  ├── ios-skill-map-2026.md
  ├── CLAUDE.md
  └── README.md
  ```
- **Branching:** `main` is always green. Feature work on `m{N}/{slug}` branches. PRs reference the milestone task ID.
- **Commits:** imperative mood, one logical change, no co-author lines auto-added unless requested.
- **ADRs:** any decision that overrides a default in `foundation.md` or this plan gets a numbered ADR. Inline comments are not a substitute.
- **CI (added in M0):** `xcodebuild test` against each package scheme on an iOS Simulator destination, plus a build of the app target. Runs on a pinned Xcode 26 macOS runner. `swift test` is **not** used in CI for `RewindIntelligence` and `RewindUI` because those packages depend on iOS-only frameworks (FoundationModels, SwiftUI lifecycle). UI tests gated behind a label until M4.

---

## 4. Cross-cutting workstreams (run in parallel with milestones)

### 4.1 FSRS parity harness

Owned by M1, maintained forever. Reference implementation: `open-spaced-repetition/rs-fsrs` (pinned commit recorded in M1 plan). Fixtures: 50 synthetic review sequences + 100 deterministic random sequences. The Swift implementation must produce stability, difficulty, and next-interval values that match the reference implementation within a documented epsilon (target: 1e-9 for doubles; absolute equality for integer intervals). Any divergence outside epsilon is a P0 bug.

### 4.2 FoundationModels evaluation set

Owned by M2, maintained forever. 100 held-out input fixtures across: textbook paragraphs (EN), language-learning sentences (multiple source languages), conversational/Twitter prose, OCR-noisy text.

**Rubric** (binary per card, all four required to pass):
- *Atomic* — one fact per card
- *Specific* — no "what is described above"
- *Hallucination-free* — every fact traceable to input
- *Q ≠ A* — question doesn't leak the answer

**Scoring rules** (locked, so the metric doesn't drift):
- A *card* passes iff all 4 rubric criteria pass.
- An *input* passes iff **every** generated card from that input passes (one bad card fails the input — generation is a unit, users see them together).
- Pass-rate = passing inputs / 100.
- Generation runs with `temperature = 0` and a fixed random seed for determinism. No best-of-N retries during eval.
- Single run per input per eval cycle. Re-running to improve a number is gaming, not evaluation.

**Ship threshold:** ≥80% input pass-rate (`foundation.md §9.2`). Eval re-runs on every prompt change; result committed alongside the prompt diff.

### 4.3 FoundationModels availability (product-level)

`SystemLanguageModel.availability` returns `.available` or `.unavailable(reason)` where reason can be `.deviceNotEligible`, `.appleIntelligenceNotEnabled`, or `.modelNotReady`. This is not a quality issue — it is a hard runtime gate on a meaningful slice of iOS 26 devices.

**Architectural consequence:** manual card creation (typed Q + typed A) is a **first-class capture path**, not a fallback. The capture UI offers AI-assisted and manual paths side-by-side. If `SystemLanguageModel` is unavailable at app launch, the AI-assisted path is hidden with a clear one-line explanation; nothing breaks, the user just types.

Owned by M2 (service design) + M3 (capture UI integration). Tracked in the risk register.

### 4.4 Performance budget

Tracked from M0, enforced by M5.
- Cold launch → first paint: <600ms on iPhone 15 Pro.
- Share-tap → card-ready-or-edit: <5s median (`foundation.md §9.1`).
- No main-thread block >100ms during a 30-min review session.
- Memory ceiling: <150MB resident during review.

MetricKit payload capture, `os_signpost` ranges, and an Instruments `.trace` are M5 deliverables and ship with `PERFORMANCE.md`.

### 4.5 Privacy manifest

`PrivacyInfo.xcprivacy` is **per-executable**: the app target and the Share Extension target each need their own. The app's manifest is stubbed in M0; the Share Extension's manifest is added when the extension target is created in M3, and both are audited and locked in M5. Required-reason API list documented in README. No third-party SDKs touch user content. If telemetry is added, it is on-device-aggregated, opt-in, and listed here.

---

## 5. Milestone roadmap

Order is chosen to **de-risk load-bearing technical bets first** (scheduler math, AI quality) before investing in capture UX and polish. Each milestone has an entry gate, exit gate, and cut-line.

### M0 — Project scaffolding
**Goal:** Empty but correct skeleton. Builds clean, tests run, CI green, conventions enforced.
**Entry gate:** §0 decisions resolved. Repo named.
**Exit gate:**
- Xcode project + 3 SPM packages compile under Swift 6 strict concurrency, target iOS 26.
- One trivial Swift Testing test passes in each package.
- App target launches an empty `ContentView` on the simulator.
- CI runs `xcodebuild test` for all packages on every PR.
- `PrivacyInfo.xcprivacy` present (empty but valid).
- `OSLog` category convention documented in `ARCHITECTURE.md`.
- ADR-0001 records the final product name.

**Cut-line:** None. M0 is non-negotiable.

> **Detailed task plan: §7 below.**

### M1 — RewindCore: schema + FSRS-6 engine
**Goal:** All persistence and scheduling logic, fully tested, no UI.
**Entry gate:** M0 green on `main`.
**Exit gate:**
- `Card`, `ReviewLog`, `Tag` SwiftData models with v1 migration.
- `FSRS6Engine` ported from pinned reference commit.
- Parity harness runs on every PR; passes 100% of fixtures.
- In-memory `ModelContainer` test container utility for downstream packages.
- All public APIs documented with DocC.
- `Logger(category: "FSRS")` and `Logger(category: "Persistence")` in place.

**Cut-line:** If parity passes for the 21-parameter default weights but custom-parameter optimization is incomplete, ship without it (per `foundation.md §4` — personal optimization is v2 anyway).

**Detailed plan to be written:** `2026-MM-DD-rewind-m1-core.md` when we enter M1.

### M2 — RewindIntelligence: FoundationModels + OCR
**Goal:** Given raw text, produce 1–N candidate Q&A cards. Given a UIImage, produce cleaned-up text.
**Entry gate:** M1 green; `Card` schema stable.
**Exit gate:**
- `CardAuthor` service exposes `func generate(from rawText: String) async throws -> [DraftCard]`.
- `@Generable` `DraftCardSet` type with 4 fields (`question`, `answer`, `tags`, `sourceSpan`).
- Prompt template under version control; ADR records the prompt iteration history.
- Eval harness runs offline, reports pass-rate per rubric criterion. Current pass-rate ≥80% on the 100-input fixture set.
- `OCRService.recognizeText(in: UIImage) async throws -> String` with hyphen/linebreak cleanup.
- Both services have `Live*` and `Mock*` implementations.

**Additional exit-gate requirements (from §4.3):**
- `CardAuthor` exposes an availability probe (`var isAvailable: Bool { get async }`) backed by `SystemLanguageModel.availability`.
- Composition root exposes the availability state to UI as an observable value so the capture screen can hide the AI path cleanly when `.unavailable(_)`.
- `MockCardAuthor` covers all three unavailability reasons in tests.

**Cut-line:** If eval pass-rate sits at 65–79% after prompt iteration, ship M2 with a "Beta AI" label in the UI and the manual capture path made equally prominent. Below 65%, hold M3 entry. Manual capture is always a first-class path regardless of pass-rate, per §4.3 — no AI quality number changes that.

### M3 — Capture: Share Sheet + in-app camera
**Goal:** The 10-second capture promise, end-to-end.
**Entry gate:** M2 exit gate met. **Inbox design document committed** (see entry deliverable below) before any Share Extension code lands.

**Entry deliverable (design-before-code):** `docs/DECISIONS/NNNN-app-group-inbox.md` specifying:
- On-disk format (one file per submission vs. append-only log; recommend one file per submission, atomic write).
- Path layout under the App Group container.
- Schema (UUID, source-app bundle ID, captured text, captured-at timestamp, kind enum: text/image-ref).
- Atomicity guarantees (temp-file + rename pattern).
- Lifecycle (extension writes only; main app reads + deletes after successful card draft; orphan retention policy).
- Dedup strategy (hash of normalized text + 60s window).
- Maximum payload size and what happens on overflow.
- Concurrency model when extension fires while main app is foregrounded.

**Exit gate:**
- Share Extension target receives text from Safari/Books/Mail, writes to App Group inbox per the design doc.
- Main app drains inbox on launch and on foreground, runs `CardAuthor` (or routes to manual entry if unavailable per §4.3), presents the review-and-approve sheet.
- In-app camera path: capture → OCR → `CardAuthor` (or manual) → review sheet. Same review sheet for both paths.
- Median share-tap → review sheet ready: <5s on iPhone 15 Pro (measured with `os_signpost`).
- App-group entitlement + bundle group ID locked.
- **Share Extension `PrivacyInfo.xcprivacy` present and audited separately from the app's.**

**Cut-line:** If camera OCR ships unstable, demote it to "v1.1" behind a feature flag and ship Share Sheet only. The wedge survives.

### M4 — Review UX + grace features
**Goal:** Daily-use surface. Looks good, feels good, never shames.
**Entry gate:** M3 green; real cards in the DB to swipe through.
**Exit gate:**
- Swipe-to-grade stack: left=Again, right=Good, up=Easy, down=edit. Spring physics, color overlay, haptics on every grade.
- Cushion Mode: when due-queue > 50, show "today's batch" (15–20). Truthful copy. Setting toggleable.
- Freeze: manual "I'm away" toggle, shifts `nextReviewAt` by N days on return.
- Library view: tag-filtered flat list, search, edit-card sheet.
- Zero shame-coded copy in the UI (string audit deliverable).

**Cut-line:** If animation/physics polish slips, ship simpler tap-buttons-for-grades fallback alongside swipe. Keep haptics either way.

### M5 — Polish, perf, privacy, eval re-run
**Goal:** Ship-ready.
**Entry gate:** M4 functionally complete.
**Exit gate:**
- `PERFORMANCE.md` published with: Instruments trace, MetricKit screenshot, before/after on at least one optimization, signpost ranges around critical paths.
- `PrivacyInfo.xcprivacy` audited; required-reason API list in README.
- Airplane-mode E2E pass (`foundation.md §9.4`).
- 30-min review session: no main-thread block >100ms, memory growth <20MB (`foundation.md §9.5`).
- Eval harness re-run; documented pass-rate.
- App Store metadata draft.
- Manual QA checklist green on iPhone 15 Pro + one lower-tier device (15 / SE 4 / 16e).

**Cut-line:** If lower-tier device fails perf gates, narrow launch device matrix to iPhone 15+ in App Store metadata.

### M6 — Beta → Submission
**Goal:** TestFlight, feedback loop, submit.
**Entry gate:** M5 exit gate met.
**Exit gate:**
- TestFlight internal for 1 week → external for 2 weeks with ≥20 testers.
- Crash-free sessions ≥99.5%.
- Top-3 feedback themes addressed or explicitly deferred to v1.1.
- App Store submission accepted.

**Cut-line:** None — this is ship gate.

---

## 6. Risk register (live)

Carried from `foundation.md §8`, with mitigation owners by milestone.

| Risk | Mitigation | Owner |
|---|---|---|
| FoundationModels card quality is mediocre on 3B model | Eval harness (§4.2), prompt iteration ADRs, mandatory user review, "Beta AI" label fallback | M2 |
| iOS 26 floor cuts addressable market | Accept; revisit in v2 | Product |
| Cushion Mode is marketing dressing | Truthful copy; "show me a manageable batch today"; no algorithmic-novelty claim | M4 |
| Capture latency exceeds 3s | Benchmark in M3 entry; async-with-notification fallback designed in M2 | M3 |
| Name collision with Rewind AI | Resolve §0 #1 before M0; ADR-0001 | §0 |
| FSRS-6 bugs silently damage retention | Parity harness (§4.1); P0 on any divergence | M1 |
| Privacy claim undermined by analytics | No third-party SDKs on user content; ADR if telemetry added | §4.4 |

---

## 7. M0 Detailed Task Plan

Each task is bite-sized and ends in a green test or a passing build. Subagent-driven execution recommended.

> **Pre-M0:** Resolve §0 decisions. Record final name in ADR-0001. Hereafter `<ProductName>` refers to the final name; `<bundle-id>` is `com.<author>.<productname>`.

### Task M0.1: Initialize git repo + baseline files

**Files:**
- Create: `.gitignore` (Swift / Xcode standard + `.DS_Store` + `*.xcuserstate`)
- Create: `README.md` (one paragraph: what this is, link to `foundation.md`)
- Create: `docs/ARCHITECTURE.md` (skeleton, sections: Modules, Concurrency, Logging, Errors)
- Create: `docs/DECISIONS/0001-product-name.md` (records the §0 #1 outcome)

- [ ] **Step 1:** `git init` in the repo root.
- [ ] **Step 2:** Write `.gitignore` from the standard Xcode/Swift template. Verify no `*.swiftpm/xcode` or `xcuserdata` paths are tracked.
- [ ] **Step 3:** Write `README.md` (≤15 lines).
- [ ] **Step 4:** Write `docs/ARCHITECTURE.md` skeleton with the four sections, each containing a one-line placeholder that references this plan.
- [ ] **Step 5:** Write `docs/DECISIONS/0001-product-name.md` with: Context, Decision, Consequences (ADR-standard).
- [ ] **Step 6:** `git add -A && git commit -m "chore: initial repo scaffolding"`.

### Task M0.2: Create Xcode project (app target only)

**Files:**
- Create: `App/<ProductName>.xcodeproj`
- Create: `App/<ProductName>/<ProductName>App.swift`
- Create: `App/<ProductName>/ContentView.swift`
- Create: `App/<ProductName>/PrivacyInfo.xcprivacy` (empty valid plist)

- [ ] **Step 1:** Create iOS App project via Xcode: SwiftUI lifecycle, Swift 6, deployment target iOS 26, bundle ID `<bundle-id>`. Place at `App/`.
- [ ] **Step 2:** In target Build Settings, set `SWIFT_STRICT_CONCURRENCY = complete`. Confirm `SWIFT_VERSION = 6.x`.
- [ ] **Step 3:** Replace template `ContentView` with `Text("Rewind")` (or final product name). No business logic.
- [ ] **Step 4:** Add an empty-but-valid `PrivacyInfo.xcprivacy` (root `<dict/>` with empty `NSPrivacyAccessedAPITypes` array). Add to target.
- [ ] **Step 5:** Build for iPhone 15 Pro simulator. Expected: build succeeds, app launches, shows the placeholder text.
- [ ] **Step 6:** `git add -A && git commit -m "chore: scaffold iOS app target with iOS 26 + Swift 6 strict concurrency"`.

### Task M0.3: Create `RewindCore` SPM package

**Files:**
- Create: `Packages/RewindCore/Package.swift`
- Create: `Packages/RewindCore/Sources/RewindCore/RewindCore.swift` (umbrella, empty public)
- Create: `Packages/RewindCore/Tests/RewindCoreTests/SmokeTests.swift`
- Create: `Packages/RewindCore/README.md`

- [ ] **Step 1:** Write `Package.swift` declaring an iOS 26 platform, Swift tools 6.x, one library product `RewindCore`, one test target using `swift-testing` (Apple's Swift Testing is bundled with Swift 6 toolchain; no external dep needed).
- [ ] **Step 2:** Add `.swiftSettings = [.enableExperimentalFeature("StrictConcurrency")]` (or `.enableUpcomingFeature("StrictConcurrency")` per the toolchain in use — confirm via current Swift docs before writing).
- [ ] **Step 3:** Write the smoke test:

```swift
import Testing
@testable import RewindCore

@Test func packageLoads() {
    #expect(Bool(true))
}
```

- [ ] **Step 4:** Run from package root: `swift test`. Expected: 1 test passes.
- [ ] **Step 5:** Write `Packages/RewindCore/README.md` (≤10 lines: purpose, dependencies = none, owner sections).
- [ ] **Step 6:** Commit: `git add -A && git commit -m "feat(core): scaffold RewindCore package with smoke test"`.

### Task M0.4: Create `RewindIntelligence` SPM package

**Files:**
- Create: `Packages/RewindIntelligence/Package.swift`
- Create: `Packages/RewindIntelligence/Sources/RewindIntelligence/RewindIntelligence.swift`
- Create: `Packages/RewindIntelligence/Tests/RewindIntelligenceTests/SmokeTests.swift`
- Create: `Packages/RewindIntelligence/README.md`

- [ ] **Step 1:** Mirror M0.3 structure. Add `.package(path: "../RewindCore")` and depend on `RewindCore` in the library target.
- [ ] **Step 2:** Leave the umbrella file empty of any `FoundationModels` references. Module availability is confirmed in M2 when we actually use it; importing here just to prove existence is checkbox-engineering and risks a wrong import that breaks the build for the rest of M0.
- [ ] **Step 3:** Write a smoke test mirroring M0.3.
- [ ] **Step 4:** `swift test`. Expected: 1 test passes.
- [ ] **Step 5:** Write package README.
- [ ] **Step 6:** Commit: `git add -A && git commit -m "feat(intelligence): scaffold RewindIntelligence package"`.

### Task M0.5: Create `RewindUI` SPM package

**Files:**
- Create: `Packages/RewindUI/Package.swift`
- Create: `Packages/RewindUI/Sources/RewindUI/RewindUI.swift`
- Create: `Packages/RewindUI/Tests/RewindUITests/SmokeTests.swift`
- Create: `Packages/RewindUI/README.md`

- [ ] **Step 1:** Mirror M0.3. Dependencies: `RewindCore` + `RewindIntelligence`.
- [ ] **Step 2:** Umbrella file exports a single SwiftUI `View` placeholder: `public struct RewindPlaceholderView: View { public init() {}; public var body: some View { Text("Rewind") } }`.
- [ ] **Step 3:** Smoke test asserts the view can be instantiated:

```swift
import Testing
import SwiftUI
@testable import RewindUI

@Test func placeholderViewInitializes() {
    _ = RewindPlaceholderView()
    #expect(Bool(true))
}
```

- [ ] **Step 4:** `swift test`. Expected: passes.
- [ ] **Step 5:** Write package README.
- [ ] **Step 6:** Commit: `git add -A && git commit -m "feat(ui): scaffold RewindUI package"`.

### Task M0.6: Wire packages into app target

**Files:**
- Modify: `App/<ProductName>.xcodeproj` (add local SPM dependencies)
- Modify: `App/<ProductName>/ContentView.swift`

- [ ] **Step 1:** In Xcode, File → Add Package Dependencies → Add Local → select `Packages/RewindUI`. Repeat for `RewindCore` and `RewindIntelligence` (or accept transitive resolution — confirm Xcode 16+ behavior).
- [ ] **Step 2:** Link `RewindUI` to the app target (Frameworks & Libraries).
- [ ] **Step 3:** Replace `ContentView` body with `RewindPlaceholderView()`:

```swift
import SwiftUI
import RewindUI

struct ContentView: View {
    var body: some View {
        RewindPlaceholderView()
    }
}
```

- [ ] **Step 4:** Build + run on iPhone 15 Pro simulator. Expected: app launches, shows "Rewind".
- [ ] **Step 5:** Commit: `git add -A && git commit -m "chore: wire local SPM packages into app target"`.

### Task M0.7: Per-package OSLog categories + injected subsystem

**Files:**
- Create: `Packages/RewindCore/Sources/RewindCore/Logging/CoreLog.swift`
- Create: `Packages/RewindIntelligence/Sources/RewindIntelligence/Logging/IntelligenceLog.swift`
- Create: `Packages/RewindUI/Sources/RewindUI/Logging/UILog.swift`
- Modify: `App/<ProductName>/<ProductName>App.swift` (set subsystem at startup)
- Modify: `docs/ARCHITECTURE.md` (fill Logging section)

- [ ] **Step 1:** In `RewindCore`, write `CoreLog.swift`:

```swift
import OSLog

public enum CoreLog {
    /// Set by the app composition root at startup. Avoids reading Bundle.main
    /// (which resolves to the extension bundle inside the Share Extension and
    /// would silently split logs across two subsystems).
    public nonisolated(unsafe) static var subsystem: String = "com.unknown.rewind"

    public static var scheduling: Logger { Logger(subsystem: subsystem, category: "Scheduling") }
    public static var persistence: Logger { Logger(subsystem: subsystem, category: "Persistence") }
    public static var captureInbox: Logger { Logger(subsystem: subsystem, category: "CaptureInbox") }
}
```

- [ ] **Step 2:** Mirror the pattern in `RewindIntelligence` (`IntelligenceLog.subsystem`, categories: `AI`, `OCR`) and `RewindUI` (`UILog.subsystem`, categories: `Review`, `Library`, `Capture`). Each package owns its own categories — no cross-package category dictionary.
- [ ] **Step 3:** In the app target's `<ProductName>App.swift` `init()`, set the subsystem on all three modules from a single source:

```swift
init() {
    let subsystem = Bundle.main.bundleIdentifier ?? "com.unknown.rewind"
    CoreLog.subsystem = subsystem
    IntelligenceLog.subsystem = subsystem
    UILog.subsystem = subsystem
}
```

  (The Share Extension target will set its own subsystem in M3, derived from the *app's* bundle ID, not the extension's, so logs unify.)
- [ ] **Step 4:** Write a Swift Testing case per package asserting the `Logger` resolves and the subsystem can be overridden.
- [ ] **Step 5:** Run `xcodebuild test` for each package scheme on the iOS Simulator. Expected: passes.
- [ ] **Step 6:** Update `docs/ARCHITECTURE.md` Logging section.
- [ ] **Step 7:** Commit: `git add -A && git commit -m "feat: per-package OSLog with injected subsystem"`.

### Task M0.8: CI skeleton (xcodebuild test on iOS Simulator)

**Files:**
- Create: `scripts/ci.sh` (always)
- Create: `.github/workflows/ci.yml` (once a remote exists)

**Rationale:** `swift test` runs against host macOS, which will not compile or exercise iOS-only frameworks (`FoundationModels`, `SwiftUI` lifecycle, `Vision` on-device APIs). For an iOS 26-only product, the only honest test command is `xcodebuild test` against an iOS Simulator destination. Pin the Xcode version so the runner doesn't drift away from the iOS 26 SDK we depend on.

- [ ] **Step 1:** Write `scripts/ci.sh` that runs, failing fast on any non-zero exit:
  - `xcodebuild test -scheme RewindCore -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=latest'` from the workspace
  - `xcodebuild test -scheme RewindIntelligence -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=latest'`
  - `xcodebuild test -scheme RewindUI -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=latest'`
  - `xcodebuild build -project App/<ProductName>.xcodeproj -scheme <ProductName> -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=latest'`

  (Each SPM package gets its own scheme in the Xcode workspace; M0.3/M0.4/M0.5 should generate them via Xcode when the packages are added.)
- [ ] **Step 2:** Run `bash scripts/ci.sh` locally end-to-end. Expected: all four steps green.
- [ ] **Step 3:** If a GitHub remote is set up, write `.github/workflows/ci.yml`:
  - Runner: `macos-15` or later (whatever ships with Xcode 26).
  - Step: `sudo xcode-select -s /Applications/Xcode_26.app` (or matrix on `xcode-version` if multiple).
  - Step: `bash scripts/ci.sh`.
- [ ] **Step 4:** Commit: `git add -A && git commit -m "ci: xcodebuild test pipeline pinned to Xcode 26 / iOS 26 Simulator"`.

### Task M0.9: M0 exit verification

- [ ] **Step 1:** Re-read §5 M0 exit gate. Walk each bullet against the repo state. Quote evidence (file path or test output) per bullet.
- [ ] **Step 2:** If any bullet fails, file a follow-up task and do not declare M0 done.
- [ ] **Step 3:** If all bullets pass, tag the commit: `git tag m0-complete`.
- [ ] **Step 4:** Open `docs/superpowers/plans/2026-MM-DD-rewind-m1-core.md` and begin the M1 detailed plan.

---

## 8. Cut-line policy

If a milestone misses its exit gate by its agreed date:

1. Look at the milestone's stated cut-line. Apply it.
2. If the cut-line is "none" (M0, M6), the project schedule extends; nothing is dropped.
3. If a feature was cut, record it in `docs/DECISIONS/` as an ADR with title `NNNN-cut-<feature>-from-v1.md`.
4. Never silently drop a `foundation.md §9` quality-bar item. Either meet it or write the ADR.

---

## 9. Self-review notes

- **Spec coverage check:** Every `foundation.md §4`-in-scope item maps to a milestone (M1 schema/scheduling, M2 AI+OCR, M3 Share Sheet + camera, M4 review/grace/library). Every `§9` quality bar maps to M5 exit gate. Every `§10` deliverable maps to a milestone artifact. Every Phase-2 skill gap in `ios-skill-map-2026.md` maps to a §2.6 row.
- **Placeholder scan:** Tasks contain real code where code is shown; M1–M6 are intentionally stub roadmap entries with detailed plans deferred (matches the strategic-plan-only scope agreed with the user).
- **Type consistency:** `CardAuthor`, `OCRService`, `SchedulerService`, `Card`, `ReviewLog`, `Tag` are the only domain types referenced; usage is consistent across §2 and §5.
