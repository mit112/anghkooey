# Workflow efficiency retro — overnight run session 2 (2026-07-09)

Behind-the-scenes analysis of *how the session ran*, for tuning session 3+.
Numbers are exact where captured from tool telemetry; wall-clock from git author
timestamps; cost from the harness cost-hook readouts.

## 1. Headline metrics

| Metric | Value |
|---|---|
| **Active wall-clock** | ~3 h 13 min (baseline ci.sh 10:07 → handoff report 13:20). A ~2.5 h user pause followed, then docs+this retro. |
| **Output** | 9 PRs merged (#76–#84) + 3 docs commits + 2 issues filed (#85/#86). 21 files, +1548/−175. |
| **Session cost** | ~$38 through #29 → ~$203 through all code → ~$236 after handoff docs → ~$268 after this retro. **≈$203 for the 9-PR code work (~$22.5/PR).** |
| **Delegated tokens** | **1.97 M across 21 dispatches** — 9 execution subagents (Sonnet) = 1.00 M; 8 review agents (ecc) = 0.64 M; 4 GPT-5.5 consults = 0.33 M. |
| **Subagent compute** | ~70 min execution + ~59 min review = **~129 min of subagent wall-time** (overlapped with orchestration; some parallel). |
| **xcodebuild/ci.sh cycles** | ~28 full runs (11 by orchestrator + ~9 by execution subagents + ~8 by reviewer agents each running their own build). Each app-target run ≈ 20–27 s test + ~30–60 s build. |
| **Orchestrator** | Opus 4.8 (1 M context), single continuous context for the whole session. StrategicCompact hook fired at 50 tool calls; never compacted. |

## 2. Per-issue timeline (wall-clock, commit→commit)

| Issue | Wall | What drove it |
|---|---|---|
| bootstrap+#29 | 10:07→10:49 (~42 min) | plan review + **3-way review fan-out** + a full **round-2 subagent**. Heaviest single unit (~520 K tokens delegated, ~$28–30). |
| #32 | ~19 min | 1 impl + 1 swift-reviewer + 1 round-2 (gated test). |
| #30 | ~23 min | 1 impl (subagent handed back mid-ci.sh) + 1 swift-reviewer; orchestrator applied 2 polish fixes by Edit. |
| #34 | ~20 min | 1 impl + 1 swift-reviewer. |
| #31 | ~13 min | 1 impl (handed back mid-ci.sh) + 1 swift-reviewer. Fastest issue. |
| #33 | ~40 min | impl subagent ran 17 min, swift-reviewer 14 min — the two longest single dispatches. |
| Epic-10 checkpoint hardening | ~11 min | GPT-5.5 epic checkpoint (134 K tok) + orchestrator-authored fix + tests. |
| #56 | ~11 min | 1 impl subagent (tooling); no swift-reviewer (GPT tooling checkpoint instead). |
| Tooling checkpoint hardening | ~8 min | GPT-5.5 tooling checkpoint (135 K tok) + orchestrator Edit. |

## 3. Where the money/time actually went

**The dominant cost is the Opus orchestrator context, not the subagents.** Sonnet
execution + ecc review + GPT total ~1.97 M tokens but run at Sonnet/GPT pricing.
The orchestrator is Opus (~5× Sonnet) on a **single 1 M-context session that only
grows** — every turn re-reads a transcript stuffed with full subagent prose
reports, full `git diff` dumps, and full checkpoint replies. By late session each
turn was re-reading ~200 K+ tokens at Opus rates. This is the #1 lever.

Secondary drivers, in order:
1. **swift-reviewer on every diff (8 runs, 640 K tok, ~59 min).** Warranted for
   AppState/concurrency/error-path hubs; **overkill for 3–15 line UI-wiring diffs**
   (#32 was 3 prod lines; #31/#34 were small). avg reviewer = 80 K tok / 7.3 min.
2. **The #29 3-way review fan-out** (swift + silent-failure-hunter + pr-test-analyzer
   = 248 K tok). Right for a hub rewrite; I correctly did NOT repeat it after #29
   (folded silent-failure/test concerns into the single swift-reviewer prompt) —
   that tightening should be the default, not a mid-session correction.
3. **Round-2 subagents** (#29 round2 150 K/11 min; #32 round2 99 K/3 min). Real
   value on #29 (cleared 2 BLOCKs), but a full subagent round-trip for what became
   small edits. For #30 I instead applied polish via orchestrator Edit — cheaper.
4. **Redundant ci.sh.** ~28 xcodebuild cycles for 9 PRs. The subagent runs ci.sh,
   the reviewer often runs its own `xcodebuild build/test`, then the orchestrator
   re-runs ci.sh before merge — on a frequently byte-identical tree.
5. **GPT-5.5 checkpoints (334 K tok total).** Expensive but **highest ROI in the
   run** — the epic checkpoint caught a real `batchCounts` swipe leak, the tooling
   checkpoint caught an unguarded CI contract. Keep them.

## 4. What worked well (keep doing)

- **Plan review before issue 1** — GPT-5.5 pre-empted the interleave/batchID design,
  the #32 bool-flag trap, and Layout A, so subagents built the right thing first
  time (fewer round-2s downstream).
- **GPT-5.5 cross-issue checkpoints** — caught bugs no per-issue review could.
- **Targeted `git add` throughout** — the iCloud `App/Anghkooey 2/3/4.xcodeproj`
  dup dirs (spawned by #56's `make generate`) were never staged.
- **Orchestrator reading only `tail`/`--stat`** of ci.sh, not full logs.
- **Applying tiny reviewer findings via orchestrator Edit** (#30 a11y+animation,
  the two checkpoint fixes) instead of a subagent round-trip.
- **Reverting unrelated churn** (#56's xcodegen UUID reshuffle) to keep PRs clean.
- **receiving-code-review discipline** — verified every BLOCK/MAJOR before acting;
  correctly rebutted GPT's #56-first reorder and several "pre-existing, not a bug"
  findings instead of blindly fixing.

## 5. Inefficiencies + concrete fixes (ranked by expected savings)

1. **Compact/segment the orchestrator context.** Biggest lever. Options:
   (a) run `/compact` (or ecc:strategic-compact) after each epic/tier boundary;
   (b) start a **fresh orchestrator context per tier** (the handoff report + memory
   already make this safe); (c) **demand terse structured subagent reports** — tell
   subagents to reply with a fixed short schema (files changed / test names /
   RED→GREEN one-liner / ci.sh tail / deviations), NOT multi-paragraph prose. The
   prose reports this session were 500–1500 tokens each and live in Opus context
   forever. Est. savings: large (this is most of the $).
2. **Tier the review gate by risk instead of "swift-reviewer on everything."**
   - Logic/concurrency/error-path/hub diff (AppState, scheduler, persistence,
     drainer) → full swift-reviewer (+ silent-failure-hunter only if it touches
     error handling; + pr-test-analyzer only for a hub rewrite).
   - Pure UI-wiring / small view / docs → **orchestrator self-review** (Opus reads
     the ≤~30-line diff directly) + one ci.sh, no reviewer subagent.
   Would have cut ~2–3 reviewer runs (~160–240 K tok, ~15–20 min). Update the
   session prompt's "MANDATORY on every diff" to "MANDATORY on every *logic* diff;
   self-review small UI/doc diffs."
3. **One ci.sh per issue, at the merge gate.** Rule: the *subagent* runs full ci.sh
   once and pastes the tail as evidence; the orchestrator re-runs **only if it
   edited the tree after the subagent**. Don't re-verify a byte-identical tree.
   Reviewer agents should be told **not** to run their own full build unless a
   finding depends on it. Est. savings: ~8–12 xcodebuild cycles.
4. **Findings-size routing for fixes.** Reviewer finding ≲10 lines → orchestrator
   Edit + single ci.sh. Larger/multi-file → subagent round-2. (Formalize what I did
   ad hoc.) Avoids full subagent round-trips for one-line log fixes.
5. **Fix the subagent "hand back mid-ci.sh" pattern.** Twice (#30, #31) a subagent
   set up a background Monitor on its own ci.sh and returned WITHOUT a final result,
   forcing the orchestrator to re-establish state and re-run ci.sh. **Instruct
   subagents: run ci.sh in the FOREGROUND (blocking) and paste the tail in the
   report; never background+Monitor+hand-back.**
6. **Parallelize independent issues.** Epic-10 was necessarily serial (all touch
   AppState/ContentView). But #33 was independent, and #85/#86 are independent of
   everything. Dispatch 2 execution subagents concurrently when they share no
   files, then review+merge sequentially. Session 3's T1 (#39/#40/#41 share
   Library; #53/#54 a11y may be separable) and the follow-ups are candidates.
7. **Batch the trivial follow-ups.** #85/#86 are two ~1-line log additions; do them
   as ONE branch/PR with one ci.sh, not two.
8. **(Lower priority) faster inner-loop test target.** ci.sh always runs the full
   Core+Intel+UI+app suite. For iteration, a scoped `xcodebuild test -only-testing:`
   on the affected suite is seconds; reserve full ci.sh for the merge gate. Adds
   complexity; only worth it if inner-loop iteration grows.

## 6. Recommended workflow deltas for the session-3 prompt

- Add a **"Reporting contract for subagents"**: fixed terse schema; run ci.sh in
  foreground; report the tail; no prose essays; no background Monitor.
- Change review-gate wording to **risk-tiered** (full reviewer for logic/error/hub;
  orchestrator self-review for small UI/doc diffs).
- Add **"ci.sh once per issue at the merge gate; re-run only after an
  orchestrator edit"** and "reviewers don't run their own full build."
- Add **"compact or fresh-context at each tier boundary."**
- Add **"batch trivial/independent issues; run 2 subagents in parallel when no
  shared files."**
- Keep unchanged (high ROI): pre-run plan review, per-tier GPT-5.5 cross-issue
  checkpoints, targeted `git add`, iCloud dup sweep, receiving-code-review verify.

## 7. Rough cost attribution (for intuition, not exact accounting)

Of the ~$203 code spend: the biggest single chunks were **#29 (~$28–30)** and
**#33 (~$26)** (long subagent + long reviewer), the **two GPT-5.5 checkpoints
(~$?? but ~270 K tok of GPT + the Opus turns wrapping them)**, and a **steadily
rising per-turn Opus floor** as context grew (~$15–20/issue late-session baseline
just to re-read context). Cutting orchestrator context growth (§5.1) and the
redundant reviewer/ci.sh work (§5.2–5.3) is where a session-3 could plausibly land
the same output for meaningfully less — target ~$12–15/PR.
