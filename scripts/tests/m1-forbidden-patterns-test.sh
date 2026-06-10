#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "${FIXTURE_ROOT}"' EXIT

mkdir -p \
  "${FIXTURE_ROOT}/scripts" \
  "${FIXTURE_ROOT}/Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence" \
  "${FIXTURE_ROOT}/Packages/AnghkooeyCore/Sources/AnghkooeyCore/Boundary"
cp "${REPO_ROOT}/scripts/m1-forbidden-patterns.sh" "${FIXTURE_ROOT}/scripts/"

cat > "${FIXTURE_ROOT}/Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/Card.swift" <<'SWIFT'
struct Tag {}
struct Card {
    var tags: [Tag]
}
SWIFT

cat > "${FIXTURE_ROOT}/Packages/AnghkooeyCore/Sources/AnghkooeyCore/Boundary/CardSnapshot.swift" <<'SWIFT'
struct CardSnapshot {
    let tags: [String]
}
SWIFT

bash "${FIXTURE_ROOT}/scripts/m1-forbidden-patterns.sh" >/dev/null

cat > "${FIXTURE_ROOT}/Packages/AnghkooeyCore/Sources/AnghkooeyCore/Persistence/Card.swift" <<'SWIFT'
struct Card {
    var tags: [String]
}
SWIFT

if bash "${FIXTURE_ROOT}/scripts/m1-forbidden-patterns.sh" >/dev/null 2>&1; then
  echo "error: forbidden Card.tags: [String] was not rejected" >&2
  exit 1
fi

echo "m1 forbidden-pattern regression test: OK"
