# Overnight run manifest — TEMPLATE

> Copy to `docs/overnight/RUN.md` and fill in per run. Every fresh launcher
> invocation reads this file as its authoritative protocol, so keep it complete
> and self-contained — a cold orchestrator with no prior context must be able to
> execute one unit correctly from this + the ledger + git alone.

## Run
- **Run id / date:** <e.g. 2026-07-11 Tier 2>
- **Repo:** /Users/mitsheth/dev/anghkooey  (canonical, non-iCloud)
- **Integration branch:** <e.g. overnight/backlog-2026-07>  (branch off this; PR into this)
- **Main branch:** main  (per-tier promotion target; never force-push)
- **Source of truth for scope:** memory `anghkooey-review-backlog-2026-07` + the issue bodies.

## Model & consult routing
- Orchestrator: **Opus** (this process). Execution subagents: dispatch with **model: sonnet**.
- Consult / arbitration + checkpoints: `codex exec -m gpt-5.5 -c model_reasoning_effort=<high|xhigh> "..." </dev/null`
  - **CHECKPOINTS: `high` + compact diff-only packets** (xhigh times out on big packets). **ARBITRATION memos: `xhigh` ok.** Always `</dev/null`; ignore the `mcp.indeed.com` line. See memory [[gpt5-checkpoint-effort-high-compact]].

## Per-unit protocol (every unit)
1. **Arbitrate if decision-bearing:** memo (question/options/tradeoffs/recommendation) → GPT-5.5 → implement the agreed choice → log `⚖️ DECISION (GPT-5.5-arbitrated, pending review)` on the issue + ledger. Reversibility is HARD: prefer the option with no data migration / no unversioned on-disk schema change; version or keep-additive otherwise. Match an existing sibling pattern before inventing a new mechanism (memory [[match-local-pattern-before-new-mechanism]]).
2. **Brief a Sonnet subagent** (absolute paths; NO git writes by the subagent; load the matching ECC Swift skill; TDD fail-first; run `bash scripts/ci.sh` in the FOREGROUND; fixed report schema).
3. **Review by TOUCHED SURFACE, not diff size:** central (AppState/persistence/CardStore/FSRS/scheduler/InboxDrainer/widget-snapshot/migrations/CI) OR error-path → full `ecc:swift-reviewer` (+ `ecc:silent-failure-hunter` on error handling). Leaf UI/docs → orchestrator self-review. Apply superpowers:receiving-code-review: verify each finding before acting; rebut false/pre-existing ones.
4. **Orchestrator OWNS the single authoritative `bash scripts/ci.sh`** on the merge candidate — never trust a subagent's CI. Content-addressed skip only when the tree hash matches a prior green run AND nothing changed since; a parallel-branch merge off a divergent base is a NOVEL tree → must re-run.
5. **One issue = one branch `issue/NN-slug` = one PR into the integration branch**, merged by the orchestrator on green ci.sh + review pass + acceptance criteria.
6. **GPT-5.5 invariant checkpoint after merge** (compact packet; the invariants to attack + changed hunks). Findings fixed or explicitly rebutted before moving on. Checkpoint-hardening → its own `issue/NN-...-hardening` PR.
7. Comment outcome on the issue; append the ledger `STATUS` line; STOP.

## Git & commits
- Targeted `git add <files>` (NEVER `git add -A`). Imperative messages, one logical change. **NO AI attribution** (no Co-Authored-By, no "Generated with"). Sync the integration branch after each merge.

## Stop conditions (record `STATUS <#> BLOCKED` and halt the run)
- (a) all units done → final pass promotes + handoff; (b) blocked on external creds/account/**physical device** → comment + label `question` + SKIP (cap 2 technical skips); (c) a test flakes 3× (quarantine, note the known SwiftData-parallel SIGSEGV — re-run once before treating as real); (d) anything needs a physical device (widget/Live-Activity: implement + simulator-verify, FLAG device-only for the human); (e) human says stop. Decisions are NOT skips.

## Units (also mirrored, ordered, in units.txt)
> Do code-verifiable units first, device-risky ones last. One section per unit.

### #<NN> — <title>
- **Slug:** <NN-slug>  **Review tier:** <full-reviewer | self-review>  **Device risk:** <none | flag F1>
- **Depends on:** <none | #MM merged first>
- **Resume plan / approach:** <hub files w/ real line refs, the arbitrated decision if known, the acceptance criteria verbatim, the specific invariants to attack>

### #<NN> — <title>
- ...
