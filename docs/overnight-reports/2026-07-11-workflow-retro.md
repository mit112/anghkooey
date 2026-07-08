# Workflow-retro delta — session 4 (2026-07-11)

Session 4 finished Stretch Tier 2 (#38, #50, #96, #35/#36). Deltas vs the 2026-07-10 retro:

## What worked / what's new

- **Parallel execution via git worktrees paid off (the biggest new lever).** When Mit asked to "fire up more cylinders," #96 and #35/#36 were dispatched as two concurrent Sonnet subagents in dedicated worktrees (`/private/tmp/anghkooey-wt-96`, `-wt-3536`) — disjoint file sets (FreezeController/Settings vs widget), off the same integration tip, merged sequentially. Two `xcodebuild` runs contend for CPU but both completed; net wall-clock win over serial. Worktrees (not full clones) were fast and, now that the repo is off iCloud, stable. Keep this pattern for genuinely independent units; the cap of 2 concurrent held.
- **Checkpoints remain the highest-ROI step — 3 real bugs this session.** #38 (notification posted inside the generation guard → dropped on supersession; generation bump unrestored on failure → stranded load), #96 (freeze-during-unfreeze clobber), and a correct **downgrade** of the #35/#36 concurrent-tap "BLOCKER" (pre-existing + bounded) with two cheap endorsed fixes instead. Never skip them.
- **GPT-5.5 `xhigh` timed out (>5 min) on the big packets; `high` with a tight packet is the right checkpoint setting.** Two `xhigh` checkpoint calls hit the 5-minute tool timeout and returned nothing. Switching to `-c model_reasoning_effort=high` with a compact invariant-only packet (diff hunks, not full files) returned in ~1–2 min AND still caught the #96 clobber and adjudicated the #35/#36 blocker. Recommendation: **`high` for checkpoints, reserve `xhigh` for the initial multi-question arbitration memos** (those returned fine at xhigh, ~1–2 min each).
- **Subagent self-recovery → still 0 round-2 dispatches.** The #35/#36 subagent hit a Swift-Testing compile error (`expect a compile-time constant literal`), fixed it, and re-ran `ci.sh` to green on its own before reporting — no orchestrator round-2 needed. Skill-loading + a precise arbitrated brief continue to yield correct-first-time execution.

## What to watch

- **The "novel combined tree" gate.** #35/#36 branched off the pre-#96 tip; merging it into an integration that had since gained #96 produced a tree **no single CI run had built**. The content-addressed skip does NOT apply there — the orchestrator must run a fresh authoritative `ci.sh` on the exact integration tip before the tier→main promotion. Handled correctly; worth stating as a rule: *parallel branches off divergent bases ⇒ re-run CI on the merge result.*
- **One subagent backgrounded `ci.sh` and handed back early** (the #38 executor), returning no schema report. Recovered by inspecting git/CI directly, and it didn't matter because the orchestrator owns the authoritative CI anyway. The "run ci.sh in the FOREGROUND, never background+handback" instruction should stay explicit in briefs; treat a missing schema report as "verify from disk," not "trust it."
- **`sed` is unusable on this shell** — it's aliased/wrapped such that `sed -n '1,40p'` is parsed as `--max-replacements '1,40p'` and errors. Use the Read tool (or `grep`/`awk`) for file viewing; don't reach for `sed`.
- **Orchestrator context rode long again.** The single Opus orchestrator context carried the whole tier (4 units + 3 hardening rounds + parallel dispatch). No autocompact/StrategicCompact fired at a tier boundary. The ledger (`scratchpad/EXECUTION-LEDGER.md`) + issue comments carried recovery state well, but the structural cost lever (harness-driven per-tier context reset) is still unrealized — same finding as sessions 2–3.

## Net
Output: all of Tier 2 (#38/#50/#96/#35+#36, 6 PRs incl. 3 checkpoint-hardening) on `main`, each reviewed + checkpointed, 0 round-2s, no flakes. The parallel-worktree pattern and the `high`-effort compact checkpoint are the two adopted improvements to carry forward.
