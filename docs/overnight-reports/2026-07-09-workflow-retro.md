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

1. **Hard, mechanical orchestrator boundaries** (biggest lever; strengthened per
   §8). StrategicCompact fired at 50 tool calls and was ignored while Opus context
   grew unbounded. Make it a RULE, not a suggestion: **after each tier/epic OR every
   2–3 merged PRs, write the handoff + restart the orchestrator context** (fresh
   context reloads from the report + memory, which already make it safe). Also:
   **artifact-based subagent reports** — subagents reply with a fixed short schema
   (files changed / tests run / final status / **CI-output file path** / deviations),
   put full CI logs in a file and report the PATH, and paste the tail ONLY on
   failure. The prose reports this session were 500–1500 tokens each and lived in
   Opus context forever. Est. savings: large (this is most of the $).
2. **Tier the review gate by TOUCHED SURFACE, not diff size.** (Corrected after a
   GPT-5.5 second-reviewer pass — see §8. My original "skip reviewer on small
   diffs" framing was wrong: #32's 3-line prod diff was in `AppState.handleSheetDismiss`
   /`advanceQueue` — central queue state — and the Epic-10 checkpoint later found a
   `batchCounts` leak in exactly that interaction. Small diffs in state machines are
   where regressions hide.)
   - **Central-surface OR error-path diff → full swift-reviewer, regardless of size.**
     Central = `AppState`/sheet queue, persistence/`CardStore`, FSRS/scheduler,
     `InboxDrainer`, `ClipboardCaptureCoordinator`, widget snapshot, CI/project
     generation, migrations, any `catch`/`try?`/fallback. (+ silent-failure-hunter
     only when it touches error handling; + pr-test-analyzer only for a hub rewrite.)
   - **Leaf UI / docs only → orchestrator self-review** (Opus reads the diff) + one
     ci.sh, no reviewer subagent. "Leaf" = a self-contained SwiftUI view with no
     shared-state logic, a pure formatting/string change, or markdown.
   The saving comes from the genuinely-leaf diffs (some of #31's view, docs), NOT
   from central-state diffs — do not downgrade those.
3. **Content-addressed CI evidence; orchestrator owns the final gate** (sharpened
   per §8). The subagent reports the **commit SHA / `git rev-parse HEAD^{tree}`
   hash + `git status --short`** alongside its ci.sh result, so "byte-identical
   tree" is *provable*, not assumed. The **orchestrator owns the one authoritative
   full ci.sh on the exact merge candidate**; it skips a redundant run only when the
   worker's reported tree-hash matches the current tree AND nothing was edited since.
   Reviewer agents **must not** run their own full build unless a finding depends on
   runtime behavior. Est. savings: ~8–12 xcodebuild cycles.
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

## 6. Recommended workflow deltas for the session-3 prompt (consensus, post-§8)

- **Orchestrator reset contract:** after each tier/epic OR every 2–3 merged PRs,
  write the handoff and **restart the orchestrator context** (don't ride one Opus
  context for a whole run). Treat StrategicCompact firing as a hard trigger.
- **Subagent reporting contract:** fixed schema — files changed / tests run / final
  status / **CI-output file path** / commit SHA + tree hash + `git status --short` /
  deviations. Full CI logs to a file; paste tail ONLY on failure. Run ci.sh in the
  FOREGROUND; **never background+Monitor+hand-back**.
- **Review gate by TOUCHED SURFACE, not size:** central-surface/error-path diff →
  full reviewer regardless of line count (`AppState`/queue, persistence, scheduler,
  drainer, clipboard, widget snapshot, migrations, CI/project generation, any
  `catch`/`try?`/fallback); leaf-UI/docs only → orchestrator self-review. Do NOT
  frame this by diff size.
- **CI gate:** orchestrator owns the single authoritative full ci.sh on the exact
  merge candidate (verified by tree hash); reviewers don't full-build unless a
  finding is runtime-dependent.
- **Findings routing:** reviewer finding ≲10 lines → orchestrator Edit + one ci.sh;
  larger/multi-file → subagent round-2.
- **GPT-5.5 checkpoints:** keep them (highest ROI), but feed an **invariant-focused
  packet** — issues merged, files touched, state machines affected, decisions, and
  the specific invariants to attack, **plus the changed hunks/functions** (not
  full-file diffs, not invariants-alone).
- **Per-epic merge to `main` — the loop is now AUTHORIZED (Mit granted 2026-07-09):**
  after a tier/epic fully completes on the integration branch (all its issues
  merged + GPT-5.5 checkpoint passed + full green ci.sh on the exact tip), the loop
  merges `overnight/backlog-2026-07` → `main` **itself**, then continues the next
  tier from the updated tip (integration == main at that boundary). The main-merge
  must: pass ci.sh on the exact merge candidate; **prominently list the ⚖️ decisions
  it carries** (all reversible — for Mit's post-hoc review, not a blocker); note
  which issues auto-close. **Start of session 3: merge the current 48-commit backlog
  (completed epics #8/#9/#10 + tooling #56) to main FIRST**, before any new work.
  Never force-push or rewrite `main`. If Mit advanced `main` out of band, pull first.
  This keeps the integration branch bounded to ~one epic instead of ballooning.
- **iCloud root cause:** the real fix is **moving the working copy out of
  `~/Documents`** (iCloud). Until then, a **mandatory pre-commit AND pre-merge sweep**
  for `* 2.*`/`* 3.*`/`* 4.*` (not just an ad-hoc cleanup).
- **Parallelism (minor lever):** only for genuinely independent work (#33/#56-style,
  or trivial #85/#86 logging); cap at 2 concurrent subagents; merge sequentially.
  Epic-style shared-file work stays serial.
- **Keep unchanged (high ROI):** pre-run plan review, per-tier GPT-5.5 cross-issue
  checkpoints, targeted `git add`, receiving-code-review verify-before-fixing.

## 7. Rough cost attribution (for intuition, not exact accounting)

Of the ~$203 code spend: the biggest single chunks were **#29 (~$28–30)** and
**#33 (~$26)** (long subagent + long reviewer), the **two GPT-5.5 checkpoints
(~$?? but ~270 K tok of GPT + the Opus turns wrapping them)**, and a **steadily
rising per-turn Opus floor** as context grew (~$15–20/issue late-session baseline
just to re-read context). Cutting orchestrator context growth (§5.1) and the
redundant reviewer/ci.sh work (§5.2–5.3) is where a session-3 could plausibly land
the same output for meaningfully less — target ~$12–15/PR.

## 8. External second-reviewer pass (GPT-5.5) — reconciliation

A GPT-5.5 review of this retro sharpened it. Changes already folded into §5/§6:

**Conceded (my original was wrong or weaker):**
- **Review tiering must be by TOUCHED SURFACE, not diff size.** My "skip reviewer on
  3–15 line diffs" was dangerous: #32's 3 prod lines were in `AppState`
  queue-advance logic, and the Epic-10 checkpoint *later found a `batchCounts` leak
  in that exact interaction*. Small diffs in state machines are precisely where
  regressions hide. (§5.2, §6 corrected.)
- **Orchestrator boundaries must be mechanical** (every 2–3 PRs / per tier), not a
  soft "consider compacting." (§5.1.)
- **Content-addressed CI evidence** (tree hash + `git status --short`), orchestrator
  owns the final gate, reviewers don't full-build. (§5.3.)
- **Artifact-based subagent reports** (CI log to a file + path, tail on failure
  only). (§5.1, §6.)
- **iCloud is a root-cause issue,** not noise — move the repo out of `~/Documents`;
  sweep is only a mitigation. (§6.)

**Accepted with nuance:**
- **"Merge to main per epic; don't let the branch reach 48 commits."** Right as risk.
  Initially reframed as Mit-attended, but **Mit then explicitly authorized the loop
  to merge to main per epic (2026-07-09)** — so §6 now has the loop do it directly
  (gated on green ci.sh + checkpoint, carrying the reversible ⚖️ decisions for
  post-hoc review). GPT was right that the accumulation was the risk.
- **"Feed checkpoints smaller packets."** Accepted, but NOT invariants-only: the
  Epic-10 checkpoint caught the leak *because* it saw the actual code. So →
  invariants-to-attack **+ the changed hunks/functions**, not full-file diffs. (§6.)
- **"Parallelism isn't the main lever."** Agree; demoted to independent-work-only,
  cap 2. (§6.)

**Not verifiable by the external reviewer:** the raw cost/token figures (from
harness telemetry) were treated as reported, not independently proven — same caveat
applies to §1/§7 here.

## 9. Tooling audit — are we using ECC to the max? (honest: no, but…)

Checked the ECC catalog (github.com/affaan-m/ECC) against this workflow. **The gap
is 80% process/config, not missing tools.** ECC's own README warns: install
"core/general skills only… avoid bloating the context budget." So the discipline is
FEWER targeted tools, not more — adding orchestration tools has overhead and grows
the very Opus context that §5.1 says is the #1 cost. Verdict + adoptions, ranked:

**ADOPT — highest ROI, low/zero overhead:**
1. **Config knobs (do these first — they directly cap the §5.1 context/cost problem,
   zero token cost):** `MAX_THINKING_TOKENS=10000`, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50`,
   `ECC_HOOK_PROFILE=minimal` (for the unattended run — each GateGuard-style
   fact-prompt costs 200–500 tok; CLAUDE.md already allows `ECC_GATEGUARD=off` for
   routine exec), `ECC_SESSION_RETENTION_DAYS=14`. These are the cheapest wins
   available and were NOT set this session.
2. **Subagent skill-loading to cut round-2s (measured cost: e.g. #29's 150 K-tok
   round-2).** Tell each execution subagent to load the relevant ECC Swift skill for
   its surface: `ecc:swift-concurrency-6-2` (AppState/actor/@MainActor work),
   `ecc:swift-protocol-di-testing` (seams/mocks like #33's PasteboardReading),
   `ecc:swift-actor-persistence` (CardStore/inbox), `ecc:swiftui-patterns` +
   `ecc:make-interfaces-feel-better` (T1 UI, #53/#54 a11y),
   `ecc:foundation-models-on-device` (any authoring change). Correct-first-time =
   fewer BLOCK→round-2 cycles, the single most controllable execution cost.
3. **Honor `strategic-compact`/autocompact as the mechanical reset trigger** (§5.1) —
   it's already installed and fired this session; we ignored it. Use it, don't add a
   new loop tool.

**ADOPT — run ONCE at session-3 start (data-driven "are we optimal"):**
4. **`/harness-audit`** (+ the `harness-optimizer` agent if the audit flags config) —
   deterministic scorecard of harness reliability/eval-readiness/risk. This is the
   literal tool for this question; run it once, apply the cheap findings, don't re-run
   per issue.
5. **`/fewer-permission-prompts`** — pre-allowlist the read-only bash/gh/git calls the
   run repeats, so the unattended loop stops prompting. One-time setup.

**CONSIDER — medium value, has switching risk:**
6. **`/checkpoint` + `ecc:verification-loop`** — formalize the content-addressed CI
   gate (§5.3) as first-class artifacts instead of ad-hoc `tail`/task-files. Nice, not
   essential.
7. **`ecc:autonomous-loops` / `/loop-start` / `loop-operator`** — a managed loop
   (sequential/PR/DAG + stop conditions + `/loop-status`) that could replace the
   hand-rolled ledger. Real, but swapping a *working* loop mid-project is risky;
   evaluate on a low-stakes tier first, don't bet a whole session on it.

**Do NOT adopt (efficiency traps for THIS workflow):**
- **`ecc:santa-loop`/`santa-method`** (two independent reviewers must BOTH approve) —
  doubles review cost. Our lighter model (per-issue swift-reviewer + per-epic GPT-5.5
  checkpoint) is cheaper and already caught the real bugs. At most, reserve santa-loop
  for the single riskiest T2 change (#35+#36 snapshot schema), not as the default.
- **`dmux-workflows`** (tmux multi-pane parallelism) — real parallelism but heavy
  orchestration overhead/fragility; §6 caps parallelism at 2 anyway.
- **Installing the broader ECC set / more reviewer agents** — context bloat; ECC's own
  guidance says don't. We already have the exact reviewers we need.

**Net:** the ceiling isn't more tools — it's (a) the config knobs above, (b) the §5–6
process changes, (c) subagent skill-loading to kill round-2s. Do a one-time
`/harness-audit` to confirm, then stop tuning and execute. Over-tooling (and
over-analyzing — this retro's own iterations cost real $) is itself an inefficiency.
