#!/usr/bin/env bash
# M1 forbidden-pattern tripwire.
#
# Cheap, dumb, effective. Exits non-zero if any banned identifier appears in
# the AnghkooeyCore sources. Banned set is derived from the schema contract
# in docs/superpowers/plans/2026-05-20-rewind-m1-core.md.
#
# Add new banned patterns when reviews catch new ways the spec gets misread.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/Packages/AnghkooeyCore/Sources/AnghkooeyCore"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: ripgrep (rg) is required for this script" >&2
  exit 2
fi

# Each entry is a regex passed to rg. Quote carefully — these are PCRE.
PATTERNS=(
  '\bclass[[:space:]]+Deck\b'               # Deck model is out of scope (foundation.md §4)
  '\benum[[:space:]]+Deck\b'
  '\bstruct[[:space:]]+Deck\b'
  '\bclass[[:space:]]+Review[[:space:]]'     # ReviewLog, not Review
  '\bvar[[:space:]]+front\b'                 # Card.question, not front
  '\bvar[[:space:]]+back\b'                  # Card.answer, not back
  '\bvar[[:space:]]+easeFactor\b'            # FSRS uses stability/difficulty, not SM-2 ease
  '\bvar[[:space:]]+interval\b'              # likewise, no SM-2 interval Int
  '\bvar[[:space:]]+nextDue\b'               # field is dueAt
  'Logger\([[:space:]]*subsystem:'           # use CoreLog.persistence; do not hard-code subsystem
  # M1 T3 — Scheduling/ contract bans. ts-fsrs is JS (snake_case); Codex's
  # priors will pull those identifiers in verbatim. Swift port is camelCase.
  '\bscheduled_days\b'
  '\belapsed_days\b'
  '\blearning_steps\b'
  '\brelearning_steps\b'
  '\blast_review\b'
  '\brequest_retention\b'
  '\bmaximum_interval\b'
  '\benable_fuzz\b'
  '\benable_short_term\b'
  '\bdefault_w\b'
  # FSRS-5 / SM-2 vocabulary that must not appear in the FSRS-6 port.
  '\bFSRS5\b'
  '\bfsrs5\b'
  '\bFSRS-5\b'
  '\bSM2\b'
  '\bSM-2\b'
)

EXIT=0
for pattern in "${PATTERNS[@]}"; do
  # CoreLog.swift is the one legitimate site that constructs Logger(subsystem:);
  # every other file must route through CoreLog.* accessors.
  if rg --no-heading --line-number --color=never \
        --glob '!**/CoreLog.swift' \
        -e "${pattern}" "${SRC}"; then
    echo "  ↑ forbidden pattern: ${pattern}" >&2
    EXIT=1
  fi
done

# Card.tags is a SwiftData [Tag] relationship. String projections are valid in
# Sendable snapshots and store APIs, so keep this schema check scoped to Card.
CARD_SOURCE="${SRC}/Persistence/Card.swift"
if rg --no-heading --line-number --color=never \
      -e '\bvar[[:space:]]+tags:[[:space:]]*\[String\]' "${CARD_SOURCE}"; then
  echo "  ↑ forbidden pattern in Card model: var tags: [String]" >&2
  EXIT=1
fi

# M2 — AnghkooeyIntelligence source checks
INT_SRC="${ROOT}/Packages/AnghkooeyIntelligence/Sources/AnghkooeyIntelligence"
INT_PATTERNS=(
  'import SwiftData'
  'import SwiftUI'
  'import UIKit'
)

if [[ -d "${INT_SRC}" ]]; then
  for pattern in "${INT_PATTERNS[@]}"; do
    if rg --no-heading --line-number --color=never \
          -e "${pattern}" "${INT_SRC}" 2>/dev/null; then
      echo "  ↑ forbidden pattern in AnghkooeyIntelligence: ${pattern}" >&2
      EXIT=1
    fi
  done
fi

if [[ "${EXIT}" -eq 0 ]]; then
  echo "M1+M2 forbidden-pattern check: OK"
fi
exit "${EXIT}"
