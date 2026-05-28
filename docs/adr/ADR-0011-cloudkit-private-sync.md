# ADR-0011 — CloudKit Private Database Sync

**Date:** 2026-05-28  
**Status:** Accepted  
**Lane:** C2 (CloudKit Private DB Sync)

---

## Context

Anghkooey's v1 storage is on-device only (SwiftData local store). Users who own
multiple Apple devices have no way to access their card library on a second device.
The project skill map lists CloudKit private-DB sync as gap #4 (demand 5/5), and
`foundation.md` §4 explicitly defers "iCloud private-database sync" to v1.1.

Constraints:
1. **On-device by default.** `foundation.md` §3 principle 4: "Cloud sync is opt-in,
   private CloudKit only." Users must not be enrolled in sync without consent.
2. **Schema was designed for CloudKit from day one.** All V2/V3 migration fields
   are Optional; relationships have inverses; no post-launch schema surgery needed.
3. **Single-container launch.** `ModelContainer` is constructed once in
   `AnghkooeyApp.init()`. Flipping the sync mode requires a relaunch.

---

## Decision

### SyncMode enum

```swift
public enum SyncMode: Sendable, Equatable {
    case local          // on-device only, explicit cloudKitDatabase: .none
    case cloudKit(containerID: String)
}
```

`AnghkooeyModelContainer.makeContainer(syncMode:url:)` switches on this enum.
Both branches use the identical `AnghkooeySchemaV3` + `AnghkooeyMigrationPlan`,
so the schema never changes when the user flips the toggle.

### iOS 26 auto-CloudKit mitigation

iOS 26 SwiftData auto-enables CloudKit mirroring on any `ModelConfiguration` when
`icloud-container-identifiers` appears in the app entitlements — even without an
explicit `cloudKitDatabase:` argument. To prevent this for `.local` mode, the
factory passes `cloudKitDatabase: .none` explicitly.

### CloudKit-legal schema invariant

| Requirement | Status |
|-------------|--------|
| All properties Optional or defaulted | ✅ All V2/V3 added fields are Optional |
| Relationship inverses declared | ✅ `Card ↔ ReviewLog` inverse present |
| No `@Attribute(.unique)` under CloudKit | ✅ SwiftData silently drops `.unique` under CloudKit; `Card.id` uniqueness is enforced at the app layer instead |

### Relaunch requirement

The `ModelContainer` is constructed exactly once in `AnghkooeyApp.init()`. Changing
`SyncPreference.isEnabled` takes effect on the next launch. The Settings UI copy
says "Restart Anghkooey for the change to take effect." An in-session switch would
require tearing down and rebuilding the entire SwiftData stack — not justified for v1.1.

### Container ID

`iCloud.com.mitsheth.anghkooey` — must be provisioned in Apple Developer portal
→ CloudKit Dashboard before any archive with sync enabled. The container ID is
defined in `AnghkooeyModelContainer.cloudKitContainerID` and documented in
`App/project.yml`.

---

## Consequences

- v1.1 ships sync as opt-in. The default experience is identical to v1 (local only).
- A user who enables sync and then disables it does **not** lose their data: the
  local store and the CloudKit store are separate; the app uses whichever was
  selected at last launch.
- Two-device sync requires both devices to have the same Apple ID signed in to
  iCloud and the toggle enabled.
- Device verification (two-device sync round-trip) is deferred — see exit gate.
  The `.local` path is fully tested and is the default; zero user-facing risk if
  device sync QA is pending.
