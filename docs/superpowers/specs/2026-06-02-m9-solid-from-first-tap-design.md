# M9 — "Solid From First Tap" — Design

> Status: approved design (2026-06-02). Next: implementation plan via `writing-plans`.
> Source-of-truth alignment: serves `foundation.md` v1 product promise (capture-first + on-device AI authoring + grace-first scheduling). Closes activation/trust gaps found in the 2026-06-02 first-user review.

## Problem

A first-user walkthrough (simulator, seeded data) found the engine is strong but the **product front door is missing**, and several first-run moments actively erode trust:

1. **No manual card creation anywhere.** The store exposes `create(question:answer:sourceSpan:tags:now:)` but no UI calls it. Card creation funnels entirely through camera→AI, clipboard→AI, share→AI, or Anki import. A new user with no Anki deck, on a device without Apple Intelligence, **cannot create a single card**.
2. **AI capture is wired to mocks / degrades silently.** `ContentView` instantiates `MockClozeAuthoringService()` (returns empty drafts). The Q&A path uses the real `LiveCardAuthoringService`, but when the model is unavailable it silently falls back to a `"(edit to add answer)"` stub with no explanation. `AuthoringAvailability` exists but is never surfaced.
3. **Permission prompts ambush the user at launch.** A system paste prompt fires on the Review tab on every appearance *even with an empty clipboard*; a camera-permission prompt appears over the Review tab at cold launch because the Capture tab's `CameraView` is instantiated eagerly by the `TabView`.
4. **Review loop is sparse and unrewarding.** No interval previews on grade buttons, no session progress, no session-complete summary, and a visually empty review card.
5. **Empty first-run.** New users land on "All caught up" with zero cards and no obvious path forward.

## Goals

- A new user feels confident within ~30 seconds of first launch (clear what to do, never blocked, never ambushed by permissions).
- Every subsequent review session feels worth the time (clear consequences, visible progress, satisfying close).
- The on-device AI works for real on capable devices and **degrades honestly** (clear messaging + manual fallback) everywhere else.
- No silent failures: captured content is never lost or mysteriously blanked.

## Non-goals

- No new sync/CloudKit work, widgets, App Intents, or scheduling-algorithm changes (those are stable post-M8).
- No watchOS/iPad-specific layouts (out of scope per CLAUDE.md).
- No redesign of the FSRS engine or optimization flow.

## Decision: one comprehensive release, internally sequenced

Per product direction this ships as **one milestone (M9)**, but the implementation plan sequences it so value lands coherently:

- **Spine (feel solid immediately):** A (manual creation) → C (permission hygiene) → E (first-run + starter deck).
- **Layer (worth my energy):** B (AI wired + honest) → D (review polish) → F (trust/a11y).

---

## Workstream A — Manual card creation (the front door)

**Approach (decided): one dual-mode editor.** Extend `LibraryCardEditView` (or rename to `CardEditorView`) to support `create` and `edit` modes rather than adding a parallel screen. Create-mode calls `cardStore.create(...)`; edit-mode keeps the existing update path. Rationale: DRY, single validation/tag surface, less divergence risk.

**Entry points:**
- Library toolbar **＋** (alongside the existing Import button).
- Empty-Review CTA (see Workstream E) → "Add a card".

**Manual Cloze parity:** the editor supports both card types. Manual cloze uses the existing `ClozeMarkupParser` / `ClozeAuthoringService` (Core) so manual and AI-authored cloze share one persistence/markup path. Type a sentence, tap tokens to mark deletions, preview the generated cloze faces before saving.

**Components touched:** `Packages/AnghkooeyUI/.../Library/LibraryCardEditView.swift` (dual-mode), `LibraryView.swift` (toolbar ＋ + sheet presentation for create), `CardStoreProtocol.create` (already present — no change expected).

**Data flow:** Editor → (validate non-empty Q/A) → `cardStore.create(...)` → `LibraryView.load()` refresh. New cards enter as `.new` due now, so they appear in Review immediately.

---

## Workstream B — AI capture wired for real + availability-honest

**Wiring:** replace `MockClozeAuthoringService()` with `LiveClozeAuthoringService()` in `ContentView` Capture/Cloze branch.

**Availability gating (new UX):** introduce a small view-model/helper that reads `AuthoringAvailability` (already maps `SystemLanguageModel.availability`) and drives Capture UX:
- `available` → AI flow as designed.
- `unavailable(deviceNotEligible | appleIntelligenceNotEnabled | modelNotReady)` → show a one-line, reason-specific explanation and route the user straight into **manual entry** (Workstream A editor), pre-filled with any captured/OCR'd text.

**Honest fallback (replaces silent stub):** in `AppState.enqueue(resolvedText:)`, when authoring fails or AI is unavailable, present the editor pre-filled with the **captured text** and a "couldn't auto-generate — edit below" note, instead of the opaque `CardDraft(question: text, answer: "(edit to add answer)")` stub. Captured text is always preserved and visible.

**Components touched:** `App/Anghkooey/ContentView.swift`, `App/Anghkooey/AppState.swift` (`enqueue` fallback), new availability helper in `AnghkooeyUI` (UI may not import FoundationModels — it reads the `AuthoringAvailability` enum exposed by `AnghkooeyIntelligence`).

**Testing:** unit-test the availability→UX mapping and the fallback-preserves-text behavior with mock services. Live generation cannot run on simulator → **on-device QA gate** (exit criterion below).

---

## Workstream C — Permission hygiene

**Camera:** stop requesting camera at app launch. `CameraView`'s access request must fire only when the user is actually viewing the Capture tab in Q&A mode — gate the `.task`/instantiation behind tab/mode visibility so eager `TabView` construction doesn't trigger the prompt over Review.

**Clipboard:** stop triggering the system paste prompt on Review appearance. Use **non-prompting** APIs (`UIPasteboard.detectPatterns(...)` / `hasStrings`) to decide whether to *offer* a clipboard capture, and only access actual contents after an explicit user tap on the clipboard banner. An empty clipboard must never prompt.

**Components touched:** `ContentView.swift` (lazy Capture), `CameraView.swift` (request timing), `App/Anghkooey/Clipboard/ClipboardCaptureCoordinator.swift` + `ClipboardBanner.swift`.

---

## Workstream D — Review loop polish

**Interval previews:** under each grade button (Again/Hard/Good/Easy), show the projected next interval ("<1m / 10m / 1d / 4d") computed by calling the live `FSRS6Engine` for each rating against the current card. Read-only projection; no scheduling change.

**Session progress:** a remaining-count indicator (and/or thin progress bar) during a review session.

**Session-complete summary:** replace the bare "All caught up" with a short summary (cards reviewed this session, retention/accuracy, current streak) before/at the empty state.

**Card redesign:** framed card surface with proper typography hierarchy (question prominent, answer revealed below), filling the empty void in the current layout.

**Components touched:** `Packages/AnghkooeyUI/.../Review/ReviewView.swift`, `ReviewScreen.swift`, `ReviewSession.swift`. Interval projection helper sits in UI calling the existing Core engine.

---

## Workstream E — First-run: guided + starter deck

**Guided intro:** a 2–3 screen first-launch sequence teaching the grace-first promise (fall behind without punishment; AI/manual capture; review rhythm). Shown once; skippable; gated by a `hasCompletedOnboarding` flag.

**Starter deck:** a one-tap "Load a sample deck" that seeds a small, well-crafted bundled deck (e.g., a mixed-topic ~10–15 card pack) so Review and Library are immediately non-empty and the loop is demonstrable in seconds. Sample content bundled as a resource; loaded via `cardStore.create(...)`.

**Empty states:** every empty surface (Review, Library) gets clear CTAs — **Add card · Import · Load sample** — instead of dead ends.

**Components touched:** new `OnboardingView` + flag in app storage; `ReviewScreen`/`LibraryView` empty states; bundled sample-deck resource + a small loader.

---

## Workstream F — Cross-cutting trust

**Silent-failure audit:** review the swallowed-error patterns (notably the `enqueue` stub draft, and `LibraryView.load()` swallowing errors into `cards = []`) and ensure failures are surfaced or logged, not silently masked. The `enqueue` fix in B is the priority instance.

**Accessibility pass:** Dynamic Type + VoiceOver on all new/changed surfaces (editor, onboarding, review buttons with interval labels, empty-state CTAs), consistent with the project's a11y intent.

---

## Architecture notes

- Module boundaries unchanged: Core (persistence/scheduling/cloze markup), Intelligence (authoring/availability/OCR), UI (views), App (wiring/state). UI reads `AuthoringAvailability` from Intelligence; it does **not** import FoundationModels directly.
- New units kept small and independently testable: `CardEditorViewModel` (create/edit + validation), `CaptureAvailabilityModel` (availability→UX), `IntervalProjection` helper (ratings→intervals), `SampleDeckLoader`, `OnboardingState`.

## Testing strategy

- **Swift Testing** primary. New unit tests: editor create/edit + validation; availability→UX mapping; fallback-preserves-captured-text; interval-projection values vs engine; sample-deck loader; onboarding-flag gating.
- **Permission hygiene** verified by absence of prompts at launch (manual device/sim check + code review that requests are visibility-gated).
- **On-device QA gate** (cannot run on simulator): live Q&A + Cloze generation, camera capture→OCR→draft, and AI-unavailable fallback all verified on a real Apple-Intelligence device.

## Exit gates

1. New user can create a card by typing within seconds of first launch (no AI, no Anki, no camera).
2. No camera or paste permission prompt appears at cold launch or on the Review tab.
3. Cloze capture uses the live service; AI-unavailable states show a clear message and route to manual entry with any captured text preserved.
4. Review shows interval previews, session progress, and a session-complete summary; card is visually framed.
5. First launch offers a guided intro and a one-tap sample deck; all empty states have actionable CTAs.
6. On-device QA checklist passed on a real device; new surfaces pass a Dynamic Type + VoiceOver pass.
7. Full Swift Testing suite green; build clean.

## Open questions

- Exact sample-deck content/theme (decide during implementation; ~10–15 mixed cards).
- Whether the guided intro is full-screen pages or a single scrollable explainer (decide in UI build; bias to minimal).
