# AGENTS.md — Anghkooey

> Loaded into every session. Keep this file tight; it is context, not documentation.

## Why this project exists

Rewind is **both a real product and a deliberate portfolio piece**. It exists to close specific 2026 iOS skill gaps identified in `ios-skill-map-2026.md` (research dated 2026-05-20) while solving a problem the author actually cares about: making spaced repetition survivable for normal humans.

The project is the practical successor to **Project A — "Verbal"** from the skill map. The product surface changed (journaling → spaced repetition) because the SRS wedge is sharper and the on-device-AI value proposition is more obvious for flashcard generation than for journaling reflection. The portfolio intent is identical.

## Source-of-truth documents (in this folder)

- `foundation.md` — locked product concept and v1 scope. **Authoritative for what we build.**
- `ios-skill-map-2026.md` — the research that motivated this project. **Authoritative for why.**
- `rewind_concept.md` — original brainstorm. Superseded by `foundation.md`; kept for history.
- `implementation_plan.md` — first-pass technical plan. **Will be rewritten in the next session** from `foundation.md`.

If any of these conflict, `foundation.md` wins for product scope and `ios-skill-map-2026.md` wins for engineering-skill targets.

## Skill gaps this project must close

These are the gaps from §Phase 2 of the skill map that Rewind is explicitly designed to demonstrate. Every architectural decision should defend at least one of these:

1. **Foundation Models framework** — `LanguageModelSession`, `@Generable`, optional custom `Tool`. (Gap rank #1, demand 5/5.)
2. **App Intents + Siri/Spotlight donation** — even if voice capture is deferred to v1.1, the AppIntent surface area should exist. (Gap rank #2.)
3. **CloudKit private DB sync** via SwiftData — the Apple-native counterpart to the author's existing Firebase depth. (Gap rank #4, demand 5/5.) Deferred to v1.1 but designed-for from day one.
4. **SPM modularization** — at minimum `RewindCore` / `RewindIntelligence` / `RewindUI`. (Gap rank #6.) No more single-target monoliths.
5. **Swift Testing** as the primary suite, with parameterized tests. XCTest only for UI tests. (Gap rank #7.)
6. **MetricKit / `os_signpost` / Instruments** — ship a `PERFORMANCE.md` with before/after traces. (Gap rank #5, senior signal.)
7. **WidgetKit + interactive Live Activity** — deferred to v1.1 but reserve the architecture seam. (Gap rank #3.)
8. **Vision OCR** via `VNRecognizeTextRequest` — part of the capture story, also closes the Vision exposure gap. (Adjacent to gap #11.)

## Anti-patterns we are *not* repeating from prior projects (StreakSync, FlickSwiper)

- **No single-target monolith.** Modularize via SPM from day one.
- **No Firebase as the sync substrate.** This project demonstrates CloudKit. Firebase is acceptable for analytics-only if needed, but card data lives in SwiftData + CloudKit private DB.
- **No XCTest-only test suite.** Swift Testing is primary.
- **No skipping the perf write-up.** A `PERFORMANCE.md` with an Instruments trace and a MetricKit screenshot is a v1 ship requirement.
- **No skipping `PrivacyInfo.xcprivacy`.** Required-reason API audit goes in the README.

## Constraints inherited from the author's global preferences

- Swift / SwiftUI, value types over classes, async/await over GCD, OSLog over print.
- Protocol-oriented design with production + mock implementations for every service crossing a module boundary.
- Direct, no-fluff communication. Explain the "why" for non-obvious decisions. Push back if an approach looks wrong.

## What this project is *not* trying to be

- Not a portfolio of every iOS framework. We picked the gaps above on purpose; resist scope-creep into watchOS, visionOS, TCA, Passkeys, App Attest. Those belong to **Project B (PaceLab)** and **Project C (Vouch)** in the skill map, not here.
- Not a clone of an existing SRS app. The product wedge (capture-first + on-device AI authoring + grace-first scheduling) is the differentiator.
- Not a vehicle for AI hype. The on-device AI exists because it removes the card-authoring tax, not because LLMs are fashionable.

## Naming note

Product name: **Anghkooey** (tagline: *remember everything*), resolved 2026-05-20. Replaces the working name "Rewind" which collided with Rewind AI / Limitless. Bundle ID `com.<author>.anghkooey`; SPM packages are `AnghkooeyCore` / `AnghkooeyIntelligence` / `AnghkooeyUI`. The local repo directory `/Users/mitsheth/Documents/rewind/` keeps its current path until a deliberate rename — that's a workspace concern, not a product one. Name availability (App Store, `.com`/`.app`, USPTO TESS) is **not yet verified** and must be checked before any public push.

## Decision rule when in doubt

When a tradeoff arises between **product polish for end users** and **portfolio signal for recruiters**, pick the option that serves both. If forced to choose, pick the option that serves users first — a recruiter pattern-matches faster on a beloved shipped app than on a checklist of frameworks.

## Model routing policy (cost discipline)

This is a long-running solo project. Opus runs cost ~5× Sonnet on API pricing and consume the Max-plan rate limit much faster. Default to Sonnet; escalate to Opus only for the high-judgment work.

**Default model for execution sessions: Sonnet 4.6.** Open every execution session with `/model sonnet`.

**Use Opus 4.7 for these specific things — and only these:**
- **FSRS-6 port + parity harness** (M1). Math correctness is non-negotiable.
- **FoundationModels prompt engineering and eval analysis** (M2). Iterative reasoning over rubric.
- **ADRs, design docs, milestone-entry/exit reviews.** Judgment > throughput.
- **`PERFORMANCE.md` and `ARCHITECTURE.md` write-ups.** Recruiters read these.
- **Debugging anything Sonnet can't solve in two attempts.** The escape hatch.

**Use Sonnet 4.6 for everything else:**
- Scaffolding, SwiftData models, SwiftUI views, Share Extension wiring, OCR pipeline, CI scripts, test boilerplate, file moves, find-replace, lint fixes.

**Don't use Haiku.** The model-switching overhead isn't worth the marginal saving over Sonnet for this stack.

### Subagent dispatch pattern

The plan is built for `superpowers:subagent-driven-development`. The optimal cost pattern is:
- **Parent session on Opus** when orchestrating + reviewing.
- **Subagents dispatched with `model: "sonnet"`** for execution work.
- This lets Opus do the thinking while Sonnet does the typing.

For pure-execution sessions (M0 scaffolding, M4 view-building), keep the parent on Sonnet too — no point paying for Opus orchestration when nothing requires it.

### Other cost-saving practices

- **Don't run multi-hour Opus sessions.** Most sessions don't need it.
- **Don't re-read source-of-truth files every session.** Quote inline from `foundation.md`, this file, and the plan.
- **Disable GateGuard for routine execution** if it's not catching real bugs (`ECC_GATEGUARD=off`). Keep it on for sessions touching secrets or destructive ops. Each fact-prompt costs 200–500 tokens.
- **Always do milestone exit reviews on Opus.** A 5-minute Opus conversation that catches a wrong architectural decision saves days of Sonnet rework.

### Concrete starting command for the next session

```
/model sonnet
"Execute M0 from docs/superpowers/plans/2026-05-20-rewind-implementation-plan.md
using superpowers:subagent-driven-development. Default subagent model: sonnet.
Switch me to opus before the FSRS port in M1 and before any ADR."
```

---

## Claude / Codex Collaboration Model

This project runs a two-agent workflow. **Claude = planner / reviewer / architect. Codex = implementation / verification.**

### Ownership split

| Claude owns | Codex owns |
|---|---|
| Writing milestone plans | Writing most Swift code |
| Breaking work into small tasks | Running builds and tests |
| Architecture decisions | Fixing compile failures |
| Reviewing Codex diffs before commit | Updating task checkboxes with evidence |
| Catching scope creep against `foundation.md` | Producing clean commits |
| Milestone exit reviews | Preparing diffs for Claude review |
| ADRs | |

### Prompt templates

**Claude → task plan for Codex:**
```
Plan the next [milestone] task for Codex.

Use:
- foundation.md
- docs/superpowers/plans/<active-plan>.md

Output:
1. exact task scope
2. files Codex may edit
3. files Codex must not edit
4. tests Codex must write first
5. verification command
6. commit message
7. review checklist
```

**Codex → execute task:**
```
Execute the task exactly as planned by Claude.

Before editing:
- read AGENTS.md
- read the active milestone plan
- inspect git status
- confirm the task scope

Rules:
- do not expand scope
- write tests before implementation where practical
- run the specified verification command
- update the Handoff Ledger and task checkboxes
- do not commit unless the task is green
```

**Claude → review Codex diff:**
```
Review Codex's diff against:
- foundation.md
- active milestone plan
- AGENTS.md / CLAUDE.md

Focus on:
- bugs
- scope creep
- architectural drift
- missing tests
- incorrect Swift/iOS API assumptions
- whether verification evidence is real

Do not rewrite unless necessary. Produce findings first.
```

### Handoff Ledger (add to each milestone plan)

```markdown
## Handoff Ledger

- Current owner:
- Current branch:
- Last good commit:
- Active task:
- Completed:
- Verification run:
- Known failures:
- Next step:
- Review needed from:
```

### Task completion gate

No task is complete until **both** are true:
1. Codex has run verification and updated the Handoff Ledger.
2. Claude has reviewed the diff — or explicitly skipped review for a trivial task.

### FSRS math exception

The FSRS-6 port requires extra scrutiny. Claude/Opus should plan and review aggressively. Codex can do the mechanical port and the parity harness, but only after Claude has pinned the reference behavior. Math correctness is non-negotiable.

### Contract-first task shape (added 2026-05-20 after M1 T1 misfire)

The original "Claude writes detailed prose spec; Codex faithfully executes" assumption is too weak. On multi-file design work (schemas, type hierarchies, public APIs), Codex on the default model treats prose as guidance and falls back to its priors — producing plausible-looking but off-spec code (e.g. `Deck`/`front`/`back` instead of `Tag`/`question`/`answer`), then writing tests that pass against the wrong implementation. The green light becomes meaningless because the same agent authored both halves.

**Rule:** for any task that involves designing public symbols (types, properties, methods, file layout), Claude owns the contract. Codex's job is only to make a Claude-authored contract pass — never to design it.

**Claude owns (the contract):**
- File layout (paths + names)
- Public type names
- Public property + method signatures
- Failing tests that pin exact symbol names and behaviors
- The forbidden-patterns list ("do not introduce X, Y, Z")
- The acceptance checklist + review gate

**Codex owns (the implementation, under the contract):**
- Filling method bodies
- Adding private helpers
- Satisfying compile errors
- Making the Claude-authored tests pass
- Running verification
- Updating the Handoff Ledger

**Preflight gate (Codex must produce before editing):**
A spec-lock declaration listing what it will create AND what it will not create, derived from the contract files Claude shipped. If the preflight contradicts the contract, Codex stops and asks. No code is run from a wrong preflight.

**Tripwire (cheap and effective):**
Each milestone may ship a `scripts/m{N}-forbidden-patterns.sh` that `rg`'s for banned names in the source tree and exits non-zero on any hit. Add it to the verification command, not just the review checklist.

**Checkpointed review (no big-bang reviews):**
- Step 1: Codex outputs the preflight. Claude reviews.
- Step 2: Codex implements bodies only — no renaming, no new public types, no new test files. Claude reviews the diff.
- Step 3: Codex fixes only reviewed items.
If Codex skips a step or invents a public symbol that wasn't in the contract, the run is aborted.

**Demotion rule:**
If a milestone's load-bearing module (schema, FSRS math, persistence) sees two Codex attempts rejected for going off-spec, demote Codex for that module to build-fix / DocC / test-runner duty only. Claude/Opus writes the rest of that module. Cleaning up invented architecture costs more Opus tokens than authoring it correctly the first time.
