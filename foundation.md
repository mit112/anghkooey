# Foundation — Product Concept (Working Name: Rewind)

> Status: Pre-implementation. This document supersedes `rewind_concept.md` and is the source of truth for the next session, where we will produce an implementation plan.

---

## 0. Open Decisions To Resolve Before Implementation

These are the things that must be locked before we write `implementation_plan.md` next session. Each has my current recommendation; treat them as defaults to either confirm or override.

| # | Decision | Recommendation |
|---|---|---|
| 1 | **Product name** | ~~Open~~ **Resolved 2026-05-20: Anghkooey** (tagline: *remember everything*). Bundle ID convention `com.<author>.anghkooey`; SPM packages renamed to `AnghkooeyCore` / `AnghkooeyIntelligence` / `AnghkooeyUI`. Availability check (App Store, domain, USPTO TESS) still required before first public push. |
| 2 | **iOS version floor** | ~~Open~~ **Resolved 2026-05-20: iOS 26 only.** FoundationModels requires it; on-device AI is the wedge. |
| 3 | **Monetization** | ~~Open~~ **Resolved 2026-05-20: Free.** No paywalls, no IAPs in v1. Only out-of-pocket cost is the Apple Developer Program ($99/year), required to ship to App Store. Revisit only if a clear reason emerges; until then, free stays free. |
| 4 | **Distribution scope** | ~~Open~~ **Resolved 2026-05-20: iPhone first; iPad and Mac post-launch; watchOS never.** |
| 5 | **Success metric for MVP** | ~~Open~~ **Resolved 2026-05-20: This is primarily a showcase / portfolio product.** Not chasing user growth. "Done" = a v1 that meets the §9 Quality Bar and that the author is willing to put in front of recruiters and friends. No D30 retention target. Telemetry stays out of v1 unless a specific question arises that needs it. |

---

## 1. Problem (Tightened)

Spaced repetition is the most evidence-backed technique for long-term retention, but two specific frictions kill it for most users:

1. **The card-creation tax.** Authoring atomic, well-formed flashcards is skilled labor. Most users spend the majority of their time formatting cards instead of reviewing them.
2. **The backlog cliff.** Miss a few days of reviews in a traditional scheduler and the queue snowballs. Users open the app, see hundreds of due cards, feel dread, and stop.

A third minor friction worth naming but not over-claiming: **privacy.** A nontrivial slice of serious learners (researchers, clinicians, lawyers) actively avoid sending personal study material to cloud LLMs.

We are not claiming dropout statistics we can't source.

---

## 2. The Wedge

> **Capture in the moment. Let the device do the authoring. Never punish a missed day.**

Three concrete promises, in priority order:

1. **Capture → reviewable card in under 10 seconds**, on-device, with no network round trip.
2. **A queue that never makes you feel behind**, even after a two-week gap.
3. **Your study material never leaves your device** unless you explicitly enable iCloud sync to your own private CloudKit database.

If we can't ship all three convincingly, we don't have a product.

---

## 3. Principles

1. **Capture is the product.** Review experience is table stakes; capture quality is the differentiator. Optimize ruthlessly for time-to-card.
2. **The AI is an editor, not an author.** It restructures user-provided material into atomic recall prompts. It does not invent facts, summarize, or "add context." Hallucination on a flashcard app is a trust-killing bug.
3. **Grace over guilt.** No streaks. No red badges by default. No shame copy. The app accommodates human schedules.
4. **On-device by default.** Cloud sync is opt-in, private CloudKit only, never a third-party server.
5. **Ship the smallest thing that proves the wedge.** Every "cool" feature defers until the core loop is loved.

---

## 4. MVP Scope (What We're Actually Building First)

### In Scope — V1

**Capture surfaces (pick two, ship well):**
- **Share Sheet extension** — primary path. Highlight text in Safari/Books/Kindle/Mail → Share → app. Raw text queued for generation.
- **In-app camera OCR** — using the Vision framework. For physical books, whiteboards, handouts.

**Card generation:**
- **Q&A only.** No cloze, no "contextual application" cards in v1.
- Apple FoundationModels (`LanguageModelSession` + `@Generable`) to parse raw text into 1–N Q&A pairs.
- User reviews and accepts/edits each generated card before it enters the deck. **No silent auto-insertion.**
- Mnemonics are an optional, per-card, user-triggered button — not auto-generated.

**Scheduling:**
- **FSRS-6** with default parameters, ported from a reference implementation (ts-fsrs or rs-fsrs is the math source of truth).
- No personalized parameter optimization in v1 — ship the default 21-parameter weights. Personal optimization is v2.

**Review UX:**
- Swipe-to-grade card stack: left = Again, right = Good, up = Easy. Down = edit. (Four-grade FSRS rating.)
- Haptics on every grade.
- One review surface. No widgets, no Live Activities, no Sketchpad in v1.

**Grace features:**
- **Cushion Mode**: when the due queue exceeds a threshold (default 50), the UI shows "today's batch" of 15–20 instead of the full backlog count. The remaining overdue cards are still tracked; we just don't display the dread number. **This is a UI veil, not an algorithmic redistribution** — be honest about that internally and externally.
- **Freeze**: a manual "I'm away" toggle that shifts all `nextReviewAt` forward by N days when you return.

**Organization:**
- Tags-first. AI proposes tags on card creation; user can edit. Smart filters/views built on tags.
- A single flat "Library" of cards. No nested decks in v1. (One optional grouping primitive — call it a "Collection" — can be added if usability testing demands it.)

**Storage:**
- SwiftData, local only. iCloud private-database sync as a v1.1 follow-up if SwiftData's CloudKit integration is stable enough by then; otherwise v2.

### Explicitly Out of Scope for V1
- Anki `.apkg` import/export (deferred — see §6).
- Cloze deletion cards.
- "Contextual application" generated cards.
- Voice/Siri capture (deferred to v1.1 — `AppIntents` donation is straightforward but UX-testable only post-launch).
- Home/Lock Screen widgets.
- Live Activities / Dynamic Island.
- Sketchpad / Apple Pencil drawing.
- AI-generated images.
- iPad-optimized UI.
- macOS app.
- Personal FSRS parameter optimization.
- Streaks, leaderboards, social.
- Multi-device sync.

The point of this list: we say no to all of it on purpose. Each item is a future bet, not an MVP requirement.

---

## 5. Anti-Goals

- We are **not** a note-taking app. No wiki, no backlinks, no daily-notes. If a user wants Obsidian, send them to Obsidian.
- We are **not** an Anki replacement on day one. We are not trying to win the power-user market in v1 — we are trying to win the "tried Anki, gave up" market and the "never tried SRS but always wanted to" market.
- We are **not** a quiz app. No multiple choice, no trivia, no gamified quiz modes.
- We are **not** an LLM chat app. The AI is a structured-output tool, not a conversational partner.

---

## 6. Anki Strategy

Reversed from the original concept's recommendation.

- **V1: No import.** Don't burn engineering capacity on `.apkg` parsing, media handling, and note-type translation when the MVP wedge is capture, not migration.
- **V1.5 or V2: One-way import only.** `.apkg` → our schema. No export back to Anki. Position it as "bring your library, leave the friction."
- Reasoning: serious Anki users will not abandon their tuned setup for a swipe UI. Lapsed Anki users (much larger group) will appreciate import as a bridge — but only once we've earned trust on the core loop.

---

## 7. Personas (Tightened)

Two primary personas for v1. Drop "Liam the med power-user" — he's a v2 persona.

### Primary: Clara — the lapsed/curious learner
Reads books, listens to podcasts, encounters interesting concepts daily, and forgets 90% of them within a week. Has heard of Anki, possibly tried it, definitely quit. Will pay $25 once if the capture loop genuinely feels effortless and the review surface doesn't shame her.

### Primary: Kenji — the language learner
Encounters vocabulary in the wild (subtitles, signs, conversations). Wants to capture it instantly and review during commute. Will tolerate v1 lacking sketchpad and audio if capture is fast enough.

### Deferred: Liam — the medical/professional power user
High-volume, deeply invested in Anki. Not our v1 buyer. We design v1 such that **we don't preclude winning him later** — meaning: solid FSRS-6 implementation, exportable data, no proprietary lock-in.

---

## 8. Risks & Honest Concerns

| Risk | Mitigation |
|---|---|
| FoundationModels card quality is mediocre on a 3B model | Heavy prompt engineering + structured output via `@Generable` + mandatory user review/edit step before cards enter the deck. Set quality bar via internal eval set before launch. |
| iOS 26 floor cuts addressable market significantly at launch | Accept it. The wedge depends on FoundationModels. Revisit floor in v2. |
| "Cushion Mode" is marketing dressing on a queue limiter | Be honest in copy. Call it what it is: "show me a manageable batch today." Don't claim algorithmic novelty. |
| Capture flow latency (Share Sheet → AI generation) feels slow | Benchmark early. If on-device generation exceeds ~3 seconds for typical input, redesign the UX to be asynchronous with a notification when cards are ready. |
| Name collision with existing "Rewind AI" / Limitless | Rename before any public-facing artifact (repo, domain, App Store metadata). |
| FSRS-6 implementation bugs damage user retention silently | Port from a well-tested reference (rs-fsrs or ts-fsrs), mirror their test suite in Swift Testing, treat scheduler as the most safety-critical module. |
| Privacy claim is undermined by analytics/crash reporting | If we ship telemetry at all, it must be on-device aggregated and opt-in. No third-party SDKs (no Firebase, no Mixpanel, no Sentry on user content). |

---

## 9. Quality Bar

Before v1 ships, all of the following must be true:

1. Time from "tap Share" to "card ready to review or edit" is < 5 seconds median on iPhone 15 Pro / iOS 26.
2. AI-generated cards pass an internal quality rubric (atomicity, specificity, no hallucination) on a held-out evaluation set of 100 inputs at ≥ 80%.
3. FSRS-6 implementation passes a parity test suite against a reference implementation (ts-fsrs or rs-fsrs) on identical input sequences.
4. App functions fully with airplane mode on, end-to-end.
5. No crashes, no main-thread blocks > 100ms, no memory growth across a 30-minute review session.
6. The phrase "you're behind" or any equivalent shame copy appears nowhere in the UI.

---

## 10. What Next Session Produces

The implementation plan session should produce `implementation_plan.md` covering:

1. **Project skeleton** — SPM modularization (Core / Intelligence / UI), Swift 6 strict concurrency, target iOS 26.
2. **FSRS-6 engine** — source of truth, port plan, test parity strategy.
3. **SwiftData schema** — `Card`, `ReviewLog`, `Tag`, `Collection` (optional). Migration plan from day one.
4. **FoundationModels integration** — `@Generable` types, prompt template, evaluation harness.
5. **Vision OCR pipeline** — `VNRecognizeTextRequest` flow, text cleanup heuristics.
6. **Share Sheet extension** — entitlements, app-group storage, handoff to main app for generation.
7. **Review UX** — gesture model, haptics, animation choices.
8. **Cushion Mode** — exact queue-display logic, what's stored vs. what's shown.
9. **Verification plan** — Swift Testing harness, FSRS parity suite, AI output eval set, manual QA checklist.
10. **Cut lines** — what we will descope if any milestone slips.

---

*Treat this document as the locked contract for v1 scope. Anything not in here is a v2 conversation.*
