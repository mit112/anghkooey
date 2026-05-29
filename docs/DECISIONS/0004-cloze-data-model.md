# 0004 — Cloze Deletion Data Model: One Card Per Deletion

**Date:** 2026-05-28
**Status:** Accepted
**Milestone:** M7 — Cloze Deletion Cards

---

## Context

M7 adds Anki-style cloze deletion cards. A single passage of source text can carry
several deletions — e.g. `The {{c1::mitochondrion}} is the {{c2::powerhouse}} of the
cell.` — and the user is meant to recall each blank independently. The product and
portfolio question is how to represent that in SwiftData without disturbing the two
subsystems that already work and are expensive to re-validate: the **FSRS-6 scheduler**
and the **swipe-to-grade review UI**.

Both of those subsystems consume a `Card` purely as a pair of pre-rendered strings —
`question` and `answer` — plus its FSRS state. Neither knows or cares how those strings
were produced. That existing contract is the lever this decision pulls on.

Cloze also introduces a new hazard absent from Q&A cards: **answer leak within a single
study session.** If two deletions from the same sentence surface back-to-back, reviewing
`c1` reveals the full sentence and gives away `c2`. The data model has to make
per-session burying expressible.

---

## Decision

**Each cloze deletion becomes its own independent `Card`.** A passage with N deletions
fans out into N sibling cards. Concretely:

- Each sibling has its `question`/`answer` **pre-rendered to plain strings** at creation
  time — the exact same two fields a Q&A card uses. For deletion `cK`, the answer is
  the revealed blank and the question is the passage with `cK` blanked (and other
  deletions shown).
- Siblings share a `clozeGroupID` (UUID) so the group can be reasoned about as a unit.
- `clozeIndex` records which deletion (`cN`) the sibling represents.
- `clozeSourceText` retains the original `{{cN::answer::hint}}` markup on every sibling
  for provenance and future re-authoring.
- `clozeBuriedUntil` (Optional `Date`) supports same-session leak prevention: when one
  sibling is reviewed, the rest are buried until the next local day.
- `cardType` distinguishes `.qa` from `.cloze`.

All five fields are Optional on `Card`, added in `AnghkooeySchemaV5` via a lightweight
V4→V5 migration. A Q&A card simply leaves them nil.

The single grammar authority for the markup is `ClozeMarkupParser` in AnghkooeyCore —
AI output, the manual editor, and future Anki import all parse through it, and
`CardStore.createClozeCards(from:tags:now:)` consumes its `ClozeTemplate` output.

---

## Rejected alternatives

### 1. One card holding all blanks

Store a single `Card` per passage and render all blanks at review time, grading the
whole template at once.

- **Pro:** Simplest schema — no sibling fan-out, no `clozeGroupID`.
- **Con (decisive):** The review UI would have to learn cloze structure — how to mask one
  blank while showing the rest — instead of consuming two opaque strings. That breaks the
  `question`/`answer` contract the swipe stack depends on.
- **Con:** FSRS scheduling collapses to **per-template, not per-deletion.** A learner who
  knows `c1` cold but keeps missing `c2` would have both intervals dragged by the worst
  blank. Per-deletion scheduling is the entire pedagogical point of cloze in Anki, and
  this design throws it away.
- **Con:** Retiring or suspending a single weak deletion becomes impossible without a
  sub-card concept — which is just sibling cards wearing a disguise.

### 2. Render-on-the-fly (store only source + indices)

Persist `clozeSourceText` and the deletion indices, and run `ClozeMarkupParser` at
**review time** to produce `question`/`answer` on demand.

- **Pro:** Editing a cloze passage would be easier — change the source, re-render, done.
- **Con:** `ClozeMarkupParser` would have to be reachable on the hot review path, coupling
  the scheduler/review surface to grammar code it otherwise never touches. A parser bug
  could then break *review*, not just *authoring*.
- **Con:** Baked strings are already exactly what FSRS, `CardStore`, and the review UI
  expect. Rendering on the fly buys flexibility the v2 scope does not ask for: **editing
  a cloze card after creation is explicitly out of scope.** Paying a coupling cost for an
  unused capability is the wrong trade.

The pre-rendered, one-card-per-deletion design wins because it keeps the two hardened
subsystems (FSRS, review UI) completely unchanged, and the only thing it gives up —
in-place editing — is not in scope.

---

## Consequences

- **Cloze cards are immutable post-creation.** There is no per-deletion edit path:
  `CardStore.update(id:question:answer:tags:)` stays Q&A-oriented, and the Library UI
  wires no edit affordance for cloze. Re-authoring means **replacing the group** —
  deleting the siblings and running `createClozeCards` again.
- **Group immutability is enforced by omission**, not by a guard. Nothing accepts a cloze
  card into the update path, so there is nothing to mutate inconsistently. This is
  deliberate for M7; a proper edit-the-group flow is deferred.
- **FSRS scheduler and review UI required zero changes.** They continue to read
  pre-rendered `question`/`answer` strings and have no awareness of cloze.
- **Same-session leak is prevented persistently.** `clozeBuriedUntil` is honored by the
  `dueCards` filter (via the `distantPast` sentinel pattern for `#Predicate` over an
  Optional `Date` — a SwiftData expressivity limitation) and set by `CardStore.apply`,
  which buries unreviewed siblings until the next local day.
- **Group-level operations need the `clozeGroupID` index.** Deleting or re-authoring a
  group is a query over `clozeGroupID`; siblings are never assumed contiguous.
- **Storage cost scales with deletion count**, not passage count. This matches the review
  semantics — N independent recall events deserve N FSRS state machines — and is accepted.

---

## Status

**Accepted — M7.** Supersedes nothing; `foundation.md §4` listed cloze as explicitly out
of scope for v1, and this ADR records the data model for the v2 milestone that ships it.
