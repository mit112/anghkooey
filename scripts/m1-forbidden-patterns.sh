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
  'tags:[[:space:]]*\[String\]'              # tags is a [Tag] relationship
  'Logger\([[:space:]]*subsystem:'           # use CoreLog.persistence; do not hard-code subsystem
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

if [[ "${EXIT}" -eq 0 ]]; then
  echo "M1 forbidden-pattern check: OK"
fi
exit "${EXIT}"
