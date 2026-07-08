#!/usr/bin/env bash
#
# Per-unit-reset overnight launcher.
#
# Each unit gets a FRESH `claude -p` invocation (fresh, small, cheap context)
# that boots off external state — the run manifest + ledger + git — does ONE
# unit end-to-end (arbitrate -> subagent -> review -> authoritative ci.sh ->
# checkpoint -> merge to the integration branch), records a one-line status in
# the ledger, and STOPS. The orchestrator never rides one long context across a
# whole tier; this script provides the per-unit context reset a running session
# can't do to itself.
#
# Idempotent / crash-safe: units the ledger already marks DONE are skipped, so
# re-running resumes where it left off.
#
# SETUP (do once per run, interactively with Claude): ask Claude to
#   "set up a launcher overnight run for <issues> on <integration branch>",
# which generates docs/overnight/RUN.md (manifest) and docs/overnight/units.txt
# and initializes docs/overnight/ledger.md. THEN run this script.
#
# Prereqs for UNATTENDED headless runs: git/gh/xcodebuild/codex and the file
# tools must be pre-permitted (headless `claude -p` cannot show permission
# prompts). Either pre-approve them in .claude/settings.local.json's allow-list,
# or pass a permission mode below. Keep GateGuard on for secret/destructive ops
# if you want the extra guard; the review gate + checkpoints are the main net.

set -uo pipefail

REPO="/Users/mitsheth/dev/anghkooey"
OVN="$REPO/docs/overnight"
MANIFEST="$OVN/RUN.md"          # the run spec — protocol, model/consult rules, per-unit resume plans
UNITS="$OVN/units.txt"          # ordered, one per line: "<issue#> <slug>"  (blank lines / #comments ok)
LEDGER="$OVN/ledger.md"         # orchestrator-owned progress + "STATUS <#> <DONE|BLOCKED|SKIP> <sha>" lines
LOGS="$OVN/logs"
MODEL="${OVN_MODEL:-opus}"      # orchestrator model; subagents are dispatched as sonnet from within
PERM_FLAGS="${OVN_PERM_FLAGS:---permission-mode acceptEdits}"  # override for a fully-sandboxed unattended box

mkdir -p "$LOGS"
cd "$REPO" || { echo "[launcher] cannot cd $REPO"; exit 1; }
[ -f "$MANIFEST" ] || { echo "[launcher] missing $MANIFEST — run SETUP first"; exit 1; }
[ -f "$UNITS" ]    || { echo "[launcher] missing $UNITS — run SETUP first"; exit 1; }
touch "$LEDGER"

seed() { # $1=issue#  $2=slug
  cat <<EOF
You are the ORCHESTRATOR resuming an unattended overnight run in LAUNCHER MODE.
You were started FRESH for ONE unit — do not try to do the whole tier, and STOP
when this unit is finished.

BOOTSTRAP (in this order, before anything else):
1. Read the run manifest: $MANIFEST  — the authoritative protocol (model/consult
   routing, the review gate by touched surface, GPT-5.5 checkpoint rules,
   one-issue=one-branch=one-PR into the integration branch, stop conditions).
2. Read the ledger: $LEDGER  — never redo a unit already marked "STATUS <#> DONE".
3. cd $REPO ; run: git log --oneline \$(git rev-parse --abbrev-ref HEAD) ~ ; git status --short ;
   and confirm the integration branch tip matches the ledger.
4. Confirm the consult channel per the manifest (codex gpt-5.5, high effort for
   checkpoints, </dev/null on every call).

YOUR UNIT THIS INVOCATION:  #$1  ($2)
Find its section in the manifest (resume plan, review tier, device-risk flag) and
execute ONLY that unit, following the manifest's protocol end to end. YOU own the
single authoritative \`bash scripts/ci.sh\` on the merge candidate — never trust a
subagent's CI. Full ecc:swift-reviewer (+ silent-failure-hunter) for central /
error-path surfaces; self-review for leaf UI/docs. Run one GPT-5.5 invariant
checkpoint after merge and resolve/rebut findings.

WHEN THE UNIT IS MERGED + CHECKPOINTED (or you hit a stop condition):
- Append exactly one line to $LEDGER:
    STATUS $1 <DONE|BLOCKED|SKIP> <merge-sha> — <one-line note>
  (plus any richer notes above it you want the next invocation to see).
- Comment the outcome on the issue.
- Then STOP. Do NOT start another unit. Do NOT promote to main (the final pass does that).
EOF
}

run_claude() { # $1 = prompt ; $2 = logfile
  echo "[launcher] $(date '+%H:%M:%S') -> claude ($MODEL)  log: $2"
  claude -p "$1" --model "$MODEL" $PERM_FLAGS 2>&1 | tee "$2"
}

# --- per-unit loop -----------------------------------------------------------
while IFS= read -r line; do
  line="${line%%#*}"; line="$(echo "$line" | xargs)"   # strip comments/whitespace
  [ -z "$line" ] && continue
  num="$(awk '{print $1}' <<<"$line")"
  slug="$(awk '{$1=""; print $0}' <<<"$line" | xargs)"
  if grep -q "^STATUS $num DONE" "$LEDGER"; then
    echo "[launcher] #$num already DONE — skipping"; continue
  fi
  run_claude "$(seed "$num" "$slug")" "$LOGS/unit-$num.log"
  if grep -q "^STATUS $num BLOCKED" "$LEDGER"; then
    echo "[launcher] #$num BLOCKED — halting run for human"; exit 2
  fi
  if ! grep -qE "^STATUS $num (DONE|SKIP)" "$LEDGER"; then
    echo "[launcher] #$num produced no DONE/SKIP status — halting (investigate $LOGS/unit-$num.log)"; exit 3
  fi
done < "$UNITS"

# --- final: integrate + promote + handoff (fresh context) --------------------
run_claude "$(cat <<EOF
You are the ORCHESTRATOR in LAUNCHER MODE, FINAL pass. Read $MANIFEST, $LEDGER,
and git. Per the ledger, every unit is merged to the integration branch.
1. Run the ONE authoritative \`bash scripts/ci.sh\` on the exact integration tip.
2. If green, promote to main per the manifest (PR integration->main whose body
   closes the issues; merge it). If a unit is BLOCKED/SKIP, promote only what's
   green and say so.
3. Write the morning handoff report, the memory PROGRESS block, and the
   workflow-retro delta. STOP.
EOF
)" "$LOGS/final.log"

echo "[launcher] done — see $LEDGER and $LOGS/final.log"
